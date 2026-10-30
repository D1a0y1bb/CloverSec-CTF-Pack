# 平台合同与 challenge.yaml

## 目录

- 平台怎么跑题目
- 动态 Flag 的真实机制（凌虚平台源码还原）
- 用环境变量传 Flag 的平台
- 镜像 tar 的格式
- Flag 路径与写入方式
- challenge.yaml 字段

## 平台怎么跑题目

1. 用 Dockerfile 构建 `linux/amd64` 镜像。在 Apple Silicon 上构建要加 `--platform linux/amd64`，否则导出的镜像在平台上起不来。
2. 平台以 `/start.sh` 作为命令起容器：

   ```python
   containers.run(img_name, name=..., detach=True, ports=...,
                  restart_policy={"Name": "on-failure", "MaximumRetryCount": 5},
                  command='/start.sh')
   ```

   所以 `/start.sh` 必须是镜像里的真实入口，末尾 `exec` 主服务让它前台运行。`ENTRYPOINT` 不为空时 `/start.sh` 会变成它的参数。
   **只有 AI 类白名单镜像会被平台加内存/CPU 上限**，普通题目不设任何限制（见 `docker_api.py`）。
3. 选手访问映射出来的端口，服务要监听 `0.0.0.0`。

## 动态 Flag 的真实机制（凌虚平台源码还原）

> 下面这些来自 `LingXu-Platform/.../system/project/` 的源码，不是推测。题目交付时按这个机制设计，不要按"平台会往 flag.path 写文件"来假设。

### 完整链路

```text
1. 出题人在平台后台填一段 flag_script（文本框，不是文件）
   保存时校验必须含 $new_flag，否则报「缺少必要参数，请确认flag脚本是否正确」
   （admin_test/serializers.py:196-200）

2. 选手开环境 → 平台 containers.run(command='/start.sh') 起容器

3. 平台生成动态值（docker_api.py:343-353）：
   s = 静态flag + str(team_id 或 user_id) + str(container.short_id)
   new_flag = "flag{" + md5(s) + "}"
   flag_script = flag_script.replace("$new_flag", new_flag)
   → 然后把 flag_script 作为 Celery 任务丢出去（tasks.dynamic_flag.delay）

4. Celery 侧 copy_to()（base_app/tasks.py:27-64）：
   a. 把 flag_script 写成临时文件，打成 tar，arcname="changeflag.sh"
   b. container.put_archive("/", tar)  →  容器里出现 /changeflag.sh
   c. container.exec_run("chmod +x /changeflag.sh")
   d. container.exec_run("/bin/bash /changeflag.sh")   ← 最多重试 30 次
   e. container.exec_run("rm -rf /changeflag.sh")

5. 重试判据：只有输出里含 "Can't connect to local MySQL server through socket"
   才会 sleep 1 再试（settings.py:410 DYNAMIC_FLAG_ERROR_LIST）。
   其他任何错误（including 找不到 bash、权限拒绝）第一次就放弃。
```

### 由此推出的硬规则

**规则 1：镜像里必须有 `/bin/bash`。**

平台是用 `/bin/bash` 执行注入脚本的，不是 `sh`。alpine、slim、distroless、scratch 系镜像默认没有 `/bin/bash`，注入会直接失败，Flag 停在占位值，选手拿到错的 Flag，而平台只在前端提示"环境启动异常"。

- 用 `python:*-alpine`、`node:*-alpine`、`php:*-alpine` 时，Dockerfile 里加 `RUN apk add --no-cache bash`。
- 用 `ubuntu`、`debian`、`python:*-slim`（bookworm 系）时默认就有，不用加。
- 用 distroless / scratch 时**不能**用动态 Flag，只能静态 Flag 或换基础镜像。

`verify.sh` 会在构建后探测镜像里有没有 `/bin/bash`，没有直接判 `failed`。

**规则 2：`flag_script` 由出题人在平台后台填，不随交付物走。**

Skill 不生成 `changeflag.sh` 交付文件（旧平台 helper 除外，见 `special.md`）。交付时在手册 1.5 里给出**可直接粘贴到平台后台的 flag_script**，出题人复制过去即可。

**规则 3：动态值不是随机的。**

`flag{md5(静态flag + 用户id + 容器short_id)}`。同一用户重开同一容器会得到同一个 Flag。所以不要用"每次不同"来判断动态 Flag 是否生效——用"和镜像里的占位值不同"来判断。

### flag_script 标准模板

直接复制到平台后台的 `flag_script` 文本框。`$new_flag` 必须保留，平台会替换它。

```bash
#!/bin/bash
set -uo pipefail
# 平台注入时已把 $new_flag 替换成本实例的动态值。
# 这里只负责把它写进题目程序真正读取的位置。
printf '%s\n' "$new_flag" > /flag
chmod 444 /flag
```

目标路径不是 `/flag` 时改最后两行；需要同步到数据库、配置文件、QEMU rootfs 时，在 `printf` 之后接你的同步命令。**不要**在这个脚本里做耗时操作——平台有 30 次重试，但每次失败都会让环境启动变慢。

多目标的例子（程序读 `/home/ctf/flag` 且另有配置文件）：

```bash
#!/bin/bash
set -uo pipefail
printf '%s\n' "$new_flag" > /home/ctf/flag
chown root:ctf /home/ctf/flag && chmod 440 /home/ctf/flag
printf 'FLAG=%s\n' "$new_flag" > /app/.env
```

### 排障：Flag 写不进去怎么查

按这个顺序查，别猜：

1. **镜像里有没有 `/bin/bash`**：`docker run --rm --entrypoint sh <镜像> -c 'test -x /bin/bash && echo OK || echo NO_BASH'`
2. **平台有没有配 `flag_script`**：题目配置里 `flag_type` 必须是 2（动态 Flag），且脚本里必须有 `$new_flag`。
3. **脚本本身有没有报错**：`docker logs` 看不到 changeflag.sh 的输出（它是在 exec 里跑的），平台把错误写进了 `DockerEnvRun.error_msg`，前端提示"环境启动异常"。让运维查这个字段。
4. **写进去了但程序读不到**：程序读的不是脚本写的那个路径，或者程序在启动时把 Flag 读进了内存。

### 时序：平台写入晚于服务启动

平台写入发生在容器启动**之后**，实测延迟多数 1~4 秒，**偶发 61 秒**（数信杯线上 6 台机器批量启动时观测到）。

如果程序在启动时读一次 Flag（Python 模块级变量、Java `static` 块、import 时读配置），或者要把 Flag 同步进 QEMU guest，就会拿到占位值或静态旧值。

处理办法见 `special.md` 的「Flag 同步等待」一节。核心是：**等到"平台写入的值"而不是"文件存在"**，判据三条件（内容≠静态值、符合 `flag{.+}`、0.3 秒复核不变），超时 120 秒不阻塞启动。

## 用环境变量传 Flag 的平台

> **只为四叶草平台出的题，这一整节都不要用。** 下面这段代码**不是模板**，是给"确实要在 GZCTF、DASCTF 上跑"的题目用的。**不要复制进交付物。**
>
> 写出来只是因为以前发生过：Agent 看到这段可复制的代码就抄进了 14 道 Pwn 题的 `start.sh`，用户问「这里面怎么还有 GZCTF_FLAG 这玩意呢」。四叶草平台不走这条路，抄进去只会带进别的平台的合同。

GZCTF、DASCTF 等平台在 `docker run` 时用环境变量传 Flag（`GZCTF_FLAG`、`DASFLAG`、`FLAG`），不会再执行写文件的命令。**只有在确认这道题要交到那几个平台时**，才在 start.sh 开头加：

```bash
# 仅用于 GZCTF / DASCTF。四叶草平台不要这段。
FLAG_VALUE="${GZCTF_FLAG:-${DASFLAG:-${FLAG:-}}}"
if [ -n "$FLAG_VALUE" ]; then
    printf '%s\n' "$FLAG_VALUE" > /flag
    unset GZCTF_FLAG DASFLAG FLAG FLAG_VALUE
fi
```

`verify.sh` 见到 `start.sh` 里有 `GZCTF_FLAG` / `DASFLAG` 会报 `partial` 提醒核实。

## 静态 Flag 题（平台不写 Flag）

有些赛事的题目不发动态 Flag：平台不写文件，只比对选手提交的字符串。这类题在 `challenge.yaml` 里写：

```yaml
challenge:
  flag:
    path: /flag          # 仍是程序实际读的路径
    mode: static         # static = 平台不写，只比对
```

规则：

- 镜像里放的静态 Flag 就是完整的那一个值，`chmod 444`。
- 手册 1.5 要写「平台覆盖方式：无，本题为静态 Flag，平台不写 Flag，只比对选手提交的字符串」，并写明这个值是从哪里考证来的。
- **多小问拼成一个完整 Flag**时，按小问顺序取各段的 `{}` 内容、用下划线连接，外层只留一层 `flag{}`。例：小问一 `flag{aaa}`、小问二 `flag{bbb}` → `flag{aaa_bbb}`。
- 多出来的小问占位文件放在 `src/flags/` 下再 `COPY`，不要直接在题目录根上放 `flag1`、`flag2`——交付目录白名单只认 `flag`，多出来的会在 `verify.sh` 里报成多余文件。
- `verify.sh` 见到 `mode: static` 会把 `flag_write` 记成 `skipped`，解题输出里必须出现镜像里 `flag.path` 的那个值，也可以用 `--expect-flag '<手册 1.5 里的值>'` 指定。附件题同样用 `--expect-flag` 断言。

## 镜像 tar 的格式

交付镜像用 `docker save`，导入用 `docker load`：

```bash
docker buildx build --platform linux/amd64 -t afterimage:latest --load .
docker save afterimage:latest -o 残影.tar
```

有些平台只接受 `docker export` 导出的文件系统 tar（`docker import` 导入）。这种格式不保留 `WORKDIR`、`ENV`、`EXPOSE`、`CMD`，start.sh 里要自己 `cd` 到绝对路径、自己 `export` 需要的环境变量，不能依赖 Dockerfile 里的设置。

## Flag 路径与写入方式

### 常用路径

**下面这张表是"常见值"，不是"默认值"。先打开源码找到读 Flag 的那一行，再填 `flag.path`。**

| 路径 | 典型题型 |
|---|---|
| `/flag` | Web、AI、Misc 大多数 |
| `/home/ctf/flag` | Pwn，属主 `root:ctf`，权限 `440` |
| `/root/flag` | 主机安全、应急响应 |
| `/var/www/html/flag` | PHP 直接 include 或 readfile |
| `/var/www/html/flag.php` | Flag 写在 PHP 文件里 |
| 数据库表 | SQL 写在手册 1.5 |

路径填错，平台写入的 Flag 程序读不到。

**迁移旧平台题（GZCTF、CTFd 等）时，`flag.path` 必须逐题判定，不许按题型或按批次一刀切填 `/flag`。** 用户选了一个全局方案也要逐题覆盖——Pwn 题的 `/home/ctf/flag`、PHP 嵌入题的 `/var/www/html/flag.php` 都有各自的理由。

### 直接写文件

- Dockerfile 用 `COPY flag <flag.path>` 放占位文件，Web 题 `chmod 444`，Pwn 题 `root:ctf 440`。
- 程序每次请求时读取 Flag 文件。
- start.sh 不创建、不覆盖、不 chmod Flag 文件（两个例外：平台用环境变量传 Flag、题目自身按原题设计生成静态 Flag）。

### 文件替换和数据库 Flag

把平台要执行的命令写进题目手册，不另写脚本：

```bash
# Flag 写在 PHP 文件里
sed -i "s/$flag/$new_flag/g" /var/www/html/flag.php

# Flag 存在数据库里，等 MySQL 就绪后更新
/usr/bin/wait-for-it.sh 127.0.0.1:3306 -- \
  mysql -e "USE ctf; UPDATE flag_tab SET flag='$new_flag' WHERE id=1;" -uroot -proot
```

### Flag 同步循环必须能证明写成功

配置里读 Flag 的题、QEMU guest 里读 Flag 的题，靠 start.sh 里的同步循环把平台写入的 `/flag` 搬进去。这个循环有三个坑：

- **不要写 `cp /flag /target 2>/dev/null || true`。** 写失败会被静默吞掉，选手拿到的永远是占位值，验证脚本还看不出原因。
- **不要把目标文件设成只读**（`chmod 444`）。下一轮同步会写不进去，同样静默失败。
- **不要让循环只在启动时跑一次。** 平台是在容器起来之后才写 `/flag` 的，启动时搬的那一次搬到的是占位值。

同步循环要在宿主侧留一条能验证的痕迹：写成功后打一行日志，或者让循环把失败写成非零退出。`verify.sh` 不重启容器，直接写第二个 Flag 再解，最多等 15 秒，用来抓"同步没生效"。同步间隔要短于这个时间。

### Flag 缓存

服务启动时把 Flag 读进内存，平台之后改了文件也不会生效：

```python
# 错误：进程启动时读一次
FLAG = open("/flag").read()

# 正确：每次请求时读
def get_flag():
    return open("/flag").read()
```

Java 的 `static { flag = readFile(); }` 同理。fork 型服务（`ForkingMixIn`、`os.fork()`）里，子进程继承的是父进程启动时读到的值，所以模块级读 Flag 的题同样会失效——要改成每次请求读，或者让子进程自己读文件。

`verify.sh` 会写入第一个测试 Flag 并解一次，再写入第二个测试 Flag 再解一次；两次都拿到对应的值才算通过。每次写入后最多等 15 秒，一直拿到旧值的题判 `failed`。

## challenge.yaml 字段

```yaml
challenge:
  name: afterimage              # 题目标识，kebab-case
  category: Web                 # 20 个题目类型之一
  stack: php                    # php / node / python / java / static / pwn
  base_image: php:5.6-apache
  workdir: /var/www/html        # 容器内工作目录
  app_src: src                  # 源码在交付目录里的位置
  app_dst: /var/www/html        # 源码 COPY 到容器的目标
  expose_ports: ["80"]          # 对外端口，字符串数组
  start:
    mode: cmd
    cmd: "apache2-foreground"   # start.sh 最后 exec 的主进程
  platform:
    entrypoint: /start.sh
    require_bash: true          # start.sh 用到 bash 语法时写 true
    docker_platform: linux/amd64  # 只能在 amd64 运行的题（Pwn、x86 二进制）写上
  flag:
    path: /flag                 # 程序实际读取的路径
    mode: platform              # platform（平台写入）/ static（平台只比对，不写）
    permission: "444"
    legacy_env: FLAG            # 旧平台用环境变量传值时写上变量名
provenance:
  status: original_adapter
  original_material: [源码, install.sql, docker-compose.yml]
  missing: []
  preserved: [漏洞类型=文件上传 TOCTOU, 链路=3 步, 服务=nginx+php-fpm+MariaDB, PHP=5.6]
  service_parity: 原 compose 的 nginx、php-fpm、MariaDB 全部装进同一镜像，配置沿用原文件
  simplified: []
  env_limited: ""
  verify: passed
```

不知道的字段不写，填错比不填更麻烦。verify.sh 用 `yaml.safe_load` 真解析这个文件：

- 解析失败直接判 `failed`——平台的解析器读不出来，题目就上不了线。flow 序列里带 `{{flag}}`、缩进用 Tab、冒号后面缺空格都会让它挂掉。
- `expose_ports` 读来自动探测端口，两种写法都支持：

  ```yaml
  expose_ports: ["80", "22"]
  expose_ports:
    - "80"
  ```

- `provenance.status` 是 `pending`、或 `provenance.verify` 空着，判 `failed`。

## provenance：题目来源与恢复状态

`provenance` 是必填字段，用来把"容器能跑"和"题目是原题还是重建的"分开。只看 `passed` 会把"能跑"误读成"题目完成"。

| 字段 | 说明 |
|---|---|
| `status` | `original_adapter`（原题材料完整，只补平台合同）/ `independent_completion`（材料缺失后独立重建）/ `incomplete`（材料缺失且没等价恢复）。附件题没有 `challenge.yaml`，这些字段写进交付说明 |
| `original_material` | 手里有的原始材料，列文件名 |
| `missing` | 缺的材料，列清楚 |
| `preserved` | 保留下来的原题特征：漏洞类型、链路步数、**服务拓扑**、**运行时版本**、要绕过的防护 |
| `service_parity` | 原题每个服务在交付里的落点。原题是 compose 多服务时必填，写清每个组件装进了同一镜像、配置沿用哪个原文件。**服务层被替换过就在这里写清楚，并标 `simplified`** |
| `simplified` | 相对原题简化了什么。有值必须写清为什么无法等价恢复。没有就写 `[]` |
| `env_limited` | 本机环境限制，例如 `Apple Silicon 模拟下无法执行原始 rt_sigreturn`。这是环境问题，不是改题的理由 |
| `verify` | 验证结论：`passed` / `environment_failed` / `incomplete` |

规则：

- `status: incomplete` 的题**不许**在手册或交付说明里写成"已验证通过"。
- `independent_completion` 必须在手册 1.8 里写明这是独立补全，不是原题还原。
- `simplified` 有值时，这道题已经偏离原题难度，要在交付说明里单独告诉用户。
- **`env_limited` 不许当垃圾桶。** 把失败记成"模拟器/环境限制"之前，必须在原生架构上复现一次，两次结果都写进交付说明。库的修订版、配置差异这类替代解释要先排除。

## RDG 相关字段

```yaml
challenge:
  category: RDG
  profile: rdg
  expose_ports: ["80", "8022"]
  flag:
    path: /flag
    permission: "444"
    legacy_env: FLAG          # 旧平台通过环境变量传 Flag 时写
  check:
    enabled: true
    path: check/check.sh
  verification:
    solve_probe:
      type: http
      path: /            # 服务可用性探测路径，根路径 403/404 时指定真实入口
      expect_status: 200
      expect_text: "版权所有 ©2015-2024"
```

- `check.enabled: true` 时 `verify.sh` 走 RDG 判定：先跑一遍 check 确认初始环境报"有漏洞"，再验证容器生命周期。
- **不需要动态 Flag 的 RDG 题**：敏感目标是自己配置里的固定内容时，`flag:` 块可以省掉，或在 `notes` 里注明 Flag 不是判据。check 直接验证那个固定目标还能不能被读到。
- ttyd 端口写进 `expose_ports`，`verify.sh` 会和 Web 端口一起探测。
- `notes` 写清 check 覆盖哪些关卡、初始环境的预期结果。
