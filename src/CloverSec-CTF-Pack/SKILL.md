---
name: cloversec-ctf-pack
description: 把 CTF 题目源码、题目设计或历史题目目录整理成能交付的题目包：容器题的 src/、Dockerfile、start.sh、challenge.yaml 和本地验证，附件题的选手附件，以及两类的 README 手册。用于四叶草安全创研中心出题、迁移旧题、给题目写 Dockerfile 或 start.sh、写题目手册、整理选手附件、排查题目起不来或 Flag 不生效。覆盖 Web、Pwn、AI、Misc 等 20 个题目类型；多服务、Bundle、Scenario、RDG/AWD、Linux-QEMU 见 references/special.md，批量交付见 references/batch.md。
license: MIT
compatibility: 需要能读写文件和跑命令的 Agent（Claude Code、Codex 等），本机装 Docker 和 curl。
allowed-tools: Bash Read Write Edit Glob Grep
metadata:
  short-description: 把题目整理成能交付的题目包，恢复原题难度，并本地验证容器题
---

# CloverSec CTF Pack

把题目想法、源码或旧题目录整理成能交付的题目包，再验证容器题能不能在平台上跑起来。

## 默认恢复原题难度

迁移旧题、整理历史题目时，**默认动作就是反推原题难度并原样恢复**，不需要用户提醒，也不要先问"要不要保持现状"。旧题经过一轮整理后常常已经被简化过，交付时要还原回去。

从题目设计出新题时，基线就是设计稿里的漏洞、链路和环境，按设计稿实现，不要自己简化。

### 第一步：写难度基线

改任何文件之前，先逐题写出一份难度基线：

- 漏洞类型和影响面（前台 SQL 注入、反序列化、堆溢出……）。
- 链路几步、卡在哪、要不要绕过防护（WAF、黑名单、`disable_functions`、权限校验）。
- **服务拓扑**：原题跑几个服务，各自是什么（nginx + php-fpm + MySQL + admin-panel）。
- **运行时版本**：PHP 5.6、Node 11、JDK 8、ImageMagick 6.9.11-60 这类具体版本。
- 需要什么前置知识。

基线写进 `challenge.yaml` 的 `provenance.preserved`（附件题写进交付说明），交付说明里逐题对照。**没有基线就不许动手改题。**

### 已经有交付目录时，先做体检

材料里已经有一版交付包时，不要接着往下做。先逐题比对"当前实现 vs 出题人原始材料"，把被换掉、被删掉、被绕过的地方列出来，再决定怎么恢复。

常见的是上一版为了"能在本地跑起来"做过替换：nginx+php-fpm 换成 `php:*-apache`、PHP 5.6 升到 7.x、MySQL 服务层删掉、多步链路压成一条。

### 什么算降级

下面每一条都改变题目难度。做了任何一条，都要先停下来问用户，不许自己决定：

| 降级动作 | 例子 |
|---|---|
| 合并服务层 | compose 里的 nginx + php-fpm 换成 `php:8.1-apache`，或只留一个服务 |
| 替换服务组件 | php-fpm 换成 mod_php，MariaDB 换成 SQLite，admin-panel 删掉 |
| 升级运行时大版本 | PHP 5.6 → 7.x、Node 8 → 11、JDK 8 → 17 |
| 压缩链路 | 多步利用压成单接口直出 Flag |
| 删除防护 | 去掉 WAF、黑名单、`disable_functions`、权限校验 |
| 换数据结构 | 需要反推的数据结构换成自己编的一套 |
| 换实现 | 原题链路跑不通，改写成一个能跑但更简单的版本 |
| 改交付形态 | 容器题改成附件题，或反过来（除非原题就是这样） |

**"本机跑不动"不是改题的理由。** Apple Silicon 跑不了 amd64、旧镜像拉不下来、模拟器里崩了，都是环境问题：在 `provenance.env_limited` 里如实记下来，把 `status` 标成 `incomplete`，然后告诉用户卡在哪。用户提供了原生 amd64 机器的，就到那台机器上跑。

### 平台只收单容器时怎么办

平台要求单容器单入口，和"原题是多服务"不冲突。正确做法是**把原来每个服务原样装进同一个镜像**：

1. 镜像里同时安装原题的 nginx、php-fpm、MySQL、Redis、admin-panel 等组件，版本按原题锁死。
2. 沿用原题配置文件（`nginx.conf`、`sandbox.ini`、`process.yaml`、`my.cnf`）。
3. `start.sh` 先后台起依赖、等就绪，再 `exec` 对外的主服务。
4. `src/` 里的题目代码、正则、黑名单、`disable_functions` 一律不动。

**禁止**用 `php:*-apache` 之类替换服务层——那样平台看到的是一个容器，题目行为却变了。多服务的 start.sh 模板见 [references/special.md](references/special.md)。

### 提问时必须先给反推结论

允许问，但不允许用"要不要保持现状"当选项。写法是：**"我反推出原题是 X（依据是 Y），缺 Z，需要你在 A / B 里选。"**

不许把"保持现在的简化版本"作为默认推荐项。

## 先查明白，再问剩下的

**提问是把只有用户知道的事问出来，不是见面就摆问题让用户决定。** 顺序是：先读材料，能从材料里定下来的自己定，只把真正推不出来的拿出来问。遇到真推不出来的事，也不要自己拿主意做到底。

### 第一步：把材料读透（这一步不提问）

开工前先把手里的东西全过一遍：题目目录、源码、`Dockerfile`、`start.sh`、已有配置、赛事归档、出题人交付包、旧手册。

大部分信息其实都躺在材料里，一眼就能看出来：

- 题目叫什么、什么类型——目录名和源码。
- 容器题还是附件题——按下面「容器题还是附件题」一节的判据，不要只看 README 里有没有 URL。
- 要哪些附件、要不要镜像 tar——原题形态、原来交付过什么。
- 是不是 RDG——有没有 `check/`。
- 材料完不完整、有没有原始手册——读一遍就知道。

### 第二步：能定的自己定，别问

上面这些是你自己的功课，不是让用户替你做的。读了材料还去问"这几道题按什么形态交付""要不要选手附件"，就是把功课推给用户。

**唯一例外**：材料里有两种以上解释且代价差很多——比如目录里既有服务端代码又有一堆静态文件，看不出是容器题还是附件题。这时候才问，而且**把你看到的情况一起说出来**。

### 第三步：只问推不出来的

读完材料之后剩下的缺口才是真问题：

- 材料里没有、也推不出来的事实：端口、启动命令、Flag 路径、运行时版本、数据库初始化数据在哪儿。
- 有多个合理方案且代价不同：单容器还是多容器、原样迁移还是重写、锁旧版本还是升版本。
- 方案会改变题目的难度构成（见「什么算降级」）。
- **你打算"降级处理""先用简化版本顶上""这次先跳过"的任何地方。**

### 怎么问

- **先说你查到了什么，再问缺口。** 例："Shiro 那道源码和 jar 都在，缺原数据库快照；按独立补全做，还是等你提供快照？"
- 支持结构化提问的环境（Codex）用 `request_user_input`；Claude Code 用 AskUserQuestion，写法一样。都不支持时用普通消息把选项列成 1/2/3。
- 给 2 到 4 个直白选项，每个选项一句话说清后果，不要写技术黑话。标出你的推荐，并说明推荐的那个为什么省事。
- 一次把同类问题问完，问完等回答再动手。
- 环境和题目合同类的问题不要问，直接读材料——比如"Flag 写哪儿"。

### 这些问法不成立

出现下面这些，说明还没读材料：

- "这几道题按什么形态交付？"——读目录就知道。
- "要不要选手附件、要不要镜像 tar？"——原题形态和已有交付物里看得出来。
- "要不要 RDG 的 check？"——有没有 `check/` 目录一看就知道。
- "这个漏洞要不要保留？""要不要保持现在的简化版本？"——难度必须保留，没有这个选项。
- 把 Skill 里已经固定下来的格式拿出来问（章节骨架、目录名规则、注释要求）。

### 自查

打算开口之前先问自己：**"这个问题我读过材料之后还是答不出来吗？"** 答得出来就自己定，答不出来才问，并把你查到的相关情况一起说。

## 交付目录名

交付目录按 `题目类型-题目名称` 命名，类型取下列之一：

```text
AI  Blockchain  Crypto  Drone  Forensics  Hardware  IC  IOT  InfoSec  Misc
Mobile  OSINT  OpposeAI  PPC  Pentest  Pwn  Quantum  RDG  Reverse  Web
```

中文题名保留中文（`Web-残影`），英文题名统一小写连字符（`Pwn-hard-fmt`）。题名里的 emoji 和标点去掉。

## 容器题还是附件题

按下面四条判，**从上往下第一条命中的就是答案**：

1. `src/` 里有 `docker-compose.yml` 且带 `ports:` → 容器题。
2. `src/` 里有 `Dockerfile`，入口程序在监听服务（Flask、gradio、socket、`accept`）→ 容器题。
3. 题面出现 `nc <ip> <port>` → 容器题。
4. `files/` 或 `附件/` 里是发给选手的文件，`src/` 为空或只有出题脚本 → 附件题。

**不要只看 README 里有没有在线地址。** 官方题解赛后会把地址换成 `{token}` 占位符或直接删掉，照这个判会漏判一批。

## 选手附件与镜像 tar

两个都默认不做，需要时按下面的位置放：

| 交付物 | 位置 | 什么时候做 |
|---|---|---|
| 选手附件 | `附件/` | 题目需要选手拿到二进制、压缩包、pcap 等文件时 |
| 镜像 tar | `镜像/` | 平台通过导入 tar 部署，或用户要求离线交付时 |

- 附件原样放进 `附件/`，不要改名、不要重新打包，除非原来的压缩包坏了。
- 附件要问清楚：哪些文件发给选手。Pwn 题的二进制、libc、loader 是附件，Dockerfile 和 solve.py 不是。
- 附件控制在能下载的体积内；大文件先问用户。
- 镜像 tar 用 `docker save` 导出，文件名 `<题目名>.tar`：

  ```bash
  docker buildx build --platform linux/amd64 -t <题目名>:latest --load .
  docker save <题目名>:latest -o 镜像/<题目名>.tar
  ```

- 镜像层要合并、构建缓存要清理，tar 体积越小越好；镜像里不装编译工具链和出题用的依赖。

## 交付目录

容器题：

```text
Web-残影/
├── README/               # 手册
│   ├── Web-残影.md
│   └── assets/           # 截图、流程图
├── src/                  # 题目源码、静态资源、二进制
├── Dockerfile
├── start.sh              # 平台入口，前台运行真实服务
├── challenge.yaml        # 端口、Flag 路径等平台字段
├── flag                  # 占位 Flag，平台启动后覆盖
├── solve/
│   └── solve.py          # 解题脚本，只用于本地验证，不进镜像
└── 附件/                 # 选手附件，需要时才有
```

纯附件题（没有容器）：

```text
Crypto-星屑密匣/
├── README/
│   ├── Crypto-星屑密匣.md
│   └── assets/
├── src/                  # 原题的出题源码，有才放
├── 附件/                 # 发给选手的文件
├── solve/                # 解题脚本，有才放
└── last/                 # 出题人原始题解/设计文档，有才放
```

- 附件题不生成 Dockerfile、start.sh、challenge.yaml、flag。provenance 的结论写进交付说明和交付根索引。
- `last/` 放搬运来源的原始文档（官方题解、出题人设计文档），备查用，不强制。放了就不要改名，下一环要能核对。
- Dockerfile 只 `COPY` 具体路径（`src/`、`start.sh`、`flag`），不用 `COPY .`，所以不需要 `.dockerignore`，`solve/`、`README/`、`附件/` 也不会进镜像。

### 多题交付要分两级

一次交付多道题时，交付根长这样：

```text
<用户指定的交付根>/
├── README.md            # 索引：逐题一行，写清题名、形态、provenance.status、verify 结论
├── 容器题/
│   └── Web-残影/
└── 附件题/
    └── Crypto-星屑密匣/
```

- 分类判据是**有没有 `Dockerfile`**，不是题目类型名。
- 只有一类时，另一类目录不建。
- **不要在交付根之外散落题目目录。** 迁移或重组时，先把新位置写全，再删旧位置；不要留"两处各一份"。工作目录根上只留交付根和与本次无关的既有目录。
- 交付根 `README.md` 是索引，**不是**题目手册；题目手册始终在各自的 `README/` 里。

### 交付目录白名单

单个题目录里**只允许**出现下面这些。用户拿到的就是这个目录，多一个不相关的文件都是垃圾。

| 形态 | 允许的内容 |
|---|---|
| 容器题 | `src/` `Dockerfile` `start.sh` `challenge.yaml` `flag` `README/` `solve/`〔`附件/`〕〔`镜像/`〕〔`last/`〕 |
| RDG 防守题 | 上面全部，加 `check/` `changeflag.sh` `ttyd` `ttyd.conf` `php.ini` 等题目真正运行需要的文件 |
| 纯附件题 | `src/` `README/` `附件/` `solve/`〔`last/`〕 |

禁止出现在交付目录里的：

- `verify.sh`、任何验证脚本副本（它在 Skill 目录里，不随题目交付）
- `verify-report.json`、`*.verify.json`、任何验证报告
- `provenance.json`、`originality.json` 这类为了交差而生的清单文件
- **内部工作文件**：`_PACK_SPEC.md`、`_交付状态.md`、任务书、进度表——放到交付目录**外面**
- `.DS_Store`、`Thumbs.db`、`__pycache__/`、`.venv/`、`.idea/`、`.vscode/`、`*.pyc`
- 构建产物、日志、临时测试文件、出题时的草稿和笔记
- 根目录的 `README.md`（手册在 `README/` 目录里）

验证报告写到系统临时目录：

```bash
bash <本 Skill 目录>/scripts/verify.sh <题目目录> --report "$(mktemp -d)/verify.json"
```

**`README/` 手册**：文件名必须是 `README/<题目类型-题目名称>.md`，和交付目录同名，不写成 `题目手册.md`、`README.md` 或英文小写连字符名。截图放 `README/assets/`，正文用相对路径引用。

### 删除题目时先扫一遍引用

用户让删某道题时，删之前和删之后各扫一次：

1. 交付根 `README.md` 索引里还有没有它。
2. **其他题的手册**里有没有引用它的目录名、路径、在线地址。
3. **其他题的 solve/附件**有没有依赖它的服务或产物（证书、镜像、生成的附件）。

漏掉第 2、3 条会留下跨题残骸：手册指向已经删掉的目录，或者另一道题因为依赖断了变成死题。发现依赖时告诉用户，让他决定是一起删还是保留。

## README/ 手册

手册是交付的一部分，两类题都要写。完整写法和范例见 [references/manual.md](references/manual.md)，写之前先读一遍。

### 判断部分优先搬运，没来源才留空

九节分两类：

| 节 | 内容来源 |
|---|---|
| 1.1 题目名称 | 查证：目录名、`challenge.yaml` |
| 1.3 题目难度 | 材料里通常标了 |
| 1.5 旗帜信息 | 查证：路径、权限、读取时机、覆盖命令 |
| 1.6 题目情况 | 查证：端口、账号、后台地址、check 位置 |
| 1.7 部署方式 | 构建跑一遍就知道对不对 |
| 1.2 题目描述 | **搬运优先** |
| 1.4 考察信息 | **搬运优先** |
| 1.8 题目设计 | **搬运优先** |
| 1.9 解题步骤 | **搬运优先** |

**判断部分先找来源，按这个顺序：**

1. **出题人材料**：赛事归档、出题人交付包、旧题目录里的设计文档、官方题解、题目源码注释。直接搬运整理，不留 TODO。
2. **外部 writeup / 战队 WP**：只能当线索。**写进手册之前必须在本次交付的环境里复跑核对**——注入点、参数形态、触发顺序、工具装法都可能和本题不一致。搬运和编造之间还有这一档，别把二手记录当出题人原话。
3. **确实没有来源**：在该节正文写一行 `TODO(人工填写)`，并在交付说明里点名哪几节空着。不要写进 `<!-- -->` 注释里，那样渲染出来看不见，空着的节没人发现。

**不许编。** 编出来的东西比空着更糟：「考察 Web 请求分析、服务端输入处理」这类句子读起来像内容，实际什么也没说，还会把空位掩盖掉，让人以为手册写完了。同样不要写"具体漏洞点以 `src/` 中的原始实现为准"这种把问题退回来的句子，不要写"复现完成判据"这种凑字数的过程说明。

### 1.9 解题步骤要能复跑

这一节决定手册能不能用。要求：

- 按真实攻击顺序分步，编号 1.9.1、1.9.2……每步给可直接复制的命令或完整报文，给预期输出。
- payload 写真的，不要写 `payload_here`、`<你的利用脚本>`。
- **每条命令和 payload 形态，必须能用本次交付的 `solve/solve.py` 复跑通过。** 顺序、注入点、参数形态不一致的，以实测为准改手册，不要以手册为准改题。
- 最后一步落到"拿到 Flag"。

### 事实部分和格式

- **1.5 旗帜信息**用「字段：值」平铺，一行一个字段，不用项目符号、不套代码块。常用字段：原始静态flag、平台覆盖方式、flag文件位置、权限属主、读取时机。**谁在什么时候读它必须写**——每次请求读的题平台换 Flag 立即生效，启动时读进内存的题不会生效。
- **1.6 题目情况**写监听端口、服务清单、初始账号、后台地址、判题脚本位置、ttyd、依赖的数据库。
- **1.7 部署方式**八项清单：目录说明、构建命令、镜像 tar 导入、**末尾带 `/start.sh` 的启动命令**、访问地址、平台写 Flag 命令、清理命令、改端口后的同步位置。
- 写作过程中可以在每节末尾放 `<!-- -->` 注释写清该节要写什么并给例子，交付前全部删掉。
- **不写"常见失败现象"这一节**，不用 emoji，不堆加粗，不写"本题目旨在……"这类铺垫。

### 交付前

判据是「手册正文写完没有」，不是「章节齐不齐」：

```bash
grep -c 'TODO(人工填写)' README/<题目名>.md     # 不是 0 就说明还有空位
grep -c '<!--' README/<题目名>.md                # 写指引注释块，必须是 0
```

**有 TODO 残留时不要报"已完成"。** 要么去把来源找出来搬运，要么如实告诉用户哪几节还空着。`verify.sh` 遇到 TODO 会判 `partial`。因为 TODO 得到的 `partial` 是正常结论，如实报告就行，**不要为了跑到 `passed` 去编内容**。

## solve/solve.py

- 从环境变量 `HOST`、`PORT` 读目标地址；多端口题用 `PORT_<容器端口>`，例如 `PORT_8080`。可以再提供 `--host`、`--port` 参数，默认值取环境变量。
- 走原题的漏洞链拿 Flag，打印到 stdout，拿到时返回 0，拿不到返回非 0。
- 不在脚本里写死 Flag。verify.sh 每次写入随机测试 Flag，输出里出现它才算通过。
- **要让 Flag 从服务端读出来，不要读本地文件。** 否则验证脚本写进去的测试 Flag 和脚本输出的固定值恰好一致时会假通过。
- 地址、偏移不要在脚本里写死。PIE 题每次运行的基址不同，格式化字符串的写入计数也依赖实际布局；要从程序里泄漏出来再算。
- **偏移必须量出来，不能猜。** 猜出来的偏移配上"环境限制"就是一道上线不可解的题。
- 脚本要能从零跑通：起手就先连一次服务确认可达，再走漏洞链。
- 依赖只用 Python 标准库；必须用第三方库时在脚本开头注释写明 `pip install` 命令。不要依赖需要手工克隆的外部仓库。
- 中间产物写 `tempfile.mkdtemp()`，不要污染交付目录。
- 解题耗时超过 120 秒的题（QEMU 类常见），把耗时写进手册 1.9，验证时用 `--solve-timeout` 调大。**不许用缩短链路来迁就超时。**
- 附件题也照这个写：从 `附件/` 里的文件解出 Flag。附件题没有测试 Flag，验证时用 `--expect-flag '<手册 1.5 里的值>'` 断言解出来的值真的对——少认一个字符、下划线认成数字，只有这一步能查出来。

## 流程

复制这份清单，逐项完成：

```text
- [ ] 1. 读材料：目录、源码、Dockerfile、start.sh、配置、赛事归档、旧手册
- [ ] 2. 写难度基线：漏洞类型、链路、服务拓扑、运行时版本（已有交付包时先做体检）
- [ ] 3. 从材料定：题目类型和名称、容器题还是附件题、要不要附件和镜像 tar、是不是 RDG
- [ ] 4. 判断 provenance：原样恢复、独立补全，还是缺材料要问用户
- [ ] 5. 只问推不出来的，先说明反推结论，再问缺口
- [ ] 6. 整理 src/，附件放进 附件/（缺的服务层按原样装回同一镜像）
- [ ] 7. 写 Dockerfile 和 start.sh，带中文注释（附件题跳过）
- [ ] 8. 写 challenge.yaml（附件题跳过）
- [ ] 9. 写 solve/solve.py；RDG 题写 check/
- [ ] 10. 写 README/ 手册：事实部分填全，判断部分搬运，没来源才留 TODO
- [ ] 11. 清理交付目录，只留白名单里的文件
- [ ] 12. 跑交付前自检清单（见下）
- [ ] 13. 容器题：verify.sh 跑到 passed；附件题：solve.py 解出 Flag 且与 1.5 一致
```

### 跑 verify.sh

```bash
bash <本 Skill 目录>/scripts/verify.sh <题目目录>
```

- 题目目录里有 `solve/solve.py` 时自动运行，输出里必须出现刚写入的随机测试 Flag；然后换一个 Flag 再解一次。解题脚本不是 Python 时用 `--solve '<命令>'` 指定。
- 静态 Flag 题和附件题没有测试 Flag，用 `--expect-flag '<手册 1.5 里的值>'` 断言。RDG 题自动走 check 判定。
- `failed`：按输出里的原因和日志改，再跑，直到 `passed`。排查时加 `--keep` 保留容器，用 `docker logs` 看输出。
- `partial`：在交付说明里写清是哪一项。
- `environment_failed`：只说明本机跑不动，换原生 amd64 重跑，不能说成通过。
- 没跑 verify.sh 的题不要说成已验证；没有 solve.py 时只能说明容器能跑，不能说明题目可解。

## 交付前自检清单

**交付前自己把这份清单跑完一遍，不要等用户说"再检查一次"。** 每一条给结论，不许只说"检查过了"。

```text
[ ] 1. 目录名：<题目类型>-<题目名称>，类型在 20 类里，无 emoji、无标点
[ ] 2. 多题交付：容器题/ 与 附件题/ 分开，根 README.md 索引逐题写状态
[ ] 3. 白名单：ls -A 逐条对照，内部工作文件、报告、日志、构建产物一个不留
[ ] 4. 垃圾扫描：find <交付根> \( -name .DS_Store -o -name __pycache__ -o -name '*.pyc' \) -print 后删除
[ ] 5. 手册文件名 = 交付目录名；章节骨架齐全；<!-- 为 0；TODO 不为 0 时在交付说明里点名哪几节
[ ] 6. 手册 1.9 的每条命令和 payload 用 solve.py 复跑通过
[ ] 7. 手册里出现的相对路径逐个 test -e（src/...、附件/...、跨题目录）
[ ] 8. 附件清单与 README 1.6 写的文件名集合一致（差集为空）
[ ] 9. challenge.yaml 能被 yaml.safe_load 解析；provenance 的 status/verify 都填了
[ ] 10. flag.path 逐题打开源码确认是程序实际读的那个，不是套模板
[ ] 11. Dockerfile：无 COPY .、无 COPY --chmod/--chown、无 --platform=$BUILDPLATFORM；FROM 版本与原题一致
[ ] 12. start.sh：LF、有 shebang、exec 主进程、没有 GZCTF_FLAG/DASFLAG 之类的别的平台合同
[ ] 13. 端口三处一致：Dockerfile EXPOSE、challenge.yaml expose_ports、手册 1.6/1.7
[ ] 14. verify.sh 跑到 passed（原始架构上）；跑不动的标 environment_failed 并说明卡在哪
[ ] 15. 交付说明里逐题列出：难度基线 vs 实际交付、provenance.status、verify 结论、还缺什么
```

`verify.sh` 覆盖第 3、4、12、14 条，第 5 条只查文件名、骨架和 TODO，第 9 条只在装了 PyYAML 时查语法；其余靠人读。脚本查不出来的项，别用"verify passed"替代。

## 环境与验证

### Apple Silicon 上的三条结论

1. 本机用 `docker buildx build --platform linux/amd64 --load` 能产出 amd64 镜像。
2. **"和原生构建完全一致"不是保证。** 构建期的 `RUN` 会在模拟层真的执行，依赖 CPU 特性、时钟或模拟层不支持的 syscall 时会失败或行为不同。要长期存档的题按 [references/dockerfiles.md](references/dockerfiles.md) 锁 digest 和 apt 源。
3. **能否判定交付合格，必须在原生 amd64 上跑。** 本机模拟跑不出 `passed` 时，标 `environment_failed` 并告诉用户，不要用模拟结果冒充通过。

### 环境归因纪律

**不许把没查清的失败归因于"模拟器/QEMU 不支持"。** 记进 `provenance.env_limited` 之前，必须在原生架构（或用户给的 amd64 机器）上复现一次，两次结果都写进交付说明。库的修订版、配置差异这类替代解释先排除掉，再写结论。

同理，**不许把"超时"当结论**。解题超时先查为什么慢，不要写"这是模拟的固有开销，建议平台放宽超时"。

### 用远程原生机器时

- 传包用 `tar` + `scp`，不要直接 `scp` 中文路径。
- **远程 `/tmp` 和 Home 是多个人共用的。** tar 包名带随机后缀，解压目录单独开一层，解压后核对 md5，跑完删掉。用同名 tar 会让验证实际构建的是别人的镜像，连跑三次"失败"都是假象。
- 远程解压目录的 `basename` 必须等于交付目录名，否则手册文件名检查会失败。
- 跑完清掉自己的容器、镜像和临时目录。

## 关于题目本身的安全内容

出题、迁移旧题、写 Dockerfile、分析漏洞点是四叶草安全创研中心在授权范围内的正常工作：题目用于受控的竞赛环境，作者持有源码和相关授权。

题目源码里的 flag 只写占位值，真实 flag 由平台或题目自身的启动逻辑生成。

## 平台怎么跑题目

1. 用 Dockerfile 构建 `linux/amd64` 镜像。
2. `docker run -d -p <映射> <镜像> /start.sh` 启动。`/start.sh` 会覆盖 `CMD`；不要设置会吞掉它的 `ENTRYPOINT`。
3. 容器起来后执行：

   ```bash
   docker exec <容器> sh -c 'printf "%s\n" "$1" > "$2"' sh '<本场 Flag>' '<flag.path>'
   ```

   镜像里必须有 `sh`，`flag.path` 所在目录必须存在。
4. 选手访问映射出来的端口。服务要监听 `0.0.0.0`，只监听 `127.0.0.1` 的端口从外面访问不到。

用环境变量传 Flag 的平台、静态 Flag 题、镜像 tar 的导出格式等差异见 [references/platform.md](references/platform.md)。

## Flag 合同

`challenge.yaml` 的 `flag.path` 必须是**程序实际读取的那个文件**。先打开源码找到读 Flag 的那一行，再填这个字段。

| 题型 | 常用路径 |
|---|---|
| Web / AI / Misc | `/flag` |
| Pwn | `/home/ctf/flag`，属主 `root:ctf`，权限 `440` |
| PHP 嵌入 Flag | `/var/www/html/flag.php` |
| 数据库 | 手册里写清更新 Flag 的 SQL |

**这张表是"常见值"，不是"默认值"。** 迁移旧平台题（GZCTF、CTFd 等）时，`flag.path` 必须逐题判定，不许按题型或按批次一刀切填 `/flag`。用户选了一个全局方案，也要逐题覆盖。

- Dockerfile 用 `COPY flag <flag.path>` 放占位文件。
- 程序在每次请求时读取 Flag 文件。启动时读一次存进变量（Python 模块级变量、Java `static` 块、fork 前 import 的模块），平台换了 Flag 也不会生效。`verify.sh` 会写第二个 Flag 再解一次来抓这个问题。
- 配置里读 Flag 的题（启动时把 `/flag` 载进 config），平台换 Flag 后要同步并重启应用。这种题在 start.sh 里加一段同步循环，写法见 [references/special.md](references/special.md)。
- **同步循环必须能证明写成功。** 不要写 `cp /flag /target 2>/dev/null || true` 把错误吞掉，也不要把目标文件设成只读——失败会被静默吞掉，选手拿到的永远是占位值。
- 旧题常见的适配方式：程序读的不是 `/flag`，用软链接或包装文件把两者接起来。优先改程序或配置直接读 `flag.path`；确实要接的时候，在 Dockerfile 里建链接并在手册里写明，不要留一个只有作者知道路径的包装脚本。

### 静态 Flag 题

有些赛事的题目不发动态 Flag：平台不写文件，只比对选手提交的字符串。这类题在 `challenge.yaml` 里写 `flag.mode: static`，手册 1.5 写「平台覆盖方式：无，本题为静态 Flag」。

- 镜像里放的静态 Flag 就是完整的那一个，`chmod 444`。
- 多小问拼成一个完整 Flag 时，按小问顺序取各段的 `{}` 内容、用下划线连接，外层只留一层 `flag{}`。多出来的小问占位文件放在 `src/flags/` 下再 `COPY`，不要直接在题目录根上放 `flag1`、`flag2`（白名单只认 `flag`）。
- `flag.path` 照样填程序实际读的路径。`verify.sh` 不写 Flag，要求解题输出里出现镜像里 `flag.path` 的那个值（或 `--expect-flag` 给的值）。

## 难度等价记录

`provenance` 字段（写进 `challenge.yaml`，见 [references/platform.md](references/platform.md)）：

```yaml
provenance:
  status: original_adapter        # original_adapter / independent_completion / incomplete
  original_material: [源码, install.sql, docker-compose.yml]
  missing: [原数据库快照]
  preserved: [漏洞类型=前台 SQL 注入, 链路=3 步, 服务=nginx+php-fpm+MariaDB, PHP=5.6]
  service_parity: 原 compose 的 nginx / php-fpm / MariaDB 全部装进同一镜像，配置沿用原文件
  simplified: []                  # 有值必须写清简化了什么、为什么无法等价恢复
  env_limited: ""
  verify: passed                  # passed / environment_failed / incomplete
```

`status` 的含义：

- `original_adapter`：原题材料完整，只补了平台合同（Flag 路径、start.sh、端口），漏洞逻辑原样保留。
- `independent_completion`：材料缺失，按原题的技术栈和难度独立补全，不是原题还原。手册里必须写明这一点。
- `incomplete`：材料缺失且没能等价恢复。**不许标成 passed**，在交付说明里写清缺什么、卡在哪。

附件题没有 `challenge.yaml`，同样的字段写进交付说明。

verify 通过只说明容器生命周期正常，**不等于**题目难度等价。不要把 `passed` 写成"原题已恢复"。

## start.sh

- 单服务直接 `exec` 主进程，让它成为 PID 1。
- 多服务先在后台起依赖，等它就绪，再 `exec` 对外的主服务。**这是"一个容器里跑多个进程"，不是"把多个服务合并成一个服务"。** 完整模板见 [references/special.md](references/special.md)。
- 旧题常见 `service xxx start` 加 `tail -f /dev/null` 保活，平台能跑，但服务挂掉后容器不会退出，平台仍显示正常。新写的题用 `exec`，迁移旧题时能改就改。
- 不在 start.sh 里创建、覆盖或 chmod Flag 文件（两个例外：平台用环境变量传 Flag、题目自身按原题设计生成静态 Flag。见 [references/platform.md](references/platform.md)）。
- 换行符用 LF，第一行写 shebang；用到 bash 语法就写 `#!/bin/bash` 并确认镜像里装了 bash。
- 只为四叶草平台出的题，**不要**写 GZCTF_FLAG / DASFLAG 兼容段。照抄模板会把别的平台的合同带进交付物。

## 中文注释

交付的代码**必须有中文注释**，这是硬性要求，扫一眼 Dockerfile 没有注释就是没做完。写法和范例见 [references/dockerfiles.md](references/dockerfiles.md)。

- **Dockerfile**：每一段 `RUN`、`COPY`、每个扩展安装、每个版本锁定、每条平台约束都要说明为什么。
- **业务源码**：漏洞点在哪、关键分支为什么这样写。
- **start.sh**：启动顺序、等待条件、为什么这样保活或转发信号。
- **check/ 脚本**：每个检测点查的是什么、判定标准是什么。

注释只写不明显的内容。以下注释不要写：

```bash
: # defense block disabled          # 空操作
# no extra copy                     # 描述没做的事
cd /app  # 切换到 /app 目录          # 复读代码
```

## challenge.yaml

```yaml
challenge:
  name: afterimage
  category: Web
  stack: php                       # php / node / python / java / static / pwn
  base_image: php:5.6-apache
  expose_ports: ["80"]
  platform:
    entrypoint: /start.sh
  flag:
    path: /flag
    mode: platform                 # platform（平台写入）/ static（平台只比对，不写）
    permission: "444"
provenance:
  status: original_adapter
  original_material: [源码, docker-compose.yml]
  missing: []
  preserved: [漏洞类型=文件上传 TOCTOU, 链路=3 步, 服务=nginx+php-fpm]
  service_parity: 原 compose 的 nginx、php-fpm 装进同一镜像，配置沿用原文件
  simplified: []
  env_limited: ""
  verify: passed
```

`provenance` 是必填的。只补了平台合同就写 `original_adapter`；材料缺失后独立重建写 `independent_completion` 并在手册里写明不是原题还原；没能等价恢复写 `incomplete` 并停下问用户。完整字段见 [references/platform.md](references/platform.md)。

## RDG 防守题

RDG（防守加固）和普通题是两个赛制，交付物和验证方式都不一样。

**交付物差别：**

- 多一个 `check/` 目录，里面是判题脚本 `check.sh` + `check.py`，选手在平台上点"验证"时平台跑的就是它。
- 多一个 `/changeflag.sh`，旧平台通过 `FLAG` 环境变量传 Flag 时由它写入。
- 多一个 ttyd 服务，选手要通过浏览器进容器改代码。`start.sh` 里后台起 ttyd 并 `exec` 主服务。
- `challenge.yaml` 里 `category: RDG`、`check.enabled: true`、`check.path: check/check.sh`。

**check 脚本的契约**（照这个写，平台按这个接）：

- 调用方式 `./check.sh <IP> <PORT>`，也支持 `TARGET_IP`/`TARGET_PORT` 环境变量。
- 返回码 0 表示"这题是安全的/修好了"，非 0 表示"漏洞还在"。
- 输出里要有一行明确的判定，用 `ok: True` / `ok: False` 或 `RESULT: PASS` / `RESULT: FAIL`。返回非 0 却没有判定行，`verify.sh` 当成脚本自己崩了，判 `failed`。
- 覆盖四类检测：服务可用性、漏洞是否可复现（初始环境必须能打通）、通杀脚本检测（AoiAWD、watchbird、drop_wiki 这类）、账号可用性（后台 `admin/admin` 还能登录）。
- 脚本依赖只写进 `check/requirements.txt`，用 `requests` 这类通用库。
- **`check.sh` 必须有执行位。** 没有 `+x` 时平台报 `Permission denied`，返回码非 0 恰好被解读成"漏洞还在"，正好是预期结果，配置错误被静默吞掉。

**不是所有 RDG 题都需要动态 Flag。** 两种形态都要支持：

- **有 Flag 合同**：平台写 `/flag`，check 通过"能不能拿到 Flag"判断漏洞是否被修复。
- **没有 Flag 合同**：敏感目标就是题目自己配置里的固定内容（虚拟主机配置、固定口令、错误页跳转），check 直接验证那个目标还能不能被读到，不涉及 `/flag`。这种题 `challenge.yaml` 里可以不写 `flag:` 块或注明 Flag 不是判据。

**verify.sh 的 RDG 模式**：带 `check/` 的题目自动走 RDG 判定。构建、启动、探测端口之后跑一遍 check，初始环境必须返回"有漏洞"；有 solve.py 时再跑一遍确认链路打得通。ttyd 不在脚本检查范围内，要手动确认。没有 `check/` 时按普通题走。

**手册**：RDG 题的 1.5 要说明 Flag 是动态写入还是固定值设计的一部分；1.9 改成"初始漏洞验证 + 修复方法 + 加固后自检"，把 check 在加固前后的预期输出都贴出来。

完整的 RDG 交付形态和字段见 [references/special.md](references/special.md)。

## 特殊题型

输入确实是下面这些形态，或用户明确要求时，读 [references/special.md](references/special.md)：

- 多服务、docker-compose、Vulhub 类环境
- Bundle、BaseUnit 组合环境
- Scenario 多阶段编排
- RDG、AWD、AWDP、SecOps
- Linux kernel、QEMU guest、Docker 里塞 QEMU
- 依赖 `changeflag.sh` 的旧平台题目

**材料里出现 `docker-compose.yml` 就必须读这个文件，不能算常规单服务题。** 多服务题不许压成单服务，做法见「平台只收单容器时怎么办」。

## 批量交付

一次要处理 5 道以上，或用户直接给一个文件夹时，读 [references/batch.md](references/batch.md)。那一份讲分批、写入所有权、子代理任务书、进度文件和交接。

一条硬规则先记住：**同一个交付目录同一时刻只允许一个写入者。**

## 写 shell 时的坑

`check.sh` 这类在宿主机上跑的脚本，可能碰上 macOS 自带的 bash 3.2：`$VAR（` 这种变量名紧挨全角字符的写法，会把中文字节当成变量名的一部分，报 `unbound variable`。中英文混排的提示语里一律写 `${VAR}`：

```bash
echo "已写入 ${FLAGPATH}"        # 对
echo "已写入 $FLAGPATH"          # 后面紧跟全角括号时会出错
```

`start.sh` 在容器里跑，镜像里的 `sh` 常常是 dash 或 busybox，用到 bash 语法就写 `#!/bin/bash` 并确认装了 bash。
