<p align="center">
  <img src=".github/assets/banner.svg" alt="CloverSec CTF Pack" width="860" />
</p>

<p align="center">
  <a href="https://github.com/D1a0y1bb/CloverSec-CTF-Pack/releases/latest"><img src="https://img.shields.io/github/v/release/D1a0y1bb/CloverSec-CTF-Pack?style=for-the-badge&color=2563eb&label=release" alt="Release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/D1a0y1bb/CloverSec-CTF-Pack?style=for-the-badge&color=16a34a" alt="License" /></a>
  <img src="https://img.shields.io/badge/Claude_Code_%C2%B7_Codex-skill-f59e0b?style=for-the-badge" alt="Claude Code · Codex" />
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#output">Output</a> ·
  <a href="#manual">Manual</a> ·
  <a href="#local-verification">Local verification</a> ·
  <a href="#flag-contract">Flag contract</a> ·
  <a href="#layout">Layout</a>
</p>

---

An agent skill for CTF challenge delivery by CloverSec @CloverSecLabs

Give Claude Code or Codex the challenge source, a design note, or an old challenge directory. For container challenges it produces a buildable directory and verifies it locally; for attachment challenges it organises the player-facing files; for RDG defence challenges it produces a hardened environment with its check script. All three get a manual.

- **The author's intent comes first.** This skill works for the challenge author, not in their place. Anything that changes a verdict, changes the deliverable, picks between several reasonable options, deletes or overwrites existing content, or that you are unsure about — state what you intend to change, why, and what it affects, and wait for confirmation. When the author says "don't care", leave it as is. Facts you can establish yourself (code, platform behaviour, files) you check yourself; don't ask about those.
- **The original difficulty is restored by default.** The first step is a difficulty baseline (vulnerability type, chain length, service topology, runtime versions), and the challenge is restored to match it — this part needs no question. Only a change *relative to* the original (downgrade, upgrade, simplification) has to be cleared with the user first.
- Directories are named `<type>-<name>`, where type is one of 20 categories such as Web, Pwn, Crypto or AI. Multi-challenge deliveries split into `容器题/` (container) and `附件题/` (attachment).
- The source, `Dockerfile` and `start.sh` are written from the examples in the skill, with comments that point out the vulnerability and any non-obvious configuration. Comments are in Chinese.
- **A dynamic-flag image must contain `/bin/bash`**: the platform runs the injected script with `/bin/bash /changeflag.sh`, and alpine / distroless / scratch images lack it, so the flag silently stays at the placeholder. `verify.sh` probes for it after the build.
- `verify.sh` runs a container challenge the way the platform does: amd64 build, start with `/start.sh`, write a random test flag, probe the ports, and run `solve/solve.py` when present, which must print that flag. It then writes a **second** flag and solves again, which catches services that read the flag into memory at startup. Finally it points the solver at a closed port, where it must fail — that catches solvers that read a local file or use `docker exec` as a fallback.
- It also checks the manual's filename, skeleton and 1.5 fields, duplicated sections and content copied from another challenge; whether `challenge.yaml` really parses; provenance values and name consistency; the delivery-directory whitelist; secrets and customer PII; leftover flags in `src/` and attachments; and whether the landing page is an error page or references an external CDN.
- The manual lives in `README/`. Fact sections are filled in; judgement sections are **carried over from the author's material first**, then from what this delivery actually tested, and only left as `TODO` when no source exists — reported honestly.
- `solve/`, `附件/` (attachments), `镜像/` (image tarball) and `last/` (original write-ups) sit next to `src/`.
- For challenges that must stay buildable for years, the references show how to pin image digests, apt snapshots and dependency versions.
- Multi-service, Bundle, Scenario, RDG/AWD and Linux-QEMU challenges have their own reference file; batches of five or more use the batch-delivery one.

## Install

```bash
npx skills add D1a0y1bb/CloverSec-CTF-Pack -g -a claude-code -a codex
```

`-g` installs into `~/.agents/skills/`, and Claude Code reads it through a symlink. Drop `-g` to install into the current project. Pass `-a` once per agent.

Verification needs Docker and `curl`. On Apple Silicon the amd64 build runs under emulation and is slower.

## Usage

Name the skill in the chat, then hand over the material. Claude Code uses `/cloversec-ctf-pack`, Codex uses `$cloversec-ctf-pack`:

```text
/cloversec-ctf-pack Turn ./ssti-notes into a platform challenge.
Flask SSTI, flag at /flag, port 5000.
```

The material can be a design note, a bare source tree, or an old challenge with its own Dockerfile. It reads the material first and settles what the directory and source already show — challenge type, delivery shape, whether attachments or an image tarball are needed. Only what genuinely cannot be inferred gets asked, and the question starts by stating what it found, using structured input (Codex's `request_user_input`, Claude Code's AskUserQuestion) with plain options and a recommended one. When a port, start command or flag path is missing and blocks the build, it does not guess its way forward.

Difficulty needs no reminder. It reconstructs the original difficulty by default before touching anything; when a downgrade really is needed it states its reconstruction first and asks, and never offers "keep the simplified version" as an option.

## Output

A container challenge:

```text
Web-afterimage/
├── README/
│   ├── Web-afterimage.md   # manual, named after the challenge directory
│   └── assets/             # screenshots used by the manual
├── src/
├── Dockerfile
├── start.sh                # platform entrypoint, runs the real service in the foreground
├── challenge.yaml          # port, flag path and other platform fields
├── flag                    # placeholder, overwritten by the platform at start
├── solve/
│   └── solve.py            # local verification only, never copied into the image
└── 附件/                    # player attachments, only when the challenge needs them
```

An attachment-only challenge has no image files: just `README/`, `src/`, `附件/`, `solve/` and optionally `last/`. `镜像/` is created only when an image tarball is requested.

A delivery of several challenges is split into two levels:

```text
<delivery root>/
├── README.md            # index: one row per challenge with its status
├── 容器题/
│   └── Web-afterimage/
└── 附件题/
    └── Crypto-cinderbox/
```

The split is decided by whether the challenge has a `Dockerfile`, not by its category name.

The output directory is a whitelist. A container challenge may contain only `src/`, `Dockerfile`, `start.sh`, `challenge.yaml`, `flag`, `README/`, `solve/`, plus `附件/`, `镜像/` and `last/` when needed; an RDG challenge may also carry `check/`, `changeflag.sh`, `ttyd` and whatever else it actually runs with. `verify.sh`, `verify-report.json`, `*.verify.json`, `.DS_Store`, `__pycache__/` and internal working files such as `_PACK_SPEC.md` never belong there and the script reports them. Write reports to a temp directory instead:

```bash
bash ~/.agents/skills/cloversec-ctf-pack/scripts/verify.sh ./ssti-notes --report "$(mktemp -d)/verify.json"
```

## Manual

The manual is written to `README/<type>-<name>.md`, named exactly like the challenge directory, with screenshots in `README/assets/`. The section order is fixed: name, description, difficulty, what it tests, flag, challenge details, deployment, design, solution steps.

**The skill only writes what it can verify.** The nine sections split in two:

| Section | Source | Contents |
|---|---|---|
| 1.1 Name | verified | matches the directory and `challenge.yaml` |
| 1.3 Difficulty | verified | usually stated in the material |
| 1.5 Flag | verified | path, permissions, when it is read, the platform overwrite command |
| 1.6 Challenge details | verified | ports, accounts, admin path, check script location |
| 1.7 Deployment | verified | build, start **with `/start.sh`**, flag write, cleanup |
| 1.2 Description | **carry over first** | needs the author's voice and intent |
| 1.4 What it tests | **carry over first** | needs real understanding of the challenge |
| 1.8 Design | **carry over first** | needs the design rationale |
| 1.9 Solution steps | **carry over first** | needs the chain actually walked through |

Judgement sections are filled from four tiers, in order:

1. **The author's material** (competition archive, author's delivery bundle, official write-up, design notes in the old directory) — carry it across and tidy it up. No TODO.
2. **External write-ups and team reports** are leads only. Before any of it goes into the manual it must be re-run against *this* delivery: injection points, parameter shapes, trigger order and tool installs are often wrong for the challenge at hand.
3. **The chain this delivery actually walked** — when the solver genuinely worked, the injection point, payload and trigger order you verified are a reliable source for 1.8/1.9. Only write what you actually ran.
4. **No source at all** — write `TODO(人工填写)` in the section body and name the empty sections in the delivery note.

**Never invent.** A sentence like "tests web request analysis and server-side input handling" reads like content but says nothing, and it hides the gap.

Section 1.9 requires every command and payload shape to be reproducible with this delivery's `solve/solve.py`; when it does not match, fix the manual.

While writing, a section may carry an HTML comment saying what to write. Delete every comment block before delivery; `grep -c '<!--'` must return `0`.

`verify.sh` checks the filename, the section skeleton, the fact fields and the start command. It deliberately **does not** check the content of the judgement sections — it cannot tell real content from filler, and pretending otherwise is how "sections present" gets mistaken for "manual finished". Leftover TODOs make the result `partial`. That is a normal result: report it as is, and never invent content to reach `passed`.

Full per-section guidance and examples: [references/manual.md](src/CloverSec-CTF-Pack/references/manual.md). There is no "common failure modes" section.

## RDG challenges

For RDG the criterion is not "can the flag be read" but "is the vulnerability still there", and both the deliverable and the verification differ:

- An extra `check/` directory (`check.sh`, `check.py`, `requirements.txt`) that the platform runs when a player hits "verify". Invoked as `./check.sh <IP> <PORT>`; exit 0 means fixed, non-zero means still vulnerable, and the output must carry an `ok: True/False` or `RESULT: PASS/FAIL` verdict line.
- An extra ttyd service so players can edit code inside the container from a browser.
- Some RDG challenges have no flag contract at all: the sensitive target is a fixed value in the challenge's own configuration, and check verifies whether that target is still readable.
- `verify.sh` detects a `check/` directory and applies RDG judgement: the initial environment must report "still vulnerable" to count as correct. Reporting "already fixed" is a hard `failed`, since players would have nothing to do. A non-zero exit without a verdict line is treated as the check script crashing, also `failed`.

## Local verification

```bash
bash ~/.agents/skills/cloversec-ctf-pack/scripts/verify.sh ./ssti-notes
```

The script builds for `linux/amd64`, starts the container with `/start.sh`, waits until the ports are really listening, writes a random test flag to `flag.path`, then probes the ports. If `solve/solve.py` exists it runs it (target address in `HOST` and `PORT`) and only passes if the output contains that test flag; it then writes a **second** flag and solves again, and both runs must return their own value. Services that read the flag into memory at startup, or sync loops that silently fail, fail here. Each write is given up to 15 seconds to take effect; use `--no-flag-rotate` for challenges that a single solve leaves broken. Use `--solve '<command>'` for solvers in other languages, and `--solve-timeout` for slow QEMU challenges. The container and image are removed afterwards; pass `--keep` to leave them.

Other useful flags:

| Flag | Purpose |
|---|---|
| `--no-cache` | Disable the build cache. **Required for the last round before delivery** — a cached build reuses stale layers and database volumes, hiding broken schema SQL or mis-installed dependencies |
| `--ready-cmd CMD` | Run after the ports listen; the service is only ready when it exits 0. Needed for QEMU challenges, where an open port does not mean the guest has booted |
| `--ready-timeout N` | Seconds to wait for the readiness command |
| `--similarity` | Compare this batch's manuals for templated content (hints only, does not change the verdict). Off by default |
| `--expect-flag F` | Assert the solved value equals F; for attachment and static-flag challenges |
| `--no-flag-rotate` | Skip the flag-rotation re-check (for challenges a single solve leaves broken) |
| `--solve-timeout N` | Solver timeout; raise it for QEMU / LLM challenges |
| `--keep` | Keep the container and image afterwards |

Beyond running the challenge it also checks: the manual's filename, skeleton, 1.5 fields, duplicated sections and content borrowed from another challenge; whether `challenge.yaml` really parses; provenance values and name consistency; the delivery whitelist; secrets and customer PII; leftover flags in `src/` and attachments; hard links; whether `start.sh` writes the flag; whether the landing page is an error page or a placeholder; whether the page pulls from an external CDN; and whether `solve.py`'s imports resolve. Checks described as **hints** print a notice and do not change the verdict.

Challenges needing KVM or extra network capabilities get them via `--run-arg --device=/dev/kvm`. Attachment challenges have no test flag, so assert the solved value with `--expect-flag '<the value from manual 1.5>'`; static-flag challenges must produce the value baked into the image.

```text
== 构建镜像 (linux/amd64)
   完成，用时 16 秒
== 启动容器
   等待端口 5000 开始监听（最多 60 秒）
   容器运行中
== 写入测试 Flag 到 /flag
   回读一致（444 root:root）
== 探测端口 5000（本机 127.0.0.1:61197）
   HTTP 200
   动态 Flag 依赖：/bin/bash 存在
== 运行解题命令: python3 solve/solve.py
   拿到 Flag
== 复查：写入第二个测试 Flag，再解一次
   第二轮拿到新 Flag，程序按请求读取 Flag

== 结果: passed
```

For RDG challenges the last stage becomes a check verdict:

```text
== 阶段: handbook: passed provenance: passed delivery: passed build: passed startup: passed flag_write: skipped port: passed check_initial: ok: False
== 结果: passed
```

| Result | Exit code | Meaning |
|---|---|---|
| `argument error` | 2 | A flag is missing or non-numeric (`--port`, `--timeout`, …) |
| `passed` | 0 | Every check passed |
| `partial` | 3 | It runs, but some checks did not pass (leftover manual TODOs, a manual `docker run` line without `/start.sh`, no port declared); each one is listed |
| `failed` | 1 | Build failed, container exited, port bound to 127.0.0.1 only, flag not writable, image lacks `/bin/bash`, image `USER` cannot write the flag, the solver still returned the old flag after rotation, the solver did not get the flag or got it while the port was closed, the manual has the wrong filename, `challenge.yaml` does not parse, the delivery directory has entries outside the whitelist, or an RDG challenge is already fixed from the start |
| `environment_failed` | 4 | The host cannot run it (a binary crashes under amd64 emulation); the challenge itself may be fine. Re-run on native amd64 |

Port and flag path come from `challenge.yaml` by default. Override them with `--port` and `--flag-path`. See `verify.sh --help` for all options.

## Difficulty equivalence

When migrating old challenges, **restoring the original difficulty is the default action and needs no reminder.** The first step writes a difficulty baseline — vulnerability type, chain length, protections to bypass, **service topology**, **runtime versions** — and the challenge is restored to it.

When migrating an old challenge, missing material or a host that cannot run it is never a reason to downgrade. Each of these is a downgrade and must be cleared with the user first:

- Collapsing the service layer: replacing nginx + php-fpm from a compose file with `php:*-apache`, or keeping only one service
- Swapping a component: php-fpm for mod_php, MariaDB for SQLite, dropping the admin panel
- Bumping a runtime major version: PHP 5.6 → 7.x, Node 8 → 11, JDK 8 → 17
- Shortening the chain, dropping protections, substituting a reverse-engineered data structure, or rewriting the challenge into something simpler

When the platform only accepts a single container, the correct move is to **install every original service into that one image** (same config files, versions pinned) and have `start.sh` bring up the dependencies before `exec`-ing the main service. That is not a downgrade.

Never offer "keep the simplified version" as an option. State the reconstruction instead: "I reconstructed X from Y, Z is missing, pick A or B."

The `provenance` block in `challenge.yaml` records where the challenge came from and how much of it survived:

```yaml
provenance:
  status: original_adapter        # original_adapter / independent_completion / incomplete
  original_material: [源码, install.sql, docker-compose.yml]
  missing: [original database snapshot]
  preserved: [bug=front-end SQL injection, chain=3 steps, services=nginx+php-fpm+MariaDB, php=5.6]
  service_parity: original nginx, php-fpm and MariaDB all in one image, original config files kept
  simplified: []
  env_limited: ""
  verify: passed
```

An `incomplete` challenge is never written up as "verified". An `independent_completion` must say so in the manual — it is a rebuild, not a restoration. A non-empty `simplified` means the challenge has drifted from its original difficulty and the challenge author needs to hear about it separately. A passing verify only proves the container lifetime is sound, not that the difficulty matches. Attachment challenges have no `challenge.yaml`; record these fields in the delivery note.

`env_limited` is not a dumping ground. Before blaming "the emulator" or "the environment", reproduce it on native hardware and put both results in the delivery note.

## Flag contract

### Dynamic flags need `/bin/bash`

The platform writes a dynamic flag by **running an injected script with `/bin/bash`**: the author fills in a `flag_script` in the admin panel, the platform drops it into the container as `/changeflag.sh` and runs `/bin/bash /changeflag.sh`, retrying up to 30 times.

**If the image has no `/bin/bash`, the flag is never written**, and it fails silently — players get the placeholder value and the platform only reports "environment failed to start". Alpine-based images need an explicit `RUN apk add --no-cache bash`; distroless and scratch images can only use a static flag.

`verify.sh` probes for this after the build and reports `failed` when it is missing.
### The `flag_script` template

The script that writes the dynamic flag is entered by the author **in the platform's admin panel**, not shipped with the delivery. `$new_flag` must be kept — the platform substitutes the per-instance value.

```bash
#!/bin/bash
set -uo pipefail
# The platform has already substituted $new_flag with this instance's value.
printf '%s\n' "$new_flag" > /flag
chmod 444 /flag
```

Change the last two lines when the target path is not `/flag`; append your own commands when the flag must also reach a database, a config file or a QEMU rootfs. **Do not do slow work in this script** — the platform retries only when the MySQL socket is not ready yet (up to 30 attempts); a missing bash or a permission denial is abandoned on the first try.

Manual section 1.5 must quote this script verbatim so the author can paste it.

### When the image sets `USER`

The platform runs the injected script through `exec_run`, which **does not pass a user and inherits the image's `USER`**. If the Dockerfile has `USER 1000:1000` while the flag file is owned by root, the platform cannot write it. Either make the target file's owner follow `USER`, or `chown`/`sudo` inside `flag_script`. `verify.sh` also writes once as the image's `USER` and reports `failed` if that fails.


### flag.path

This has to be the file the program actually reads — open the source and find the line that reads the flag before filling the field in:

| Category | Usual path |
|---|---|
| Web / AI / Misc | `/flag` |
| Pwn | `/home/ctf/flag` (`root:ctf`, `440`) |
| Flag embedded in PHP | `/var/www/html/flag.php` |
| Database | Document the SQL that updates the flag |

That table lists common values, not defaults. When migrating a challenge from another platform (GZCTF, CTFd), `flag.path` must be decided **per challenge** — never filled with `/flag` by category or by batch.

Read the flag file on every request. If it is read once at startup and cached (a Python module-level variable, a Java `static` block, a module imported before `fork()`), the platform's new flag never shows up; `verify.sh` writes a second flag and solves again precisely to catch that.

**Static-flag challenges** (the platform does not write a flag, it only compares the submitted string) set `flag.mode: static` in `challenge.yaml` and write "platform overwrite: none, this is a static flag" in manual 1.5. Multi-part flags and where to keep the extra placeholder files: see [references/platform.md](src/CloverSec-CTF-Pack/references/platform.md).

## Layout

```text
src/CloverSec-CTF-Pack/
├── SKILL.md              # entry: author intent, difficulty baseline, question rules, output whitelist, workflow, severity, report discipline, pre-delivery checklist, flag, RDG
├── agents/openai.yaml    # name, default prompt, question and difficulty guidance for Codex
├── references/
│   ├── manual.md         # per-section manual guidance, the four source tiers, examples
│   ├── platform.md       # how the platform starts challenges, static flags, image tar formats, challenge.yaml and provenance
│   ├── dockerfiles.md    # Dockerfile / start.sh per language, legacy-builder compatibility, version pinning
│   ├── special.md        # multi-service, Bundle, Scenario, RDG/AWD, Linux-QEMU
│   └── batch.md          # batch delivery: batching, write ownership, subagent work orders, status file, handover
└── scripts/
    └── verify.sh         # local build and run check, plus manual, provenance, whitelist, flag rotation and RDG judgements
```

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

[MIT](LICENSE)
