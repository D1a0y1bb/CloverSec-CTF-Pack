# 更新日志

本项目的重要变更都会记录在本文件中。

## Unreleased

### 修复

- 手册 1.5、1.6 的事实字段改成只在本节正文里匹配。原来是对整份手册 grep，1.5 空着但 1.9 顺口提了一句"flag 文件位置"也能过，空着的节没人发现。
- 附件题手册的 1.6 不再要求写「端口 / 账号 / 地址」。附件题本来就没有这些字段，按 manual.md 的要求写清附件清单反而被判 `partial`。
- 附件题手册的 1.5 接受静态 Flag（「平台覆盖方式：无」）和 RDG 无 Flag 合同（敏感目标不是 `/flag`）两种写法，不再拿容器题的字段去卡。
- 手册有 TODO 时提示的节号按题型给。附件题的题目设计和解题步骤顺延成 1.7、1.8，原来写死成 1.8、1.9。
- `NO_FLAG_CONTRACT` 改成「challenge.yaml 没声明 **且** 镜像里没有占位 Flag」才成立。原来缺 `challenge.yaml` 就判没有合同，镜像里明明 `COPY flag` 了还提示"镜像里也没有占位 Flag 文件"。
- `--port` 非数字时直接退出码 2。原来会带着这个值去等端口，白等到超时才报错。
- `--report` 的帮助文字改成「不给就不写」，和实际行为一致。
- `start.sh` 静态检查补上 `exec`/`wait`：既没有 `exec` 也没有 `wait` 时报 `partial`，注释里写了不算。
- `verify.sh` 改用 `docker buildx build --load` 构建，和手册里让用户写的那条命令一致；只有经典构建器时退回 `docker build`。

### 变更

- `SKILL.md` 自检清单第 11 条去掉 `--chown`。`dockerfiles.md` 写明 `COPY --chown` 经典构建器也支持，两处原来互相矛盾。
- `SKILL.md` 自检清单第 12 条补上「多服务后台起主服务后 wait」，并写清 `verify.sh` 对第 3、4、5、9、12、14 条的实际覆盖范围，第 10、11、13 条靠人读。
- `allowed-tools` 加回 `Task` 和 `AskUserQuestion`。跳过提问规则要在 Claude Code 里用 AskUserQuestion，批量交付要派子 Agent，原来的列表把这两样排除在外。
- `SKILL.md` 写明白名单同时接受 `last/` 和 `lasted/`，和 `verify.sh` 一致。

### CI

- 新增容器题静态检查回归 9 项：手册事实字段只在节内匹配、附件题 1.6 不要求端口、`start.sh` 的 `exec`/`wait`、`COPY .` 拦截、CRLF、缺 shebang、手册文件名、`--port` 非数字。
- 新增 VERSION 与 CHANGELOG 最新条目一致性检查；打 tag 时再检查 tag 名和 VERSION 一致。

## v6.3.0 - 2026-10-13

### 变更

- 迁移旧题时默认反推原题难度并原样恢复，开工第一步写难度基线：漏洞类型、链路、服务拓扑、运行时版本。从题目设计出新题时，基线就是设计稿。
- 降级清单改成表格，补上服务层替换：nginx+php-fpm 换成 `php:*-apache`、换数据库、升级运行时大版本都要先问用户。
- 平台只收单容器时，把原题每个服务原样装进同一镜像，新增 `provenance.service_parity` 记录逐服务对照。
- 提问时先给反推结论再问缺口，不拿"要不要保持现状"当选项。
- 手册判断部分改为搬运优先：出题人材料直接搬运；外部 writeup 只当线索，写进手册前要在本次环境复跑核对；没有来源才在正文写 `TODO(人工填写)`。
- `TODO(人工填写)` 不再放进 HTML 注释，写指引的注释交付前全部删掉。
- 1.9 解题步骤要求能用本次的 `solve/solve.py` 复跑通过。
- 容器题和附件题的判定给出四条优先级规则，不再只看 README 里有没有在线地址。
- 多题交付分 `容器题/`、`附件题/` 两级，根 `README.md` 只做索引；新增删除题目前后的引用检查。
- 新增 15 条交付前自检清单。
- 新增静态 Flag 题（`flag.mode: static`）的写法；`flag.path` 逐题判定，不按题型或批次一刀切。
- 附件题没有 `challenge.yaml`，provenance 写进交付说明；去掉 `attachment_only` 取值。
- 新增 `references/batch.md`：分批、一个目录一个写入者、子 Agent 任务书和回报格式、进度文件、交接、远程机器共用资源。
- `references/dockerfiles.md` 新增兼容旧构建器和解释器大版本两节。
- `references/special.md` 重写多服务一节，Linux-QEMU 补 Flag 同步校验清单。
- SKILL.md 补回 verify.sh 的跑法和各结论的处理方式；去掉与 references 重复的 Dockerfile 范例。
- `agents/openai.yaml` 的描述和指引同步难度恢复。

### verify.sh

- RDG 判题脚本返回 126/127，或返回非 0 但输出里没有 `ok: False` / `RESULT: FAIL` 判定行时判 `failed`，不再当成"漏洞还在"。
- 附件题手册按八节顺延写时不再误判缺 1.9。
- 手册里用反斜杠续行的多行 `docker run` 不再误判没带 `/start.sh`。
- `challenge.yaml` 用 `yaml.safe_load` 解析，语法错误判 `failed`；provenance、`flag.mode`、`check.path` 放在顶层或 `challenge:` 下都能读到，没有 PyYAML 时 `flag.mode` 和 `check.path` 退回文本匹配。
- 写入 Flag 后换第二个 Flag 再解一次，拿到旧值判 `failed`；每次写入后最多等 15 秒，`--no-flag-rotate` 跳过。
- 静态 Flag 题要求解题输出里出现镜像里 `flag.path` 的值，或 `--expect-flag` 给的值。
- 附件题解题也按 `--solve-timeout` 超时，支持 `--solve`。
- 手册有 `TODO(人工填写)` 时判 `partial`。
- 递归检查 `.DS_Store`、`__pycache__` 等垃圾文件，与多余文件同时报出；`_*` 内部工作文件和根目录 `README.md` 判 `failed`。
- `start.sh` 里有 `GZCTF_FLAG` / `DASFLAG` 兼容段报 `partial`；`solve.py` 引用第三方库但没写 `pip install` 报 `partial`。
- 新增 `--solve-timeout`、`--run-arg`、`--expect-flag`、`--no-flag-rotate`。
- 修复 `cleanup: command not found`、非数字 `--timeout` 死等、`environment_failed` 覆盖 `failed`、`--report` 遇到反斜杠写出非法 JSON、`COPY --chown=... flag` 识别不到占位 Flag。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- CI 附件题回归 7 项本地跑通：八节顺延手册、`--expect-flag` 不一致、手册 TODO、内部工作文件、非数字 `--timeout`、JSON 报告、解题超时。
- 容器题实测：每次请求读 Flag 的题 passed；启动时缓存和第一次请求时缓存的题 failed；同步循环 6 秒一次的题 passed；静态 Flag 题 passed；中文目录名 passed；RDG 判定行正常且输出带 not found 的题 passed，check.py 缺依赖崩掉的题 failed；去掉 PyYAML 后静态 Flag 题和 RDG 题结论不变。


## v6.2.1 - 2026-10-08

### 变更

- 提问顺序改回「先查明白，再问剩下的」：原来写成「第一步就是提问」，模型会没读材料就抛出一串泛泛的问题（「这几道题按什么形态交付」「要不要选手附件」），把本该自己判断的功课推给用户。现在改成先读材料，把能从目录和源码里看出来的自己定，只问真推不出来的。
- 提问时要先说明「查到了什么」再问缺口，用户一眼能看出做了功课。
- 新增「这些问法不成立」一节，把没读材料就会问出的问题直接列出来。
- 「先问清楚这几件事」一节并入「交付目录名」，避免两节自相矛盾。
- 流程清单重排：读材料 → 从材料定交付形状 → 判断 provenance → 只问推不出来的。
- `agents/openai.yaml` 的 `ask_first` 改为 `false`，指引同步改成「先读材料再提问」。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告（本次只改文档，未动脚本逻辑）。


## v6.2.0 - 2026-10-08

### 变更

- **手册改成"只填事实 + 留空给人"。** 九节分两类：1.1 题目名称、1.3 题目难度、1.5 旗帜信息、1.6 题目情况、1.7 部署方式由 Skill 填（这几项能从源码和配置查证）；1.2 题目描述、1.4 考察信息、1.8 题目设计、1.9 解题步骤留 `<!-- TODO(人工填写) -->` 给人工写。
- 明确禁止编造判断部分：占位句（"考察 Web 请求分析、服务端输入处理"）、把问题退回来的句子（"具体漏洞点以 src/ 中的原始实现为准"）、凑字数的过程说明（"复现完成判据"）都算编造。原材料里本来就有手册的，判断部分直接搬运整理，不留 TODO。
- 1.5 旗帜信息改成「字段：值」平铺格式，一行一个字段，不用项目符号、不套代码块。
- `verify.sh` 的手册检查重写：不再强制判断部分写满，只查文件名、章节骨架、事实字段、`/start.sh` 启动命令和"常见失败现象"残留。有 TODO 残留时报 `handbook: todo: N` 并如实提示还缺哪几节，**不再判失败**。
- 每节末尾放 `<!-- -->` 写指引，渲染看不见、源文件可见，交付前删除。
- 提问改成流程的第一个节点：新增「第一步就是提问，不是动手」一节，列清开工前必须问的四项和过程中必须停下来问的情形，并给出动手前的自查问题。
- `agents/openai.yaml` 补 `ask_first` 和提问指引。
- `verify.sh` 新增 `provenance` 检查：`status: pending` 或 `verify` 为空判 `failed`；老题没有这个字段时不报。
- README 中英文同步更新手册章节的说明。

### 验证

- 回归 11 项全过：正常题、中文目录名、`COPY .`、CRLF、缺 shebang、无手册、手册名错、交付目录脏、无 solve.py、Flag 缓存、手册事实字段缺失。
- 手册检查五种情况：事实全填 + 4 处 TODO → `passed` 加提示；TODO 全填完 → `passed` 无提示；事实字段缺失 → `partial`；缺章节 → `failed`；手册名错 → `failed`。
- `provenance` 四种情况：无字段 → `passed`（老题）；`status: pending` → `failed`；`verify` 为空 → `failed`；完整 → `passed`。
- `shellcheck -S warning` 无警告，`bash -n` 通过。


## v6.1.2 - 2026-10-07

### 变更

- 修复 `verify.sh` 里嵌套双引号触发 shellcheck SC2140 导致 CI 失败的问题。
- `verify.sh` 参数解析改用 `if` 分支，避免 `A && B || C` 在赋值成功时仍可能执行 usage。
- `verify.sh` 修掉一处变量名紧挨全角括号的写法（bash 3.2 下会把中文字节当成变量名的一部分，报 `unbound variable`）。
- `verify.sh` 新增 RDG 题 `check.sh` 执行位检查：没有 `+x` 时平台按 `./check.sh` 调用会报 `Permission denied`，返回码非 0 恰好被解读成「有漏洞」，配置错误被静默吞掉，现在单独报出来。
- `verify.sh` 新增 RDG 题解题验证：题目有 `solve/solve.py` 时顺手跑一遍，拿到测试 Flag 记 `solve: passed`，确认漏洞链真的能打通（check 只证明漏洞存在）。
- 交付目录白名单里的 `last*` 收紧为 `last|lasted`，避免误放行同类前缀的无关目录。
- `SKILL.md` 新增「写 shell 时的两个坑」：变量名别紧挨全角字符、`check.sh` 要有执行位。

### 验证

- `shellcheck -S warning` 无警告，`bash -n` 通过（此前 CI 挂在 SC2140）。
- 回归 10 项全过：正常题、中文目录名、`COPY .`、CRLF、缺 shebang、无手册、手册名错、交付目录脏、无 solve.py、重复跑。
- RDG 三种情况：`check.sh` 可执行且 solve 拿得到 Flag → `passed`；`check.sh` 缺执行位 → `failed`；check 通过但 solve 拿不到 Flag → `passed` 加提示。



## v6.1.0 - 2026-10-07

### 变更

- 手册要求大幅加厚，`references/manual.md` 重写：逐节给出必填项和范例，1.2 题目描述、1.5 旗帜信息、1.7 部署方式、1.9 解题步骤四节按交付标准写死。
- 手册文件名强制为 `README/<题目类型-题目名称>.md`，和交付目录同名，不再允许 `题目手册.md` 这类写法。
- `verify.sh` 新增手册检查：文件名、章节骨架、`docker run` 是否带 `/start.sh`、有没有"常见失败现象"这一节。
- 1.7 部署方式改为八项硬性清单，明确要求启动命令必须带 `/start.sh`，并补上镜像 tar 导入、端口调整后的同步位置。
- 1.9 解题步骤要求给出可直接复制的命令和 payload、预期输出、截图位置。
- 手册不再写"常见失败现象"一节。
- 1.2 题目描述要求写得风趣有悬念，禁止泄漏技术栈、漏洞类型、路径和函数名。
- 新增"遇到拿不准的先问用户"一节：影响交付形状的选择、材料缺关键事实、需要重新设计题目、多个合理方案、任何打算降级处理的地方，都要用 `request_user_input` 或 AskUserQuestion 给出直白选项后再动手。
- 新增"交付目录白名单"一节：`verify.sh`、`verify-report.json`、`*.verify.json`、`.DS_Store`、`__pycache__/` 等一律不许留在交付目录；`verify.sh` 会扫描并报出来，报告类残留直接判 `failed`。
- `verify.sh --report` 的路径落在交付目录里时拒绝执行，报告改写到系统临时目录。
- 新增"难度等价：不许降级兜底"一节：环境跑不动、依赖拉不下来都不是把题目换成简化变体的理由；确实要改必须问用户，并在 `provenance` 里写清简化边界。
- 新增 `challenge.yaml` 的 `provenance` 字段：`status`（`original_adapter` / `independent_completion` / `incomplete` / `attachment_only`）、`original_material`、`missing`、`preserved`、`simplified`、`env_limited`、`verify`。`incomplete` 不许写成"已验证通过"。
- 新增 RDG 专用验证模式：`verify.sh` 识别 `check/check.sh` 或 `challenge.yaml` 的 `check.enabled`，跑判题脚本判定初始环境必须"有漏洞"。初始环境报"已修复"直接判 `failed`。新增 `--check`、`--rdg` 参数。
- 支持没有 Flag 合同的 RDG 题：`flag_write` 记为 `skipped`，判据交给 check 脚本。
- `references/special.md` 的 RDG 一节扩写：交付形态、check 脚本契约（调用方式、返回码、`ok: True/False` 输出、四类检测点）、有无 Flag 合同两种写法、ttyd 启动模板、手册重点。
- Dockerfile 中文注释改为硬性要求，`SKILL.md` 给出带注释的完整范例。
- `references/platform.md` 新增 `provenance` 和 RDG 字段说明。
- 交付目录树补上 `check/`、`changeflag.sh`、`ttyd` 等 RDG 特有文件。
- `agents/openai.yaml` 补上 `request_user_input` 的提问约定。

### 验证

- 手册检查：文件名不对、缺章节、有常见失败现象、`docker run` 没带 `/start.sh` 四种情况逐条测过，都能报出来。
- 交付目录检查：`verify-report.json` 和 `verify.sh` 残留判 `failed`；`--report` 写进交付目录时退出码 2 并给出正确写法。
- RDG 判定：真实 RDG 题（`RDG-某企业官网信息系统`，DedeCMS + MariaDB + ttyd）跑通，初始环境 check 返回 `RESULT: FAIL` 判为符合预期；初始环境返回 `ok: True` 的反向用例判 `failed`；无 Flag 合同的 RDG 题 `flag_write` 正确记为 `skipped`。
- 普通题回归：完整合格题 `passed`（退出码 0），中文目录名、`COPY .`、CRLF、缺 shebang、Flag 缓存等原有检查未受影响。

## v6.0.0 - 2026-10-07

### 变更

- 改名 CloverSec CTF Pack，Skill 名 `cloversec-ctf-pack`，源码目录 `src/CloverSec-CTF-Pack/`，仓库改为 `D1a0y1bb/CloverSec-CTF-Pack`。
- 交付目录按 `题目类型-题目名称` 命名，类型取 Web、Pwn、Crypto、AI 等 20 种；材料不全时先问清类型、名称、容器题还是附件题、要不要附件和镜像 tar。
- 新增 `README/` 手册：`README/<题目类型-题目名称>.md` 加 `assets/`，章节顺序固定，格式见 `references/manual.md`。
- 新增纯附件题支持：不生成 Dockerfile、start.sh、challenge.yaml、flag，有出题源码就整理成 `src/`，选手文件放同级的 `附件/`；`verify.sh` 会跑 `solve/solve.py` 并要求输出里出现 Flag。
- 新增 `附件/` 和 `镜像/` 两个可选目录，默认都不生成。
- `verify.sh` 每个阶段单独给结论并汇总成一行，例如 `build: passed  startup: passed  port: passed  flag_write: passed  solve: passed`。
- `verify.sh` 新增 `environment_failed`（退出码 4），把本机模拟运行导致的解题崩溃和题目自身失败分开。
- `verify.sh` 新增 `solve: missing`，没有解题脚本时明确说明只验证了容器能跑。
- `verify.sh` 支持 `verification.solve_probe.path` 指定 HTTP 探测路径。
- `verify.sh` 拦下所有 `COPY .`：它会把 `solve/`、`README/`、`附件/` 打进镜像并改变目录结构。
- `verify.sh` 新增 `--report PATH` 输出 JSON 报告，`--keep` 时打印清理命令。
- 没有 Flag 合同（`challenge.yaml` 缺 `flag:`，镜像里没有占位 Flag）时 `flag_write` 记为 `partial`，不当成适配失败。
- `references/dockerfiles.md` 新增：旧版本运行时的归档 apt 源、migrate 时不要误删题解依赖、Pwn 免 PTY 的 Python 标准库转发、chroot 最小依赖清单、交付前文件 SHA256 校验。
- `references/special.md` 新增：CMS 老框架缺数据库快照、AI 题本地模型与离线权重、设计不完整的题（恢复与补全区分）。
- SKILL.md 新增出题授权说明、Pwn 偏移不要写死、Flag 同步循环、镜像体积要求。

### 验证

- 19 个测试题全量回归通过：容器题正常流程、中文目录名、无 solve.py、Pwn xinetd/socat、Flag 缓存、只监听回环、CRLF、启动即退出、`COPY .` 泄露（两种）、缺 shebang、自定义 ENTRYPOINT、模拟器环境失败、缺 Flag 合同、附件题三种、空附件、路径不存在。
- 退出码与阶段结论逐一核对：passed 0、failed 1、参数错误 2、partial 3、environment_failed 4。
- shellcheck `-S warning` 通过。

## v5.1.0 - 2026-10-07

### 变更

- 交付目录新增 `solve/solve.py`，约定从 `HOST`、`PORT`、`PORT_<容器端口>` 读地址，打印 Flag，拿到时返回 0。`verify.sh` 发现它就自动运行，输出里必须出现随机测试 Flag。
- 交付目录去掉 `.dockerignore`，Dockerfile 只 `COPY` 具体路径。
- `verify.sh`：start.sh 缺 shebang 改为 failed；有 `solve/` 时 Dockerfile 用 `COPY .` 判为 failed；自定义 `ENTRYPOINT` 改为 partial；解题命令可用 `PORT_<容器端口>` 访问每个端口；写入 Flag 后等 2 秒再解题，给同步循环留时间。
- `special.md` 新增多服务 start.sh 模板：依赖就绪等待、数据初始化、日志并入 stdout、Flag 同步进数据库、转发 TERM 优雅退出。
- `dockerfiles.md` 新增从旧镜像或 rootfs 查运行时版本的命令，SKILL.md 要求在 Dockerfile 里锁定并注释来源。

### 验证

- 本地测试题：多端口 + 自动 solve.py、`COPY .` 泄露、缺 shebang、MariaDB + 主服务 + Flag 同步，结果和退出码符合预期；多服务模板 `docker stop` 2 秒内退出。
- shellcheck `-S warning` 通过。

## v5.0.1 - 2026-10-06

### 修复

- `verify.sh` 在 Docker Desktop 上把没有监听的端口报成“TCP 可连通”，改为读取容器内 `/proc/net/tcp` 判断。
- `verify.sh` 对中文目录名和 `.` 生成了非法镜像 tag，导致构建失败。
- `verify.sh` 无论结果都返回 0，改为 passed 0、failed 1、partial 3。
- `verify.sh` 只读第一个端口，`flag.path` 可能读到其他配置块里的 `path`。
- Pwn 范例的 socat 带 `pty`，会改写 payload 里的 `0x7f`、`0x03` 等字节；Flag 属主是 `ctf:ctf`，选手能改写 Flag。改为不加 `pty`、Flag 属主 `root:ctf`、权限 `440`，并且不在镜像里重新编译二进制。

### 变更

- `verify.sh` 按 `linux/amd64` 构建，等端口真正开始监听再探测，端口只绑定 127.0.0.1。
- `verify.sh` 新增 `--solve`：运行解题命令，输出里必须出现随机测试 Flag，能发现启动时缓存 Flag 的问题。
- `verify.sh` 新增检查：start.sh 的 CRLF 换行、服务只监听 127.0.0.1、容器启动后退出、PID 1 仍是 start.sh、`ENTRYPOINT` 吞掉 `/start.sh`。
- SKILL.md 改为清单式流程，要求跑到 `passed`；`description` 补充触发场景；删除不起限制作用的 `allowed-tools`。
- start.sh 的 `tail -f` 保活从“错误”改为“能跑但不推荐”，并写明风险。
- `platform.md` 新增平台执行的写入命令、环境变量传 Flag（`GZCTF_FLAG`、`DASFLAG`、`FLAG`）的处理、`docker save` 与 `docker export` 两种镜像 tar 的差异。
- `dockerfiles.md` 新增 xinetd 写法、国内构建与 CRLF 说明，加目录；静态题补 start.sh；删除范例里的 `# syntax=` 行。
- `special.md` 补充数据库就绪等待的写法。
- 新增 `agents/openai.yaml`，设置 Codex 里的显示名称和默认提示词。
- 删除 `legacy/`，`special.md` 中的旧文件路径改为 v3.0.1 链接；重写 README，新增英文版。

### 验证

- 9 个测试题覆盖正常 Web、Flag 缓存、只监听回环、CRLF、启动即退出、`tail -f` 保活、无端口、`ENTRYPOINT`、Pwn，`verify.sh` 结果和退出码均符合预期，macOS 自带 bash 3.2 下运行正常。
- socat Pwn 范例实测：`0x7f`、`0x03` 原样送达，ctf 用户能读 Flag。

## v5.0.0 - 2026-10-06

### 变更

- Skill 本体只保留 `SKILL.md`、`references/platform.md`、`references/dockerfiles.md`、`references/special.md` 和 `scripts/verify.sh`。
- 交付文件改由模型参照范例编写，`render.py`、`ctfctl.py` 和模板不再参与默认流程。
- `references/dockerfiles.md` 提供 Python、Node、PHP、PHP-FPM、Java、静态页面、C/Pwn 范例，以及镜像 digest、snapshot 源、apt/PECL 版本锁定方法。
- `references/platform.md` 记录平台启动方式、常用 Flag 路径和 Flag 缓存问题。
- 新增 `scripts/verify.sh`，在本机构建镜像、启动容器、写入并回读 Flag、探测端口。
- 精简 `description`。
- 旧渲染器、模板、示例、文档和仓库发布脚本移入 `legacy/`。
- CI 只保留 `verify.sh` 语法检查和 Skill 发现。

### 验证

- Flask SSTI 和 Ubuntu + socat 栈溢出两道测试题经 `verify.sh` 构建、启动、Flag 回读和端口探测通过。

## v3.0.1 - 2026-10-06

### 修复

- 修复 direct-exec 清理只删除 `changeflag.sh` 文件、但遗漏 Dockerfile `COPY` 或 `chmod` 引用的问题。
- 迁移前临时提升只读入口文件的写权限，避免历史题目 scaffold 因复制文件权限失败。
- 为 scaffold 写入完成状态；`package` 拒绝未完成目录，并将 attachment-only 归档标记为 `partial`。
- `inspect` 输出高级输入的后续入口，attachment-only 输出保留 `challenge.yaml`。
- `verify` 真实检查 HTTP 响应文本、TCP banner 和 `container_exec`，并在启动竞态时重试 HTTP/TCP probe。
- Python 审计递归识别源码目录中的 `requirements.txt` 等嵌套依赖文件。
- 更新 Build_test 预期，移除 direct-exec 迁移后仍要求 `changeflag.sh` 的过期失败条件。

### 验证

- `ctfctl_v3_test` 8 项通过。
- Build_test 8 个用例通过。
- 真实 Minesweeper 和 Pwn-Boundary 源码完成 clean、static validate、Docker build、container verify 和 package。
- 独立 Codex 子代理完成 Python IDOR 题目的真实构建、HTTP probe 重试、动态 Flag 攻击和清理验收。

## v3.0.0 - 2026-10-06

### 变更

- 重定义默认产品为“题目想法或半成品源码 → 干净、易读、可构建、可验证的单服务题目目录”。
- 新增统一 `ctfctl.py build` 入口，默认链路收敛为 `inspect → scaffold → build → verify → package`。
- `clean` 模式移除未被运行入口引用的 compose、停止脚本、作者工具和旧 helper，保留真实运行源码。
- 输入只有 Dockerfile 和启动脚本时，自动生成最小 `challenge.yaml`，不再交付缺少平台合同的目录。
- `verify` 改为等待容器状态，支持多端口、声明的 solve probe 和可选 `smoke_assert.sh`。
- 非 direct-exec Flag 模式未执行题目专用更新命令时，只报告 `not_reproduced` 或 `partial`，不再误报通过。
- 重写 Skill 入口，普通题目不再加载高级模式和仓库维护流程，保留用户原有 description 的职责范围。

### 验证

- 新增 `tests/ctfctl_v3_test.py`，覆盖无 challenge.yaml 生成合同和 clean 辅助文件清理。
- 完成 Skill 官方快速校验、文档治理、源码回归和真实 Docker 题目验证。

## v2.2.0-r12 - 2026-10-06

### 变更

- 将 Skill 主入口收敛为普通题目的产品合同：想法或半成品源码整理为干净、可读、可构建、可验证的题目目录。
- 新增 `ctfctl.py inspect`、`scaffold --profile clean` 默认链路，保留 `audit`、`prepare` 兼容别名。
- `clean` profile 默认生成 `src/`、最小 Dockerfile、最小 `start.sh`、`challenge.yaml` 和 `.dockerignore`，不生成根目录机器报告。
- 将审计、验证和归档清单写入 `.ctfbuild/`，并保存结构化 `audit.json`、`verify.json` 和 `delivery-manifest.json`。
- 普通 direct-exec 输入会清理旧 `changeflag.sh` 引用；文件替换题和数据库题只在 `.ctfbuild/flag-update.md` 保存真实业务更新命令。
- 将 Scenario、Bundle、RDG/SecOps、Linux-QEMU 和镜像归档入口移到按需路由文档，减少普通题目的默认上下文。

### 验证

- `scripts/check_fast.sh` 通过。
- `skill-creator` 官方快速校验通过。
- 39 个示例和场景回归通过，0 个失败。
- Golden snapshot 通过，clean/preserve/legacy 和 direct-exec helper 清理行为通过。
- `python-flask-basic` 真实 Docker build/run、direct-exec Flag 回读和 HTTP 入口探测通过。

## v2.2.0-r11 - 2026-10-05

### 变更

- 普通题目默认使用 `direct-exec-v1`，平台通过 `docker exec` 写入 `challenge.flag.path`，不再生成无用的 `changeflag.sh`。
- 文件替换题和数据库题使用 `flag.mode=file_replace|database`，并在 `flag.update` 中记录真实更新命令、等待条件和业务路径。
- 新增 `ctfctl.py audit/prepare/verify/package`，统一输入审计、干净交付目录、启动合同检查、真实 Docker 验证和归档打包。
- `render.py` 默认使用 minimal 输出，移除 Dockerfile、start.sh 和 changeflag 模板中的叙述性废话；legacy helper 与 Linux-QEMU 仍可显式生成 `changeflag.sh`。
- 示例、平台契约、迁移文档和三种语言 README 同步 direct-exec、legacy-helper、Linux-QEMU 三类合同。

### 验证

- `scripts/release_build.sh --with-smoke` 通过。
- 39 个示例和场景通过真实回归，4 个仅结构校验场景按设计跳过运行构建，0 个失败。
- `skill-creator` 官方快速校验通过，文档治理检查通过，发布 zip、SBOM 和依赖清单生成成功。

## v2.2.0-r10 - 2026-06-23

### 修复

- `workflow.py auto-render` 和 `workflow.py validate` 共用 validate 命令构造函数，避免两处路径处理不一致。
- Windows 通过 WSL `bash.exe` 执行 `validate.sh` 时，`validate.sh`、输出 JSON、`Dockerfile`、`start.sh`、`challenge.yaml` 和项目目录会转换成 `/mnt/...` 路径。
- 非 WSL bash 保持原有命令行为，不改变 macOS/Linux 与 Git Bash 路径处理。

### 验证

- 插件仓库新增纯函数回归测试覆盖 Windows/WSL 路径转换。
- 发布前执行 `check_fast.sh`、release build、tag CI 和 release 资产复核。

## v2.2.0-r9 - 2026-06-22

### 变更

- 以 CloverSec CTF For Example 插件内置 Dockerizer 为准，同步 `SKILL.md` 与 `agents/openai.yaml`。独立 GitHub skill、插件内置 skill、本机安装 skill 的运行入口说明现在一致。
- 入口默认推荐 `workflow.py auto-render`：普通题目直接生成平台交付文件并执行静态校验；真实启动未知容器、高权限运行或业务取舍不清楚时再停止询问。
- 为了和插件内置 skill 完整一致，Java JAR 示例的 `build/` 文件纳入独立仓库版本管理。

### 验证

- 发布前执行 `check_fast.sh`、`release_build.sh --with-smoke` 和 tag CI。

## v2.2.0-r8 - 2026-06-22

### 修复

- Python Web 源码审计增加本地 import、Flask template、依赖声明、启动命令和 `FLAG`/`CTF_FLAG` 环境变量线索检查；存在阻断项时 `workflow.py auto-render` 不再直接生成交付物。
- 所有核心渲染输出统一写 LF 换行，避免 Windows CRLF 进入 `Dockerfile`、`start.sh`、`changeflag.sh`、`flag` 和派生配置文件。
- `validate.sh` 增加 CRLF 明确报错，并把动态 flag 验证扩展为位置参数、`FLAG`、`CTF_FLAG` 三种调用方式。
- `workflow.py auto-render` 改为执行动态 flag 校验，避免只做静态检查后误判交付物可用。

### 验证

- `scripts/check_fast.sh` 通过。
- 插件仓库新增的 Dockerizer 回归测试覆盖 proposal 阻断、LF 输出、CRLF 报错和三种动态 flag 输入。

## v2.2.0-r7 - 2026-06-13

### 修复

- 按官方 Skill 校验规则移除非标准顶层字段，把 `challenge.yaml` 与 `--project-dir` 的输入提示移入 `SKILL.md` 正文和 `agents/openai.yaml` 默认提示。
- 保留 Docker artifact 工作流，继续输出 `environment`、`docker_artifacts` 与 `xlsx_fields`，用于归档阶段生成 amd64 镜像包、导出 tar 包和表格字段。
- 删除已不适合随 Git 管理的 Linux-QEMU 示例 `initrd.img`，并通过 `.gitignore` 阻止该大文件再次进入源码提交。

### 验证

- 本版本发布前执行官方 Skill 校验、发布脚本校验与 release build。

## v2.2.0-r6 - 2026-06-11

### 修复

- 修复 `smoke_test.sh` 在 macOS 上生成 `solve_probe` 临时 YAML 时可能得到字面量 `XXXXXX.yaml` 文件名的问题，改为使用随机临时目录。
- `derive_config.py` 保证 `gates` 与 `manual_required` 一致；已有 `challenge.yaml` 明确提供 stack、端口和启动命令时，关闭对应确认 gate。
- `audit_input.py` 区分明确配置和自动探测：显式 `challenge.stack` 优先，自动探测结果作为 `detected_stack_hint` 复核提示，不再覆盖明确配置。
- Pwn 输入新增源码 flag 路径提示，识别 `flag0`、`flag1`、`flag.txt`、`/home/ctf/flag*` 等线索，并要求确认 `challenge.flag.sync_paths`。
- `workflow.py` 新增 `reviewed-render --reason "..."`，用于低风险、明确配置或已接受 proposal 的快速审查渲染；mixed/dirty/high_risk 输入仍会被 gate 阻断。
- 新增 `src/CloverSec-CTF-Build-Dockerizer/docs/solve_probe_recipes.md`，提供 HTTP、TCP、container_exec、Pwn nc 和动态 flag 路径的业务断言片段。

### 验证

- `check_fast.sh` 通过；`validate_examples.sh` 通过，39 通过、0 失败、0 跳过。
- `smoke_test.sh --case python-flask-basic` 通过，`challenge.verification.solve_probe` 使用随机临时目录中的 `solve_probe.yaml` 执行成功。
- `release_build.sh --with-smoke` 通过，`dist/CloverSec-CTF-Build-Dockerizer-v2.2.0-r6.release-status.json` 显示 `release_ready=true`。
- 定向行为验证通过：显式 `stack=python` 优先于 AI 探测提示；Pwn `flag0/flag1` 会提示并转换为 `/home/ctf/flag0`、`/home/ctf/flag1`；`reviewed-render` 可渲染低风险 Node 示例，并会阻断未接受 proposal 的 Pwn 输入。
- 真实 LLM A/B 使用 `gpt-5.4`、4 组输入比较 r5 安装版与 r6 当前工作区：r5 为 2/4，r6 为 4/4。报告保存在 `开发文档（不同步）/llm_ab_v220_r6_retry_20260611_191223/REPORT.md`。

## v2.2.0-r5 - 2026-06-11

### 修复

- 运行时文档明确 `challenge.verification.solve_probe` 的直接执行入口：`bash scripts/smoke_test.sh --case python-flask-basic`。此前 r4 已有正式 example，但真实 LLM A/B 仍会只给出 `render.py` / `validate.sh`，没有走到业务入口断言。
- `examples/python-flask-basic/README.md` 不再让用户去仓库根 README 查命令，改为写出安装版 Skill 可直接执行的命令。
- `SKILL.md`、scripts README 与 `validation_guide.md` 收紧 `flag.sync_paths` 说明：默认同步发生在平台调用 `/changeflag.sh` 时；只有用户明确说明平台不会调用 `/changeflag.sh`，才把启动时同步写成题目特定兼容逻辑。
- `doc_guard.py` 允许运行时文档引用 `smoke_test.sh`，但继续阻断发布治理和源码维护说明进入 Skill 运行包。

### 验证

- `check_fast.sh` 通过；`smoke_test.sh --case python-flask-basic` 通过并执行 `challenge.verification.solve_probe`；`release_build.sh --with-smoke` 通过，`release_ready=true`。
- 真实 LLM A/B 使用 `gpt-5.4`、`flag_sync_lifecycle` 和 `solve_probe_example` 两组输入：r4 为 0/2，r5 为 2/2。报告保存在 `开发文档（不同步）/llm_ab_v220_r5_explicit_context_retry_20260611_183710/REPORT.md`。

## v2.2.0-r4 - 2026-06-11

### 修复

- `python-flask-basic` 正式加入 `challenge.verification.solve_probe` 示例，`smoke_test.sh --case python-flask-basic` 可直接验证从 `challenge.yaml` 读取业务入口断言的链路。
- 文档明确 `challenge.flag.sync_paths` 的生效边界：它由生成的 `/changeflag.sh` 同步业务路径，不代表任意 `start.sh` 启动时都会自动写好 `flag0/flag1` 等路径。
- `SKILL.md`、schema、平台契约、栈手册和脚本 README 同步提醒：真实 Pwn/Web 题若不读 `/flag`，仍需看源码配置业务路径并执行 smoke probe 或实际拿 flag 验证。

### 验证

- r4 发布前验证覆盖 `check_fast.sh`、`validate_examples.sh`、`smoke_test.sh --case python-flask-basic`、`release_build.sh --with-smoke`。

## v2.2.0-r3 - 2026-06-11

### 变更

- Compose/Vulhub-like 导入增强：draft 保留 ports、environment、depends_on、volumes、networks、healthcheck、command/entrypoint 等线索；renderable subset 支持 image tag/digest 别名匹配、host/container 端口带入、environment 带入和 `depends_on` 写回。
- check-service 生成器增强：HTTP 支持状态码、正向/反向文本和 header 断言；Redis 支持 key/value 检查；MySQL 支持 query 结果断言；SSH 支持 banner 断言。
- `smoke_test.sh` 增加可选 `smoke_assert.yaml` 业务断言，支持 HTTP、TCP 和容器内命令；已有 `smoke_assert.sh` 保持兼容。
- Linux-QEMU 样例维护规则细化：Fragnesia 继续作为外部真实资产样例；Copy Fail 记录为候选负例，缺资产 manifest、boot、flag readback 与 PoC 证据前不升级为真实样例。
- 新增 `scripts/check_fast.sh`，日常维护只执行 Python/Bash 语法、文档治理和 `git diff --check`。
- `smoke_test.sh` 增加 `--case <name>` 与 `SMOKE_CASES=a,b`，可只跑受影响的示例，避免每次都执行全量 Docker smoke。

### 修复

- 真实历史题复刻路径增强：Pwn/BOF 输入会优先识别 ELF、C 源码、Makefile、xinetd/socat/tcpserver/chroot 等强证据，减少被遗留 `package.json` 或前端说明页误判为 Node 的情况。
- 历史运行时保留更明确：渲染基础镜像优先级调整为 `--base-image > CLI --runtime-profile > challenge.base_image > challenge.runtime_profile > infer/default`，避免 `challenge.yaml` 中明确写出的 PHP 7.4、Node 14、JDK 8 等老环境被自动推断覆盖。
- `parse_config_block.py` 保留更多已确认字段，包括 `runtime_deps`、`build_deps`、`extra.*`、`flag.sync_paths`、`verification.solve_probe`、`platform.docker_platform` 和 `support_level`。
- `workflow.py accept --refresh` 可在用户确认后重新记录当前 `challenge.yaml` hash，适配人工修正配置后继续走 gate 的场景。
- `workflow.py --pretty` 与子命令 `--pretty` 兼容，等价于 `--format json`，避免真实使用中因参数不支持中断。
- 动态 flag 同步能力增强：`changeflag.sh` 可把动态 flag 同步到题目业务实际读取路径，避免题目读 `/home/ctf/flag` 等路径时只更新 `/flag`。
- `validate.sh` 明确说明自身只验证平台交付契约，不证明题目已经可解；如果配置 `verification.solve_probe`，会提示业务入口断言应在 smoke 阶段执行。
- `smoke_test.sh` 支持 `challenge.verification.solve_probe`，可直接从 `challenge.yaml` 生成业务断言并执行 HTTP/TCP/容器命令类检查。
- 发布包路径继续校验，安装版 Skill 文档不再引用 `src/CloverSec-CTF-Build-Dockerizer/` 这类安装后不存在的源码路径。

### 验证

- 真实 LLM A/B：修复前 HEAD 为 3/6，当前 r3 候选为 6/6；Pwn BOF 混合输入、PHP 7.4 保留、业务 flag 路径 + solve_probe 均从失败变为通过。
- 本地完整验证通过：`check_fast.sh`、`golden_snapshot.py`、`platform_matrix.py --profile release`、`validate_build_test.py`、`validate_examples.sh`、Linux-QEMU Fragnesia preflight、`release_build.sh --with-smoke` 均通过。
- Docker smoke：35 通过 / 0 失败 / 4 按策略跳过。
- 定向反馈验证通过：真实 Pwn ELF + 遗留 `package.json` 识别为 `pwn`；PHP Dockerfile 保持 `FROM php:7.4-cli`；动态 flag 精确写入 `flag{abc}`；`verification.solve_probe` smoke 通过。

## v2.2.0-r2 - 2026-06-11

### 修复

- Bundle/Recipe 支持显式 custom 组合：用户明确提供 base image、安装命令、启动命令、端口和服务清单后，可以生成单容器多服务交付目录；信息不完整时仍返回 `BUNDLE_UNSUPPORTED_COMBINATION`，不自动猜测依赖或版本。
- Linux-QEMU release/manual 验证补齐完整链路：新增外部 VM 资产清单校验、CI full check、Fragnesia PoC 自动复现脚本，可覆盖 Docker build、QEMU TCG boot、guest flag 写入和 PoC 验证。
- 修复 Linux-QEMU 动态 flag 写入顺序：在 QEMU guest 启动前通过外层 `/start.sh` 写入 guest rootfs，避免 guest 已挂载 rootfs 后再改文件导致 flag 不生效。
- 修复 `flag{...}` 在 Bash 参数展开中多出 `}` 的真实样例问题，并通过 Fragnesia 真实资产验证 guest `/root/flag` 与动态 flag 一致。
- `golden_snapshot.py` 适配 Scenario 确认门槛，回归场景显式使用 `--accepted --reason`，避免测试脚本绕过当前交互规则。
- 运行时 Skill 文档继续聚焦题目构建：移除安装包内不必要的源码发布治理说明，并由 `doc_guard.py` 阻止源码维护命令进入运行时文档。

### 验证

- 真实 LLM A/B：已安装 `v2.2.0` 入口为 3/4，当前 r2 候选为 4/4；custom Bundle 用例从“不支持”变为正确进入显式 custom proposal。
- 完整 Docker smoke：35 通过 / 0 失败 / 4 跳过。
- Linux-QEMU full check：Docker build、QEMU TCG boot、guest SSH、动态 flag、PoC 均通过。

## v2.2.0-r1 - 2026-06-11

### 修复

- 修复安装版 Skill 文档路径表述，运行时文档统一使用相对于 `SKILL.md` 的 `docs/`、`data/`、`scripts/`、`templates/`、`examples/` 路径。
- `doc_guard.py` 与 `release_build.py` 增加发布包运行时路径检查，阻止 `src/CloverSec-CTF-Build-Dockerizer/` 这类源码仓库前缀进入安装包文档。
- 补齐 `linux_qemu_manual_check.sh` 在 Skill 运行包内的入口，避免文档引用存在但发布包缺脚本。
- Bundle/Recipe 增加显式 custom 组合：用户提供 base image、安装命令、启动命令、端口和服务清单后可生成交付目录；不完整组合仍返回 `BUNDLE_UNSUPPORTED_COMBINATION`。
- `release-full-check` 增加 Linux-QEMU full check 步骤；CI 能取得外部 VM 资产时执行 boot、guest flag 与 PoC 检查，资产不存在时按策略记录 skip 或失败。

### 发布

- 本版本计划通过 `publish_release.sh --wait-release-full-check` 发布，等待 GitHub Actions `release-full-check` job 成功后再公开 GitHub Release。
- 本版本不改变 `challenge.yaml` schema、Proposal Gate、render/validate 契约或 Linux-QEMU 渲染行为。

## v2.2.0 - 2026-06-10

### 新增

- 新增 `scripts/golden_snapshot.py` 与 `tests/golden/snapshots.json`，对关键样例的渲染产物做哈希快照回归。
- 新增 `scripts/platform_matrix.py`，采集 Python、Docker、Compose、QEMU、SBOM 工具状态并输出跨平台矩阵结果。
- `Build_test/` 升级为真实样例池，新增 `cases.yaml`、每个样例的 `case_note.md` 和独立说明文档。
- 新增 `scripts/validate_build_test.py`，按 `cases.yaml` 对真实样例执行输入审计与 Docker 契约期望匹配，支持 `--format json`、`--case` 和 `--fail-fast`。
- 首批样例覆盖现有历史样例、cPanel/WHM 仿真、Linux-QEMU 缺资产、Web 历史题、Pwn compose/xinetd 输入和 PHP compose 输入。
- 新增 Linux-QEMU release/manual 验证套件：`linux_qemu_manual_validation.md`、`scripts/linux_qemu_manual_check.sh` 和真实 Fragnesia 外部资产记录。
- 新增 Bundle/Recipe 原型，提供两个固定组合、`render_bundle.py`、`validate_bundle.py`、schema、设计文档和输入示例。
- 新增 compose import draft：`import_compose.py` 输出 `scenario.draft.yaml`、`scenario.renderable.yaml` 与 `import-report.json`，并提供导入示例。
- 新增 `generate_check_stub.py`，支持 HTTP/TCP/Redis/MySQL/SSH check-service 可编辑骨架。
- 新增 `validation_guide.md`，承接 `SKILL.md` 中迁出的 validate、check-service、Linux-QEMU 静态校验和发布前检查细节。
- 新增 `orchestrated_workflow.md`，承接旧版 `SKILL.md` 的方案确认、OK 门槛和 5 项确认协议。

### 变更

- `SKILL.md` 改为渐进加载入口，只保留任务定位、首选工作流、门槛规则、输入路由和按需读取索引。
- `doc_guard.py` 增加 `SKILL.md` 行数、关键入口和大段迁出内容检查，防止入口文件再次膨胀。
- `doc_guard.py` 扩展到 `src/CloverSec-CTF-Build-Dockerizer/examples/README.md`、`src/CloverSec-CTF-Build-Dockerizer/scripts/README.md` 和 `agents/openai.yaml`，检查回归入口、治理脚本和默认确认提示。
- `generate_sbom.py` 新增 `--strict`，`release_build.py` 新增 `--sbom-strict`，可要求 syft/docker sbom 真正生成 SBOM，不再退回 source-inventory。
- `stack_cookbook.md` 补充旧版 `SKILL.md` 的 12 栈最小模板库索引，`validation_guide.md` 补充模板变量速查。
- 移除运行包中的迁移映射文档，避免 Agent 把审计记录当作执行手册；长参考文档补充目录以提升按需读取质量。
- `validate.sh` 读取 `support_level`，发布 digest 门禁对 `partial` 原型样例记录 WARN 而不阻断；Redis 7.2 BaseUnit 组件改用 digest 固定镜像。
- `validate.sh` 的 Linux-QEMU debugfs 检测支持 `sif` 别名，避免真实 `changeflag.sh` 被误判为没有写入 guest rootfs。
- `validate_examples.sh` 识别 `bundle.yaml`，在临时目录渲染并校验 Bundle 示例，保持 examples 只读。
- `validate_examples.sh` 识别 compose 示例，默认校验导入后的可渲染 Scenario 子集。
- `validate.sh` 将 `CHECK_REVIEW_REQUIRED` 视为未确认 check-service 标记，继续阻断发布。

### 验证

- 改版前后对照验证基线：P1.8 前 `29d470e`，P1.8 后 `108977d`。
- `SKILL.md` 从 1089 行降到 206 行，入口减少约 81.1%；字节数从 39254 降到 10204，减少约 74.0%。
- OK 门槛、5 项确认、低风险 Node 生成与验证流程、Linux-QEMU 缺资产审计均保持一致。
- Bundle partial 严格 digest 和 Scenario Vulhub-like 严格 digest 从失败变为通过。
- 报告保存在 `开发文档（不同步）/golden_snapshot_p18/REPORT.md` 与 `开发文档（不同步）/golden_snapshot_p18/summary.json`；该目录不进入发布包。

## v2.1.2 - 2026-06-10

### 新增

- 新增 `workflow.py` 推荐入口，提供 `intake / propose / accept / render / validate / status` 命令，并在题目目录维护 `.ctfbuild/session.json`、proposal 与 accepted proposal 状态文件。
- 新增 `audit_input.py` 输入审计，输出风险等级、推荐处理路径、支持等级、验证等级、是否需要人工确认和发现项；`derive_config.py` 的 JSON/YAML 输出同步携带审计结果。
- `render.py` 新增 Proposal Gate、`--format text|json`、`--manual --reason`。混合输入、脏目录、高风险输入或 derive gates 为 true 时，默认要求 accepted proposal。
- `validate.sh` 新增 `--json-summary <path>`，`validate_scenario.py` 新增 `--format text|json`，失败结果可稳定输出结构化错误码。

### 变更

- `validate_context.py` 在传入 `challenge.yaml` 后如遇文件缺失、PyYAML 缺失或 YAML 解析失败，会返回非 0，并统一归类为 `CONFIG_CONTEXT_PARSE_FAILED`。
- 发布检查升级：`release_build.py` 支持 `--with-smoke`、SkillHub metadata 检查、当前版本 CHANGELOG 标题检查、`agents/` 打包检查、SBOM 来源记录和 `release-status.json`。
- `publish_release.sh` 正式发布默认执行 Docker smoke；如需跳过必须传入 `--skip-smoke-with-reason "..."`。找不到当前版本 release notes 时发布失败。

### 发布

- 本版本聚焦工作流门槛、输入审计、结构化错误与发布前检查，不扩展样例池，不引入 Bundle/Recipe 或 Scenario import，也不重写 `SKILL.md` 主体。

## v2.1.1 - 2026-06-10

### 修复

- 修复 `SKILL.md` frontmatter `name` 不符合 SkillHub slug 规则的问题，发布包现在使用 `cloversec-ctf-build-dockerizer`。
- 移除 `SKILL.md` 中会触发内部 Git 导出 `diff --check` 失败的行尾空格。
- 发布构建增加 SkillHub slug 与行尾空格检查，提前拦截会导致同步失败的包内容。
- 三语 README 增加 `v2.1.1` 发布修复说明，公开 docs 标题同步到当前版本。
- 文档检查增加当前版本说明章节检查，避免只更新顶部版本号而遗漏正文说明。

## v2.1.0 - 2026-06-10

### 新增

- 新增 `linux-qemu` 技术栈，面向 Linux kernel CVE/LPE 题目：外层 Docker 镜像启动 QEMU，内层 guest 承载指定 vulnerable kernel、initrd/rootfs。
- 新增 `challenge.vm` 配置，覆盖 QEMU binary、arch、TCG/KVM、kernel/initrd/rootfs、hostfwd、guest flag 路径和 flag 注入方式。
- 新增 `templates/linux-qemu/` 与 `examples/linux-qemu-basic/`，轻量示例用于 render/validate，不携带可启动大型 VM 资产。

### 变更

- `render.py` 支持把 `challenge.vm` 渲染为结构化 QEMU 启动脚本，并为 `linux-qemu` 生成可写 guest rootfs 的 `changeflag.sh`。
- `derive_config.py`、`parse_config_block.py`、`data/stacks.yaml`、`data/patterns.yaml` 同步支持 `linux-qemu`。
- `validate.sh` 增加 QEMU 专项检查：QEMU 依赖、`-nographic`、`hostfwd`、monitor/gdbstub 风险、VM 资产、KVM 要求、guest flag 路径、EXPOSE 与 hostfwd 一致性。
- `smoke_test.sh` 增加 `LINUX_QEMU_RUN_MODE=validate-only|build-only|full`，默认仅做 render/validate。
- `linux-qemu` 渲染增加 VM 字段字符级校验、TCP-only guest forward、`healthcheck_mode` 默认命令映射与 aarch64 QEMU 包校验。
- release 打包跳过 Git ignored 文件，SBOM 工具不可用时生成源码清单型 SBOM，并阻止打包校验阶段改写源目录。

### 发布

- 完整 QEMU boot、PoC 复现、真实动态 flag 注入仍属于 release/manual 级验证；默认回归不启动占位 VM 示例。

## v2.0.3-r1 - 2026-03-06

### 变更

- 新增 `src/CloverSec-CTF-Build-Dockerizer/agents/openai.yaml`，用于 Codex UI 中的 Skill 卡片展示、短描述与默认提示词配置。
- `src/CloverSec-CTF-Build-Dockerizer/SKILL.md` 顶部说明结构前移，采用 `一句话定位 / 能力边界 / 适用场景 / 注意事项` 的前置展示方式，便于在技能详情页中直接阅读。
- `README.md` 追加 `v2.0.3-r1` 补充说明，并同步三语 README 顶部版本号到 `v2.0.3-r1`。

### 发布

- 本版本为展示层与文档整理发布，不引入 `render.py`、`validate.sh`、`render_component.py`、`render_scenario.py` 等运行时逻辑变更。

## v2.0.3 - 2026-03-06

### 变更

- 修复三语 README 的历史错链，统一当前文档入口为：`README.md`（中文默认）、`README.en.md`（英文完整）、`README.ja.md`（日文完整）。
- 收敛 README 中过强或易过时的承诺性表述，改为以“当前已验证能力范围”和“兼容优先迭代”描述项目边界。
- 将 `beginner_guide.md` 升级到 V2 表达，完善 `changeflag.sh`、`secops`、`baseunit`、`scenario`、`awd`、`awdp` 等能力说明。
- 修正文档契约错位：
  - `changeflag.sh` 明确为硬产物
  - `/flag` 明确为条件产物
  - `challenge.yaml` 不再被表述为所有渲染路径都必然重新输出的硬产物
- 更新 `directory_guide.md`、`SKILL.md`、`platform_contract.md`、`architecture_overview.md`、`stack_cookbook.md`、`data/README.md`，统一到当前实现语义。
- `scripts/doc_guard.py` 按当前三语 README 结构检查，不再强依赖已删除的历史中文入口文件。

### 发布

- 本版本为纯文档一致性修复，不引入新的运行时功能。

## v2.0.2 - 2026-03-06

### 变更

- README 体系重写为“中文默认 + 三语完整等价文档”
  - `README.md`：中文默认完整手册
  - `README.en.md`：英文完整手册（不再是 legacy 短入口）
  - `README.ja.md`：日文完整手册
- 新增“版本演进叙事”并覆盖 `v1.5.0 -> v2.0.0 -> v2.0.1 -> v2.0.2` 全链路说明。
- 补齐并扩展高价值文档板块：
  - 一键安装与技能发现
  - AI 编排流程与方案确认门
  - AI 编程工具实战（Codex/Cursor/Trae/Claude Code/Copilot Chat/Aider）
  - 竞赛模式构建手册（Jeopardy/RDG/AWD/AWDP/SecOps/BaseUnit/Vulhub-like）
  - 文件级目录索引、FAQ、排障与发布验收清单
  - Workflow 截图与 Build_test 真实样例说明
- 移除三语 README 中的“参考资料”章节，改为仓库内文档与命令导航。
- `scripts/doc_guard.py` 增强 README 结构守卫：
  - 校验三份完整 README 存在与语言互链完整性
  - 校验关键章节存在（重点更新、AI 工具、模式手册、目录索引、FAQ）
  - 校验三份完整 README 的版本号与 `VERSION` 一致
  - 校验不再出现 `References/参考资料/参考` 章节
- `scripts/publish_guard.py` 新增发布前文档守卫：
  - 校验 README 资产完整性
  - 校验 `README.en.md` 非 legacy 短入口

### 发布

- 本版本为“文档与使用体验增强版”，不引入新的运行时行为变更。

## v2.0.1 - 2026-03-06

### 变更

- 补齐并固化 Vulhub-like 迁移示例：新增 `examples/scenario-vulhub-like-basic`，覆盖「challenge 来源 + component 来源」混合编排。
- 修复 `stacks.yaml` 重复定义风险：清理重复 `secops/baseunit`，并在 `utils.load_stack_defs` 对重复 stack id 直接报错，避免静默覆盖。
- 修复 AWDP 补丁包重复构建漂移：`patch_bundle.tar.gz` 改为确定性打包（固定 mtime/uid/gid 与排序）。
- 三语 README 与 `scenario_schema.md` 同步补充 Vulhub-like 示例命令与边界说明，强调 compose 仅用于本地编排，平台最终交付仍为单服务目录。

### 发布

- 该版本为 `v2.0.0` 整理补丁发布，保持接口与契约不变，仅做一致性整理与可重复构建修复。

## v2.0.0 - 2026-03-06

### 新增

- 新增 V2 交付契约：每次渲染默认产出 `Dockerfile`、`start.sh`、`changeflag.sh`，并在需要时产出 `flag` 与 `check/check.sh`。
- 新增 V2 推荐配置字段：`challenge.profile` 与 `challenge.defense`，覆盖 `jeopardy / rdg / awd / awdp / secops` 五类 profile。
- 新增独立技术栈：`secops`、`baseunit`。
- 新增 `data/profiles.yaml`，统一管理 profile 默认行为。
- 新增 `src/CloverSec-CTF-Build-Dockerizer/data/components.yaml` 与 `src/CloverSec-CTF-Build-Dockerizer/scripts/render_component.py`，支持指定组件和指定版本变体生成“纯服务包 / 纯基座镜像最小单元”。
- 新增 `src/CloverSec-CTF-Build-Dockerizer/data/scenario_schema.md`、`src/CloverSec-CTF-Build-Dockerizer/data/validate_scenario_rules.yaml`、`src/CloverSec-CTF-Build-Dockerizer/scripts/render_scenario.py`、`src/CloverSec-CTF-Build-Dockerizer/scripts/validate_scenario.py`，支持 AWD / AWDP / Vulhub-like 本地多服务场景编排与校验。
- 新增示例：
  - `examples/baseunit-redis-basic`
  - `examples/baseunit-sshd-basic`
  - `examples/secops-nginx-basic`
  - `examples/secops-nginx-hardening-basic`
  - `examples/secops-redis-hardening-basic`
  - `examples/node-awdp-basic`
  - `examples/scenario-awd-basic`
  - `examples/scenario-awdp-basic`
  - `examples/scenario-vulhub-like-basic`
- 新增日文完整文档：`README.ja.md`。
- 新增 `src/CloverSec-CTF-Build-Dockerizer/scripts/validate_context.py`，将 `validate.sh` 的 challenge 上下文解析逻辑稳定下沉到 Python。

### 变更

- `render.py` 升级到 V2 语义：
  - 支持 `profile` / `defense` / `secops` / `baseunit`
  - 强制生成 `/changeflag.sh`
  - 对 `awdp` 自动生成 `patch/src/`、`patch/patch.sh`、`patch_bundle.tar.gz`
  - 非 `rdg/secops` 栈可在 `profile!=jeopardy` 下复用 defense block
  - `patch_bundle.tar.gz` 改为确定性打包，避免重复回归触发二进制漂移
- `parse_config_block.py`、`derive_config.py` 升级为 V2 模型，兼容 legacy `challenge.rdg` 输入，但推荐输出 `challenge.defense`。
- `validate.sh` 升级：
  - `/changeflag.sh` 纳入硬规则
  - `profile` / `defense` / `secops` 场景进入统一门禁
  - 修复 challenge 上下文解析链路，消除嵌入式 Python 语法与兼容性问题
- `data/stacks.yaml` 去除重复 `secops/baseunit` 定义，`utils.load_stack_defs` 对重复 stack id 改为显式报错，避免静默覆盖。
- `smoke_test.sh` 与 `validate_examples.sh` 增强：
  - 识别 `scenario.yaml`
  - 调用 `render_scenario.py` / `validate_scenario.py`
  - `check_service` 不再只绑定 `rdg`，而是按 `profile + scoring_mode + check_enabled` 泛化执行
- `render_component.py` 改为把 `challenge.yaml` 持久写入输出目录，便于 `scenario` 二次覆盖与再渲染。

### 文档

- `README.md` / `README.en.md` / `README.ja.md` 统一升级到 `v2.0.0`，补齐：
  - 多语言导航
  - `profile / defense / secops / baseunit / scenario / changeflag`
  - 平台最终交付与本地 compose 编排边界
  - baseunit 组件生成器用法
  - AWDP 补丁包工作流
  - AWD 与 secops 的差异
- `SKILL.md`、`schema.md`、`platform_contract.md`、`architecture_overview.md`、`directory_guide.md`、`stack_cookbook.md`、`data/README.md`、`templates/README.md` 同步到 V2 语义。

### 发布与兼容

- 对外安装入口保持不变：`npx -y skills add ... --skill cloversec-ctf-build-dockerizer`
- Release 继续采用 immutable-compatible 流程。
- 仍保留 `README.en.md` 作为历史英文兼容入口。

## v1.5.0 - 2026-02-28

### 新增

- 新增运行时档位数据源：`src/CloverSec-CTF-Build-Dockerizer/data/runtime_profiles.yaml`（php/node/java）。
- 新增文档：
  - `src/CloverSec-CTF-Build-Dockerizer/docs/architecture_overview.md`
  - `src/CloverSec-CTF-Build-Dockerizer/docs/directory_guide.md`
- 新增治理脚本 Python 主实现：
  - `scripts/doc_guard.py`
  - `scripts/release_build.py`
  - `scripts/generate_sbom.py`
  - `scripts/sync.py`
  - `scripts/publish_guard.py`
- 新增运行时推断回归脚本：`src/CloverSec-CTF-Build-Dockerizer/scripts/test_runtime_profiles.sh`。

### 变更

- `derive_config.py` 增加运行时档位输出：`runtime_profile_candidates`、`recommended_profile`、`recommended_base_image`、`runtime_profile_evidence`。
- `render.py` 新增 `--runtime-profile`，并明确基础镜像优先级：`--base-image > --runtime-profile > challenge.base_image > infer/default`。
- `validate.sh` 增加 legacy 运行时告警（WARN，不阻断）：`php:5.6/7.4`、`node:14/16`、`temurin:8`（含 digest 形式）。
- 根目录治理 `.sh` 脚本改为 Python 兼容入口 wrapper，命令入口保持不变。
- `publish_release.sh` 维持编排角色，版本读取与白名单路径判定下沉到 `publish_guard.py`。
- `data/stacks.yaml` 与模板文档统一 Pwn 表达为 `xinetd/tcpserver/socat`。
