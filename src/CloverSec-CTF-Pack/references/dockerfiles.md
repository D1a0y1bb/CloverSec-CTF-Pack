# 各语言 Dockerfile / start.sh 范例

照这些写法改成题目实际的版本、端口和命令。

## 目录

- 镜像版本固定
- Python（Flask / gunicorn）
- Node
- PHP（cli 内置服务器）
- PHP-FPM + nginx
- Java（jar / 多阶段编译）
- 纯静态
- Pwn（socat / xinetd）
- 国内构建与 CRLF

---

## 镜像版本固定

同一份源码过段时间再构建就失败，通常是构建输入变了：浮动 tag、没锁时间点的 apt 源、PECL/pip 装到了新版本。

普通题目用 `python:3.11-slim` 这样的 tag 即可。漏洞只在特定版本成立（某个 ImageMagick、Redis 或库的 CVE），或者题目要长期存档时，按下面四步锁定：

1. **基础镜像锁 digest**，不只用 tag：

   ```dockerfile
   FROM php:8.2.29-apache-bookworm@sha256:bb954ec03238abf760e91a3fa74202f192d644be12bd4bda5bac577997a76466
   ```

2. **Debian/apt 源锁到 snapshot 时间点**，并关掉有效期检查：

   ```dockerfile
   RUN printf '%s\n' \
       'Types: deb' \
       'URIs: http://snapshot.debian.org/archive/debian/20251117T000000Z' \
       'Suites: bookworm' 'Components: main' \
       'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' \
       > /etc/apt/sources.list.d/debian.sources; \
       echo 'Acquire::Check-Valid-Until false;' > /etc/apt/apt.conf.d/99snapshot
   ```

3. **apt 包锁具体版本号**：

   ```dockerfile
   RUN apt-get update && apt-get install -y --no-install-recommends \
       imagemagick=8:6.9.11.60+dfsg-1.6+deb12u4 \
       redis-server=5:7.0.15-1~deb12u6
   ```

4. **PECL/源码包锁版本 + 校验 SHA256**：

   ```dockerfile
   RUN wget -O /tmp/imagick.tgz https://pecl.php.net/get/imagick-3.8.0.tgz; \
       echo 'bda67461c854f20d6105782b769c524fc37388b75d4481d951644d2167ffeec6  /tmp/imagick.tgz' | sha256sum -c -; \
       pecl install /tmp/imagick.tgz
   ```

从旧镜像或 rootfs 恢复题目时，先查出原来的版本再锁定：

```bash
docker run --rm --entrypoint sh <旧镜像> -c '
  uname -m; cat /etc/os-release | head -2
  php -v; php -r "echo phpversion(\"imagick\"), PHP_EOL;"; convert -version | head -1
  redis-server --version; java -version 2>&1 | head -1; catalina.sh version 2>/dev/null | grep "Server number"
  dpkg -l 2>/dev/null | grep -E "imagemagick|libmagick|redis|mysql|mariadb" '
```

只有 rootfs 时，看 `etc/os-release`、`var/lib/dpkg/status`、`usr/local/lib/php/extensions/` 和 `/opt` 下的目录名。查到的版本在 Dockerfile 里锁定，旁边注释写来源：

```dockerfile
# 版本取自原题镜像：漏洞依赖 imagick 3.7.0 + Redis 6.0.8
RUN pecl install imagick-3.7.0
```

不要把旧版本的包装到新的基础镜像上，例如旧 `libxml2-dev` 配新基础镜像自带的 `libxml2` 会依赖冲突。基础镜像、apt 源和包版本锁到同一个时间点。

---

## Python（Flask / gunicorn）

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY src/ /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY start.sh /start.sh
COPY flag /flag
RUN chmod 555 /start.sh && chmod 444 /flag

EXPOSE 5000
CMD ["/start.sh"]
```

```bash
#!/bin/sh
set -eu
cd /app
# 单 worker：题目状态存在进程内存里，多 worker 之间不共享。
exec gunicorn -w 1 -b 0.0.0.0:5000 app:app
```

小题也可以 `exec python app.py`，app 里要监听 `0.0.0.0`。

---

## Node

```dockerfile
FROM node:20-alpine

WORKDIR /app
COPY src/ /app/
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

COPY start.sh /start.sh
COPY flag /flag
RUN chmod 555 /start.sh && chmod 444 /flag

EXPOSE 3000
CMD ["/start.sh"]
```

```bash
#!/bin/sh
set -eu
cd /app
exec node server.js
```

---

## PHP（cli 内置服务器）

```dockerfile
FROM php:7.4-cli

WORKDIR /var/www/html
COPY src/ /var/www/html/
COPY start.sh /start.sh
COPY flag /flag
RUN chmod 555 /start.sh && chmod 444 /flag

EXPOSE 5000
CMD ["/start.sh"]
```

```bash
#!/bin/sh
set -eu
cd /var/www/html
exec php -S 0.0.0.0:5000 -t /var/www/html
```

---

## PHP-FPM + nginx

```dockerfile
FROM php:8.1-fpm-alpine

# 题目的解法依赖 pcntl_fork + pcntl_exec 绕过 disable_functions，必须编译 pcntl。
RUN set -eux; \
    apk add --no-cache nginx bash; \
    docker-php-ext-install pcntl

COPY nginx/nginx.conf /etc/nginx/nginx.conf
WORKDIR /var/www/html
COPY src/ /var/www/html/

COPY start.sh /start.sh
COPY flag /flag
RUN chmod 555 /start.sh && chmod 444 /flag

EXPOSE 80
CMD ["/start.sh"]
```

```bash
#!/bin/bash
set -euo pipefail
# nginx 通过 127.0.0.1:9000 转发给 php-fpm，先起 fpm 再起 nginx。
php-fpm --nodaemonize &
nginx -t
exec nginx -g 'daemon off;'
```

---

## Java（jar / 多阶段编译）

有现成 jar：

```dockerfile
FROM eclipse-temurin:17-jre

WORKDIR /app
COPY src/app.jar /app/app.jar
COPY start.sh /start.sh
COPY flag /flag
RUN chmod 555 /start.sh && chmod 444 /flag

EXPOSE 8080
CMD ["/start.sh"]
```

```bash
#!/bin/sh
set -eu
exec java -jar /app/app.jar
```

从源码编译时用多阶段构建，运行镜像里不带 maven：

```dockerfile
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build
COPY src/pom.xml ./pom.xml
COPY src/src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:17-jre
COPY --from=build /build/target/app.jar /app/app.jar
COPY start.sh /start.sh
COPY flag /flag
RUN chmod 555 /start.sh && chmod 444 /flag
EXPOSE 8080
CMD ["/start.sh"]
```

---

## 纯静态

```dockerfile
FROM nginx:alpine
COPY src/ /usr/share/nginx/html/
COPY start.sh /start.sh
COPY flag /flag
RUN chmod 555 /start.sh && chmod 444 /flag
EXPOSE 80
```

```bash
#!/bin/sh
exec nginx -g 'daemon off;'
```

平台用 `/start.sh` 覆盖 `CMD`，静态题也要有 start.sh。

---

## Pwn（socat / xinetd）

发给选手的二进制和镜像里运行的必须是同一个文件，否则选手本地算出的偏移在远程不成立。直接 `COPY` 现成二进制，不要在镜像里重新编译。

### socat

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends socat \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m ctf

COPY src/pwn /home/ctf/pwn
# Flag 属主 root:ctf、权限 440：题目进程以 ctf 运行，能读不能改。
COPY flag /home/ctf/flag
RUN chown root:ctf /home/ctf/pwn /home/ctf/flag \
    && chmod 550 /home/ctf/pwn \
    && chmod 440 /home/ctf/flag

COPY start.sh /start.sh
RUN chmod 555 /start.sh

EXPOSE 10000
CMD ["/start.sh"]
```

```bash
#!/bin/sh
cd /home/ctf
# 不加 pty：pty 会把 0x7f、0x03 等字节当成控制字符处理，payload 里的地址会被改掉。
exec socat TCP-LISTEN:10000,reuseaddr,fork EXEC:/home/ctf/pwn,su=ctf,stderr
```

程序里要 `setvbuf(stdout, NULL, _IONBF, 0)`，否则没有 pty 时输出会被缓冲，选手看不到提示。源码不在手里时用 `stdbuf -o0 /home/ctf/pwn`。

### 不用 socat：Python 标准库转发

镜像里不方便装 socat（极简镜像、静态编译）时，用几十行的 Python 转发脚本，每来一个连接 fork 一个题目进程，以 ctf 用户运行：

```python
#!/usr/bin/env python3
import os, socket

PORT = 10000


def serve(conn):
    pid = os.fork()
    if pid == 0:
        for fd in (0, 1, 2):
            os.dup2(conn.fileno(), fd)
        if conn.fileno() > 2:
            conn.close()
        # 先 setgid 再 setuid，顺序反了会留下 root 的 gid。
        os.setgid(1000)
        os.setuid(1000)
        os.chdir("/home/ctf")
        os.execv("/home/ctf/pwn", ["/home/ctf/pwn"])
    conn.close()
    os.waitpid(pid, 0)


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", PORT))
srv.listen(64)
while True:
    conn, _ = srv.accept()
    serve(conn)
```

- 不接 pty，理由和 socat 一样：pty 会改写 payload 里的控制字符。
- 题目程序要自己 `setvbuf(stdout, NULL, _IONBF, 0)`，否则输出被缓冲，选手看不到提示。
- 脚本放进 `src/`，Dockerfile 里 `COPY` 进去，start.sh 用 `exec python3 /home/ctf/forward.py`。

### xinetd

旧题和很多外部题用 xinetd + chroot，迁移时保留原写法即可：

```text
service ctf
{
    disable     = no
    socket_type = stream
    protocol    = tcp
    wait        = no
    user        = root
    type        = UNLISTED
    port        = 10000
    bind        = 0.0.0.0
    server      = /usr/sbin/chroot
    server_args = --userspec=1000:1000 /home/ctf ./pwn
    per_source  = 10
    rlimit_cpu  = 20
}
```

```bash
#!/bin/sh
exec /usr/sbin/xinetd -dontfork
```

chroot 的目录要自带程序运行需要的一切，缺一个文件题就起不来。最小清单：

```text
/home/ctf/
├── pwn                                   # 选手二进制
├── flag                                  # root:ctf 440，程序读的是 chroot 后的 /flag
├── lib/x86_64-linux-gnu/libc.so.6        # 程序依赖的动态库，用 ldd 查
├── lib64/ld-linux-x86-64.so.2            # 动态 loader，路径要和 ELF 里的 interpreter 一致
└── bin/sh, bin/cat                       # 漏洞链里要用的工具，静态编译或用 ldd 补齐依赖
```

```bash
# 用 ldd 查出程序真正需要的库，逐个拷进 chroot。
ldd /home/ctf/pwn
```

- Pwn 题**不要**在 chroot 里放 `/proc`、`/sys`；确实需要设备节点时只补题目用到的那个。
- chroot 后程序看到的 `flag.path` 是 `/flag`，但 `challenge.yaml` 里要写容器里的真实路径 `/home/ctf/flag`，平台按这个路径写入。
- 迁移旧题时先 `docker run -it <镜像> sh` 进去跑一遍二进制，缺什么文件会直接报出来。

---

## 旧版本运行时（镜像和源已经归档）

PHP 5.6、PHP 7.1、PHP 7.2、Node 11 这类镜像还在 Docker Hub，但自带的 apt 源已经失效，构建时会 404：

```dockerfile
# 旧镜像自带的源已归档，换成 archive.debian.org 并关掉有效期检查。
RUN sed -i -e 's|deb.debian.org|archive.debian.org|g' \
           -e 's|security.debian.org|archive.debian.org|g' \
           -e '/-updates/d' /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until false;' > /etc/apt/apt.conf.d/99archive
```

- 卡在 `apt-get update` 404：先确认基础镜像的发行版代号，再挑对应归档周期。
- 归档源很慢，首次构建可能十几分钟，本地调试可以先 `docker pull` 好基础镜像。
- 长期交付的题按“镜像版本固定”锁 digest 和 snapshot 源，别依赖浮动的归档地址。

## 语言依赖：不要把题解需要的包删掉

`composer install --no-dev`、`npm ci --omit=dev`、maven 排除 test scope，都可能删掉原题解法依赖的包。典型情况是题目链用到 `Faker`、`PHPUnit`、`monolog` 这类“开发依赖”里的 gadget，删掉后容器能起来，但题目解不出来了。

- 先看原题解题脚本用到哪些依赖，再决定要不要 `--no-dev`。
- 项目不大的话直接全装，省去排查。
- 装完必须跑一次 `solve/solve.py`，依赖被删会直接反映成解题失败。

## 交付前校验文件一致性

Pwn 题的二进制、libc、loader，发出去的和容器里跑的必须是同一份，否则偏移对不上。交付前对一遍：

```bash
sha256sum 附件/pwn 附件/libc.so.6
docker run --rm --entrypoint sha256sum <镜像> /home/ctf/pwn /home/ctf/libc.so.6
```

两边不一致说明 Dockerfile 重新编译过，或者 COPY 的是另一份文件。

## 兼容旧构建器

有些平台和远程构建机只有经典 `docker build`，没有 BuildKit。下面这些写法只有 BuildKit 认，到那边直接报错：

| 不要写 | 写成 |
|---|---|
| `COPY --chmod=555 start.sh /start.sh` | `COPY start.sh /start.sh` + `RUN chmod 555 /start.sh` |
| `RUN --mount=type=cache,...` | 去掉缓存挂载，正常的 `RUN` |
| `FROM --platform=$BUILDPLATFORM ...` | 去掉这个参数（经典构建器不会自动填 `BUILDPLATFORM`，展开成空串直接报错） |

`COPY --chown` 经典构建器也支持，可以照常用。

**写完 Dockerfile 用 `DOCKER_BUILDKIT=0 docker build` 再过一遍**，本地 BuildKit 能过不代表平台能过。

### chmod 的目标必须是文件

批量改权限时最容易踩的坑：把 `chmod 644 /app/www/index.html` 写成 `chmod 644 /app/www/`。**给目录去掉执行位会让整个目录进不去**，服务直接返回 404，而构建日志一个字都不报。

改权限前先确认目标是文件：

```dockerfile
RUN chmod 555 /start.sh && chmod 644 /app/www/index.html
```

脚本批量处理时，先 `test -f` 再 `chmod`。

## 解释器大版本必须和原题一致

迁移旧题时，基础镜像的**大版本**是题目难度的一部分，不是可以顺手升级的细节：

| 原题 | 不要升级成 | 为什么 |
|---|---|---|
| PHP 5.x | PHP 7.x / 8.x | 7.0 移除了 `preg_replace` 的 `/e` 修饰符和 `mysql_*` 函数，很多旧利用链直接失效 |
| PHP 7.x | PHP 8.x | 8.0 改了字符串和数字的弱比较规则，`"abc" == 0` 从 true 变成 false |
| Node 旧大版本 | 新大版本 | 依赖包和内置 API 随大版本变化，原型链污染这类利用链可能失效 |
| JDK 8 | JDK 9+ | 模块系统限制反射；JNDI 远程类加载在 8u191 之后默认关闭，反序列化链受小版本影响 |
| ImageMagick 某个修订版 | 更新的修订版 | 编码器（MSL、MVG）和安全策略随修订版变化 |

老镜像自带的 apt 源已经失效，按「旧版本运行时」一节换归档源；**换源不等于升级版本**。锁定写法：

```dockerfile
# 版本取自原题镜像：漏洞依赖 PHP 5.6 + nginx 1.x，不升级。
FROM php:5.6-fpm@sha256:<原 digest>
```

同一道题原题是 nginx + php-fpm 时，两个组件都要装进同一镜像、沿用原配置文件，**不要**换成 `php:*-apache`。详见 [special.md](special.md) 的多服务一节。

## 国内构建与 CRLF

- 基础镜像拉不下来时加镜像前缀，例如 `docker.m.daocloud.io/library/php:7.4-cli`。手册里写清原始镜像名，方便在别处构建。
- apt 慢可以换 `mirrors.aliyun.com`，换源只改 `sources.list`，不要顺手升级系统包。
- Windows 上编辑过的 start.sh 可能是 CRLF，容器里会报 `bad interpreter`。直接把文件转成 LF；`verify.sh` 会检查这一项。
