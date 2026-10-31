# 更新日志

本项目的重要变更都会记录在本文件中。

## v6.3.16 - 2026-10-31

发布后用 4 个子 Agent + DeepSeek 实测暴露的 bug。

### 修复

- **`section_body` 不识别代码块围栏**：用 awk 提取手册各节正文时，把 flag_script 模板里的 `# 平台注入时…` 注释当成 markdown 标题，导致代码块之后的「读取时机」「$new_flag」字段读不到，照官方手册模板写反而误判 partial。改成跳过 ``` 围栏内的行。
- **`COPY .` 检查跨平台失效**：`grep -viE '--from='` 在 BSD grep 和 GNU grep 里都把 `--from=` 当长选项报错，导致 COPYDOT 恒空、检查被跳过。改用 `grep -viE -e '--from='`。
- **`.tar` 目录报 passed**：只含 tar 的打包成品目录给绿色 passed 但什么都没验证，是假信号。改成 partial，明确「未验证」。
- **端口探测时序竞态**：对「等 flag 写完再起服务」的题（Skill 推荐的 Flag 同步等待模式），verify.sh 先等端口再写 flag 的顺序会导致端口永远等不到、误报「端口没监听」。改成端口 none 时写 flag 后再等 15 秒，给服务起的机会。
- **QEMU 环境失败归因不全**：端口超时 + 出题人已在 provenance.env_limited 声明本机跑不动时，仍判成题目 failed。改成归为 environment_failed。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 4 个子 Agent 实测：容器题、附件题、打包成品、从零做新题、排查坏题，除上述 bug 外全部正常。

## v6.3.15 - 2026-10-31

发版前最后一轮（代码 + 文档两个 Agent 审查）的收尾。

### 修复

- **`flag.mode` 大小写不敏感只改了一半**：有 PyYAML 的路径改了小写化，无 PyYAML 的文本兜底 grep 还是大小写敏感。补 `-i`。
- **`COPY .` 检查被多阶段 Dockerfile 绕过**：文件里只要有 `COPY --from=` 就放行整份文件的 `COPY .`。改成行级排除，只有该行本身不含 `--from=` 才拦。
- **`passwd` 扫描没跟上收紧**：`password` 加了引号字面量要求，`passwd` 还是裸 `[:=]`，变量赋值仍产生噪声。补齐。
- **`stage hygiene partial` 残留**：PII/凭据/手机号这三处已降为 hint 但保留了 `stage ... partial`，导致报告 stages 和最终 status 对不上。删掉残留的 stage。

### 文档

- README 仓库结构注释「三档来源」→「四档来源」（中英）。
- SKILL「两类」→「三类」（漏计 RDG）；删 SKILL 命名链的重复段。
- platform.md 补 `metadata.image_tag` 字段定义。
- README 退出码表补「参数错误 2」。
- 四处 flag_script 模板注释统一。
- SKILL 覆盖表第 9 条分清「判 failed」和「已降提示」。
- 清掉 batch.md 的对仗句和 SKILL 的 hedge 词。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 两个审查 Agent 结论均为「可以发版」。

## v6.3.14 - 2026-10-31

边界与兼容性测试的收尾修复。

### 修复

- **`_killtree` 作用域 bug**：原来定义在 `run_solve` 函数体内，负向对照（dead-port 探测）调用的是全局 `_killtree`，而 solve 正常通过时它从未被定义，导致负向对照的 solve 超时后留下孤儿进程。提为顶层函数。
- **`flag.mode` 大小写敏感**：`STATIC`、`Static` 被当成动态 Flag 题。改成大小写不敏感（无 PyYAML 兜底也加了 `-i`）。
- **`provenance` 缺 `verify` 整行不检查**：`status` 有但 `verify:` 行整个缺失时直接 passed。现在判 failed。
- **`--report` 写失败污染结论**：报告的 IO 错误原来把题目判成 failed。降为提示，不影响题目结论。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 实测：`mode: STATIC` 大写 → passed；缺 verify 行 → failed；报告写失败 → passed + 提示。

## v6.3.13 - 2026-10-31

用真实产物回归（AI-81 81 题、数信杯 20 题、EXP-23 8 题、甘肃电信 18 题）量化了误报率，修掉 5 处确定性误报 + 按用户决定调整 3 条判定。

### 修复

- **flag 残留检查的 516 个噪声文件**：正则「任意 token + {」把内联 CSS（`body{…}`）、f-string 拼 HTML（`n{item}`）、SQL 里的 JSON 全当成 flag。改成只认 `flag/ctf/dasflag` 前缀。
- **`password =` 变量名被判生产凭据**：`password = _get_kv(...)`、`String password = params.get(...)` 全被误报。改成只认 `=` 右边是引号字面量。
- **start.sh 写 flag 的注释/日志误判**：注释里引用平台命令、日志里的 `/root/flag` 被当成覆盖。改成先剥行内注释，且要求重定向紧跟路径。
- **目录形态漏了 AWD 现场打包**：`题目镜像/ + attachment/ + check.py + source/ + 手册(带括号)` 没被识别。改成只要有 `题目镜像/` 目录就按比赛归档跳过。

### 判定调整（按用户决定）

- **`name` 与目录名不一致降为提示**：历史题大量用短 id（asi-01、redis-topk），实际没采纳「name 必须等于中文目录名」，报 partial 只会淹没真问题。
- **`original_material` 路径检查降为提示**：它记的是「出题人手里的原始材料清单」，写上游仓库路径（dvlaa/modules/xx.py）而交付目录里没有，是正常的上游来源引用，不是错。
- **`attachment_only` 保持 failed**：v6.3.0 已废弃的取值，还写的题要改。
- **1.6 端口写法放宽**：`127.0.0.1 的 8099 端口`、只写 `0.0.0.0` 都算写了端口。
- **PII/凭据扫描降为提示**：只提示不改结论。
- **数据来源统一为四档**：出题人材料、外部 writeup、本次交付实测、留 TODO（manual.md 和 README 之前只有三档）。

### 文档

- CHANGELOG 里错误插入的 `## Unreleased` 并回 `## v6.3.0`。
- README 删掉已废弃的「镜像 tar 一致性检查」表述。
- 中英 README 仓库结构注释、白名单 `last/`、RDG 样例阶段、数据来源四档、`challenge.yaml` 示例 `name` 统一。
- SKILL.md 补「solve 不许有本地文件/docker exec 兜底」。
- 清理文档里的破折号和对仗句（README/SKILL/references 全部，代码注释保留）。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 真实产物：AI-81 抽检告警从每题 3-5 条降到 1-2 条，且剩下的都是 `attachment_only`（真问题）或上游引用提示。

## v6.3.12 - 2026-10-31

用真实产物做回归时发现的一批误报，大多是检查写得过严。样本：AI-81 的 81 道、数信杯的 20 道。

### 修复

- **串题检查命中题目自己**：按目录名排自己，但比的时候用的是 `challenge.yaml` 的 `name`，两者不同时自己的 name 会留在候选集里再被搜到。AI-81 的 24 条串题告警**全部是命中自身**。改成按 `challenge.yaml` 的 name 排。
- **串题检查按空格截断 name**：`name: What is hikvision` 被解析成 `What`（4 字符，恰好过门槛），然后任何写 "What" 的手册都误报。改成取整行。
- **`original_material` 两类误报**：带中文括注的条目（`src/ICPV2（ICP 备案系统 webapp 原始目录）`）整串当路径；带斜杠的路径只在根目录核对，不查 `src/`。数信杯 26HW 的 8 条里 7 条其实存在。改成剥括注 + 所有路径都回退到 `src/` 等子目录找。
- **1.6 关键词检查太窄**：写 `http://127.0.0.1:8080/` 或 `127.0.0.1:5020` 比写"端口：8080"信息更全，但不含"端口/账号/地址"三个词就判字段不全。补 URL 和 `ip:port` 形态。
- **`COPY --from=builder . /app/` 被当成 `COPY .`**：多阶段构建的合法写法，拷的是构建阶段产物不是构建上下文，会被直接判 failed。带 `--from=` 的放行。
- **`stage` 覆盖 partial**：手册和 provenance 的检查里，1.5/串题报了 partial 之后仍执行 `stage ... passed`，报告 JSON 的 stages 和最终 status 对不上。改成按 notes 判断。
- **`--expect-flag` 只取第一个 flag**：题目先打印诱饵旗、后打印真旗时误判。改成输出里任一匹配等于 expect 就算过。
- **附件题被按容器题标准卡 1.5**：要求含 `$new_flag` 的脚本、要求写 `读取时机`、要求 `flag.mode: static`——附件题没有容器，这些都不成立。改成只对容器题查。
- **0 字节附件、硬链接降为 hint**：这两项是交付硬伤，恢复成 `partial`。

### 删除

- **镜像 tar 一致性检查**。实测不可靠：即使源码没改，两次构建的 base 层摘要也会不同（alpine 重新拉取），`RootFS.Layers` 同样对不上。这个判据没法稳定成立。

### CI

- 显式安装 PyYAML。没装时 `verify.sh` 退回文本匹配，provenance 枚举校验和 `name` 一致性检查会静默失效。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 实测：AI-81 抽检无串题告警；数信杯 26HW 的 material 告警从 8 条降到 1 条（剩的那条是真缺失）；诱饵旗场景正确解出真旗；0 字节附件判 partial；附件题带 `challenge.yaml` 判 passed。

## v6.3.11 - 2026-10-30

代码正确性审查第三轮，加上 README 补齐。

### 修复

- **`--report` 写失败仍报 `passed`**：目标目录不存在时只往 stderr 打一行，`finish` 照走 passed、退出码 0。现在写失败判 `failed`。
- **报告 JSON 遇到多行 note 就是非法 JSON**：`json_str` 只转义了反斜杠和双引号，没转换行。凭据命中时 note 是多行，`json.load` 直接报错。现在换行也转义。
- **solve 超时留下孤儿进程**：只 kill 子 shell，真正的 `python3 solve/solve.py` 被 init 收养继续跑（`PPID=1`）。受控复现：`--solve-timeout 3` 的 `sleep(120)`，脚本退出后进程还在。改成递归杀整棵进程树。`setsid` 只在有它的系统上用——**macOS 没有 `setsid`**，之前硬写导致所有解题命令报 `exec: setsid: not found`。
- **负向对照不传 `PORT_<容器端口>`**：只传 `PORT`，只读 `PORT_8080` 的 solve 在负向轮因缺变量直接退出、不输出 Flag，负向对照恒通过——正好漏掉它要抓的场景。
- **`--similarity-report` 没有交付目录守卫**：能把报告写进交付目录，随后被白名单判 failed（自伤）。现在和 `--report` 用同一段守卫。
- **缺参数退出码是 1 不是 2**：`${2:?}` 直接终止，和文档写的"2 参数错误"不符。改成显式检查。

### 文档

- README 中英文补齐 v6.3.5~v6.3.11 的新特性：出题人意愿优先、问题分级、动态 Flag `/bin/bash` 规则、`flag_script` 模板、镜像 `USER` 注意事项、`--no-cache`/`--ready-cmd`/`--similarity` 等参数、solve 负向对照、新增检查项清单、partial/failed 的准确语义。中文 +70 行，英文 +56 行。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 实测：报告写不进目录 → `failed`；凭据多行 note → JSON 合法；`--solve-timeout 3` 的 `sleep(120)` → 无孤儿进程（macOS 无 setsid 也有效）；缺参数 → 退出码 2。

## v6.3.10 - 2026-10-30

多 Agent 终检（代码正确性 / 文档一致性 / 回归与误报 / 交付可用性）发现的问题。

### 修复

- **静态 Flag 题被误判 `partial`**：`STATIC_FLAG` 到写 Flag 那段才赋值，而手册 1.5 检查在它之前跑，导致所有静态 Flag 题、RDG 无 Flag 合同题走动态分支，报三条假阳性（缺 `$new_flag`、缺读取时机、「写了平台覆盖方式无但没写 mode: static」）。赋值提前到手册检查之前。
- **根目录 `.DS_Store` 仍判 `failed`**：白名单遍历把 `.DS_Store` 当白名单外条目判死，和「垃圾文件只提醒」打架。白名单遍历现在跳过已知垃圾文件，统一走 JUNK 的提示。
- **`solve.py` 依赖检查三种误报**：本地模块（`from helper import ...`）、`try/except ImportError` 包住的可选依赖（z3）、文件头已注明 `pip install` 的，全都被判 `failed`。改成 AST 解析并排除这三类，且降为 `hint` 只提示。删掉旧的 grep 正则检查（会误报可选依赖）。
- **缺 Dockerfile 的容器题被静默当附件题通过**：有 `start.sh` 却漏了 `Dockerfile` 时，原来走附件题分支直接 `passed`。现在报 `failed`。（`challenge.yaml` 不算判据——附件题可以带一个只声明 provenance 的。）
- **手册串题检查按字节算长度**：`Web`、`Pwn`、`某` 这类短名字会误报。改成按字符算，门槛 4 字符。
- **PII/凭据扫描漏了 `题目附件/`**：外层门认这个目录，但 `grep` 参数里没列。
- **「提醒」类检查实际降为 `partial`**：雷同度、垃圾文件、凭据、flag 残留、CDN、首页 404、`start.sh` 写 flag、镜像 tar 不一致、硬链接、附件 0 字节——全部改成 `hint`，只提示不改结论。
- **Flag 同步等待模板照抄会崩**：`IMAGE_STATIC_FLAG` 从未赋值，`set -u` 直接退出。改成从 `/opt/static-flag.sha256` 读哈希比对，读不到就退化成只校验格式。

### 文档

- 「出题人意愿优先」与「默认恢复原题难度」的冲突：恢复原状不算「改难度」，已注明。
- `provenance.verify` 的枚举补 `no_flag_contract`（`platform.md`、`SKILL.md`）。
- SKILL.md 补「附件题手册去掉 1.7、编号顺延」。
- `env_limited` 该标 `verify: environment_failed`，`status` 保持原判定（原来写的是标 `status: incomplete`）。
- `alpine、slim、distroless` 那句自相矛盾：slim 是 Debian 系，自带 bash。
- 平台「30 次重试」的说法改为准确版：只有 MySQL socket 未就绪才重试，缺 bash、权限拒绝第一次就放弃。
- ttyd 说法统一：端口会被探测，登录可用性要人确认。
- 自检清单条数（batch.md 的 15 → 逐条）、「其余四处」→「其余五处」。
- `verify.sh` 里「平台以 root 执行 docker exec」的旧注释改掉（平台 `exec_run` 不传 user，继承镜像 `USER`）。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 实测：静态 Flag 题 `passed`；本地模块 solve `passed`；`try/except` 可选依赖 `passed`；缺 Dockerfile 的容器题 `failed`；根目录 `.DS_Store` 只提示；短题目名不再误报串题。

## v6.3.9 - 2026-10-30

逐条复核 v6.3.5 ~ v6.3.8 里未经确认的判断，共 34 条，用户逐条表态。结论：33 条保留，1 条改回。

### 修复

- **`.DS_Store` / `__pycache__` / `*.pyc` 改回只提醒**。v6.3.6 把它们从 `partial` 收成了 `failed`，用户裁定改回：这类垃圾文件只提示清理，不改交付结论。白名单外的顶层条目仍然判 `failed`。

### 新增

- **SKILL.md 新增「出题人意愿优先」**，放在所有规则最前面。核心是：这个 Skill 是给作者打工的，不是替作者做主的。改判定结果、改交付物、在多个方案里选、删改已有内容、自己拿不准的，动手前必须先问，说清"打算改什么、为什么、会影响什么"；自己查得证的事实（代码、平台、文件）照旧自己查；作者说"无所谓"就保持现状，不要过两轮又提一次。
- `agents/openai.yaml` 的 `guidance` 同步这条原则。

### 复核结论（保留不变）

- 白名单外条目判 `failed`、provenance 取值枚举校验、`no_flag_contract` 取值
- `name` 与目录名一致、`original_material` 路径存在、手册同节号重复判 `failed`、手册串题提醒
- 手册 1.5 四项核对、`start.sh` 写 flag 提醒、首页 404 提醒、外网 CDN 提醒
- 镜像 tar 与构建一致、flag 残留扫描、solve 负向对照、PII 文件类型扩到 20 种
- 问题分级三档、雷同度阈值 0.6、`--similarity` 默认关闭
- `APP_NAME`、打包成品三种形态、原材料缺陷四类、单题止损线
- 自检清单 21 条、`COPY --chown` 允许、`allowed-tools` 声明
- 静态 Flag 写来源、动态 Flag 占位值不要求、`/sync-flag.sh` 命名建议、AI 题运行时限制、子 Agent 降级顺序

## v6.3.8 - 2026-10-30

第四个维度（验证盲区）的复查结果，以及修复 v6.3.7 引入的一个严重 bug。

### 修复

- **v6.3.7 的镜像 tar 一致性检查在 containerd 镜像存储下 100% 误报**。启用 containerd image store 时 `docker save` 出的是 OCI 布局，`manifest.json` 的 `Config` 是 config blob 摘要，而 `docker image inspect` 的 `.Id` 是 manifest 摘要，两者天然不等。本机实测确认（`Driver=overlayfs` 但 tar 是 OCI 布局）。现在先读 `index.json` 的 digest，读不到才退回 `manifest.json`。
- **不是 `docker save` 产物的 tar 原来静默跳过**，现在报 partial（平台 `docker load` 不进去）。
- **手册串题检测的单字误匹配**：同批题目名里有个叫「某」的，导致所有手册都报串题。改成按字符长度 ≥4 才参与匹配。
- **手册 1.5 的 `$new_flag` 检查加了等价例外**：1.5 已经写了 `docker exec` 或 `flag_script` 命令的，只给 hint 不判 partial。

### 新增

- **`verify.sh` 增加 solve 负向对照**。拿完 Flag 后，把 `HOST/PORT` 指向一个确定关着的端口再跑一次，必须失败。真实事故：solve 里有 `docker exec` 兜底、或写死了答案，正向永远通过但平台链路上根本不通。实测能抓到「兜底读容器」的 solve。
- **手册 1.5 的字段核对**（原来只判「出现过 flag 两个字」）：
  - 动态 Flag 题：检查有没有含 `$new_flag` 的 flag_script（平台保存题目时校验必填）；检查有没有写「读取时机」。
  - 静态 Flag 题：1.5 写的原始静态值和 `flag` 文件比对（真实事故：差一个后缀，选手提交不对）。
  - 1.5 写「平台覆盖方式：无」但 `challenge.yaml` 没写 `flag.mode: static` → partial。
- **PII/凭据扫描补文件类型**：加 `*.xml *.txt *.html *.log *.ini *.sh *.jsp *.cfg`。真实事故的 8 万条 PII 就在 `Export/temp/*.xml` 里，而原来的 `--include` 列表恰好漏了 xml。
- **手机号密度检查补 `*.xml *.txt *.log *.xlsx`**，外层门补 `题目附件/`。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 负向对照实测：正常题不误报（`solve: passed`），带 `docker exec` 兜底的 solve 被抓（`solve: failed`）。
- tar 检查实测：本机 `docker save` 出的 tar，`index.json` 的 digest 与 `.Id` 一致；数信杯 `Web-FastDestruct` 的 tar 与当前构建**确实不一致**（`9feebe76` vs `4bba2a86`）。
- 真实产物抽检：手册串题误报消除；1.5 字段核对不误报正常题。

## v6.3.7 - 2026-10-30

第二轮全量复查：4 个子 Agent 按「产物质量 / 平台环境 / 用户诉求 / 验证盲区」四个维度重扫 30 个主会话和 189 个子 Agent 会话，并用真实产物（AI-81-DVLAA 81 题、数信杯决赛 20 题、甘肃电信成品）实跑验证。

### 修复

- **`verify.sh` 不认识「打包成品」形态**。比赛结束后留下的产物有三种：只有 `<题目名>.tar`、`题目附件/` + `题目手册.md`、`题目镜像/` + `题目源码/` + `题目手册/`。原来一律报「没有 Dockerfile」「白名单外的条目」，全是噪音。现在先判形态，成品直接 `skipped` 并说明。
- **附件目录名三种都认**：`附件/`、`附件/`、`题目附件/`。镜像目录认 `镜像/` 和 `题目镜像/`。
- **`original_material` 常写裸文件名**，实际在 `src/` 或 `solve/` 里。原来只在根目录核对，误报「不存在」。现在在 `src/`、`solve/`、附件目录、`题目源码/`、`镜像/` 里都找一遍。
- **flag 残留检查的误报**：`flag{FLAG_NOT_WRITTEN}`、`asi{CHALLENGE_ID:02d}` 这类占位串和 f-string 不算真实残留。
- **凭据检查的误报**：题目设计里的 `AIC10_HIS_USERNAME`、`username=`、`password=` 这类变量引用不算生产凭据。

### 新增

- **SKILL.md 新增「问题分级：什么才算缺陷」**。三档：阻断（拿不到 Flag / 难度被削 / 平台起不来 / Flag 写不进去）、要修（手册和实际不符）、记录即可（`.DS_Store`、镜像体积、未锁 digest、随机口令、动态 Flag 占位值）。用户已经为此连续否掉两份审计报告——「这些问题都不影响解题」「这是个 CTF 题目，不需要什么运维」「也不要为了寻找错误而寻找错误」。
- **SKILL.md 新增「汇报纪律」**：默认不中途汇报；用户喊停时先用已有结果回答、不再起新命令；flag/路径/命令从输出直接复制（真实事故：手打 flag 多了一个空格，用户当故障查了一轮）；用户不在场时单列「我替你做的决定」。
- **SKILL.md 新增「原材料自带缺陷」**：四类（泄题、实现与题解不一致、出题脚本 bug、Flag 路径矛盾）各给标准改法，改完必须在 1.8 写清并备份原文件。
- **`verify.sh` 检查手册串题**：同一节号出现 ≥2 次判 `failed`（真实案例：一份手册里有两套 1.5–1.8）；手册里出现同批其他题目的 `name` 判 `partial`。
- **`verify.sh` 检查选手第一屏**：root 路径 404/403 且没配 `probe_path`、首页是 `NOT-FOUND`/错误 JSON、页面引用外网 CDN——都报 `partial`。真实事故：nghttpx 首页返回纯文本 `NOT-FOUND`，Agent 自陈「确实像糊弄」；JeecgBoot **HTTP 404 但 `port: passed`**。
- **`verify.sh` 检查镜像 tar 一致性**：`docker image inspect` 的 Id 与 `manifest.json` 的 Config 比对。真实事故：改了 `start.sh` 后忘了重导，tar 里还是旧版（带 `touch /flag`），平台按 tar 部署时改动不生效。实测数信杯 `Web-FastDestruct` 就是这样（`f63c325d` vs `82a4f7d2`）。
- **`verify.sh` 检查 `src/` 和附件里的 flag 形态残留**：真实事故：`src/cache/trace.json` 带真 flag 进了镜像；附件 `test.py` 明文写着真 flag。
- **`references/special.md` 补 AI 题运行时**：进程内 CPU 推理（`llama-cpp-python`），不起 ollama，不调远程 API；判分确定性（温度 0、随机标识符固定、重试次数写进 1.9）；模型替换会改变难度，换模型要在同样判据下实测对比。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 三个 CI 步骤本地全部通过。
- 真实产物实测：
  - 甘肃电信成品（tar / 题目附件 / 题目镜像三种形态）全部正确识别为成品，不再报结构错误。
  - 数信杯决赛 20 题：`OpposeAI-小宝`/`OpposeAI-套壳` 归档形态正确跳过；`IOT` 的 `附件/` 正确识别；`original_material` 裸文件名不再误报。
  - AI-81-DVLAA 抽检：`flag{FLAG_NOT_WRITTEN}` 和 `asi{CHALLENGE_ID:02d}` 不再误报，真有残留的 `src/leak.py` 仍能报出。
  - `Web-FastDestruct` 抓到镜像 tar 与当前构建不一致。
- 数信杯 20 题里 17 题仍有结构问题（`name` 与目录名不一致、`original_material` 路径缺失、`.DS_Store`），这些不是误报——是历史交付物按新规范看确实不合规。

## v6.3.6 - 2026-10-30

在 v6.3.5 基础上，合并组 A、组 C 两份会话复盘的剩余发现。组 C 覆盖 5 个会话 + 6 份审计报告（20 个包、约 176 条确定问题）。

### 修复

- **`verify.sh` 不再用 `-u 0` 掩盖 Dockerfile `USER` 导致的写 Flag 失败**。平台注入脚本用 `exec_run` 不传 user，继承镜像 USER；镜像写了 `USER 1000:1000` 而 flag 属主是 root 时平台写不进去，而 `docker exec -u 0` 照样成功，verify 报 passed。现在按镜像 USER 再写一次，失败即 failed。真实事故：5 道题中招。
- **`references/platform.md` 的「平台以 root 执行 docker exec」是事实错误**，`docker exec` 默认继承镜像 `USER`。整段已换成真实机制。
- **`provenance.verify` 增加 `no_flag_contract` 终态**。原题没有 Flag 合同、按构造不可能验证 Flag 的题（证书固定文案、`flagFormat: (no flag format)`），原来只能写非法的 `partial`。
- **没装 PyYAML 时明确提示**，不再静默退回文本匹配。`{{flag}}` 写进 flow 序列这类语法错误只有真解析才查得出。
- **白名单外的顶层条目一律判 failed**。之前 305MB 的 `vendor/` 目录、夹带真实 flag 的 DSH 会话 zip 都能以 passed 交付。
- **`.DS_Store` / `__pycache__` / `*.pyc` 改判 failed**，不再只是 partial。
- **`start.sh` 写或 chmod flag 文件报 partial**。真实交付里 10 道题踩了这条。
- **新增硬链接检查**：多包共享 inode 时单独复制会丢内容。真实事故：两题共用 5114 个硬链接。
- **新增附件卫生检查**：0 字节文件、`__MACOSX`。
- **新增敏感数据扫描**：`src/`、`附件/` 里的口令、AKIA、私钥、成批手机号形态的数据。真实事故：企业备案题带着 8 万条真实 PII 和生产库口令。

### 新增

- **`verify.sh --no-cache`**：交付前最后一轮必须带。真实事故：建表 SQL 有重复 `AUTO_INCREMENT`，104 张表只建到 95 张，带缓存构建一直没暴露。
- **SKILL.md 新增「交付前扫 PII 和生产凭据」**：迁移企业源码时必须做，含扫描清单和处理方式。
- **SKILL.md 难度基线补「防护层实测」**：光看代码在不在不够，要在容器里实测拦不拦得住。真实事故：重建的 SSO 题 Shiro 完全没生效，题目变成全接口未授权。
- **SKILL.md 命名链补 `start.sh` 的 `APP_NAME`**：六处派生。真实事故：15 道题中文名做镜像 tag，`AI-多智能体记忆投毒与命令执行:latest`。
- **SKILL.md 附件规则细化**：压缩包和解压目录二选一、不能带 `__MACOSX`、不能有 0 字节文件。
- **SKILL.md 自检清单扩到 21 条**：新增防护层实测、敏感数据、可独立复制、`--no-cache`。
- **`references/batch.md` 新增「只读审计也要隔离」**：解包用独立临时目录、`python3 -B`、临时脚本不落题目目录。真实事故：审计员 `tar` 少写 `-C` 把镜像层解到题目根目录，多出一个 `flag`；用户要求「给出证据证明未被修改」。
- **`references/batch.md` 新增「静态审计的结论要运行期复核」**：S1/S2 没附运行期证据只能记待确认。真实误报：只读 INSERT 没读文件尾 UPDATE。
- **`references/batch.md` 补「一台机器不要并发跑多道」**：43 道并发验证，一道 1846 秒假失败，触发全量重跑。
- **`references/batch.md` 新增「单题止损线」**：同一道题超过 10 轮或 1 小时停下报告；官方解在本环境不可复现时标 `incomplete` 是合法交付。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 原有 7 项附件回归全过。
- 新增检查逐项实测：`USER 1000:1000` → `flag_write: failed`（exit 1）；无 USER → passed；`vendor/` 目录 → `delivery: failed`；`.DS_Store` → `delivery: failed`；硬链接 → `delivery: partial`；`start.sh` 写 flag → partial；`jdbc.password=...` → 凭据警告；正常附件题仍然 `passed`。
- 三个 CI 步骤本地全部通过。
- `--similarity` 在 AI-81-DVLAA 81 题上仍精准标出 9 份套模板手册。

## v6.3.5 - 2026-10-30

基于 30 个会话、205 个子 Agent 会话、两个交付产物目录（AI-81-DVLAA 81 题、EXP-23-CVEnew 8 题）的复盘，以及凌虚平台源码核对。

### 新增

- **动态 Flag 的真实机制**（`references/platform.md`）：从凌虚源码还原完整链路——平台把出题人配的 `flag_script` 打成 tar、`put_archive` 成 `/changeflag.sh`、`chmod +x`、`/bin/bash /changeflag.sh`、最多重试 30 次、`rm -rf`。`$new_flag` 是 `flag{md5(静态flag+用户id+容器short_id)}`，不是随机值。
- **硬规则：动态 Flag 题镜像必须有 `/bin/bash`**。alpine/slim/distroless 系镜像缺 bash 时平台注入静默失败，Flag 停在占位值，平台只提示"环境启动异常"。`verify.sh` 新增 `dynflag_bash` 阶段探测。
- **`flag_script` 标准模板**：可直接复制到平台后台，`$new_flag` 必须保留。手册 1.5 要求贴出这段原文。
- **Flag 同步等待模板**（`references/special.md`）：三条件判据（内容≠静态值、符合 `flag{.+}`、0.3 秒复核不变），超时 120 秒不阻塞启动。替代原来只比 `cksum` 的写法——实测平台写入延迟 1~4 秒、偶发 61 秒。
- **`verify.sh --ready-cmd` / `--ready-timeout`**：QEMU 题端口一开就判"已就绪"会吃掉 solve 的时间预算，现在可以指定真正的就绪判据。
- **`verify.sh --similarity` / `--similarity-report`**：同批手册雷同度检查，默认关闭。阈值 0.6，取自 AI-81-DVLAA 实测断崖（套模板组 0.61~0.66，其余 ≤0.34）。只报警告不改结论。
- **`verify.sh` 检查 `solve.py` 的第三方依赖**：用 AST 解析 import，逐个 `find_spec`，导不进来的直接 `failed`。本机装了某个库导致 verify 通过、评测机 ImportError 的问题从此能检出。
- **`verify.sh` 检查 provenance 内容**：status/verify 取值枚举、`name` 与目录名一致、`original_material` 列的文件是否真的存在。
- **SKILL.md 新增「不许套模板批量生成」**：手册正文不能是模板填空、1.9 必须是真实攻击顺序、Web 入口页不能是 `NOT-FOUND`、同批页面样式要有差异。
- **SKILL.md 新增「照手册手工复走一遍」**：`verify.sh` 全绿但手册命令写错的题，只有这一步能查出来。
- **SKILL.md 新增「不许为了让 verify 变绿去改产物」**：禁止删 apt 层、把 ENTRYPOINT 改 CMD、把题改简单来迁就验证器。
- **SKILL.md 新增「效率纪律」**：先手动确认单点事实、单题先手测再批量、长跑先说时长、不用全量重跑回答"还有没有问题"、不轮询。
- **SKILL.md 新增「主名派生一切」**：目录名是主名，challenge.yaml name、README 文件名、镜像 tag、tar 名全部从它派生。
- **SKILL.md 新增「Flag 的内容形态」**：solve.py 不许假设长度和字符集。真实踩坑：只认 `flag{` 前缀、39 字符因向下取整少一位、`&` 被 XML 转义成 `&amp;`。
- **SKILL.md 新增「已经有交付目录时」的五个体检问题**：上一版是简化版时逐题列出降级点，包括后门式简化（软链接直接放 web 根目录）。
- **SKILL.md 新增「Pwn / 内核题必须原生跑一次」**：libc 段地址假设在模拟下成立、原生不成立的真实案例。
- **SKILL.md 新增「垃圾清理一键命令」** 和 `python3 -B` 规定（避免只读检查生成 `__pycache__`）。
- **SKILL.md 命名补「简洁可读优先，不要文艺化」**。
- **SKILL.md 交付迁移补正确顺序**（先拷后核再删，先删后拷会丢数据）。
- **`references/special.md` 新增「平台层限制的标准改法」**：`/dev/shm` noexec、token 鉴权、消息节奏、上游镜像拉不到，逐条给标准改法和是否算降级。
- **`references/special.md` 新增「资源纪律」**：禁止 `docker system prune -af --volumes`（真实事故：删掉本机全部镜像 + 12 个卷约 65 GB）。
- **`references/batch.md` 新增「共享规范文件放哪儿」**（交付根之外，`verify.sh` 会把 `_*` 判 failed）、**「接手检查清单」**、**「子 Agent 叫不醒时」的降级顺序**。
- **`references/manual.md` 新增 1.7 完整可复制模板**、**「Web 类题的入口页」要求**、**1.5 里贴 flag_script**。
- **`references/platform.md` 的 GZCTF 模板加醒目警告**：不是模板、不要抄进交付物（真实事故：14 道 Pwn 题的 start.sh 全抄了这段）。
- **`references/dockerfiles.md` 新增「alpine 系必须装 bash」**，Node/nginx 范例同步加 `apk add bash`。

### 变更

- 判定「附件题少了 1.9」改为按 `is_container` 变量判断，不再重复 `-f Dockerfile`。
- 手册 TODO 提示的节号按题型给：附件题的题目设计和解题步骤顺延成 1.7、1.8。
- `references/special.md` 的 `changeflag.sh` 一节重写：平台自己注入，交付物里不该有同名文件；题目自己的 helper 改用 `/sync-flag.sh` 之类避免撞车。
- 静态 Flag 题要求手册 1.5 写明这个值从哪考证来的；动态 Flag 题的占位值写什么都行，不再要求"必须占位"。

### verify.sh

- 新增 `dynflag_bash` 阶段：构建后探测镜像里有没有 `/bin/bash`。
- 新增 `ready` 阶段：`--ready-cmd` 指定的命令返回 0 才算服务真的可用。
- 新增 `check_similarity()`：3-gram Jaccard，跳过代码块和注释，只比正文。
- 新增 solve.py 依赖检测：AST 解析 import + `importlib.util.find_spec`。
- `assert_provenance()` 补取值枚举、`name` 与目录名一致、`original_material` 路径存在。
- `--ready-timeout` 非数字直接退出码 2。
- 修复：编辑时重复插入的「交付前自检清单」已删除。

### 验证

- `bash -n` 通过，`shellcheck -S warning` 无警告。
- 原有 7 项附件题回归全部通过。
- 新增 6 项回归（solve 依赖缺失、provenance 非法取值、name 不一致、original_material 缺失、`--ready-timeout` 非数字、`--similarity` 报告），CI 新增 `verify.sh regression (6.3.5 additions)` 步骤，本地跑通。
- 容器题实测：alpine 无 bash → `dynflag_bash: failed`（exit 1）；`apk add bash` 后 → `dynflag_bash: passed`（exit 0）。
- `--similarity` 在 AI-81-DVLAA 81 题上实测：精准标出 9 份套模板手册（0.61~0.66），其余 72 份零误报。
- 三个 CI 步骤本地全部通过：attachment fixture、container static checks、6.3.5 additions。

## v6.3.0 - 2026-10-13


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

### CI
- 新增容器题静态检查回归 9 项：手册事实字段只在节内匹配、附件题 1.6 不要求端口、`start.sh` 的 `exec`/`wait`、`COPY .` 拦截、CRLF、缺 shebang、手册文件名、`--port` 非数字。
- 新增 VERSION 与 CHANGELOG 最新条目一致性检查；打 tag 时再检查 tag 名和 VERSION 一致。

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
