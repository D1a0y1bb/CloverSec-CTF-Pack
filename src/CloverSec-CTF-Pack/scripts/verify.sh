#!/usr/bin/env bash
# verify.sh —— 按平台的方式跑一遍题目：构建、/start.sh 启动、写入测试 Flag、探测端口，可选跑解题脚本。
#
# 这个脚本只证明「容器生命周期正常」和「解题脚本能拿到刚写入的 Flag」，
# 它证明不了题目难度有没有被降级，也证明不了手册正文写得对不对。别把 passed 当成交付完成。
set -uo pipefail

usage() {
  cat <<'EOF'
用法：bash verify.sh <题目目录> [选项]

选项：
  --port N            要探测的容器端口（容器内端口，不是宿主机端口），可重复；
                      默认读 challenge.yaml 的 expose_ports，再退到 Dockerfile 的 EXPOSE
  --flag-path P       平台写入 Flag 的路径；默认读 challenge.yaml 的 flag.path，再退到 /flag
  --solve CMD         写入测试 Flag 后执行的解题命令；不给时题目目录有 solve/solve.py 就运行它
                      环境变量 HOST、PORT 指向第一个端口，PORT_<容器端口> 指向各个端口
  --solve-timeout N   解题命令的超时秒数，默认 120。QEMU 类题目按实际耗时调大
  --no-flag-rotate    跳过「换一个 Flag 再解一次」的复查。默认会复查，用来抓「启动时把 Flag
                      读进内存」的题；解一次就会把题目状态打坏的题用这个跳过
  --expect-flag F     断言解题输出里出现的是 F。只对附件题和静态 Flag 题生效：附件题没有测试 Flag，
                      静态 Flag 题不给时取镜像里 flag.path 的内容
  --check CMD         指定 RDG 判题命令；默认题目目录有 check/check.sh 就自动走 RDG 判定。
                      返回非 0 且输出有 ok: False / RESULT: FAIL 才算初始环境有漏洞
  --rdg               题目目录不在交付目录形态时，强制按 RDG 判定
  --platform P        构建和运行的平台，默认 linux/amd64（与比赛平台一致）
  --run-arg ARG       docker run 额外参数，可重复。需要 KVM 或网络能力的题用，
                      例如 --run-arg --device=/dev/kvm --run-arg --cap-add=NET_ADMIN
  --ready-cmd CMD     端口开始监听后再执行的就绪命令（在宿主机上跑），返回 0 才算服务真的可用。
                      QEMU 题必用：端口一开就判"已就绪"会把 solve 的时间预算吃在启动上。
                      可用 <PORT> 占位第一个端口，例如 --ready-cmd 'ssh -o ConnectTimeout=3 root@127.0.0.1 -p <PORT> true'
  --ready-timeout N   等待 --ready-cmd 返回 0 的秒数，默认跟 --timeout 相同
  --similarity        对同批目录的手册做雷同度检查（只报警告，不改结论）。默认关闭
  --similarity-report PATH  雷同度报告写到 PATH，不给就只打印
  --no-cache          构建时禁用 Docker 缓存。交付前最后一轮必须带这个：
                      带缓存构建会复用旧层和旧数据库卷，建表 SQL 报错、依赖装错都被掩盖。
  --timeout N         等待服务开始监听的秒数，默认 60
  --keep              结束后保留容器和镜像，便于进去排查
  --report PATH       把构建日志、端口结果和阶段结论写成 JSON 报告；不给就不写。
                      报告里的 notes 是 {severity, message} 数组，severity 取 blocked/fix/env。
                      路径只要落在交付目录里就拒绝执行，报告不属于交付物，写到系统临时目录。

退出码：0 passed / 1 failed / 2 参数错误 / 3 partial / 4 environment_failed
  每一阶段都单独给结论，最后汇总成一行：
    普通题  build: passed  startup: passed  port: passed  flag_write: passed  solve: passed
    RDG 题  build: passed  startup: passed  port: passed  flag_write: skipped  check_initial: ok: False
  failed              明确违反平台合同，或解题拿不到 Flag，或 RDG 初始环境就是修好的
  partial             能跑，但有检查没通过（手册有 TODO、交付目录有多余文件、找不到 check 脚本等）
  environment_failed  本机环境跑不动（amd64 模拟下被调试的二进制崩溃等），题目本身没错
EOF
  exit 2
}

PROJECT=""; PORTS=(); FLAGPATH=""; SOLVE=""; CHECK=""; FORCE_RDG=0
PLATFORM="linux/amd64"; KEEP=0; REPORT=""; EXPECT_FLAG=""; FLAG_ROTATE=1
RUN_ARGS_EXTRA=()
READY_CMD=""; READY_TIMEOUT=""; SIMILARITY=0; SIMILARITY_REPORT=""; NO_CACHE=0
# Java、php-fpm、MySQL 冷启动常见 10~40 秒，amd64 模拟运行还会更慢，60 秒留出余量。
START_TIMEOUT=60
# 解题脚本一般几秒结束；竞态类题目要多跑几轮，给到 120 秒。QEMU 题用 --solve-timeout 调大。
SOLVE_TIMEOUT=120

is_num() { case "$1" in ''|*[!0-9]*) return 1;; esac; return 0; }

# 需要值的参数统一走这里：缺值直接退出码 2。用 ${2:?} 的话 bash 会以 1 退出，
# 和文档写的"2 参数错误"对不上。
need_val() { # $1 = 参数名；$2 = 值（可能是空）
  [ $# -ge 2 ] && [ -n "$2" ] || { echo "failed: $1 需要参数"; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --port) need_val --port "${2:-}"; PORTS+=("$2"); shift 2;;
    --flag-path) need_val --flag-path "${2:-}"; FLAGPATH="$2"; shift 2;;
    --solve) need_val --solve "${2:-}"; SOLVE="$2"; shift 2;;
    --solve-timeout) need_val --solve-timeout "${2:-}"; SOLVE_TIMEOUT="$2"; shift 2;;
    --no-flag-rotate) FLAG_ROTATE=0; shift;;
    --expect-flag) need_val --expect-flag "${2:-}"; EXPECT_FLAG="$2"; shift 2;;
    --check) need_val --check "${2:-}"; CHECK="$2"; shift 2;;
    --rdg) FORCE_RDG=1; shift;;
    --platform) need_val --platform "${2:-}"; PLATFORM="$2"; shift 2;;
    --run-arg) need_val --run-arg "${2:-}"; RUN_ARGS_EXTRA+=("$2"); shift 2;;
    --ready-cmd) need_val --ready-cmd "${2:-}"; READY_CMD="$2"; shift 2;;
    --ready-timeout) need_val --ready-timeout "${2:-}"; READY_TIMEOUT="$2"; shift 2;;
    --similarity) SIMILARITY=1; shift;;
    --no-cache) NO_CACHE=1; shift;;
    --similarity-report) need_val --similarity-report "${2:-}"; SIMILARITY_REPORT="$2"; shift 2;;
    --timeout) need_val --timeout "${2:-}"; START_TIMEOUT="$2"; shift 2;;
    --keep) KEEP=1; shift;;
    --report) need_val --report "${2:-}"; REPORT="$2"; shift 2;;
    -h|--help) usage;;
    -*) echo "未知参数: $1"; usage;;
    # 第一个非选项参数是题目目录，多出来的直接报错，避免悄悄忽略拼错的路径。
    *)
      if [ -z "$PROJECT" ]; then
        PROJECT="$1"
      else
        echo "多余参数: $1"; usage
      fi
      shift;;
  esac
done
[ -n "$PROJECT" ] || usage
# 非数字的 --timeout 会让下面的等待循环永远不超时，先挡住。
is_num "$START_TIMEOUT" || { echo "failed: --timeout 需要整数秒，收到 '${START_TIMEOUT}'"; exit 2; }
is_num "$SOLVE_TIMEOUT" || { echo "failed: --solve-timeout 需要整数秒，收到 '${SOLVE_TIMEOUT}'"; exit 2; }
[ -n "$READY_TIMEOUT" ] || READY_TIMEOUT="$START_TIMEOUT"
is_num "$READY_TIMEOUT" || { echo "failed: --ready-timeout 需要整数秒，收到 '${READY_TIMEOUT}'"; exit 2; }
# 非数字端口会让 listen_state 永远匹配不上，白等到超时才报错，先挡住。
for p in "${PORTS[@]+"${PORTS[@]}"}"; do
  is_num "$p" || { echo "failed: --port 需要整数端口，收到 '${p}'"; exit 2; }
done
command -v docker >/dev/null || { echo "failed: 找不到 docker"; exit 1; }
command -v curl >/dev/null || { echo "failed: 找不到 curl"; exit 1; }
PROJECT=$(cd "$PROJECT" 2>/dev/null && pwd) || { echo "failed: 目录不存在"; exit 2; }
cd "$PROJECT" || exit 2

# 报告是给跑验证的人看的，不是交付物。路径落在交付目录里直接拒绝，避免又把它交出去。
# --report 和 --similarity-report 都不许落在交付目录里，报告不是交付物。
for _rpt in "$REPORT" "$SIMILARITY_REPORT"; do
  [ -n "$_rpt" ] || continue
  case "$(cd "$(dirname "$_rpt")" 2>/dev/null && pwd || echo "")" in
    "$PROJECT"|"$PROJECT"/*)
      echo "failed: 报告路径在交付目录里（${_rpt}）。报告不属于交付物，写到系统临时目录，例如："
      echo "  --report \"\$(mktemp -d)/verify.json\""
      exit 2;;
  esac
done
if [ -n "$REPORT" ]; then
  case "$(cd "$(dirname "$REPORT")" 2>/dev/null && pwd || echo "")" in
    "$PROJECT"|"$PROJECT"/*)
      echo "failed: --report 的路径在交付目录里（${REPORT}）。报告不属于交付物，写到系统临时目录，例如："
      echo "  --report \"\$(mktemp -d)/verify.json\""
      exit 2;;
  esac
fi

STATUS=passed; NOTES=(); HINTS=(); STAGE=()
# 每条结论带严重级别，对应 SKILL.md 的三档：blocked=阻断、fix=要修、env=环境失败。
# 不分级的话，`.DS_Store` 和「拿不到 Flag」在报告里长得一样，Agent 容易为了变绿做表面修改。
fail()    { STATUS=failed; NOTES+=("blocked|$1"); }
partial() { [ "$STATUS" = passed ] && STATUS=partial; NOTES+=("fix|$1"); }
# 环境失败不许覆盖真实失败：已经判 failed 的题目，后面再遇到模拟器崩溃也还是 failed，
# 否则「构建失败 + 模拟器崩溃」会被粉饰成 environment_failed。
envfail() {
  [ "$STATUS" = failed ] || STATUS=environment_failed
  NOTES+=("env|$1")
}
hint()    { HINTS+=("$1"); }
stage() { # 同一阶段重复设置时只保留最后一次结论
  local i
  for i in "${!STAGE[@]}"; do
    [ "${STAGE[$i]%%:*}" = "$1" ] && { STAGE[i]="$1: $2"; return; }
  done
  STAGE+=("$1: $2")
}

# JSON 字符串转义：反斜杠、双引号、制表符、换行、回车都要处理。
# 只转前两个的话，带多行的 note（比如凭据命中清单）会写出非法 JSON。
json_str() {
  printf '%s' "$1" | tr '\t' ' ' | tr -d '\r' \
    | awk 'BEGIN{ORS=""} NR>1{print "\\n"} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}'
}

write_report() {
  [ -n "$REPORT" ] || return 0
  {
    printf '{\n  "project": "%s",\n  "status": "%s",\n  "platform": "%s",\n  "host_emulated": %s,\n  "stages": {' "$(json_str "$PROJECT")" "$STATUS" "$PLATFORM" "${HOST_IS_EMULATED:-0}"
    first=1
    for e in "${STAGE[@]+"${STAGE[@]}"}"; do
      k=${e%%:*}; v=${e#*: }
      [ "$first" = 1 ] || printf ','
      printf '\n    "%s": "%s"' "$k" "$(json_str "$v")"; first=0
    done
    printf '\n  },\n  "notes": ['
    first=1
    for n in "${NOTES[@]+"${NOTES[@]}"}"; do
      [ "$first" = 1 ] || printf ','
      printf '\n    {"severity": "%s", "message": "%s"}' "$(json_str "${n%%|*}")" "$(json_str "${n#*|}")"; first=0
    done
    printf '\n  ]\n}\n'
  } > "$REPORT" 2>/dev/null || {
    # 报告的 IO 错误不该改变题目验证结论，只提示。
    hint "报告写不进去：${REPORT}。确认目录存在，或写到 \$(mktemp -d) 下"
    rm -f "$REPORT" 2>/dev/null
    return 1
  }
  echo "   报告: ${REPORT}"
}

finish() {
  write_report
  echo
  [ ${#STAGE[@]} -gt 0 ] && echo "== 阶段: ${STAGE[*]}"
  echo "== 结果: $STATUS"
  for n in "${NOTES[@]+"${NOTES[@]}"}"; do echo "   - [${n%%|*}] ${n#*|}"; done
  for h in "${HINTS[@]+"${HINTS[@]}"}"; do echo "   提示: $h"; done
  case "$STATUS" in
    passed) exit 0;;
    partial) exit 3;;
    environment_failed) exit 4;;
    *) exit 1;;
  esac
}

BUILDLOG=$(mktemp); SOLVELOG=$(mktemp); CHECKLOG=$(mktemp)

# ---------- 交付目录白名单：用户拿到的是这个目录，多余文件就是垃圾
# 允许的顶层条目。RDG 题额外允许 check/、ttyd、changeflag.sh、php.ini 等题目真正运行需要的文件。
whitelisted() {
  case "$1" in
    # 附件目录历史上两种都在用：附件/ 和 题目附件/。镜像目录同理：镜像/ 和 题目镜像/。
    src|Dockerfile|start.sh|challenge.yaml|flag|README|solve|镜像|题目镜像) return 0;;
    附件|题目附件) return 0;;
    check|changeflag.sh|ttyd|ttyd.conf|php.ini|docker-entrypoint.sh|xinetd.conf|ctf.xinetd) return 0;;
    last|lasted) return 0;;   # 出题人保留原始交付材料的目录，按惯例叫 last/lasted
    *) return 1;;
  esac
}

cleanup() {
  rm -f "$BUILDLOG" "$SOLVELOG" "$CHECKLOG" 2>/dev/null
  [ -n "${IMAGE:-}" ] || return 0
  if [ "$KEEP" = 1 ]; then
    echo "[keep] 容器 ${CONTAINER}，镜像 ${IMAGE}"
    echo "   排查完删除: docker rm -f ${CONTAINER} && docker rmi ${IMAGE}"
    return
  fi
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  docker rmi "$IMAGE" >/dev/null 2>&1
}
# trap 必须放在 cleanup 定义之后：脚本在早期分支退出时会触发 EXIT trap，
# 那时函数还不存在就会打出 "cleanup: command not found"。
trap cleanup EXIT

# ---------- challenge.yaml 解析
# 能用 PyYAML 就真解析一遍：YAML 语法错误（flow 序列里带 {{flag}} 这种）只有真解析才查得出来，
# grep 读得出来但平台的解析器读不出来。没有 PyYAML 时退回 awk 取值。
HAVE_PYYAML=0
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  HAVE_PYYAML=1
elif [ -f challenge.yaml ]; then
  # 没有 PyYAML 时只能文本匹配，YAML 语法错误查不出来。换一台机器上跑就"变绿"的题
  # 多半就是这种情况，必须说出来，不能静默降级。
  hint "没装 PyYAML，challenge.yaml 只做了文本匹配，语法错误查不出来（StoryCreator 那种 {{flag}} 写进 flow 序列的题会被漏掉）。装一下：pip install pyyaml"
fi

YAML_ERROR=""
yaml_probe() { # 输出 TSV：字段名<Tab>值
  [ -f challenge.yaml ] || return 0
  [ "$HAVE_PYYAML" = 1 ] || return 1
  python3 - challenge.yaml <<'PY'
import sys

try:
    import yaml
except Exception:
    sys.exit(1)

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
except Exception as exc:  # YAML 语法错误，平台的解析器同样会失败
    print("YAML_ERROR\t%s" % str(exc).replace("\t", " ").replace("\n", " "))
    sys.exit(0)

if not isinstance(data, dict):
    data = {}


def walk(node, path):
    """按 a.b.c 取嵌套值。"""
    cur = node
    for key in path.split("."):
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def dump(key, *paths):
    """按顺序取第一个存在的路径。字段既可以放在 challenge: 下面，也可以放在顶层。"""
    val = None
    for path in paths:
        val = walk(data, path)
        if val is not None:
            break
    if val is None:
        return
    if isinstance(val, (list, tuple)):
        val = ",".join(str(x) for x in val)
    print("%s\t%s" % (key, str(val).replace("\t", " ").replace("\n", " ")))


dump("expose_ports", "challenge.expose_ports", "expose_ports")
dump("flag_path", "challenge.flag.path", "flag.path")
dump("flag_mode", "challenge.flag.mode", "flag.mode")
dump("probe_path", "challenge.verification.solve_probe.path", "verification.solve_probe.path")
dump("name", "challenge.name", "name")
dump("prov_status", "provenance.status", "challenge.provenance.status")
dump("prov_verify", "provenance.verify", "challenge.provenance.verify")
dump("env_limited", "provenance.env_limited", "challenge.provenance.env_limited")
dump("check_path", "challenge.check.path", "check.path")
PY
}

YAML_PORTS=""; YAML_FLAGPATH=""; YAML_PROBE=""; YAML_PROV_STATUS=""; YAML_PROV_VERIFY=""; YAML_CHECK_PATH=""; YAML_FLAG_MODE=""; YAML_NAME=""; YAML_ENV_LIMITED=""
if [ -f challenge.yaml ] && [ "$HAVE_PYYAML" = 1 ]; then
  while IFS="$(printf '\t')" read -r k v; do
    case "$k" in
      YAML_ERROR) YAML_ERROR="$v";;
      expose_ports) YAML_PORTS="$v";;
      flag_path) YAML_FLAGPATH="$v";;
      probe_path) YAML_PROBE="$v";;
      name) YAML_NAME="$v";;
      prov_status) YAML_PROV_STATUS="$v";;
      prov_verify) YAML_PROV_VERIFY="$v";;
      env_limited) YAML_ENV_LIMITED="$v";;
      check_path) YAML_CHECK_PATH="$v";;
      flag_mode) YAML_FLAG_MODE="$v";;
    esac
  done < <(yaml_probe)
elif [ -f challenge.yaml ]; then
  # 没有 PyYAML 时，这两个字段决定判定方式，用文本匹配兜一下，免得静态 Flag 题被当成平台写 Flag 的题。
  grep -qE '^[[:space:]]+mode:[[:space:]]*["'"'"']?static' challenge.yaml && YAML_FLAG_MODE=static
  YAML_CHECK_PATH=$(sed -nE 's/^[[:space:]]+path:[[:space:]]*["'"'"']?(\.?\/?check\/[^"'"'"'[:space:]]+).*/\1/p' challenge.yaml | head -1)
fi

# 取某一节的正文（到下一个一至三级标题为止），用于按节检查。
# 全文 grep 会被别的章节里的同名字段蒙混过去：1.5 没写"平台覆盖方式"但 1.9 提了一句
# "flag 文件位置"，全文匹配同样能过，空着的 1.5 就没人发现了。
section_body() { # $1 = 节号，$2 = 手册路径
  awk -v num="$1" '
    BEGIN { target = "^#+[[:space:]]*" num "[[:space:]]" }
    $0 ~ target { inb = 1; next }
    # 代码块里的 # 注释（如 flag_script 模板的 # 平台注入时…）不是标题，跳过。
    /^```/ { fence = !fence; if (inb) print; next }
    inb && !fence && /^#{1,3}[[:space:]]/ { exit }
    inb { print }
  ' "$2"
}

# 取某一节里含 $new_flag 的围栏代码块，用来真跑手册 1.5 贴的 flag_script。
# 平台后台保存题目校验的就是这段原文；只在手册里「出现过 $new_flag」不够，
# 脚本里路径写错、变量名写错，照样能过文字检查，题目上线后 Flag 写不进去。
section_code_block() { # $1 = 节号，$2 = 手册路径
  awk -v num="$1" '
    BEGIN { target = "^#+[[:space:]]*" num "[[:space:]]" }
    $0 ~ target { inb = 1; next }
    inb && !fence && /^#{1,3}[[:space:]]/ { exit }
    inb && /^```/ {
      if (fence) {
        fence = 0
        # 只取第一个含 $new_flag 的块。1.5 里贴了多个示例时，拼接起来执行会互相覆盖。
        if (!found && block ~ /\$new_flag|\$\{new_flag\}/) { printf "%s", block; found = 1 }
        block = ""
      } else { fence = 1; block = "" }
      next
    }
    inb && fence { block = block $0 "\n" }
    END { exit(found ? 0 : 1) }
  ' "$2"
}

# 执行容器内的 flag_script。脚本里等数据库是常见写法，加 60 秒上限，
# 免得一个死循环把 verify.sh 挂在这里。
run_flag_script() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 60 docker exec "$CONTAINER" /bin/bash /tmp/verify_changeflag.sh >/dev/null 2>&1
  else
    docker exec "$CONTAINER" /bin/bash /tmp/verify_changeflag.sh >/dev/null 2>&1
  fi
}

# 手册检查：文件名、章节骨架、事实字段、启动命令，以及 TODO 残留。
# 判断部分（1.2/1.4/1.8/1.9）的内容不检查——这个脚本查不出内容真假，
# 假装能查只会让人把"章节齐全"当成"手册写完"。有 TODO 残留时按 partial 报，
# 不判 failed（材料确实没有来源时留 TODO 是对的），但也不许再报 passed。
assert_handbook() {
  local expected base found=() todo missing=() joined is_container=0
  base=$(basename "$PROJECT")
  [ -f Dockerfile ] && is_container=1
  shopt -s nullglob
  found=("${PROJECT}/README"/*.md)
  if [ ${#found[@]} -eq 0 ]; then
    stage handbook failed
    fail "README/ 下没有手册。手册是交付的一部分，文件名写成 README/${base}.md"
    return
  fi
  expected="${PROJECT}/README/${base}.md"
  MANUAL_PATH="$expected"
  if [ ! -f "$expected" ]; then
    stage handbook failed
    fail "手册文件名不对。必须是 README/${base}.md，现在是：$(printf '%s ' "${found[@]##*/}")"
    return
  fi

  # 章节骨架。容器题和附件题都按九节写；
  # 附件题按 references/manual.md 去掉 1.7 部署方式、编号顺延（1.7 题目设计、1.8 解题步骤），
  # 所以附件题少 1.9 也算齐全。
  local sec
  for sec in 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9; do
    grep -qE "^#+[[:space:]]*${sec}[[:space:]]" "$expected" || missing+=("$sec")
  done
  # 附件题实际有三种写法，都认：
  #   1. 九节齐全（有些人懒得顺延）
  #   2. 去掉 1.7 部署方式、编号顺延（缺 1.9）
  #   3. 去掉 1.7、保留 1.8/1.9 的编号（AI-81 和 EXP-23 那批就是这种）
  local skeleton="九节"
  if [ ${#missing[@]} -gt 0 ]; then
    if [ "$is_container" = 0 ] && [ ${#missing[@]} -eq 1 ] && [ "${missing[0]}" = 1.9 ]; then
      skeleton="八节（附件题顺延）"
    elif [ "$is_container" = 0 ] && [ ${#missing[@]} -eq 1 ] && [ "${missing[0]}" = 1.7 ]; then
      skeleton="八节（附件题去掉 1.7）"
    else
      stage handbook failed
      fail "手册缺章节：${missing[*]}。骨架见 references/manual.md"
      return
    fi
  fi

  # 事实字段：这几项 Skill 有能力查证，缺了就是没写全。
  # 只在本节正文里找，别让别的章节顺手提到关键词就把空着的节蒙过去。
  local fact_missing=() sec15 sec16
  sec15=$(section_body 1.5 "$expected")
  sec16=$(section_body 1.6 "$expected")
  # 1.5 的写法按题型不同：容器题写平台覆盖命令和读取时机，静态 Flag 题写「平台覆盖方式：无」，
  # RDG 无 Flag 合同时写「敏感目标不是 /flag」。所以只要本节写了 flag 这件事就算写了，
  # 不拿容器题的字段去卡另外两类题。
  if [ -z "$(printf '%s' "$sec15" | tr -d '[:space:]')" ] \
     || ! printf '%s' "$sec15" | grep -qiE 'flag|平台覆盖'; then
    fact_missing+=("1.5 旗帜信息（平台覆盖方式 / flag 文件位置 / 读取时机）")
  fi
  # 容器题查端口和账号；附件题没有端口，按 manual.md 只要求写清发了哪些附件，
  # 所以只要求本节有内容，不要求出现"端口 / 账号 / 地址"这些它本来就没有的字段。
  if [ "$is_container" = 1 ]; then
    # 写 `http://127.0.0.1:8080/` 或 `127.0.0.1:5020` 比写"端口：8080"信息更全，
    # 也要认，不能只匹配"端口/账号/地址"这三个词。
    printf '%s' "$sec16" | grep -qE '端口|账号|地址|https?://|[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]{2,5}|:[0-9]{2,5}\b|ssh |nc ' \
      || fact_missing+=("1.6 题目情况（端口 / 账号 / 地址）")
  else
    [ -n "$(printf '%s' "$sec16" | tr -d '[:space:]')" ] \
      || fact_missing+=("1.6 题目情况（发了哪些附件、每个附件是什么）")
  fi
  if [ ${#fact_missing[@]} -gt 0 ]; then
    stage handbook partial
    partial "手册事实字段不全：${fact_missing[*]}。这几项能从源码和配置读出来，不该缺"
    return
  fi

  if grep -qE '常见失败现象|常见问题排查' "$expected"; then
    stage handbook partial
    partial "手册里有常见失败现象这一节，这一节不写进交付手册"
    return
  fi
  # 部署命令里没带 /start.sh 是最常见的漏写，平台就是按这个启动的。
  # 手册里的模板用反斜杠续行写成多行，所以先把续行合并再匹配。
  joined=$(awk '{ if ($0 ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, " "); printf "%s", $0 } else print }' "$expected")
  if [ "$is_container" = 1 ] && ! printf '%s\n' "$joined" | grep -qE 'docker run[^`]*start\.sh'; then
    stage handbook partial
    partial "手册 1.7 的 docker run 命令没带 /start.sh，平台按 /start.sh 启动容器，手册要和平台一致"
    return
  fi

  # TODO 残留：判断部分没有来源时本来就该留空给人工写，所以不判失败——
  # 但也不能算 passed，否则「手册没写完」和「全部通过」会同时成立。
  todo=$(grep -c 'TODO(人工填写)' "$expected" 2>/dev/null); todo=${todo:-0}
  if [ "$todo" -gt 0 ] 2>/dev/null; then
    stage handbook "todo: $todo"
    # 节号按形态给：附件题的题目设计和解题步骤顺延成 1.7、1.8，写死九节的编号会指错节。
    if [ "$is_container" = 1 ]; then
      partial "手册有 ${todo} 处 TODO(人工填写) 没填（1.2 题目描述、1.4 考察信息、1.8 题目设计、1.9 解题步骤），交付前要么从原始材料搬运整理，要么如实告诉用户哪几节还空着"
    else
      partial "手册有 ${todo} 处 TODO(人工填写) 没填（1.2 题目描述、1.4 考察信息、1.7 题目设计、1.8 解题步骤），交付前要么从原始材料搬运整理，要么如实告诉用户哪几节还空着"
    fi
    return
  fi
  # 同一节号出现两次以上，说明这份手册混进了别的内容（真实案例：一份手册里有两套 1.5-1.8，
  # 前半是另一道 Node/jsfuck 题）。骨架检查只查"每节在不在"，查不出重复。
  DUP_SECS=$(grep -oE '^#+[[:space:]]*1\.[1-9][[:space:]]' "$expected" \
    | grep -oE '1\.[1-9]' | sort | uniq -d | tr '\n' ' ')
  if [ -n "$DUP_SECS" ]; then
    stage handbook failed
    fail "手册里这些节号出现了不止一次：${DUP_SECS}。多半是混进了别的题的内容，逐节核对，把不属于本题的删掉"
    return
  fi
  # 手册里出现同级别的题目的 name，说明是复制粘贴串了。
  # 同批其他题目的 name，用来发现"手册里混进了别的题的内容"。
  # 三个坑都要避开，否则误报比真报多：
  #   1. 自己那份要排掉——按 challenge.yaml 的 name 排，不是按目录名（两者常常不同）
  #   2. name 里可能有空格（`What is hikvision`），不能按空格截断取第一个词
  #   3. 太短的名字（Web、Pwn、某）不参与比对，任何手册都会写到这些词
  if [ -d "${PROJECT}/.." ]; then
    SELF_NAME=$(sed -nE 's/^[[:space:]]*name:[[:space:]]*(.*)$/\1/p' challenge.yaml 2>/dev/null \
      | head -1 | sed -E 's/[[:space:]]+#.*$//; s/^["'\'']//; s/["'\'']$//')
    OTHER_NAMES=$(for f in "${PROJECT}/../"*/challenge.yaml; do
      [ -f "$f" ] || continue
      # 排掉本目录自己的 yaml
      [ "$(cd "$(dirname "$f")" && pwd)" != "$PROJECT" ] || continue
      sed -nE 's/^[[:space:]]*name:[[:space:]]*(.*)$/\1/p' "$f" | head -1 \
        | sed -E 's/[[:space:]]+#.*$//; s/^["'\'']//; s/["'\'']$//'
    done | grep -vxF "$SELF_NAME" 2>/dev/null \
      | python3 -c 'import sys
for line in sys.stdin:
    line = line.rstrip("\n")
    if len(line) >= 4:
        print(line)' 2>/dev/null | sort -u)
    if [ -n "$OTHER_NAMES" ]; then
      HIT_OTHER=$(printf '%s\n' "$OTHER_NAMES" | while IFS= read -r on; do
        [ -n "$on" ] && grep -qF "$on" "$expected" && echo "$on"
      done | head -3 | tr '\n' ' ')
      if [ -n "$HIT_OTHER" ]; then
        stage handbook partial
        partial "手册里出现了同批其他题目的 name：${HIT_OTHER}。确认不是复制粘贴串题"
      fi
    fi
  fi
  # ---- 1.5 的字段核对（不只是"出现过 flag 两个字"）
  SEC15=$(section_body 1.5 "$expected")
  if [ -n "$SEC15" ]; then
    # 动态 Flag 题：1.5 必须贴出含 $new_flag 的 flag_script，否则平台后台存不进去（阻断级）。
    # 附件题没有容器、平台也不写 Flag，1.5 只要求写「平台覆盖方式：无」，不按容器题的四项卡。
    if [ "${STATIC_FLAG:-0}" = 0 ] && [ -f challenge.yaml ] && [ "$is_container" = 1 ]; then
      if ! printf '%s' "$SEC15" | grep -q '\$new_flag'; then
        # 1.5 里已经给了等价的平台写入命令时不算缺——历史题常写 docker exec 形态。
        if printf '%s' "$SEC15" | grep -qiE 'docker[[:space:]]+exec|flag_script|平台覆盖方式[：:][[:space:]]*[^无]'; then
          hint "手册 1.5 没贴含 \$new_flag 的 flag_script，给的是 docker exec 等价命令。新题仍建议贴脚本原文，平台后台要的就是那段"
        else
          stage handbook partial
          partial "手册 1.5 里没有含 \$new_flag 的 flag_script，也没有平台写入命令。平台保存题目时校验必须含 \$new_flag，缺了题目存不进去"
        fi
      fi
      if ! printf '%s' "$SEC15" | grep -q '读取时机'; then
        stage handbook partial
        partial "手册 1.5 缺「读取时机」。这一条决定平台换 Flag 后生不生效：每次请求读立即生效，启动时读进内存要重启"
      fi
    fi
    # 静态 Flag 题：1.5 写的原始静态值要和仓库 flag 文件对得上。
    if [ "${STATIC_FLAG:-0}" = 1 ] && [ -f flag ]; then
      DOC_FLAG=$(printf '%s' "$SEC15" | sed -nE 's/.*原始静态[Ff]lag[：:][[:space:]]*`?([^`[:space:]]+)`?.*/\1/p' | head -1)
      FILE_FLAG=$(tr -d '\r\n' < flag)
      if [ -n "$DOC_FLAG" ] && [ -n "$FILE_FLAG" ] && [ "$DOC_FLAG" != "$FILE_FLAG" ]; then
        stage handbook partial
        partial "手册 1.5 写的静态 Flag（${DOC_FLAG}）和 flag 文件（${FILE_FLAG}）不一致。真实事故：差一个后缀，选手提交不对"
      fi
    fi
    # 动态/静态声明要和 flag.mode 一致。
    # 只对容器题查：附件题本来就没有平台写 Flag 这回事，不需要写 flag.mode。
    if [ "$is_container" = 1 ] && printf '%s' "$SEC15" | grep -qE '平台覆盖方式[：:][[:space:]]*无'; then
      [ "${STATIC_FLAG:-0}" = 0 ] && [ -f challenge.yaml ] && {
        stage handbook partial
        partial "手册 1.5 写「平台覆盖方式：无」，但 challenge.yaml 没写 flag.mode: static。两处要一致"
      }
    fi
  fi
  echo "   手册 $(basename "$expected") ${skeleton}齐全，无待填项"
  # 前面 1.5/串题那些检查如果有 partial，别再把它盖成 passed——报告 JSON 的 stages
  # 和最终 status 对不上，下游按 stages 判断会漏。
  case " ${NOTES[*]+"${NOTES[*]}"} " in
    *"手册"*) stage handbook partial ;;
    *) stage handbook passed ;;
  esac
}

# provenance 是必填的，写成 pending 或者 verify 空着等于把"没证据"伪装成"待整理"。
# 老题没有这个字段时不报——那是历史包袱，不是这次没做；有新题忘了写才值得说。
assert_provenance() {
  [ -f challenge.yaml ] || return 0
  if [ -n "$YAML_PROV_STATUS" ] || [ -n "$YAML_PROV_VERIFY" ] || grep -qE '^provenance:' challenge.yaml; then
    if [ "$YAML_PROV_STATUS" = pending ] \
       || grep -qE '^[[:space:]]+status:[[:space:]]*pending[[:space:]]*$' challenge.yaml; then
      stage provenance loaded
      fail "provenance.status 是 pending。它只能取 original_adapter / independent_completion / incomplete，没定下来就先别交付"
      return
    fi
    if [ "$YAML_PROV_VERIFY" = pending ] \
       || grep -qE '^[[:space:]]+verify:[[:space:]]*(""|'"''"'|[[:space:]]*)$' challenge.yaml; then
      stage provenance loaded
      fail "provenance.verify 是空的。填 passed / environment_failed / incomplete / no_flag_contract，空着等于没给结论"
      return
    fi
    # status 写了但 verify 整行缺失：PyYAML 读不到 verify 就拿到空串，上面那个 grep 也匹配不到
    # 「verify: 空」的形态。单独查：status 非空而 verify 为空，就是缺结论。
    if [ -n "$YAML_PROV_STATUS" ] && [ -z "$YAML_PROV_VERIFY" ] \
       && ! grep -qE '^[[:space:]]+verify:[[:space:]]*[^[:space:]]' challenge.yaml; then
      stage provenance loaded
      fail "provenance 有 status 但没有 verify。verify 填 passed / environment_failed / incomplete / no_flag_contract，空着等于没给结论"
      return
    fi
    # 枚举值之外的值一律不认。"verified""ok"这类自造取值读起来像通过，实际平台和下一环都不认。
    case "$YAML_PROV_STATUS" in
      ""|original_adapter|independent_completion|incomplete) ;;
      *) stage provenance loaded
         fail "provenance.status 取值不合法：${YAML_PROV_STATUS}。只能取 original_adapter / independent_completion / incomplete"
         return;;
    esac
    case "$YAML_PROV_VERIFY" in
      ""|passed|environment_failed|incomplete|no_flag_contract) ;;
      *) stage provenance loaded
         fail "provenance.verify 取值不合法：${YAML_PROV_VERIFY}。只能取 passed / environment_failed / incomplete / no_flag_contract（原题没有 Flag 合同、按构造不可能验证 Flag 的题用这个）"
         return;;
    esac
    # 声称保留了原始材料，就要能证明这些文件真的在。审查里出现过 original_material 列出不存在路径的情况。
    PROV_MISSING_MATERIAL=()
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      # 条目后面常带中文括注（`src/ICPV2（ICP 备案系统 webapp 原始目录）`），先剥掉再判。
      m=${m%%（*}; m=${m%%(*}
      m=$(printf '%s' "$m" | sed -E 's/[[:space:]]+$//')
      [ -n "$m" ] || continue
      case "$m" in
        http://*|https://*|/*) continue;;   # 外部引用和绝对路径不核对
      esac
      [ -e "$m" ] && continue
      # 裸文件名和带斜杠的路径都可能在 src/ 下（`dvlaa/content/x.py` → `src/dvlaa/content/x.py`）。
      # 按「根目录 / src/ / solve/ / 附件目录 / 题目源码/ 任一命中」判定。
      for _d in src solve 附件 题目附件 题目源码 镜像 题目镜像 README/参考资料; do
        [ -e "$_d/$m" ] && continue 2
      done
      # 泛指词、外部引用、出题侧不交付的证据，都不当路径核对。
      case "$m" in
        源码|题目源码|设计稿|原始材料|附件|题目手册|官方题解|官方验证脚本|原始|README.md|UPSTREAM-README.md|exp.py)
          continue;;
        "VM 资产") continue;;
      esac
      # 出题侧引用（论文、研究文档、artifact）本来就不在交付目录，不属于漏交付，不提示。
      case "$m" in
        *.pdf|*.PDF|*.doc|*.docx|*.tex|*.bib|*.ppt|*.pptx|*.md) continue;;
        artifact/*|artifact|paper/*|paper|*论文*) continue;;
      esac
      # 只记下不存在的，留给下面统一报
      PROV_MISSING_MATERIAL+=("$m")
    done < <(awk '
      /^[[:space:]]*original_material:/ { inb=1; v=$0; sub(/.*original_material:[[:space:]]*\[?/, "", v); gsub(/[][",]/, "", v); n=split(v, a, /[[:space:]]+/); for(i=1;i<=n;i++) if(a[i]!="") print a[i]; next }
      inb && /^[[:space:]]*-/ { v=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", v); gsub(/["'\'']/, "", v); print v; next }
      inb && $0 !~ /^[[:space:]]*$/ { inb=0 }
    ' challenge.yaml)
    # original_material 是「出题人手里的原始材料清单」，不是「交付目录里必须存在的文件」。
    # 写的是上游仓库路径（dvlaa/modules/xx.py）却不在交付目录，是正常的上游来源引用，不是错。
    # 只提示，不判 partial。
    if [ ${#PROV_MISSING_MATERIAL[@]} -gt 0 ]; then
      hint "provenance.original_material 里这些路径不在交付目录：${PROV_MISSING_MATERIAL[*]}。可能是上游仓库来源引用（正常），也可能是声称保留却漏了。确认一下即可"
    fi
    # name 和目录名不一致时只提示。历史交付物大量用短 id（asi-01、redis-topk），
    # 用户实际没有采纳「name 必须等于中文目录名」这条，报 partial 只会淹没真问题。
    if [ -n "$YAML_NAME" ] && [ "$YAML_NAME" != "$(basename "$PROJECT")" ]; then
      hint "challenge.yaml 的 name（${YAML_NAME}）和交付目录名（$(basename "$PROJECT")）不一致。规范要求目录名是主名、其余五处派生，但历史题常用短 id，这条仅提示"
    fi
    case " ${NOTES[*]+"${NOTES[*]}"} " in
      *"provenance"*) stage provenance partial ;;
      *) stage provenance passed ;;
    esac
  fi
}

# ---------- 先判断目录形态：出题阶段的交付包 / 比赛现场的打包成品 / 归档
# 交付物有三种形态，verify.sh 只对第一种做结构检查：
#   1. 出题阶段交付包：src/ Dockerfile start.sh challenge.yaml README/ solve/
#   2. 比赛现场打包成品：只有一个 <题目名>.tar，或 题目附件/ + 题目手册.md
#   3. 比赛归档：题目镜像/ 题目源码/ 题目手册/
# 后两种已经在平台上跑过、比赛用过了，结构检查对它们没有意义，
# 别报一堆「没有 Dockerfile」「白名单外的条目」把真问题淹掉。
# 有 start.sh 就说明按容器题交付，缺 Dockerfile 是错误，不是"当成附件题"静默放过。
# challenge.yaml 不算判据——附件题可以带一个只声明 provenance 的 challenge.yaml。
if [ ! -f Dockerfile ] && [ -f start.sh ]; then
  echo "== 目录形态"
  echo "   有 start.sh 但没有 Dockerfile"
  stage delivery failed
  fail "这个目录有 start.sh，按容器题交付，但没有 Dockerfile。确认是漏了文件还是拿错了目录"
  finish
fi

if [ ! -f Dockerfile ] && [ ! -f start.sh ] && [ ! -f challenge.yaml ]; then
  echo "== 目录形态"
  ONLY_TAR=$(ls -1 *.tar 2>/dev/null | head -1)
  if [ -n "$ONLY_TAR" ]; then
    echo "   打包成品：只有镜像 tar $(basename "$ONLY_TAR")（$(du -h "$ONLY_TAR" | cut -f1)）"
    stage delivery skipped
    partial "这是比赛现场的打包成品，不是出题阶段的交付包，verify.sh 没有验证它。要用它，先 docker load 后手工起容器确认"
    finish
  fi
  if [ -d 题目附件 ] && [ -f 题目手册.md ]; then
    echo "   打包成品：题目附件/ + 题目手册.md"
    echo "   附件 $(ls -1 题目附件 | wc -l | tr -d ' ') 个，手册 $(wc -l < 题目手册.md | tr -d ' ') 行"
    stage delivery skipped
    partial "这是比赛现场的打包成品，verify.sh 没有验证附件内容。确认附件能在干净环境打开"
    finish
  fi
  # AWD 现场打包形态：题目镜像/ + attachment/ + check.py + source/ + 设计文档 + 手册(带括号)。
  # 只要有 题目镜像/ 目录就按比赛归档跳过，不苛求 题目源码/题目手册 的目录名。
  if [ -d 题目镜像 ] || [ -d 题目源码 ] || [ -d 题目手册 ]; then
    echo "   比赛归档：$(ls -d 题目镜像 题目源码 题目手册 2>/dev/null | tr '\n' ' ')"
    stage delivery skipped
    partial "这是比赛归档形态（镜像/源码/手册分开放），不是出题阶段的交付包，verify.sh 没有验证它"
    finish
  fi
  # 附件题：只有 附件/（或 题目附件/）+ solve/，没有容器
  ATT_DIR=""
  [ -d 附件 ] && ATT_DIR=附件
  [ -z "$ATT_DIR" ] && [ -d 题目附件 ] && ATT_DIR=题目附件
  if [ -n "$ATT_DIR" ] || [ -f solve/solve.py ]; then
    :   # 走后面的附件题分支
  else
    stage delivery failed
    fail "目录形态无法识别：既没有 Dockerfile/start.sh/challenge.yaml，也没有 <题目名>.tar / 题目附件+题目手册.md / 题目源码+题目手册。确认是不是拿错了目录"
    finish
  fi
fi

# STATIC_FLAG 要在手册检查之前就算出来：assert_handbook 里的 1.5 核对要按静态/动态分支。
# 原来它到写 Flag 那一段才赋值，导致所有静态 Flag 题走动态分支，报三条假阳性。
STATIC_FLAG=0
case "$(printf '%s' "$YAML_FLAG_MODE" | LC_ALL=C tr '[:upper:]' '[:lower:]')" in static) STATIC_FLAG=1;; esac

echo "== 检查手册"
assert_handbook
echo "== 检查 provenance"
assert_provenance

# ---------- 手册雷同度（可选）：批量交付时最容易被骂"一坨一模一样的垃圾"
# 只比对同批目录（父子两级）里的手册正文，算 3-gram Jaccard 相似度。
# 只报警告，不改结论——同源题目（同一框架换参数）本来就会像，硬判 failed 会误伤。
check_similarity() {
  [ "$SIMILARITY" = 1 ] || return 0
  echo "== 检查手册雷同度"
  command -v python3 >/dev/null || { hint "没有 python3，跳过雷同度检查"; return 0; }
  local sim_rc=0
  python3 - "$PROJECT" "$(basename "$PROJECT")" "$SIMILARITY_REPORT" <<'PY' || sim_rc=$?
import os, re, sys, json
from collections import Counter

proj, base, report = sys.argv[1], sys.argv[2], sys.argv[3]
# 同批范围：题目目录的父目录下所有同级交付目录
batch_root = os.path.dirname(os.path.abspath(proj))

def body(path):
    """取手册正文，去掉标题行、代码块、TODO 和注释，只留叙述文字。"""
    try:
        s = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    s = re.sub(r"```.*?```", " ", s, flags=re.S)          # 代码块不算雷同，题目命令本来就不同
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.S)
    s = re.sub(r"^#+.*$", " ", s, flags=re.M)
    s = re.sub(r"TODO\(人工填写\)", " ", s)
    s = re.sub(r"[\s\W_]+", "", s)                        # 只留汉字字母数字，消掉格式差异
    return [s[i:i+3] for i in range(len(s) - 2)]

def jaccard(a, b):
    A, B = set(a), set(b)
    if not A or not B:
        return 0.0
    return len(A & B) / len(A | B)

me = os.path.join(proj, "README", base + ".md")
mine = body(me)
if not mine:
    print("   本题目录没有可比对的手册正文，跳过")
    sys.exit(0)

rows = []
for name in sorted(os.listdir(batch_root)):
    other = os.path.join(batch_root, name)
    if other == os.path.abspath(proj) or not os.path.isdir(other):
        continue
    f = os.path.join(other, "README", name + ".md")
    if not os.path.isfile(f):
        continue
    b = body(f)
    if not b:
        continue
    rows.append({"other": name, "similarity": round(jaccard(mine, b), 3)})

rows.sort(key=lambda r: -r["similarity"])
# 阈值按实测定：AI-81-DVLAA 的 81 份手册里，套模板的那组 0.61~0.66，其余 <=0.34，
# 中间是空的。0.6 落在断崖上方，既不漏掉整组套模板，也不会误伤正常同源题目。
high = [r for r in rows if r["similarity"] >= 0.6]
mid = [r for r in rows if 0.45 <= r["similarity"] < 0.6]
print(f"   同批 {len(rows)} 份手册，>=0.6 的 {len(high)} 份，0.45~0.6 的 {len(mid)} 份")
for r in high[:5]:
    print(f"   [雷同] {r['similarity']:.2f}  {r['other']}")
for r in mid[:3]:
    print(f"   [接近] {r['similarity']:.2f}  {r['other']}")
if report:
    with open(report, "w", encoding="utf-8") as fh:
        json.dump({"project": base, "rows": rows}, fh, ensure_ascii=False, indent=1)
    print(f"   报告: {report}")
sys.exit(2 if high else 0)
PY
  [ "$sim_rc" = 2 ] && hint "手册与同批其他题目高度雷同（>=0.6），逐题确认这不是套模板批量生成。用户明确说过「样式不能都一样」"
  return 0
}
check_similarity

# ---------- 交付目录检查：白名单 + 垃圾文件（递归）
echo "== 检查交付目录"
shopt -s nullglob dotglob
EXTRA=()
for entry in "$PROJECT"/*; do
  name=$(basename "$entry")
  # 已知垃圾文件走下面的 JUNK 检查（只提醒），不要在这里判成白名单外条目（failed）。
  # 否则根目录一个 .DS_Store 就会把整题判死，和"垃圾文件只提醒"的规则打架。
  case "$name" in
    .DS_Store|Thumbs.db|__pycache__|.venv|*.pyc) continue;;
  esac
  whitelisted "$name" || EXTRA+=("$name")
done
JUNK=()
while IFS= read -r junk; do
  [ -n "$junk" ] && JUNK+=("${junk#"$PROJECT"/}")
done < <(find "$PROJECT" \( -name '.DS_Store' -o -name 'Thumbs.db' -o -name '__pycache__' -o -name '*.pyc' -o -name '.venv' \) -print 2>/dev/null)

DELIVERY=passed
if [ ${#EXTRA[@]} -gt 0 ]; then
  echo "   多余文件："
  for e in "${EXTRA[@]}"; do echo "   - $e"; done
  # 白名单以外的顶层条目一律 failed，不再分软硬。
  # 之前只把 verify.sh/报告/内部文件判 failed、其余判 partial，结果 305MB 的 vendor 目录、
  # 夹带真实 flag 的 DSH 会话 zip 都能以 passed 交付出去。
  DELIVERY=failed
  fail "交付目录里有白名单外的条目：${EXTRA[*]}。单个题目录只允许 src/ Dockerfile start.sh challenge.yaml flag README/ solve/，按需加 附件/ 镜像/ last/（RDG 题另有 check/ changeflag.sh ttyd 等）。多出来的要么删掉，要么确认后加进白名单"
fi
if [ ${#JUNK[@]} -gt 0 ]; then
  # .DS_Store / __pycache__ / *.pyc 只提醒，不改结论，也不改 delivery 阶段。
  # 之前这里顺手写了 DELIVERY=partial，阶段行和报告里显示 partial 而最终结果 passed，
  # 和 SKILL 里「记录即可」的三档定义对不上，Agent 看到 partial 就去做表面清理。
  hint "交付目录里有垃圾文件：${JUNK[*]}。一条命令清掉：find <交付根> \\( -name .DS_Store -o -name __pycache__ -o -name '*.pyc' \\) -print -delete"
fi
if [ "$DELIVERY" = passed ]; then
  # 两个包共用硬链接时，单独复制其中一个会丢内容——交付包必须能独立拷走。
  HARDLINK=$(find "$PROJECT" -type f -links +1 -print 2>/dev/null | head -5)
  if [ -n "$HARDLINK" ]; then
    DELIVERY=partial
    partial "交付目录里有硬链接文件（多包共享同一 inode），单独复制这个包会丢内容。逐个 cp 一遍即可拆开：$(printf '%s ' $HARDLINK)"
  fi
fi
if [ "$DELIVERY" = passed ]; then
  # 选手附件必须是能独立打开的：0 字节、坏 zip、macOS 垃圾都算。
  if [ -d 附件 ]; then
    # .DS_Store / __MACOSX 是打包垃圾，不是发给选手的附件，0 字节也不该判 partial。
    EMPTY_ATT=$(find 附件 -type f -size 0 ! -name '.DS_Store' ! -name 'Thumbs.db' ! -path '*/__MACOSX/*' -print 2>/dev/null | head -3)
    [ -n "$EMPTY_ATT" ] && { DELIVERY=partial; partial "附件里有 0 字节文件：$(printf '%s ' $EMPTY_ATT)，选手拿到也解不了"; }
    MACOS_JUNK=$(find 附件 \( -name '__MACOSX' -o -name '.DS_Store' \) -print 2>/dev/null | head -3)
    [ -n "$MACOS_JUNK" ] && hint "附件里带 macOS 打包垃圾：$(printf '%s ' $MACOS_JUNK)。在 Linux 上重打，或清除后再交付"
  fi
fi
[ "$DELIVERY" = passed ] && echo "   干净"
stage delivery "$DELIVERY"

# ---------- 附件压缩包与 src 的一致性
# 真事故：改了 src 里的检测器，忘了重新打包附件 zip，选手拿到的还是旧版本。
# 只比对两边都有的同名文件；src 有而包里缺的，仅在覆盖率 >= 50% 时才算漏打包，
# 避免把「故意只发部分源码」的题误报成漏打包。
if [ -d src ] && [ -d 附件 ]; then
  sha_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'
    fi
  }
  while IFS= read -r archive; do
    [ -n "$archive" ] || continue
    case "$archive" in
      *.zip) command -v unzip >/dev/null 2>&1 || continue ;;
    esac
    TMPX=$(mktemp -d "${TMPDIR:-/tmp}/verify-att.XXXXXX")
    case "$archive" in
      *.zip) unzip -q "$archive" -d "$TMPX" >/dev/null 2>&1 || { rm -rf "$TMPX"; continue; } ;;
      *.tar.gz|*.tgz) tar -xzf "$archive" -C "$TMPX" >/dev/null 2>&1 || { rm -rf "$TMPX"; continue; } ;;
      *.tar) tar -xf "$archive" -C "$TMPX" >/dev/null 2>&1 || { rm -rf "$TMPX"; continue; } ;;
      *) rm -rf "$TMPX"; continue ;;
    esac
    find "$TMPX" -type f -print > "$TMPX.list" 2>/dev/null
    SRC_TOTAL=0; ATT_MATCH=0; ATT_DIFF=(); ATT_MISS=()
    while IFS= read -r s; do
      [ -f "$s" ] || continue
      SRC_TOTAL=$((SRC_TOTAL + 1))
      rel=${s#src/}
      base=${rel##*/}
      cand=""
      if [ -f "$TMPX/$rel" ]; then
        cand="$TMPX/$rel"
      else
        # 压缩包常带一层根目录，按 basename 找；同名多个时放弃，留给人判断。
        cand=$(awk -v b="$base" 'BEGIN{FS="/"} $NF==b { if (f) { m=1 } else f=$0 } END { if (f && !m) print f }' "$TMPX.list" 2>/dev/null)
      fi
      if [ -z "$cand" ]; then
        ATT_MISS+=("$rel")
        continue
      fi
      ATT_MATCH=$((ATT_MATCH + 1))
      [ "$(sha_of "$s")" = "$(sha_of "$cand")" ] || ATT_DIFF+=("$rel")
    done < <(find src -type f -print 2>/dev/null)
    rm -f "$TMPX.list"
    if [ "$ATT_MATCH" -gt 0 ]; then
      if [ ${#ATT_DIFF[@]} -gt 0 ]; then
        partial "附件压缩包 $(basename "$archive") 里有 ${#ATT_DIFF[@]} 个文件和 src 不一致（改了源码忘了重打包？）：$(printf '%s ' "${ATT_DIFF[@]:0:5}")"
      fi
      if [ ${#ATT_MISS[@]} -gt 0 ] && [ $((ATT_MATCH * 100 / SRC_TOTAL)) -ge 50 ]; then
        partial "src 里有 ${#ATT_MISS[@]} 个文件没进附件压缩包 $(basename "$archive")（同名覆盖 $((ATT_MATCH * 100 / SRC_TOTAL))%）：$(printf '%s ' "${ATT_MISS[@]:0:5}")"
      fi
    fi
    rm -rf "$TMPX"
  done < <(find 附件 -type f \( -name '*.zip' -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \) -print 2>/dev/null)
fi

# ---------- 启动脚本的静态检查
if [ -f start.sh ]; then
  if grep -q $'\r' start.sh; then
    fail "start.sh 是 CRLF 换行，容器里会报 bad interpreter，转成 LF 后再验证"; finish
  fi
  head -n1 start.sh | grep -q '^#!' || { fail "start.sh 第一行没有 #!，平台执行 /start.sh 会报 exec format error"; finish; }
  [ -x start.sh ] || hint "本机的 start.sh 没有执行位。镜像里由 Dockerfile 的 chmod 决定，确认 Dockerfile 里有 chmod 555"
  # 主服务要成为容器里能跟着退出的那个进程：单服务 exec，多服务后台起主服务再 wait。
  # 两样都没有时，start.sh 多半是起完服务就结束了，容器会被判成"已退出"或靠 tail -f 假保活。
  if ! grep -vE '^[[:space:]]*#' start.sh | grep -qE '(^|[[:space:]])(exec|wait)([[:space:]]|$)'; then
    partial "start.sh 里既没有 exec 也没有 wait，确认主服务是怎么前台运行、退出时容器跟着退出的"
  fi
  # 平台注入脚本会自己写 flag，start.sh 再写一遍会打架：要么把平台写的值覆盖掉，
  # 要么在反序执行时把占位值写死。真实交付里 10 道题踩了这条。
  # 先剥掉行内注释再查，避免把注释里引用的平台命令、日志里的 /root/flag 当覆盖。
  # 只认重定向（> / >>）紧跟 flag 路径，或 chmod 紧跟 flag 路径。
  FLAG_WRITE_LINES=$(sed 's/[[:space:]]*#.*$//' start.sh \
    | grep -nE '(>|>>)[[:space:]]*/?[^[:space:]]*flag|chmod[[:space:]]+[0-7]+[[:space:]]+/?[^[:space:]]*flag' \
    2>/dev/null | head -3)
  if [ -n "$FLAG_WRITE_LINES" ]; then
    hint "start.sh 里在写或改 flag 文件：${FLAG_WRITE_LINES//$'\n'/; }。平台注入的脚本自己会写 Flag，start.sh 再写一遍会覆盖或写死占位值。只有「平台用环境变量传 Flag」和「题目按原设计生成静态 Flag」两个例外，其余删掉"
  fi
  # 只为四叶草平台出的题不需要环境变量兼容段，照抄模板会把别的平台的合同带进交付物。
  if grep -qE 'GZCTF_FLAG|DASFLAG' start.sh; then
    stage hygiene partial
    partial "start.sh 里有 GZCTF_FLAG / DASFLAG 兼容段。只为四叶草平台出的题不需要加，确认这道题真的要在那些平台跑，否则删掉"
  fi
fi

# ---------- 敏感数据扫描：客户 PII 和生产凭据不能随交付物发出去
# 真实事故：企业备案题带着 8 万条真实企业 PII（企业名、证件号、手机号、邮箱），
# 配置文件注释里还有生产库地址和口令。题目发出去等于把客户数据发出了。
# 只报警告不改结论——正常题目也会有邮箱、内网地址，需要人判断。
if [ -d src ] || [ -d 附件 ] || [ -d 题目附件 ]; then
  PII_HITS=$(grep -rInE \
    --include='*.sql' --include='*.csv' --include='*.json' --include='*.properties' \
    --include='*.yml' --include='*.yaml' --include='*.conf' --include='*.php' \
    --include='*.py' --include='*.java' --include='*.js' --include='*.env' \
    --include='*.xml' --include='*.txt' --include='*.html' --include='*.log' \
    --include='*.ini' --include='*.sh' --include='*.jsp' --include='*.cfg' \
    -e '密码[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{4,}["'"'"']' \
    -e 'password[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{4,}["'"'"']' \
    -e 'passwd[[:space:]]*[:=][[:space:]]*["'][^"']{4,}["']' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
    src 附件 题目附件 2>/dev/null \
    | grep -viE 'placeholder|example|your_|changeme|<.*>|\$\{|\{[a-zA-Z_]|FLAG|flag\{|FLAG_|test|demo|dummy|123456|password2|密码框|_USERNAME|_PASSWORD|_USER|_PASS|username=|password=|HIS_' \
    | head -5)
  if [ -n "$PII_HITS" ]; then
    hint "src/ 或 附件/ 里疑似有生产凭据或密钥，交付前逐条确认（都是发给选手的）：
$(printf '%s\n' "$PII_HITS" | sed 's/^/     /')"
  fi
  # src/ 和 附件/ 里的 flag 形态字符串：出题人的测试残留会随镜像发给选手。
  # 真实事故：src/cache/trace.json 带真 flag 进了镜像；附件 test.py 明文写着真 flag。
  # 排掉明显的占位/提示串（FLAG_NOT_WRITTEN、PLACEHOLDER、TODO 等），只报像真值的。
  # 只看"去掉占位词之后还剩不剩"，占位词一大堆的整串不算。
  # 只认 flag/ctf/dasflag 前缀。之前用「任意 token + {」会把内联 CSS（body{…}）、
  # f-string 拼 HTML（n{item}）、SQL 里的 JSON（{"inputType":…}）全当成 flag，516 个纯噪声文件。
  FLAG_RESIDUE=""
  for f in $(grep -rIlE '(^|[^.A-Za-z0-9_#-])(flag|ctf|dasflag)[A-Za-z0-9_-]*\{[^}]{8,}\}' src 附件 题目附件 2>/dev/null | grep -v '\.md$' | head -40); do
    [ -n "$(grep -oiE '(^|[^.A-Za-z0-9_#-])(flag|ctf|dasflag)[A-Za-z0-9_-]*\{[^}]{8,}\}' "$f" 2>/dev/null \
      | grep -viE 'placeholder|not_written|not-written|change_?me|your_|example|dummy|fake|todo|xxxx|flag_placeholder')" ] \
      && FLAG_RESIDUE="$FLAG_RESIDUE $f"
  done
  FLAG_RESIDUE=$(printf '%s' "$FLAG_RESIDUE" | tr ' ' '\n' | grep -v '^$' | head -5 | tr '\n' ' ')
  if [ -n "$FLAG_RESIDUE" ]; then
    if [ -f Dockerfile ]; then
      # 容器题：src/ 会进镜像，真 flag 跟着发给选手。
      hint "这些文件里有 flag 形态的字符串：$(printf '%s ' $FLAG_RESIDUE)。确认是占位值不是测试残留——容器题里真 flag 随镜像发给选手，题目就白给了"
    else
      # 附件题：src/ 不发给选手（附件题只发 附件/），src 里留测试残留不泄题，
      # 但要确认 附件/ 里没有。
      hint "这些文件里有 flag 形态的字符串：$(printf '%s ' $FLAG_RESIDUE)。附件题里 src/ 不发给选手，不影响；但 附件/ 里出现的话就是泄题"
    fi
  fi

  # 真实 PII：证件号、手机号密度高的数据文件。单条不算，文件里成批出现才报。
  PII_BULK=$(grep -rIlE '1[3-9][0-9]{9}' --include='*.sql' --include='*.csv' --include='*.json' \
    --include='*.xml' --include='*.txt' --include='*.log' --include='*.xlsx' \
    src 附件 题目附件 2>/dev/null | head -3)
  if [ -n "$PII_BULK" ]; then
    hint "这些文件里成批出现手机号形态的数据，确认不是真实客户 PII：$(printf '%s ' $PII_BULK)。真实 PII 必须换成合成数据，并在 provenance 记一笔"
  fi
fi

# ---------- RDG 判定方式：有 check/check.sh 或 challenge.yaml 里 check.enabled，走 check 判定
RDG=0
[ "$FORCE_RDG" = 1 ] && RDG=1
if [ -z "$CHECK" ] && [ -n "$YAML_CHECK_PATH" ] && [ -f "$YAML_CHECK_PATH" ]; then CHECK="./${YAML_CHECK_PATH#./}"; fi
if [ -z "$CHECK" ] && [ -f "${PROJECT}/check/check.sh" ]; then CHECK="./check/check.sh"; fi
[ -n "$CHECK" ] && RDG=1

# ---------- 解题命令
[ -n "$SOLVE" ] || { [ -f solve/solve.py ] && SOLVE="python3 solve/solve.py"; }
# 本机装了某个库所以 verify passed、换到评测机 ImportError。逐个验证 solve.py 里 import 的模块。
# 三种情况不算问题，必须排除，否则误报率很高：
#   1. solve/ 目录下的本地模块（from helper import ...）
#   2. try/except ImportError 包住的可选依赖（z3 之类只是加速路径）
#   3. 文件头已经注明 pip install 的
# 而且这条只提示，不判 failed——依赖能不能装上是评测环境的事，本地判不了。
if [ -f solve/solve.py ] && command -v python3 >/dev/null 2>&1; then
  MISSING_MODS=$(python3 -B - solve/solve.py <<'PYDEP' 2>/dev/null
import ast, importlib.util, os, sys

STD = set(sys.stdlib_module_names) if hasattr(sys, "stdlib_module_names") else set()
path = sys.argv[1]
local_dir = os.path.dirname(os.path.abspath(path))
local = {os.path.splitext(f)[0] for f in os.listdir(local_dir) if f.endswith(".py")}
try:
    tree = ast.parse(open(path, encoding="utf-8", errors="replace").read())
except Exception:
    sys.exit(0)

# try/except ImportError 包住的是可选依赖（z3 之类只当加速路径），不算缺失。
optional = set()
for node in ast.walk(tree):
    if not isinstance(node, ast.Try):
        continue
    body_mods = set()
    for sub in ast.walk(node):
        if isinstance(sub, ast.Import):
            for a in sub.names:
                body_mods.add(a.name.split(".")[0])
        elif isinstance(sub, ast.ImportFrom) and sub.level == 0 and sub.module:
            body_mods.add(sub.module.split(".")[0])
    handled = any(
        (getattr(h.type, "id", None) or getattr(h.type, "attr", None)) in ("ImportError", "ModuleNotFoundError")
        for h in node.handlers if h.type is not None
    )
    if body_mods and handled:
        optional |= body_mods

mods = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for a in node.names:
            mods.add(a.name.split(".")[0])
    elif isinstance(node, ast.ImportFrom):
        if node.level == 0 and node.module:
            mods.add(node.module.split(".")[0])

missing = []
for m in sorted(mods):
    if m in STD or m.startswith("_") or m in local or m in optional:
        continue
    try:
        if importlib.util.find_spec(m) is None:
            missing.append(m)
    except (ImportError, ValueError):
        missing.append(m)
print(" ".join(missing))
PYDEP
)
  if [ -n "$MISSING_MODS" ]; then
    if grep -q 'pip install' solve/solve.py; then
      hint "solve/solve.py 依赖的模块本机没装：${MISSING_MODS}。文件里注明了 pip install，确认评测环境会装即可"
    else
      hint "solve/solve.py 依赖的模块在本机导不进来：${MISSING_MODS}。如果它不是标准库也不是本地模块，文件开头写清 pip install 命令，并确认评测环境会装"
    fi
  fi
fi

# 递归杀整棵进程树。只 kill 子 shell 的话，真正的解题进程会被 init 收养继续跑。
# 必须是顶层函数：run_solve 超时分支和负向对照都会用它，函数体内的定义在正常路径下不会生效。
_killtree() {
  local pid=$1 sig=$2 child
  for child in $(pgrep -P "$pid" 2>/dev/null); do _killtree "$child" "$sig"; done
  kill -"$sig" "$pid" 2>/dev/null
}

# 跑一次解题命令，带超时。结果写进 SOLVE_SRC，超时时置 SOLVE_TIMED_OUT=1。
FIRST_HOSTPORT=""; SOLVE_ENV=(); SOLVE_SRC=0; SOLVE_TIMED_OUT=0
run_solve() {
  # 超时后杀整棵进程树。只 kill 子 shell 的话，真正的解题进程会被 init 收养
  # 继续跑（PPID=1），批量验证时堆一堆孤儿把机器拖垮。
  # setsid 只在有它的系统上用（macOS 没有），有就顺便让它自成进程组。
  if command -v setsid >/dev/null 2>&1; then
    ( cd "$PROJECT" && exec setsid env HOST=127.0.0.1 PORT="$FIRST_HOSTPORT" \
        "${SOLVE_ENV[@]+"${SOLVE_ENV[@]}"}" sh -c "$SOLVE" ) >"$SOLVELOG" 2>&1 &
  else
    ( cd "$PROJECT" && env HOST=127.0.0.1 PORT="$FIRST_HOSTPORT" \
        "${SOLVE_ENV[@]+"${SOLVE_ENV[@]}"}" sh -c "$SOLVE" ) >"$SOLVELOG" 2>&1 &
  fi
  local spid=$! t0
  t0=$(date +%s)
  while kill -0 "$spid" 2>/dev/null && [ $(( $(date +%s) - t0 )) -lt "$SOLVE_TIMEOUT" ]; do sleep 1; done
  if kill -0 "$spid" 2>/dev/null; then
    _killtree "$spid" TERM
    sleep 2
    _killtree "$spid" KILL
    wait "$spid" 2>/dev/null
    # 记录一个哨兵：超时后如果还能 pgrep 到刚才那条解题命令，说明没收干净。
    SOLVE_SRC=124; SOLVE_TIMED_OUT=1
  else
    wait "$spid" 2>/dev/null; SOLVE_SRC=$?
    SOLVE_TIMED_OUT=0
  fi
}

# 写完 Flag 后解题。同步循环、重启应用、QEMU guest 读 Flag 都要几秒才生效，
# 拿不到就再等再解，最多三轮共等 15 秒。SOLVE_GOT 取 want / old / none。
solve_until() { # $1 = 要拿到的 Flag，$2 = 上一个 Flag（复查时用来判断是不是缓存）
  local w
  SOLVE_GOT=none
  for w in 2 5 8; do
    sleep "$w"; run_solve
    if grep -qF "$1" "$SOLVELOG"; then SOLVE_GOT=want; return; fi
    [ -n "${2:-}" ] && grep -qF "$2" "$SOLVELOG" && SOLVE_GOT=old
    # 超时说明脚本本身卡住了，再等也没用。
    [ "$SOLVE_TIMED_OUT" = 1 ] && return
  done
}

# ---------- 构建前的静态检查：这些问题会让容器起不来，提前说清楚比翻日志快
if [ ! -f Dockerfile ]; then
  # 附件题：没有容器，只检查交付结构和解题脚本。
  ATT_DIR=""
  [ -d "${PROJECT}/附件" ] && ATT_DIR="${PROJECT}/附件"
  [ -z "$ATT_DIR" ] && [ -d "${PROJECT}/题目附件" ] && ATT_DIR="${PROJECT}/题目附件"
  if [ -f "${PROJECT}/solve/solve.py" ] || [ -n "$ATT_DIR" ]; then
    echo "== 附件题（没有 Dockerfile，跳过容器验证）"
    if [ -z "$ATT_DIR" ]; then
      stage attachments partial
      partial "没有 附件/ 或 题目附件/ 目录，确认选手该拿到哪些文件"
    elif [ -z "$(ls -A "$ATT_DIR" 2>/dev/null)" ]; then
      stage attachments partial
      partial "$(basename "$ATT_DIR")/ 是空的，确认选手该拿到哪些文件"
    else
      ATT_COUNT=$(ls -A "$ATT_DIR" 2>/dev/null | wc -l | tr -d ' ')
      echo "   附件 ${ATT_COUNT} 个"
      for a in "$ATT_DIR"/*; do echo "   - $(basename "$a")"; done
      stage attachments passed
    fi
    # 附件题也要用解题脚本确认题目真的能解，否则只证明目录结构像附件题。
    if [ -n "$SOLVE" ]; then
      echo "== 运行解题命令: $SOLVE"
      run_solve
      if [ "$SOLVE_TIMED_OUT" = 1 ]; then
        tail -15 "$SOLVELOG" | sed 's/^/   | /'
        stage solve failed; fail "解题命令超过 ${SOLVE_TIMEOUT} 秒没结束，被终止。确实要跑这么久就用 --solve-timeout 调大"
      elif [ "$SOLVE_SRC" != 0 ]; then
        tail -15 "$SOLVELOG" | sed 's/^/   | /'
        stage solve failed; fail "解题命令返回 ${SOLVE_SRC}"
      else
        # 题目可能先打印诱饵旗、后打印真旗，取第一个会对不上。输出里任一匹配等于 expect 就算过。
        SOLVED=""
        while IFS= read -r _cand; do
          [ -n "$_cand" ] || continue
          if [ -n "$EXPECT_FLAG" ] && [ "$_cand" = "$EXPECT_FLAG" ]; then SOLVED="$_cand"; break; fi
          [ -n "$SOLVED" ] || SOLVED="$_cand"
        done < <(grep -oE '[A-Za-z0-9_]+\{[^}]{4,}\}' "$SOLVELOG")
        if [ -z "$SOLVED" ]; then
          tail -15 "$SOLVELOG" | sed 's/^/   | /'
          stage solve failed; fail "解题命令的输出里没有 Flag"
        elif [ -n "$EXPECT_FLAG" ] && [ "$SOLVED" != "$EXPECT_FLAG" ]; then
          # 附件题没有测试 Flag，只有这个断言能拦住"解出来的值不对"。
          # 少认一个字符、下划线认成数字，都会在这里暴露。
          echo "   解出 ${SOLVED}"
          stage solve failed
          fail "solve 解出的 Flag 与 --expect-flag 不一致：期望 ${EXPECT_FLAG}，实际 ${SOLVED}"
        elif [ -z "$EXPECT_FLAG" ]; then
          echo "   解出 ${SOLVED}"
          stage solve passed
          hint "附件题没有测试 Flag，脚本只确认输出里有 flag 形态的字符串。用 --expect-flag '<手册 1.5 里的值>' 再跑一次，确认解出来的值真的是那个"
        else
          echo "   解出 ${SOLVED}（与 --expect-flag 一致）"
          stage solve passed
        fi
      fi
    else
      stage solve missing
      hint "没有 solve/solve.py，只整理了附件，没有验证题目可解"
    fi
    finish
  fi
  fail "没有 Dockerfile，也不是附件题（没有 附件/ 和 solve/solve.py）"; finish
fi
# COPY . 会把 solve/、README/、附件/、镜像/ 一起打进镜像，路径也会变，直接拦下来。
# COPY --from=builder . /app/ 拷的是构建阶段产物，不是构建上下文，不会把 solve/README/ 打进镜像。
# COPY . 会把 solve/、README/、附件/ 打进镜像。多阶段构建的 COPY --from=builder . 是合法的，
# 要行级排除，不能因为文件里有一行 --from= 就放行整份文件的 COPY .。
COPYDOT=$(grep -iE '^[[:space:]]*(COPY|ADD)[[:space:]]+(--[^[:space:]]+[[:space:]]+)*\./?[[:space:]]' Dockerfile \
  | grep -viE -e '--from=' | head -1)
if [ -n "$COPYDOT" ]; then
  fail "Dockerfile 用了 COPY . ，会把 solve/、README/、附件/ 打进镜像，并且改变目录结构，改成 COPY 具体路径"; finish
fi

# YAML 语法错误必须在构建前拦住：平台的解析器读这个文件，读不出来题目就上不了。
if [ -n "$YAML_ERROR" ]; then
  fail "challenge.yaml 解析失败：${YAML_ERROR}。平台的解析器同样会读不出来，先修 YAML 语法"
  finish
fi

YAML=challenge.yaml
if [ ${#PORTS[@]} -eq 0 ] && [ -f "$YAML" ]; then
  if [ -n "$YAML_PORTS" ]; then
    for p in $(printf '%s' "$YAML_PORTS" | tr ',' '\n' | grep -oE '[0-9]+'); do PORTS+=("$p"); done
  else
    # 没有 PyYAML 时退回文本解析，兼容 expose_ports: ["80", "22"] 和逐行 - "80" 两种写法。
    for p in $(awk '
      /^[[:space:]]*expose_ports:/ { s=$0; sub(/.*expose_ports:/, "", s); if (s ~ /\[/) { print s; exit } blk=1; next }
      blk { if ($0 ~ /^[[:space:]]*-/) print; else if ($0 !~ /^[[:space:]]*$/) exit }
    ' "$YAML" | grep -oE '[0-9]+'); do PORTS+=("$p"); done
  fi
fi
if [ ${#PORTS[@]} -eq 0 ]; then
  for p in $(grep -iE '^[[:space:]]*EXPOSE[[:space:]]' Dockerfile | grep -oE '[0-9]+'); do PORTS+=("$p"); done
fi
if [ -z "$FLAGPATH" ]; then
  if [ -n "$YAML_FLAGPATH" ]; then
    FLAGPATH="$YAML_FLAGPATH"
  elif [ -f "$YAML" ]; then
    # 只在 flag: 块里找 path，避免拿到 verification 等其他块的 path。
    FLAGPATH=$(awk '
      /^[[:space:]]*flag:[[:space:]]*$/ { inb=1; ind=match($0, /[^ ]/); next }
      inb && $0 !~ /^[[:space:]]*$/ {
        if (match($0, /[^ ]/) <= ind) exit
        if ($0 ~ /^[[:space:]]*path:/) { sub(/^[[:space:]]*path:[[:space:]]*/, ""); sub(/[[:space:]]+#.*/, ""); gsub(/["'\'']/, ""); print; exit }
      }' "$YAML")
  fi
fi
[ -n "$FLAGPATH" ] || FLAGPATH=/flag

# HTTP 探测路径：根路径返回 403/404 不代表服务有问题，题目可以用
# verification.solve_probe.path 指定真实入口。
PROBE_PATH=/
if [ -n "$YAML_PROBE" ]; then
  PROBE_PATH="$YAML_PROBE"
elif [ -f "$YAML" ]; then
  CASE_PATH=$(awk '
    /^[[:space:]]*solve_probe:[[:space:]]*$/ { inb=1; next }
    inb && /^[[:space:]]*[a-zA-Z_]+:[[:space:]]*$/ { inb=0 }
    inb && /^[[:space:]]*path:[[:space:]]*[^[:space:]]/ {
      sub(/^[[:space:]]*path:[[:space:]]*/, ""); sub(/[[:space:]]+#.*/, "")
      gsub(/["'"'"']/, ""); print; exit
    }' "$YAML")
  [ -n "$CASE_PATH" ] && PROBE_PATH="$CASE_PATH"
fi
case "$PROBE_PATH" in /*) ;; *) PROBE_PATH="/$PROBE_PATH";; esac

# 镜像名只允许小写字母数字，中文目录名或 "." 直接拿来当 tag 会让 docker build 报错。
# 按字节替换：UTF-8 locale 下部分 sed 会把中文留在结果里，docker 报 invalid reference format。
SLUG=$(basename "$PROJECT" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
SUFFIX=$(printf '%s' "$PROJECT" | cksum | cut -d' ' -f1)
# 本机架构与目标架构不一致时，走的是模拟运行，解题阶段要区分题目失败和环境失败。
case "$PLATFORM" in
  *arm64*|*aarch64*) PLATFORM_ARCH=arm64;;
  *) PLATFORM_ARCH=amd64;;
esac
case "$(docker info --format '{{.Architecture}}' 2>/dev/null)" in
  x86_64|amd64) HOST_ARCH=amd64;;
  aarch64|arm64) HOST_ARCH=arm64;;
  *) HOST_ARCH="";;
esac
if [ -n "$HOST_ARCH" ] && [ "$PLATFORM_ARCH" != "$HOST_ARCH" ]; then HOST_IS_EMULATED=1; else HOST_IS_EMULATED=0; fi

IMAGE="ctf-verify-${SLUG:-challenge}-${SUFFIX}:test"
CONTAINER="ctf-verify-$$"

show_logs() { echo "   ---- docker logs 最后 30 行"; docker logs "$CONTAINER" 2>&1 | tail -30 | sed 's/^/   | /'; }

# ---------- 构建
echo "== 构建镜像 ($PLATFORM)"
T0=$(date +%s)
# 手册 1.7 让用户写的是 docker buildx build，这里跟着用同一条链路，免得本地验证和手册里的构建
# 走的不是同一套构建器。只有经典构建器时退回 docker build。
BUILD_CMD=(docker build)
if docker buildx version >/dev/null 2>&1; then
  BUILD_CMD=(docker buildx build --load)
fi
[ "$NO_CACHE" = 1 ] && BUILD_CMD+=(--no-cache)
if ! "${BUILD_CMD[@]}" --platform "$PLATFORM" -t "$IMAGE" . >"$BUILDLOG" 2>&1; then
  echo "   ---- 构建日志最后 40 行"; tail -40 "$BUILDLOG" | sed 's/^/   | /'
  stage build failed; fail "docker build 失败"; finish
fi
echo "   完成，用时 $(( $(date +%s) - T0 )) 秒"
stage build passed

# 官方 php/nginx/node 镜像的 docker-*entrypoint 会把参数原样 exec，不影响 /start.sh；其他 ENTRYPOINT 会吞掉它。
ENTRY=$(docker image inspect -f '{{json .Config.Entrypoint}}' "$IMAGE" 2>/dev/null)
case "$ENTRY" in null|\[\]|""|*docker-*entrypoint*) ;; *) partial "镜像设置了 ENTRYPOINT ${ENTRY}，平台传入的 /start.sh 会变成它的参数，确认它最后会执行 /start.sh";; esac

# ---------- 启动：和平台一样以 /start.sh 为命令；端口只绑本机，漏洞服务不暴露到局域网
echo "== 启动容器"
RUN_ARGS=(-d --name "$CONTAINER" --platform "$PLATFORM")
for p in "${PORTS[@]+"${PORTS[@]}"}"; do RUN_ARGS+=(-p "127.0.0.1::$p"); done
# 需要 KVM、NET_ADMIN 这类能力的题，默认参数盖不到真实链路，用 --run-arg 补。
for a in "${RUN_ARGS_EXTRA[@]+"${RUN_ARGS_EXTRA[@]}"}"; do RUN_ARGS+=("$a"); done
if ! docker run "${RUN_ARGS[@]}" "$IMAGE" /start.sh >/dev/null 2>"$BUILDLOG"; then
  sed 's/^/   | /' "$BUILDLOG"; stage startup failed; fail "容器启动失败"; finish
fi
stage startup passed

# 读容器内的 /proc/net/tcp 判断真实监听。Docker Desktop 的端口转发在服务没起来时也会接受连接，
# 只从宿主机探测会误判成"已连通"。
listen_state() { # 输出 any / loopback / none
  local want=$1 table addr port state=none
  table=$(docker exec "$CONTAINER" sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null' 2>/dev/null) || { echo unknown; return; }
  [ -n "$table" ] || { echo unknown; return; }
  for addr in $(printf '%s\n' "$table" | awk '$4=="0A" {print $2}'); do
    port=$(( 16#${addr##*:} ))
    [ "$port" = "$want" ] || continue
    case "${addr%%:*}" in
      0100007F|00000000000000000000000001000000) [ "$state" = none ] && state=loopback;;
      *) state=any;;
    esac
  done
  echo "$state"
}

running() { [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = true ]; }

if [ ${#PORTS[@]} -gt 0 ]; then
  echo "   等待端口 ${PORTS[*]} 开始监听（最多 ${START_TIMEOUT} 秒）"
  T0=$(date +%s)
  while :; do
    running || break
    ALL=1
    for p in "${PORTS[@]}"; do [ "$(listen_state "$p")" = any ] || ALL=0; done
    [ "$ALL" = 1 ] && break
    [ $(( $(date +%s) - T0 )) -ge "$START_TIMEOUT" ] && break
    sleep 1
  done
else
  sleep 3
fi
if ! running; then
  show_logs; stage startup failed; fail "容器已退出，start.sh 需要在前台运行真实服务"; finish
fi
echo "   容器运行中"

PID1=$(docker exec "$CONTAINER" sh -c 'tr "\0" " " </proc/1/cmdline' 2>/dev/null)
case "$PID1" in *start.sh*) hint "PID 1 是 start.sh（${PID1}），确认主服务退出时 start.sh 也会退出，否则平台发现不了题目挂掉";; esac

# ---------- 写入测试 Flag：先用 root 确认目标可写，再按镜像 USER 模拟平台
# 用 -u 0 写只能证明目标文件本身可写，不能证明平台写得进去——平台 exec_run 不传 user，
# 继承镜像的 USER。下面还会按镜像 USER 再写一次。
# 两边都缺才算没有合同：challenge.yaml 没声明 flag.path，镜像里也没有占位 Flag。
# 只有一边缺时照常跑——缺的那边多半是别的问题，不该在这里当成"没有 Flag 合同"放过去。
HAS_PLACEHOLDER=0
if [ -f flag ] || grep -qiE '^[[:space:]]*(COPY|ADD).*flag([[:space:]]|$)' Dockerfile; then
  HAS_PLACEHOLDER=1
fi
HAS_DECLARED=0
if [ -f "$YAML" ] && { [ -n "$YAML_FLAGPATH" ] || grep -qE '^[[:space:]]*flag:' "$YAML"; }; then
  HAS_DECLARED=1
fi
NO_FLAG_CONTRACT=0
[ "$HAS_PLACEHOLDER" = 1 ] || [ "$HAS_DECLARED" = 1 ] || NO_FLAG_CONTRACT=1

# 静态 Flag 题：平台不写 Flag，只比对选手提交的字符串，写 Flag 这一步没有意义。
# STATIC_FLAG 已在手册检查之前赋值。

TESTFLAG="flag{verify_$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')}"
TESTFLAG2="flag{rotate_$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')}"
# 平台写 Flag 用的是容器内默认用户（exec_run 不传 user，继承镜像的 USER）。
# 而题目程序可能在 Dockerfile 里写了 USER 1000:1000，这时平台照样以 1000 身份去写，
# 目标文件属主是 root 就写不进去。所以这里分两次：
#   -u 0 是给"确认写入链路本身通不通"用的；
#   默认用户那次是真实模拟平台，这才是判据。
write_flag() { # $1 = 要写入的值
  docker exec -u 0 "$CONTAINER" sh -c 'printf "%s\n" "$1" > "$2"' sh "$1" "$FLAGPATH" 2>/dev/null
}
write_flag_as_platform() { # $1 = 要写入的值；不传 -u，继承镜像 USER
  docker exec "$CONTAINER" sh -c 'printf "%s\n" "$1" > "$2"' sh "$1" "$FLAGPATH" 2>/dev/null
}
# 镜像里有没有显式 USER（没有时 exec 就是 root，两次写入等价，不用额外测）
IMAGE_USER=$(docker image inspect -f '{{.Config.User}}' "$IMAGE" 2>/dev/null)
# 解题输出里必须出现的值。平台写 Flag 的题是随机测试 Flag；静态 Flag 题是镜像里那个值。
WANT_FLAG="$TESTFLAG"
if [ "$STATIC_FLAG" = 1 ]; then
  echo "== 跳过 Flag 写入（flag.mode=static，平台不写 Flag，只比对选手提交的字符串）"
  stage flag_write skipped
  if [ -n "$EXPECT_FLAG" ]; then
    WANT_FLAG="$EXPECT_FLAG"
  else
    WANT_FLAG=$(docker exec -u 0 "$CONTAINER" cat "$FLAGPATH" 2>/dev/null | tr -d '\r\n')
    [ -n "$WANT_FLAG" ] && echo "   镜像里的静态 Flag：${WANT_FLAG}"
  fi
elif [ "$RDG" = 1 ] && [ "$NO_FLAG_CONTRACT" = 1 ]; then
  # 有些 RDG 题的判据是题目自己配置里的固定目标，本来就没有 Flag 合同，不算缺项。
  echo "== 跳过 Flag 写入（RDG 题没有 Flag 合同，判据由 check 脚本给出）"
  stage flag_write skipped
else
  [ -n "$EXPECT_FLAG" ] && hint "--expect-flag 只对附件题和静态 Flag 题生效，平台写 Flag 的题用随机测试 Flag 校验"
  FLAG_SCRIPT_STATUS=""
  # 手册 1.5 贴了 flag_script 时，先按平台的方式真跑一遍：/bin/bash 执行、$new_flag 换成测试值。
  # 平台后台保存的就是这段脚本，只查「出现过 $new_flag」拦不住路径写错、变量名写错。
  if [ -n "$MANUAL_PATH" ] && [ -f "$MANUAL_PATH" ]; then
    FLAG_SCRIPT=$(section_code_block 1.5 "$MANUAL_PATH")
    if [ -n "$FLAG_SCRIPT" ]; then
      echo "== 执行手册 1.5 的 flag_script（容器内 /bin/bash，模拟平台注入）"
      FLAG_SCRIPT=$(printf '%s' "$FLAG_SCRIPT" \
        | sed -e "s|\${new_flag}|${TESTFLAG}|g" -e "s|\$new_flag|${TESTFLAG}|g")
      TMP_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/verify-changeflag.XXXXXX")
      printf '%s\n' "$FLAG_SCRIPT" > "$TMP_SCRIPT"
      if docker cp "$TMP_SCRIPT" "$CONTAINER:/tmp/verify_changeflag.sh" >/dev/null 2>&1 \
         && run_flag_script; then
        BACK=$(docker exec -u 0 "$CONTAINER" cat "$FLAGPATH" 2>/dev/null | tr -d '\r\n')
        if [ "$BACK" = "$TESTFLAG" ]; then
          echo "   脚本执行成功，回读一致"
          FLAG_SCRIPT_STATUS=passed
        else
          stage flag_write partial
          partial "手册 1.5 的 flag_script 执行完了，但 ${FLAGPATH} 里不是注入值（回读：${BACK:-空}）。脚本写的路径和 flag.path 对不上，平台上线后选手拿到的是占位值"
          FLAG_SCRIPT_STATUS=fix
        fi
      else
        stage flag_write partial
        partial "手册 1.5 的 flag_script 在容器里跑不起来（/bin/bash 执行失败）。平台保存的就是这段脚本，写错题目上线后 Flag 写不进去；下面是回退到直接写入的结果"
        FLAG_SCRIPT_STATUS=fix
      fi
      rm -f "$TMP_SCRIPT"
    fi
  fi
  echo "== 写入测试 Flag 到 ${FLAGPATH}"
  if write_flag "$TESTFLAG"; then
    BACK=$(docker exec -u 0 "$CONTAINER" cat "$FLAGPATH" 2>/dev/null | tr -d '\r\n')
    MODE=$(docker exec -u 0 "$CONTAINER" stat -c '%a %U:%G' "$FLAGPATH" 2>/dev/null)
    if [ "$BACK" != "$TESTFLAG" ]; then
      stage flag_write failed; fail "Flag 写入后回读不一致"
    elif [ "$NO_FLAG_CONTRACT" = 1 ]; then
      stage flag_write partial
      partial "题目没有 Flag 合同：challenge.yaml 没有 flag.path，镜像里也没有占位 Flag 文件。平台能写进 ${FLAGPATH}，但程序未必读它，先补上读取逻辑"
    else
      echo "   回读一致（${MODE}）"
      stage flag_write passed
      # 脚本那一步失败过时，阶段结论保持 partial，别被这里的 passed 盖掉。
      [ "$FLAG_SCRIPT_STATUS" = fix ] && stage flag_write partial
      # 镜像里写了 USER 时，平台注入的那个 exec 会以那个身份执行，写 root 属主的
      # 目标文件会 Permission denied。用 -u 0 写是测不出来的，必须按平台身份再试一次。
      if [ -n "$IMAGE_USER" ]; then
        echo "== 按镜像 USER（${IMAGE_USER}）模拟平台写入"
        if write_flag_as_platform "$TESTFLAG"; then
          echo "   镜像默认用户能写入"
        else
          stage flag_write failed
          fail "镜像设了 USER ${IMAGE_USER}，平台注入脚本会以这个身份执行，写不进 ${FLAGPATH}（属主是 root 时必然失败）。改成目标文件属主随 USER，或去掉 Dockerfile 的 USER，或在 flag_script 里 sudo/chown。用 root 身份 docker exec 测是测不出来的"
        fi
      fi
    fi
  else
    stage flag_write failed
    fail "平台无法写入 ${FLAGPATH}（镜像里没有 sh，或目录不存在）"
  fi
fi

# ---------- 动态 Flag 的平台合同：镜像里必须有 /bin/bash
# 平台用 exec_run("/bin/bash /changeflag.sh") 注入 Flag（LingXu base_app/tasks.py:56），
# 不是 sh，也不是直接写文件。alpine / distroless / scratch 系镜像没有 /bin/bash，
# 注入静默失败，Flag 停在占位值，平台只在前端提示"环境启动异常"。
# 静态 Flag 题平台不写 Flag，不查这一项。
if [ "$STATIC_FLAG" = 0 ] && [ "$NO_FLAG_CONTRACT" = 0 ]; then
  if docker run --rm --platform "$PLATFORM" --entrypoint sh "$IMAGE" -c 'test -x /bin/bash' >/dev/null 2>&1; then
    echo "   动态 Flag 依赖：/bin/bash 存在"
    stage dynflag_bash passed
  else
    stage dynflag_bash failed
    fail "镜像里没有 /bin/bash。平台用 /bin/bash 执行注入的 changeflag.sh，缺它 Flag 写不进去，选手拿到的永远是占位值。alpine/slim/distroless 系镜像要显式装 bash（apk add --no-cache bash）；确实只能静态 Flag 的题在 challenge.yaml 写 flag.mode: static"
  fi
fi

# ---------- 端口探测
FIRST_HOSTPORT=""; SOLVE_ENV=(); PORTS_OK=1
for p in "${PORTS[@]+"${PORTS[@]}"}"; do
  HP=$(docker port "$CONTAINER" "$p/tcp" 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/')
  [ -n "$FIRST_HOSTPORT" ] || FIRST_HOSTPORT=$HP
  SOLVE_ENV+=("PORT_$p=$HP")
  echo "== 探测端口 ${p}（本机 127.0.0.1:${HP}）"
  case "$(listen_state "$p")" in
    loopback) PORTS_OK=0; fail "端口 $p 只监听 127.0.0.1，平台映射后访问不到，改成 0.0.0.0"; continue;;
    none)
      # 端口现在还没监听，不急着判死。有的题 start.sh 是「等平台写完 flag 再起服务」
      # （Skill 自己推荐的 Flag 同步等待模式），此时 flag 刚写完，服务可能马上要起。
      # 再等一小段，给这种题一个机会；还不起才判失败。
      PORTS_OK=0
      T0=$(date +%s)
      while :; do
        [ "$(listen_state "$p")" = any ] && { PORTS_OK=1; echo "   端口 $p 在写 flag 后开始监听"; break; }
        [ $(( $(date +%s) - T0 )) -ge 15 ] && break
        sleep 1
      done
      if [ "$PORTS_OK" = 0 ]; then
        # 出题人在 provenance.env_limited 里已经声明「本机跑不动」时（QEMU guest 起不来、
        # Apple Silicon TCG 嵌套模拟等），端口起不来是环境问题，不是题目问题。
        if [ -n "$YAML_ENV_LIMITED" ]; then
          envfail "端口 $p 没有开始监听，但 provenance.env_limited 已声明本机环境限制（${YAML_ENV_LIMITED}）。这是环境问题，换原生 amd64 重跑，不要当成题目 failed"
        else
          fail "端口 $p 在 ${START_TIMEOUT} 秒内没有开始监听"; show_logs
        fi
      fi
      continue;;
    unknown) hint "读不到容器内的监听表，端口 $p 只能从宿主机探测，TCP 结果可能不准";;
  esac
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${HP}${PROBE_PATH}" 2>/dev/null)
  [ "$PROBE_PATH" = / ] || echo "   探测路径 ${PROBE_PATH}"
  if [ -n "$CODE" ] && [ "$CODE" != 000 ]; then
    echo "   HTTP $CODE"
    [ "$CODE" -ge 500 ] && partial "端口 $p 返回 HTTP ${CODE}，服务可能有报错"
    # 选手第一屏：root 路径 404/403 且没配 probe_path 时，选手打开看到的是错误页。
    # 真实案例：nghttpx 题首页返回纯文本 NOT-FOUND，Agent 自陈"确实像糊弄"。
    if { [ "$CODE" = 404 ] || [ "$CODE" = 403 ]; } && [ "$PROBE_PATH" = / ]; then
      hint "端口 $p 的根路径返回 ${CODE}，选手打开就是错误页。有真实入口就在 challenge.yaml 的 verification.solve_probe.path 里指定，或把首页做成能说明这道题是什么的页面"
    elif [ "$CODE" = 200 ]; then
      # 200 但内容是一行 NOT-FOUND / OK / 错误 JSON，也是糊弄。
      FIRST=$(curl -s --max-time 5 "http://127.0.0.1:${HP}${PROBE_PATH}" 2>/dev/null | head -c 400 | tr -s '[:space:]' ' ')
      LOW=$(printf '%s' "$FIRST" | LC_ALL=C tr '[:upper:]' '[:lower:]')
      PLACEHOLDER=0
      case "$LOW" in *not-found*|*notfound*) PLACEHOLDER=1;; esac
      case "$LOW" in *'"error"'*|*'not implemented'*) PLACEHOLDER=1;; esac
      if [ "$PLACEHOLDER" = 1 ]; then
        hint "端口 $p 的首页返回的是占位内容（$(printf '%.60s' "$FIRST")）。选手打开第一屏必须能说明这道题是什么"
      fi
    fi
    # 页面引用外网 CDN：比赛内网没有外网时页面直接裸奔。
    if [ "$CODE" = 200 ]; then
      CDN=$(curl -s --max-time 5 "http://127.0.0.1:${HP}${PROBE_PATH}" 2>/dev/null \
        | grep -oE 'https?://(cdn\.jsdelivr\.net|unpkg\.com|fonts\.googleapis\.com|cdnjs\.cloudflare\.com|ajax\.googleapis\.com)[^"'"'"' >]*' \
        | head -3 | tr '\n' ' ')
      if [ -n "$CDN" ]; then
        hint "端口 $p 的页面引用了外网 CDN：${CDN}。比赛内网通常无外网，页面资源要全部打包进镜像"
      fi
    fi
  else
    BANNER=$(curl -s --max-time 3 "telnet://127.0.0.1:$HP" </dev/null 2>/dev/null | LC_ALL=C tr -cd '[:print:]\n' | grep -v '^$' | head -2)
    if [ -n "$BANNER" ]; then
      printf '%s\n' "$BANNER" | sed 's/^/   TCP 输出: /'
    else
      echo "   TCP 已监听，连接后没有输出"
    fi
  fi
done
[ ${#PORTS[@]} -gt 0 ] || partial "没有声明端口（challenge.yaml 的 expose_ports 或 Dockerfile 的 EXPOSE），跳过端口探测"
[ "$PORTS_OK" = 1 ] && [ ${#PORTS[@]} -gt 0 ] && stage port passed

# ---------- 就绪探针：端口监听 ≠ 服务可用
# QEMU 题最典型：QEMU 一启动就占住转发端口，但 guest 还没起来，verify 判"已就绪"，
# 然后 solve 的超时全被启动吃掉。用 --ready-cmd 给出"真的能用"的判据。
if [ -n "$READY_CMD" ] && [ -n "$FIRST_HOSTPORT" ]; then
  READY_CMD_EXPANDED=${READY_CMD//<PORT>/$FIRST_HOSTPORT}
  echo "== 等待服务就绪：${READY_CMD_EXPANDED}（最多 ${READY_TIMEOUT} 秒）"
  T0=$(date +%s); READY_OK=0
  while :; do
    running || break
    if sh -c "$READY_CMD_EXPANDED" >/dev/null 2>&1; then READY_OK=1; break; fi
    [ $(( $(date +%s) - T0 )) -ge "$READY_TIMEOUT" ] && break
    sleep 2
  done
  if [ "$READY_OK" = 1 ]; then
    echo "   服务就绪，用时 $(( $(date +%s) - T0 )) 秒"
    stage ready passed
  else
    stage ready failed
    fail "端口已经在监听，但 --ready-cmd 在 ${READY_TIMEOUT} 秒内没有返回 0。端口监听不等于服务可用（QEMU 题常见：QEMU 占着端口，guest 还没起完），确认就绪判据或加 --ready-timeout"
  fi
fi

# ---------- RDG 判定：跑一遍判题脚本，初始环境必须"有漏洞"才算题目状态正确
# 判据不是 Flag，而是"漏洞还在不在"，和普通题是两套逻辑。
if [ "$RDG" = 1 ]; then
  echo "== 运行 RDG 判题脚本: $CHECK"
  if [ -z "$CHECK" ]; then
    stage check_initial failed
    fail "按 RDG 判定但找不到判题脚本。写 check/check.sh，或用 --check 指定"
    finish
  fi
  # check.sh 没有执行位时，平台按 ./check.sh 调用会报 Permission denied，返回码非 0 会被当成
  # "有漏洞"——正好是 RDG 的预期结果，于是这个配置错误会被静默吞掉。先单独查出来。
  CHECKS_FOR_EXEC=$(printf '%s' "$CHECK" | sed 's/^\.\///' | awk '{print $1}')
  if [ -f "$CHECKS_FOR_EXEC" ] && [ ! -x "$CHECKS_FOR_EXEC" ]; then
    stage check_initial failed
    fail "check.sh 没有执行权限（${CHECKS_FOR_EXEC}）。平台按 ./check.sh 调用会报 Permission denied，加上执行位：chmod +x ${CHECKS_FOR_EXEC}"
    finish
  fi
  if [ -z "$FIRST_HOSTPORT" ]; then
    stage check_initial skipped
    partial "没有可用端口，跳过 RDG 判题"
  else
    ( cd "$PROJECT" && env TARGET_IP=127.0.0.1 TARGET_PORT="$FIRST_HOSTPORT" \
        "${SOLVE_ENV[@]+"${SOLVE_ENV[@]}"}" sh -c "$CHECK 127.0.0.1 $FIRST_HOSTPORT" ) >"$CHECKLOG" 2>&1
    CHECK_SRC=$?
    tail -40 "$CHECKLOG" | sed 's/^/   | /'
    # 返回非 0 不一定是"漏洞还在"：路径写错（127）、没有执行位（126）、check.py 缺依赖崩掉，
    # 返回码同样非 0。所以非 0 时还要看到契约里的判定行，才算初始环境有漏洞。
    VERDICT=$(grep -iE 'ok:[[:space:]]*(true|false)|RESULT:[[:space:]]*(PASS|FAIL)' "$CHECKLOG" | tail -1)
    if [ "$CHECK_SRC" = 126 ] || [ "$CHECK_SRC" = 127 ]; then
      stage check_initial failed
      fail "RDG 判题脚本没能执行（退出码 ${CHECK_SRC}）。check 路径写错、缺执行位或解释器不存在都会落到这里，修好再跑"
      finish
    elif [ "$CHECK_SRC" != 0 ] && ! printf '%s' "$VERDICT" | grep -qiE 'false|fail'; then
      stage check_initial failed
      fail "RDG 判题脚本返回 ${CHECK_SRC}，但输出里没有 ok: False 或 RESULT: FAIL 判定行。多半是脚本自己崩了（缺依赖、路径不对），不能当成漏洞还在"
      finish
    elif [ "$CHECK_SRC" = 0 ]; then
      stage check_initial "ok: True"
      fail "RDG 判题脚本在初始环境就报已修复（返回 0）。选手没得打，先确认题目初始状态和 check 判定是不是反了"
    else
      stage check_initial "ok: False"
      echo "   初始环境判定为「有漏洞」，符合 RDG 预期"
    fi
  fi

  # 有解题脚本时顺手跑一遍：check 只证明"漏洞还在"，solve.py 才证明"这条链真的打得通"。
  # 拿到刚写入的测试 Flag 才算通过；没解出只记提示，不当失败——RDG 的正式判据是 check。
  if [ -n "$SOLVE" ] && [ -n "$FIRST_HOSTPORT" ]; then
    echo "== 运行 RDG 解题脚本: $SOLVE"
    solve_until "$WANT_FLAG"
    [ "$SOLVE_TIMED_OUT" = 1 ] && hint "解题命令超过 ${SOLVE_TIMEOUT} 秒被终止"
    if [ "$SOLVE_GOT" = want ]; then
      echo "   漏洞链打通，拿到 Flag"
      stage solve passed
    else
      tail -10 "$SOLVELOG" | sed 's/^/   | /'
      stage solve "no flag"
      hint "RDG 解题脚本没有拿到 Flag，确认漏洞链是通的（check 只说明漏洞存在）"
    fi
  fi
  finish
fi

# ---------- 解题验证：拿到的是刚写入的测试 Flag，才说明程序按请求读取 Flag、没有缓存
if [ -z "$SOLVE" ]; then
  # 没有解题脚本时，"容器能跑"不等于"题目可解"，阶段回执里明确标出来。
  stage solve missing
  hint "没有 solve/solve.py，只验证了容器能跑，没有验证题目可解"
else
  echo "== 运行解题命令: $SOLVE"
  case "$SOLVE" in
    *solve.py*) grep -qE 'HOST|PORT|argparse|--host|--port' solve/solve.py 2>/dev/null \
      || hint "solve/solve.py 里没有读 HOST/PORT 的代码，确认它能接受目标地址";;
  esac
  if [ -z "$FIRST_HOSTPORT" ]; then
    partial "没有可用端口，跳过解题命令"
  elif [[ "$SOLVE" == python3* ]] && ! command -v python3 >/dev/null; then
    partial "本机没有 python3，跳过解题命令"
  elif [ -z "$WANT_FLAG" ]; then
    stage solve failed
    fail "静态 Flag 题读不到镜像里的 ${FLAGPATH}，确认 flag.path，或用 --expect-flag 指定要解出的值"
  else
    solve_until "$WANT_FLAG"
    if [ "$SOLVE_GOT" = want ]; then
      echo "   拿到 Flag"
      stage solve passed
      [ "$SOLVE_SRC" = 0 ] || hint "解题命令拿到了 Flag 但退出码是 ${SOLVE_SRC}，约定成功时返回 0"
      # 负向对照：指向一个确定关着的端口再解一次，必须失败。
      # 真实事故：solve 里有 docker exec 兜底、或写死了答案，正向永远通过，
      # 但平台链路上根本连不通——只有这一步能抓出来。
      DEAD_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null)
      if [ -n "$DEAD_PORT" ]; then
        # 正向跑时会展开 SOLVE_ENV（PORT_<容器端口>=...）。负向也要给这些变量，否则只读
        # PORT_8080 的 solve 会因缺变量直接退出、什么都不输出，负向对照就永远"通过"。
        DEAD_ENV=()
        for e in "${SOLVE_ENV[@]+"${SOLVE_ENV[@]}"}"; do
          case "$e" in PORT_*=*) DEAD_ENV+=("${e%%=*}=${DEAD_PORT}");; *) DEAD_ENV+=("$e");; esac
        done
        if command -v setsid >/dev/null 2>&1; then
          ( cd "$PROJECT" && exec setsid env HOST=127.0.0.1 PORT="$DEAD_PORT" \
              "${DEAD_ENV[@]+"${DEAD_ENV[@]}"}" sh -c "$SOLVE" ) >"$SOLVELOG.dead" 2>&1 &
        else
          ( cd "$PROJECT" && env HOST=127.0.0.1 PORT="$DEAD_PORT" \
              "${DEAD_ENV[@]+"${DEAD_ENV[@]}"}" sh -c "$SOLVE" ) >"$SOLVELOG.dead" 2>&1 &
        fi
        DEAD_PID=$!; DEAD_T0=$(date +%s)
        while kill -0 "$DEAD_PID" 2>/dev/null && [ $(( $(date +%s) - DEAD_T0 )) -lt 20 ]; do sleep 1; done
        _killtree "$DEAD_PID" TERM 2>/dev/null
        sleep 1
        _killtree "$DEAD_PID" KILL 2>/dev/null
        wait "$DEAD_PID" 2>/dev/null; DEAD_SRC=$?
        if grep -qF "$WANT_FLAG" "$SOLVELOG.dead" 2>/dev/null; then
          stage solve failed
          fail "solve 在指向一个关着的端口时仍然输出了 Flag（${WANT_FLAG}）。说明它没有走网络：要么有本地文件/docker exec 兜底，要么答案写死在脚本里。改成只能从服务端拿"
        elif [ "$DEAD_SRC" = 0 ]; then
          hint "solve 在目标端口关着时仍返回 0，确认它有正确报错（约定拿不到 Flag 要返回非 0）"
        fi
        rm -f "$SOLVELOG.dead"
      fi
      # 换一个 Flag 再解一次。启动时把 Flag 读进内存的题，第一次能过、第二次过不了，
      # 平台换了 Flag 也不会生效——只有这一步能发现。
      if [ "$FLAG_ROTATE" = 1 ] && [ "$STATIC_FLAG" = 0 ] && [ "$NO_FLAG_CONTRACT" = 0 ]; then
        echo "== 复查：写入第二个测试 Flag，再解一次"
        if write_flag "$TESTFLAG2"; then
          solve_until "$TESTFLAG2" "$TESTFLAG"
          case "$SOLVE_GOT" in
            want) echo "   第二轮拿到新 Flag，程序按请求读取 Flag";;
            old)
              stage solve failed
              fail "换 Flag 后等了 15 秒，解题脚本拿到的还是旧值，程序把 Flag 读进了内存（启动时或第一次请求时）。改成每次请求读 ${FLAGPATH}，或按 references/platform.md 加同步循环";;
            *)
              tail -15 "$SOLVELOG" | sed 's/^/   | /'
              partial "复查时解题脚本既没拿到新 Flag 也没拿到旧 Flag，确认第二次运行的失败原因（题目被第一次解题打坏了也会这样，这种题用 --no-flag-rotate 跳过）";;
          esac
        else
          partial "复查时第二个测试 Flag 写不进 ${FLAGPATH}，跳过复查"
        fi
      fi
    else
      tail -15 "$SOLVELOG" | sed 's/^/   | /'
      [ "$SOLVE_TIMED_OUT" = 1 ] && hint "解题命令超过 ${SOLVE_TIMEOUT} 秒被终止。QEMU 类题目用 --solve-timeout 调大，不要用缩短链路来迁就超时"
      # 本机模拟运行 amd64 时，被调试的二进制可能崩在模拟器里，这不是题目本身的问题。
      if [ "$HOST_IS_EMULATED" = 1 ] && grep -qE 'Segmentation fault|Bus error|Illegal instruction|core dumped|qemu:' "$SOLVELOG"; then
        stage solve environment_failed
        envfail "解题命令崩在本机模拟器里，题目本身可能没问题。换原生 amd64 机器重跑，或用 --platform linux/arm64 先确认镜像其余部分"
      else
        stage solve failed
        fail "解题命令的输出里没有 ${WANT_FLAG}（Flag 被缓存、路径不对，或解题脚本没打通）"
      fi
    fi
  fi
fi

finish
