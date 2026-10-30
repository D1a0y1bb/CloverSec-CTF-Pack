<p align="center">
  <img src=".github/assets/banner.svg" alt="CloverSec CTF Pack" width="860" />
</p>

<p align="center">
  <a href="https://github.com/D1a0y1bb/CloverSec-CTF-Pack/releases/latest"><img src="https://img.shields.io/github/v/release/D1a0y1bb/CloverSec-CTF-Pack?style=for-the-badge&color=2563eb&label=release" alt="Release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/D1a0y1bb/CloverSec-CTF-Pack?style=for-the-badge&color=16a34a" alt="License" /></a>
  <img src="https://img.shields.io/badge/Claude_Code_%C2%B7_Codex-skill-f59e0b?style=for-the-badge" alt="Claude Code · Codex" />
</p>

<p align="center">
  <strong>简体中文</strong> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="#安装">安装</a> ·
  <a href="#使用">使用</a> ·
  <a href="#交付目录">交付目录</a> ·
  <a href="#手册">手册</a> ·
  <a href="#本地验证">本地验证</a> ·
  <a href="#flag-约定">Flag 约定</a> ·
  <a href="#仓库结构">仓库结构</a>
</p>

---

面向 Agent 的四叶草安全 CTF 题目交付 Skill @CloverSecLabs

把题目源码、一段题目设计或者一个旧题目录交给 Claude Code / Codex，整理成能交付的题目包：容器题给出可构建的镜像目录并本地验证，附件题给出整理好的选手附件，RDG 防守题给出带判题脚本的加固环境，三类都带手册。

- **默认恢复原题难度**：开工第一步写难度基线（漏洞类型、链路、服务拓扑、运行时版本），默认原样恢复。合并服务层、升级运行时大版本、压缩链路、删防护都算降级，必须先问过用户。迁移旧题时这一步不用等提醒。
- 交付目录按 `题目类型-题目名称` 命名，类型取 Web、Pwn、Crypto、AI 等 20 种；多题交付分 `容器题/` 与 `附件题/` 两级。
- 源码、`Dockerfile`、`start.sh` 按内置范例编写，带中文注释，讲清漏洞点和不明显的配置。
- 容器题用 `verify.sh` 按平台的方式跑一遍：amd64 构建、`/start.sh` 启动、写入随机测试 Flag、探测端口，有 `solve/solve.py` 就运行它，必须拿到这个 Flag；再换一个 Flag 解第二次，抓"启动时把 Flag 读进内存"的题。
- 顺手检查手册文件名和章节、`docker run` 有没有带 `/start.sh`、交付目录有没有多余文件和 `.DS_Store`、`challenge.yaml` 能不能真解析。
- 手册写在 `README/`：事实部分填全，判断部分**优先从出题人材料搬运**，只有确实没有来源才留 `TODO` 并如实报告。
- `solve/`、`附件/`、`镜像/`、`last/` 都放在和 `src/` 同级的目录。
- 需要长期存档的题，按参考文档锁定镜像 digest、apt 源和依赖版本，上游更新后照样能 build。
- 多服务、Bundle、Scenario、RDG/AWD、Linux-QEMU 有单独的参考文档；一次处理 5 道以上时读批量交付那份。

## 安装

```bash
npx skills add D1a0y1bb/CloverSec-CTF-Pack -g -a claude-code -a codex
```

`-g` 装到用户目录 `~/.agents/skills/`，Claude Code 通过软链接读取；去掉 `-g` 装进当前项目。`-a` 指定装给哪些 Agent，可以写多个。

本机需要 Docker 和 `curl`。Apple Silicon 上按 amd64 构建会走模拟，比原生慢。

## 使用

在对话里点名 Skill，再给材料。Claude Code 用 `/cloversec-ctf-pack`，Codex 用 `$cloversec-ctf-pack`：

```text
/cloversec-ctf-pack 把 ./ssti-notes 做成平台题目。
Flask 写的 SSTI，flag 放 /flag，端口 5000。
```

材料可以是题目设计、只有源码的目录，或者带旧 Dockerfile 的历史题目。它先把材料读透，把题目类型、交付形态、要不要附件和镜像 tar 这些能从目录和源码里看出来的自己定下来，只把真正推不出来的拿来问——而且问之前先说明查到了什么，再用结构化提问（Codex 的 `request_user_input`、Claude Code 的 AskUserQuestion）给出直白选项和推荐项。缺端口、启动命令、Flag 路径这类会卡住构建的信息时不会自己猜着往下做。

难度不用提醒。它默认会去反推原题难度再动手；确实需要降级时，会先给出反推结论再问，不会拿"要不要保持现状"当选项。

## 交付目录

容器题：

```text
Web-残影/
├── README/
│   ├── Web-残影.md       # 手册，文件名同交付目录
│   └── assets/           # 手册里的截图
├── src/
│   ├── index.php
│   └── upload.php
├── Dockerfile
├── start.sh              # 平台入口，前台运行真实服务
├── challenge.yaml        # 端口、Flag 路径等平台字段
├── flag                  # 占位 Flag，平台启动后覆盖
├── solve/
│   └── solve.py          # 解题脚本，本地验证用，不进镜像
└── 附件/                 # 选手附件，需要时才有
```

纯附件题没有镜像相关文件，只有 `README/`、`src/`、`附件/`、`solve/`。`镜像/` 在需要导出镜像 tar 时才建。

交付目录是一份白名单：容器题只允许 `src/`、`Dockerfile`、`start.sh`、`challenge.yaml`、`flag`、`README/`、`solve/`，按需加 `附件/`、`镜像/`；RDG 题再加 `check/`、`changeflag.sh`、`ttyd` 这些题目真正运行需要的文件。`verify.sh`、`verify-report.json`、`*.verify.json`、`.DS_Store`、`__pycache__/` 一律不许留下，`verify.sh` 会扫出来。验证报告写到系统临时目录：

```bash
bash ~/.agents/skills/cloversec-ctf-pack/scripts/verify.sh ./ssti-notes --report "$(mktemp -d)/verify.json"
```

## 手册

手册写在 `README/<题目类型-题目名称>.md`，文件名必须和交付目录同名，截图放 `README/assets/`。章节顺序固定：题目名称、题目描述、题目难度、考察信息、旗帜信息、题目情况、部署方式、题目设计、解题步骤。

**Skill 只写它查得证的部分。** 九节分两类：

| 节 | 内容来源 | 内容 |
|---|---|---|
| 1.1 题目名称 | 查证 | 和目录名、`challenge.yaml` 对得上 |
| 1.3 题目难度 | 查证 | 材料里通常标了 |
| 1.5 旗帜信息 | 查证 | 路径、权限、读取时机、平台覆盖命令 |
| 1.6 题目情况 | 查证 | 端口、账号、后台地址、check 位置 |
| 1.7 部署方式 | 查证 | 构建、带 `/start.sh` 的启动、写 Flag、清理 |
| 1.2 题目描述 | **搬运优先** | 需要出题人的语气和意图 |
| 1.4 考察信息 | **搬运优先** | 需要真读懂题目 |
| 1.8 题目设计 | **搬运优先** | 需要理解设计动机 |
| 1.9 解题步骤 | **搬运优先** | 需要真打通链路 |

判断部分按三档处理：

1. **出题人材料**（赛事归档、出题人交付包、官方题解、旧题目录里的设计文档）直接搬进来整理，不留 TODO。
2. **外部 writeup / 战队 WP** 只能当线索，写进手册前必须在本次交付环境里复跑核对——注入点、参数形态、触发顺序、工具装法都可能和本题不一致。
3. **确实没有来源**才在该节正文写 `TODO(人工填写)`，并在交付说明里点名哪几节空着。

**不许编。**「考察 Web 请求分析、服务端输入处理」这类句子读起来像内容，实际什么也没说，还会把空位掩盖掉。

1.9 要求每条命令和 payload 形态能用本次交付的 `solve/solve.py` 复跑通过；对不上就改手册。

写作过程中可以在每节末尾放 `<!-- -->` 注释写指引，交付前全部删掉，`grep -c '<!--'` 必须是 `0`。

`verify.sh` 检查文件名、章节骨架、事实字段和启动命令，**不检查判断部分的内容**——脚本查不出内容真假，假装能查只会让人把"章节齐全"当成"手册写完"。有 TODO 残留时判 `partial`，这是正常结论，如实报告就行，不要为了跑到 `passed` 去编内容。

完整写法和范例见 [references/manual.md](src/CloverSec-CTF-Pack/references/manual.md)。不写"常见失败现象"一节。

## RDG 防守题

RDG 的判据不是"能不能拿到 Flag"，而是"漏洞还在不在"，交付物和验证方式都和普通题不同：

- 多一个 `check/` 目录（`check.sh` + `check.py` + `requirements.txt`），平台点"验证"时跑的就是它。调用方式 `./check.sh <IP> <PORT>`，返回 0 表示已修复、非 0 表示漏洞还在，输出里必须有 `ok: True/False` 或 `RESULT: PASS/FAIL` 判定行。
- 多一个 ttyd 服务，选手通过浏览器进容器改代码。
- 有些 RDG 题没有 Flag 合同：敏感目标就是题目自己配置里的固定内容，check 直接验证那个目标还能不能被读到。
- `verify.sh` 自动识别带 `check/` 的题目，跑 RDG 判定：初始环境必须报"有漏洞"才算题目状态正确，报"已修复"直接判 `failed`，那样选手没得打。返回非 0 却没有判定行的，当成判题脚本自己崩了，也判 `failed`。

## 本地验证

```bash
bash ~/.agents/skills/cloversec-ctf-pack/scripts/verify.sh ./ssti-notes
```

脚本按 `linux/amd64` 构建镜像，用 `/start.sh` 起容器，等端口真正开始监听，往 `flag.path` 写一个随机测试 Flag，再探测端口。目录里有 `solve/solve.py` 时自动运行它（从环境变量 `HOST`、`PORT` 读地址），输出里出现这个测试 Flag 才算通过；然后换一个 Flag 再解第二次，两次都拿到对应的值才通过，启动时把 Flag 读进内存的题会在这一步暴露。每次写入后最多等 15 秒，给同步循环留出生效时间；解一次就会打坏题目状态的题用 `--no-flag-rotate` 跳过。其他语言的解题脚本用 `--solve '<命令>'` 指定，QEMU 那类慢题用 `--solve-timeout` 调大超时。跑完删除容器和镜像，加 `--keep` 保留。

它还会顺手检查四件和运行无关、但最常被漏掉的事：手册文件名和章节是否齐全、`docker run` 命令有没有带 `/start.sh`、交付目录有没有多余文件和 `.DS_Store`、`challenge.yaml` 能不能被真正解析。需要 KVM 或额外网络能力的题，用 `--run-arg --device=/dev/kvm` 这类参数补进 `docker run`。附件题没有测试 Flag，用 `--expect-flag '<手册 1.5 里的值>'` 断言解出来的值真的对；静态 Flag 题默认要求解出镜像里那个值。

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
== 运行解题命令: python3 solve/solve.py
   拿到测试 Flag
== 复查：写入第二个测试 Flag，再解一次
   第二轮拿到新 Flag，程序按请求读取 Flag

== 结果: passed
```

RDG 题的输出换成 check 判定：

```text
== 阶段: handbook: passed provenance: passed delivery: passed build: passed startup: passed port: passed flag_write: skipped check_initial: ok: False
== 结果: passed
```

| 结果 | 退出码 | 含义 |
|---|---|---|
| `passed` | 0 | 全部检查通过 |
| `partial` | 3 | 能跑，但有检查项没通过（手册有 TODO、手册的 `docker run` 没带 `/start.sh`、没声明端口、目录有多余文件等），输出里逐条列出 |
| `failed` | 1 | 构建失败、容器退出、端口只监听 127.0.0.1、Flag 写不进去、换 Flag 后拿到旧值、解题拿不到 Flag、手册文件名不对、`challenge.yaml` 解析失败，或 RDG 初始环境就是修好的 |
| `environment_failed` | 4 | 本机跑不动（amd64 模拟下被调试的二进制崩溃等），题目本身没错。换原生 amd64 重跑 |

端口和 Flag 路径默认从 `challenge.yaml` 读取，也可以用 `--port`、`--flag-path` 指定。完整参数见 `verify.sh --help`。

## 难度等价

迁移旧题时，**恢复原题难度是默认动作，不需要用户提醒。** 开工第一步写难度基线：漏洞类型、链路几步、要绕过什么防护、**服务拓扑**、**运行时版本**。然后按基线原样恢复。

迁移旧题时，缺材料、本机跑不动，都不是把题目降级的理由。下面每一条都算降级，做了要先停下来问用户：

- 合并服务层：compose 里的 nginx + php-fpm 换成 `php:*-apache`，或只留一个服务
- 替换服务组件：php-fpm 换成 mod_php，MariaDB 换成 SQLite，admin-panel 删掉
- 升级运行时大版本：PHP 5.6 → 7.x，Node 8 → 11，JDK 8 → 17
- 压缩链路、删除防护、换掉需要反推的数据结构、换一个更简单的实现

平台只收单容器时，正确做法是**把原题每个服务原样装进同一个镜像**（沿用原配置文件、版本锁死），start.sh 先起依赖再 `exec` 主服务，这不算降级。

提问时不许拿"要不要保持现状"当选项。写法是："我反推出原题是 X（依据是 Y），缺 Z，需要你在 A / B 里选。"

`challenge.yaml` 里的 `provenance` 记录这道题的来源和恢复状态：

```yaml
provenance:
  status: original_adapter        # original_adapter / independent_completion / incomplete
  original_material: [源码, install.sql, docker-compose.yml]
  missing: [原数据库快照]
  preserved: [漏洞类型=前台 SQL 注入, 链路=3 步, 服务=nginx+php-fpm+MariaDB, PHP=5.6]
  service_parity: 原 compose 的 nginx、php-fpm、MariaDB 全部装进同一镜像，配置沿用原文件
  simplified: []
  env_limited: ""
  verify: passed
```

`incomplete` 的题不许写成"已验证通过"；`independent_completion` 必须在手册里写明这是独立补全、不是原题还原；`simplified` 有值时说明这道题已经偏离原题难度，要单独告诉出题人。verify 通过只说明容器生命周期正常，不等于题目难度等价。附件题没有 `challenge.yaml`，这些字段写进交付说明。

`env_limited` 不许当垃圾桶。把失败记成"模拟器/环境限制"之前，必须在原生架构上复现一次，两次结果都写进交付说明。

## Flag 约定

### 动态 Flag 必须有 `/bin/bash`

平台的动态 Flag 是**用 `/bin/bash` 执行一段注入脚本**的：出题人在后台填 `flag_script`，平台把它塞进容器叫 `/changeflag.sh`，然后 `/bin/bash /changeflag.sh` 执行。只有 MySQL socket 未就绪这类错误会重试（最多 30 次），缺 bash、权限拒绝第一次就放弃。

**镜像里没有 `/bin/bash`，Flag 就写不进去**，而且失败是静默的——选手拿到占位值，平台只提示"环境启动异常"。alpine 系镜像要显式 `RUN apk add --no-cache bash`；distroless / scratch 只能用静态 Flag。

`verify.sh` 构建后会探测这一项，缺了直接判 `failed`。

### flag.path

必须是**程序实际读取的那个文件**——先打开源码找到读 Flag 的那一行再填：

| 题型 | 常用路径 |
|---|---|
| Web / AI / Misc | `/flag` |
| Pwn | `/home/ctf/flag`（`root:ctf`，`440`） |
| PHP 嵌入 Flag | `/var/www/html/flag.php` |
| 数据库 | 在手册里写清更新 Flag 的 SQL |

这张表是"常见值"，不是"默认值"。迁移旧平台题（GZCTF、CTFd 等）时 `flag.path` 必须逐题判定，不许按题型或按批次一刀切。

程序要在每次请求时读取 Flag 文件。启动时读一次存进变量（Python 模块级变量、Java `static` 块、fork 前 import 的模块），平台换了 Flag 也不会生效；`verify.sh` 换第二个 Flag 再解一次就是为了抓这个。

平台写入还**晚于服务启动**（实测多数 1~4 秒，偶发 61 秒）。要把 Flag 搬进配置文件、数据库或 QEMU guest 的题，必须等"平台真的写完了"，不能只判文件存在——模板见 [references/special.md](src/CloverSec-CTF-Pack/references/special.md)。

`solve.py` 不许假设 Flag 的长度和字符集。真实踩过的坑：只认 `flag{` 前缀、39 字符因向下取整少一位、`&` 被 XML 转义成 `&amp;`。

**静态 Flag 题**（平台不写 Flag，只比对选手提交的字符串）在 `challenge.yaml` 里写 `flag.mode: static`，手册 1.5 写「平台覆盖方式：无，本题为静态 Flag」，并写明这个值从哪考证来的。占位值必须是明显的占位，不能是真实形态的值。多小问拼完整 Flag、多出来的占位文件放哪儿，见 [references/platform.md](src/CloverSec-CTF-Pack/references/platform.md)。

## 仓库结构

```text
src/CloverSec-CTF-Pack/
├── SKILL.md              # 入口：难度基线、提问规则、交付目录白名单、流程、自检清单、Flag、RDG
├── agents/openai.yaml    # Codex 里显示的名称、默认提示词、提问与难度约定
├── references/
│   ├── manual.md         # 手册逐节写法、判断部分的三档来源和范例
│   ├── platform.md       # 平台启动方式、静态 Flag、镜像 tar 格式、challenge.yaml 与 provenance
│   ├── dockerfiles.md    # 各语言 Dockerfile / start.sh 范例、旧构建器兼容、版本锁定
│   ├── special.md        # 多服务、Bundle、Scenario、RDG/AWD、Linux-QEMU
│   └── batch.md          # 批量交付：分批、写入所有权、子代理任务书、进度文件、交接
└── scripts/
    └── verify.sh         # 本地构建与运行验证，含手册、provenance、白名单、Flag 轮换和 RDG 判定
```

版本记录见 [CHANGELOG.md](CHANGELOG.md)。

## License

[MIT](LICENSE)
