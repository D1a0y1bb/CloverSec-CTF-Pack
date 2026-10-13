# 平台合同与 challenge.yaml

## 目录

- 平台怎么跑题目
- 用环境变量传 Flag 的平台
- 镜像 tar 的格式
- Flag 路径与写入方式
- challenge.yaml 字段

## 平台怎么跑题目

1. 用 Dockerfile 构建 `linux/amd64` 镜像。在 Apple Silicon 上构建要加 `--platform linux/amd64`，否则导出的镜像在平台上起不来。
2. `docker run -d -p <映射> <镜像> /start.sh` 启动。`/start.sh` 覆盖 `CMD`；`ENTRYPOINT` 不为空时 `/start.sh` 会变成它的参数，官方 php、nginx、node 镜像的 `docker-*-entrypoint` 会原样执行参数，不受影响。
3. 容器起来后，平台以 root 执行：

   ```bash
   docker exec <容器> sh -c 'printf "%s\n" "$1" > "$2"' sh "$new_flag" "$flag_path"
   ```

   所以镜像里要有 `sh`，`flag.path` 的目录要存在。distroless、scratch 镜像不能直接用。
4. 选手访问映射出来的端口，服务要监听 `0.0.0.0`。

## 用环境变量传 Flag 的平台

**只为四叶草平台出的题不要加这一段。** 下面的代码不是模板，是给"确实要在 GZCTF、DASCTF 上跑"的题目用的。照抄进交付物会把别的平台的合同带进四叶草平台，`verify.sh` 会报 `partial` 提醒。

GZCTF、DASCTF 等平台在 `docker run` 时用环境变量传 Flag（`GZCTF_FLAG`、`DASFLAG`、`FLAG`），不会再执行写文件的命令。题目要在这类平台上用时，start.sh 开头加一段：

```bash
# 平台用环境变量传 Flag 时写进 flag.path，写完清掉变量，选手读 /proc/1/environ 拿不到。
FLAG_VALUE="${GZCTF_FLAG:-${DASFLAG:-${FLAG:-}}}"
if [ -n "$FLAG_VALUE" ]; then
    printf '%s\n' "$FLAG_VALUE" > /flag
    unset GZCTF_FLAG DASFLAG FLAG FLAG_VALUE
fi
```

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
