# 特殊形态（按需查）

输入确实是下面这些形态，或用户明确要求时才读。写法要求和 SKILL.md 一样：带中文注释，只放运行需要的文件。

常用几节：多服务与 compose、CMS 老框架缺数据库快照、AI 题本地模型、设计不完整的题、Bundle、Scenario、RDG/AWD、Linux-QEMU、旧平台 helper。

旧版渲染器和各类模板（`render.py`、`render_scenario.py`、`render_bundle.py`、各栈模板等）留在 [v3.0.1](https://github.com/D1a0y1bb/CloverSec-CTF-Pack/tree/v3.0.1/src/CloverSec-CTF-Build-Dockerizer) 标签里，不随 Skill 安装。优先手写干净版本；只有老环境复杂到手写不划算时，再去 v3.0.1 里翻对应文件参考。

---

## 多服务 / docker-compose / Vulhub-like

输入带 `docker-compose.yml`，或题目需要 web + db + redis 等多个容器。

### 平台只收单容器时，把服务装进同一镜像

四叶草平台一个容器一个入口。原题是 compose 多服务时，**正确做法是把原来每个服务原样装进同一个镜像，不是把服务合并掉**。

```
原题 compose                        交付的单个镜像
├── nginx        ─┐
├── php-fpm      ─┼─ 全部装进同一镜像，沿用原配置文件，版本按原题锁死
├── mariadb      ─┤   start.sh 先起依赖、等就绪，再 exec 对外主服务
└── admin-panel  ─┘
```

**不算降级的**：把 nginx、php-fpm、MariaDB 装进同一个镜像，配置沿用原文件，版本不变。

**算降级的**（必须先问用户）：把 nginx + php-fpm 换成 `php:*-apache`；把 php-fpm 换成 mod_php；把 MariaDB 换成 SQLite；删掉 admin-panel；升级 PHP / Node / JDK 的大版本。

判断标准很简单：**选手打的那条链，经过的每一层是不是还在。** 原题要过 nginx 的 location 匹配再进 php-fpm，交付里就必须还有 nginx 和 php-fpm。

### 服务层要逐项对照

改 Dockerfile 前后各列一次对照表，写进 `provenance.service_parity`：

```text
原题 compose         交付镜像
nginx:1.25.2         nginx 1.25.2（apt 装，配置文件沿用 src/nginx.conf）
php:5.6.33-fpm       php-fpm 5.6.33（配置文件沿用 src/sandbox.ini）
mariadb:10.4         mariadb 10.4（同一镜像，init.sql 沿用 src/install.sql）
```

对不上的那一行就是要停下来问用户的地方。

### start.sh 模板

五段按题目删减。这一段是"一个容器里跑多个进程"，和上面说的"不要把多个服务合并成一个服务"是两件事。

```bash
#!/bin/bash
set -euo pipefail

# 后台服务的日志直接写到容器 stdout，docker logs 能看到全部进程的输出。
log() { echo "[start] $*"; }

# 1. 依赖服务：后台启动，日志带前缀并入 stdout。
log "starting mariadb"
mysqld_safe --user=mysql 2>&1 | sed -u 's/^/[mysql] /' &

# 2. 等依赖就绪：探测真实可用状态，超时直接失败，平台会看到容器退出。
for i in $(seq 1 60); do
    mysqladmin ping --silent 2>/dev/null && break
    [ "$i" = 60 ] && { log "mariadb not ready after 60s"; exit 1; }
    sleep 1
done

# 3. 初始化数据：脚本可重复执行，容器重启不会报错。
mysql < /app/init.sql

# 4. 主服务：后台启动以便下面同步 Flag；收到 TERM/INT 时转发给它，平台停止容器不用等超时。
log "starting app"
python3 /app/app.py &
MAIN_PID=$!
trap 'kill -TERM "$MAIN_PID" 2>/dev/null; mysqladmin shutdown 2>/dev/null' TERM INT

# 5. 平台在容器启动后才写 /flag，数据库里的 Flag 要跟着更新。
#    题目不需要同步时删掉这段，改成 exec 主服务。
sync_flag() {
    local value
    value=$(sed "s/\\\\/\\\\\\\\/g; s/'/''/g" /flag)
    mysql ctf -e "UPDATE flag SET value='${value}' WHERE id=1;" || { log "flag sync FAILED"; return 1; }
    log "flag synced"
}
sync_flag || log "首次同步失败，循环会重试"
last=$(cksum < /flag)
while kill -0 "$MAIN_PID" 2>/dev/null; do
    now=$(cksum < /flag)
    [ "$now" != "$last" ] && { sync_flag && last=$now; }
    sleep 1
done

# 主服务退出时容器跟着退出，平台能发现题目挂了。
wait "$MAIN_PID"
```

- 第 5 段只在 Flag 存在数据库或配置文件里时需要；Flag 直接从 `/flag` 读的题删掉第 5 段，最后一行改成 `exec` 主服务。
- **同步失败要能看见。** 不要写 `|| true` 把错误吞掉，也不要把目标文件设成 `chmod 444`——下一轮同步会写不进去，选手拿到的永远是占位值。
- 后台服务不要把日志重定向到 `/tmp/*.log`，排查时 `docker logs` 看不到。
- 主服务是 `catalina.sh run`、`apache2-foreground` 这类前台命令时，第 4 段把它放后台即可。
- 排查时用 `verify.sh <题目目录> --keep` 保留容器，再 `docker logs -f <容器>` 看所有进程的输出。

必须保留多容器时，保留 `docker-compose.yml`，每个服务一个 Dockerfile，手册写清 Flag 写进哪个服务的哪个路径，并在交付说明里说明平台侧要额外支持 compose。`verify.sh` 只验证单容器，compose 题用 `docker compose up` 手动验证。

## CMS / 老框架题（源码完整但缺原题数据库快照）

老 CMS、二开系统的题经常只有源码，`install.sql`、`data/`、`database.sql` 要么缺失要么是占位内容。这类题的容器能起来，页面却是空的，漏洞链走不通。

- 先把缺口写清楚：缺哪张表、缺哪些初始数据、原来的快照在哪台机器上。
- 能补的补：从源码里的 `install/`、`schema.sql`、Model 定义反推建表语句，初始化最小数据让业务跑起来。
- 补不了的去问用户要原库快照，不要凭猜造数据结构，造出来的表和源码里的查询对不上。
- 手册里记"原资料缺口"和"补全边界"：补了哪张表、哪些字段是推断的、漏洞链是否还和原题一致。
- 缺口影响漏洞链时，这题按补全题交付，在手册和验证结论里写明，不要当成原题恢复。

## AI 题（本地模型 / 推理题）

AI 题常见的失败不是代码写错，是模型跑不起来。

- 权重文件要么打进镜像，要么在 Dockerfile 里下载并校验 SHA256。构建前先确认权重体积，超过几百 MB 的先问用户是打进镜像还是运行时挂载。
- 不要在 start.sh 里下载权重：平台环境可能没有外网，镜像构建阶段下载失败能立刻发现，运行时失败只会表现为超时。
- 构建后在容器里跑一次最小推理（`python -c "..."` 跑一个 forward），确认模型能离线加载。verify.sh 的 solve.py 正好可以承担这一步：解题脚本里包含一次推理，拿到输出再走漏洞链。
- 需要 GPU 的题要写清平台是否提供显卡；本机验证时 CPU 推理慢，给 `--timeout` 留余量。
- 题目的 Flag 合同和普通题一样，写进 `flag.path`，不要藏在模型输出里靠字符串匹配。

## 设计不完整的题（需要补全）

源码没有 Flag 读取逻辑、没有可行解题链，或者题目本身只写了一半时：

- 先判断是"恢复"还是"补全"。恢复是把原题整理干净，补全要新写逻辑，风险不同，结论也要分开写。
- 补全的边界写进手册：补了什么、依据是什么、原题哪些部分没动。
- 补全出来的漏洞链也要写 solve.py 验证，别只验证容器能起。
- 手册和交付说明里标注这题属于补全题，验证结论是"补全后通道可解"，不是"原题已恢复"。

## Bundle / BaseUnit（组合环境）

把多个可复用基础单元（BaseUnit）组合成一道题。保留各单元边界清晰，别揉成一个大镜像。历史格式见 v3.0.1 的 [`data/bundle_schema.md`](https://github.com/D1a0y1bb/CloverSec-CTF-Pack/blob/v3.0.1/src/CloverSec-CTF-Build-Dockerizer/data/bundle_schema.md)。

## Scenario（多阶段编排）

一道题分多个阶段/关卡，阶段间有状态流转。每个阶段源码独立成目录，编排关系写在配置里。历史 schema 见 v3.0.1 的 [`data/scenario_schema.md`](https://github.com/D1a0y1bb/CloverSec-CTF-Pack/blob/v3.0.1/src/CloverSec-CTF-Build-Dockerizer/data/scenario_schema.md)。

## RDG / AWD / AWDP / SecOps

这些是对抗/运维类赛制，和普通题的根本区别是：**判据不是"选手能不能拿到 Flag"，而是"漏洞还在不在"**。选手要进容器改代码把漏洞修掉，平台跑 check 脚本判断修好没有。

### 交付形态

```text
RDG-某企业官网信息系统/
├── README/
│   └── RDG-某企业官网信息系统.md     # 手册，文件名同交付目录
├── src/                              # 题目源码
├── check/                            # 判题脚本，平台调用
│   ├── check.sh                      # 入口，./check.sh <IP> <PORT>
│   ├── check.py                      # 检测逻辑
│   └── requirements.txt
├── Dockerfile
├── start.sh                          # 起 ttyd + exec 主服务
├── changeflag.sh                     # 旧平台用环境变量传 Flag 时用
├── ttyd                              # ttyd 二进制或配置，按原题保留
├── php.ini                           # 原题的 PHP 配置，按原题保留
├── challenge.yaml
├── flag
└── solve/                            # 本地验证用，可选
```

`check/`、`changeflag.sh`、`ttyd`、`php.ini` 这些是 RDG 特有的，必须和原题一起保留，不要为了"目录干净"删掉。

### check 脚本契约

平台按这个方式调用，照这个写：

```bash
./check.sh <IP> <PORT>
# 也支持环境变量
TARGET_IP=127.0.0.1 TARGET_PORT=8080 ./check.sh
```

- **返回码**：0 表示安全（漏洞已修复），非 0 表示漏洞还在。
- **输出**：每个检测点一行结果，最后一行是可判定的结论，用 `ok: True` / `ok: False` 或 `RESULT: PASS` / `RESULT: FAIL`。
- **检测点分四类**：
  1. 服务可用性：首页、后台登录页、关键接口能正常访问。这关挂了说明选手改崩了服务，直接判不通过。
  2. 漏洞是否可复现：初始环境必须能打通，加固后必须打不通。
  3. 通杀脚本检测：AoiAWD、watchbird、`waf.php`、`drop_wiki.php` 这类"一键通杀"文件是否存在。
  4. 账号可用性：后台 `admin/admin` 还能登录。选手改密码会让 check 失败。
- **初始环境预期返回"有漏洞"**。这是设计如此，不是 check 写错了。
- 依赖只写进 `check/requirements.txt`。

```python
# check.py 的判定结构
import sys

import requests


def check_index_alive(target):
    """检测点：首页可访问。服务被改崩时后面所有检测都没有意义。"""
    try:
        return requests.get(f"http://{target}/", timeout=10).status_code == 200
    except requests.RequestException:
        return False


def check_sql_injection(target):
    """检测点：前台 SQL 注入是否还能读出数据库用户。"""
    r = requests.get(f"http://{target}/search/?keys=1%27", timeout=10)
    # 还能报出 XPATH 错误，说明注入没被修掉
    return "XPATH syntax error" not in r.text


def check(target):
    ok = True
    if not check_index_alive(target):
        print(f"[-]: {target}, 服务检测失败 - 首页异常")
        return False
    print(f"[+]: {target}, 服务检测通过 - 首页正常")
    if not check_sql_injection(target):
        print("[-]: 前台 SQL 注入仍可利用，防御未生效")
        ok = False
    else:
        print("[+]: 前台 SQL 注入已被拦截")
    return ok


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = sys.argv[2] if len(sys.argv) > 2 else "80"
    result = check(target if port in ("", "80") else f"{target}:{port}")
    print(f"ok: {result}")
    sys.exit(0 if result else 1)
```

### 两种 RDG 题：有没有 Flag 合同

**有 Flag 合同**：平台写 `/flag`，check 通过"能不能拿到 Flag"判断漏洞修没修。

```python
def check_flag_leak(target):
    """漏洞利用成功后能读到 Flag，修好后读不到。"""
    r = requests.get(f"http://{target}/read?file=flag", timeout=10)
    return "flag{" not in r.text
```

**没有 Flag 合同**：敏感目标就是题目自己配置里的固定内容。这道题不需要 `/flag`，`challenge.yaml` 里 `flag:` 块可以省掉。

```python
def check_vhost_isolation(target):
    """加固目标是虚拟主机的 Host 隔离，读到固定内容说明没修好。"""
    r = requests.get(f"http://{target}/flag.html",
                     headers={"Host": "infernityhost"}, timeout=10)
    return "银行卡密码" not in r.text
```

写这类题时在手册 1.5 里明确说明：这道题的 Flag 不是平台写入的动态值，敏感目标是配置里的固定内容。别让运维以为平台写 Flag 没生效。

### start.sh：ttyd + 主服务

```bash
#!/bin/bash
set -euo pipefail

cd /var/www/html

# 旧平台通过 FLAG 环境变量传值时，先同步到兼容文件。
if [ -n "${FLAG:-}" ]; then
  /bin/bash /changeflag.sh "$FLAG"
fi

# ttyd 让选手从浏览器进容器改代码，端口必须监听 0.0.0.0 平台才映射得出去。
/ttyd -p 8022 -i 0.0.0.0 -W login &

# 主服务前台运行，容器跟着它退出。
exec apache2-foreground
```

没有 ttyd 二进制时用包管理器装，或按原题保留一份。ttyd 端口写进 `challenge.yaml` 的 `expose_ports`，`verify.sh` 会一起探测。

### verify.sh 的 RDG 判定

带 `check/` 的题目自动走 RDG 分支：

```text
build           passed
startup         passed
port            passed   （Web 端口 + ttyd 端口）
check_initial   ok: False  ← 初始环境有漏洞，符合预期
flag_write      skipped  （没有 Flag 合同）
```

跑法不变：

```bash
bash <本 Skill 目录>/scripts/verify.sh <题目目录>
```

拿到 `ok: False`（初始环境有漏洞）是**通过**；拿到 `ok: True` 反而说明题目初始状态不对——漏洞初始就修好了，选手没得打——要报出来。

**判题脚本没能执行会判 `failed`，不算"有漏洞"。** 退出码 126（没有执行权限）、127（路径或命令找不到），以及返回非 0 但输出里没有 `ok: False` / `RESULT: FAIL` 判定行的（`check.py` 缺依赖崩掉这类），都按配置错误处理。`check` 路径写错、`check.sh` 忘了 `chmod +x` 时返回码恰好非 0，不单独判掉就会被当成 RDG 的预期结果。

### 手册

RDG 手册的重点和普通题不同，见 [manual.md](manual.md)：

- 1.5 说明 Flag 是动态写入还是固定值设计的一部分。
- 1.6 列出 ttyd 端口和账号、后台地址和账号、`check/check.sh` 位置。
- 1.8 逐条列出 check 覆盖的关卡和每关在加固前后的预期结果。
- 1.9 改成"初始漏洞验证 + 修复方法 + 加固后自检"，贴出 check 在加固前后的输出。

不写"常见失败现象"一节。

历史 check 模板见 v3.0.1 的 [`scripts/generate_check_stub.py`](https://github.com/D1a0y1bb/CloverSec-CTF-Pack/blob/v3.0.1/src/CloverSec-CTF-Build-Dockerizer/scripts/generate_check_stub.py)。

## Linux kernel / QEMU guest 题

内核 CVE/LPE 题，用 QEMU 起 guest。常见形态是**容器里塞一个 QEMU**：平台只看到一个容器，guest 在容器内部的 QEMU 里跑。

这类题的 Flag 在 guest 内部，host 层的 `changeflag.sh` 只写 host 文件、guest 看不到——Flag 要写进 rootfs（或 FAT 分区），或者由 guest 的启动脚本从共享位置读。

### Flag 同步的校验清单

平台是**容器起来之后**才写 `/flag` 的，所以容器启动时搬一次是不够的。逐条核对：

1. **同步循环要一直跑**，不能只在启动时搬一次。判断依据是 `while` 循环里比较校验和，不是启动时一句 `cp`。
2. **写失败要能看见。** 不写 `cp /flag <target> 2>/dev/null || true`。写不进去时打一行明确日志，或让循环返回非零。
3. **目标文件不能是只读。** 给 guest 镜像里的 `esp/FLAG` 加 `chmod 444`，下一轮同步就写不进去，QEMU 只会打一行 `Tried to write to write-protected file`，选手拿到的永远是占位值。
4. **宿主侧要能回读 guest 实际看到的值。** 只确认 host 上的文件写成功不算通过。
5. **验证脚本写第二个 Flag 再解一次。** `verify.sh` 默认会做这一步；第一次能过、第二次拿旧值，就说明同步没生效。

### 不许把超时当结论

QEMU 题跑得慢是正常的，但**慢不是结论**。看到解题超时，先查为什么慢：

- 同步循环是不是在空转重试（写不进去，一直重试）。
- guest 每次开机多久，能不能并发跑多个小问。
- 串口传输有没有开回显，逐块等回显会慢一个数量级。

**不要写"这是 QEMU 模拟的固有开销，建议平台放宽超时"这种结论。** 同步循环里的 `chmod 444` 让 `cp` 静默失败、循环一直重试，也会表现成"解题很慢"。**先把替代解释排除掉，再写结论。**

解题确实需要更长时间时，把实测耗时写进手册 1.9，验证时用 `--solve-timeout` 调大，而不是压缩题目链路。

### 其他实测要点

- 串口用 QEMU 自带的 TCP 监听（`-chardev socket,...` + `-serial chardev:char0`），不要自己写 pty 转发——客户端断开后容易卡住不再出数据。
- QEMU 需要 KVM 时，`verify.sh` 默认的 `docker run` 不带 `--device`。用 `--run-arg --device=/dev/kvm` 补上；没有 KVM 走 TCG 会慢好几倍。
- 一个容器里跑两个 QEMU 实例时，两个小问要并发解，串行必然超时。

构建和手动验证的历史流程见 v3.0.1 的 [`docs/linux_qemu_manual_validation.md`](https://github.com/D1a0y1bb/CloverSec-CTF-Pack/blob/v3.0.1/src/CloverSec-CTF-Build-Dockerizer/docs/linux_qemu_manual_validation.md)。

## 旧平台 helper（changeflag.sh）

有些老题/老平台约定由容器内 `/changeflag.sh` 来写 Flag，而不是平台直接写。只有这三种情况才需要它：
1. 迁移的老题本身就依赖 `/changeflag.sh`；
2. Linux-QEMU 需要 guest 注入；
3. 用户明确要求旧 helper 合同。

需要时的最小形态：

```bash
#!/bin/bash
set -euo pipefail
# 平台把新 flag 作为参数或 FLAG 环境变量传入，写到目标路径。
TARGET="${FLAG_PATH:-/flag}"
printf '%s\n' "${FLAG:-${1:-}}" > "$TARGET"
chmod 444 "$TARGET"
```

对应 Dockerfile 要 `COPY changeflag.sh /changeflag.sh` 且 `chmod 555`，并确保镜像里有 `/bin/bash`。常规 direct-write 题不需要这个文件。
