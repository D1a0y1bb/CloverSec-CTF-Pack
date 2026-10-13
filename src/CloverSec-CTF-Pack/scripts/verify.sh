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
  --timeout N         等待服务开始监听的秒数，默认 60
  --keep              结束后保留容器和镜像，便于进去排查
  --report PATH       把构建日志、端口结果和阶段结论写成 JSON 报告。默认写到系统临时目录，
                      路径只要落在交付目录里就拒绝执行，报告不属于交付物。

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
# Java、php-fpm、MySQL 冷启动常见 10~40 秒，amd64 模拟运行还会更慢，60 秒留出余量。
START_TIMEOUT=60
# 解题脚本一般几秒结束；竞态类题目要多跑几轮，给到 120 秒。QEMU 题用 --solve-timeout 调大。
SOLVE_TIMEOUT=120

is_num() { case "$1" in ''|*[!0-9]*) return 1;; esac; return 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORTS+=("${2:?--port 需要参数}"); shift 2;;
    --flag-path) FLAGPATH="${2:?--flag-path 需要参数}"; shift 2;;
    --solve) SOLVE="${2:?--solve 需要参数}"; shift 2;;
    --solve-timeout) SOLVE_TIMEOUT="${2:?--solve-timeout 需要参数}"; shift 2;;
    --no-flag-rotate) FLAG_ROTATE=0; shift;;
    --expect-flag) EXPECT_FLAG="${2:?--expect-flag 需要参数}"; shift 2;;
    --check) CHECK="${2:?--check 需要参数}"; shift 2;;
    --rdg) FORCE_RDG=1; shift;;
    --platform) PLATFORM="${2:?--platform 需要参数}"; shift 2;;
    --run-arg) RUN_ARGS_EXTRA+=("${2:?--run-arg 需要参数}"); shift 2;;
    --timeout) START_TIMEOUT="${2:?--timeout 需要参数}"; shift 2;;
    --keep) KEEP=1; shift;;
    --report) REPORT="${2:?--report 需要参数}"; shift 2;;
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
command -v docker >/dev/null || { echo "failed: 找不到 docker"; exit 1; }
command -v curl >/dev/null || { echo "failed: 找不到 curl"; exit 1; }
PROJECT=$(cd "$PROJECT" 2>/dev/null && pwd) || { echo "failed: 目录不存在"; exit 2; }
cd "$PROJECT" || exit 2

# 报告是给跑验证的人看的，不是交付物。路径落在交付目录里直接拒绝，避免又把它交出去。
if [ -n "$REPORT" ]; then
  case "$(cd "$(dirname "$REPORT")" 2>/dev/null && pwd || echo "")" in
    "$PROJECT"|"$PROJECT"/*)
      echo "failed: --report 的路径在交付目录里（${REPORT}）。报告不属于交付物，写到系统临时目录，例如："
      echo "  --report \"\$(mktemp -d)/verify.json\""
      exit 2;;
  esac
fi

STATUS=passed; NOTES=(); HINTS=(); STAGE=()
fail()    { STATUS=failed; NOTES+=("$1"); }
partial() { [ "$STATUS" = passed ] && STATUS=partial; NOTES+=("$1"); }
# 环境失败不许覆盖真实失败：已经判 failed 的题目，后面再遇到模拟器崩溃也还是 failed，
# 否则「构建失败 + 模拟器崩溃」会被粉饰成 environment_failed。
envfail() {
  [ "$STATUS" = failed ] || STATUS=environment_failed
  NOTES+=("$1")
}
hint()    { HINTS+=("$1"); }
stage() { # 同一阶段重复设置时只保留最后一次结论
  local i
  for i in "${!STAGE[@]}"; do
    [ "${STAGE[$i]%%:*}" = "$1" ] && { STAGE[i]="$1: $2"; return; }
  done
  STAGE+=("$1: $2")
}

json_str() { printf '%s' "$1" | tr '\t' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

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
      printf '\n    "%s"' "$(json_str "$n")"; first=0
    done
    printf '\n  ]\n}\n'
  } > "$REPORT"
  echo "   报告: ${REPORT}"
}

finish() {
  write_report
  echo
  [ ${#STAGE[@]} -gt 0 ] && echo "== 阶段: ${STAGE[*]}"
  echo "== 结果: $STATUS"
  for n in "${NOTES[@]+"${NOTES[@]}"}"; do echo "   - $n"; done
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
    src|Dockerfile|start.sh|challenge.yaml|flag|README|solve|附件|镜像) return 0;;
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
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then HAVE_PYYAML=1; fi

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
dump("prov_status", "provenance.status", "challenge.provenance.status")
dump("prov_verify", "provenance.verify", "challenge.provenance.verify")
dump("check_path", "challenge.check.path", "check.path")
PY
}

YAML_PORTS=""; YAML_FLAGPATH=""; YAML_PROBE=""; YAML_PROV_STATUS=""; YAML_PROV_VERIFY=""; YAML_CHECK_PATH=""; YAML_FLAG_MODE=""
if [ -f challenge.yaml ] && [ "$HAVE_PYYAML" = 1 ]; then
  while IFS="$(printf '\t')" read -r k v; do
    case "$k" in
      YAML_ERROR) YAML_ERROR="$v";;
      expose_ports) YAML_PORTS="$v";;
      flag_path) YAML_FLAGPATH="$v";;
      probe_path) YAML_PROBE="$v";;
      prov_status) YAML_PROV_STATUS="$v";;
      prov_verify) YAML_PROV_VERIFY="$v";;
      check_path) YAML_CHECK_PATH="$v";;
      flag_mode) YAML_FLAG_MODE="$v";;
    esac
  done < <(yaml_probe)
elif [ -f challenge.yaml ]; then
  # 没有 PyYAML 时，这两个字段决定判定方式，用文本匹配兜一下，免得静态 Flag 题被当成平台写 Flag 的题。
  grep -qE '^[[:space:]]+mode:[[:space:]]*["'"'"']?static' challenge.yaml && YAML_FLAG_MODE=static
  YAML_CHECK_PATH=$(sed -nE 's/^[[:space:]]+path:[[:space:]]*["'"'"']?(\.?\/?check\/[^"'"'"'[:space:]]+).*/\1/p' challenge.yaml | head -1)
fi

# 手册检查：文件名、章节骨架、事实字段、启动命令，以及 TODO 残留。
# 判断部分（1.2/1.4/1.8/1.9）的内容不检查——这个脚本查不出内容真假，
# 假装能查只会让人把"章节齐全"当成"手册写完"。有 TODO 残留时按 partial 报，
# 不判 failed（材料确实没有来源时留 TODO 是对的），但也不许再报 passed。
assert_handbook() {
  local expected base found=() todo missing=() joined
  base=$(basename "$PROJECT")
  shopt -s nullglob
  found=("${PROJECT}/README"/*.md)
  if [ ${#found[@]} -eq 0 ]; then
    stage handbook failed
    fail "README/ 下没有手册。手册是交付的一部分，文件名写成 README/${base}.md"
    return
  fi
  expected="${PROJECT}/README/${base}.md"
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
  local skeleton="九节"
  if [ ${#missing[@]} -gt 0 ]; then
    if [ ! -f Dockerfile ] && [ ${#missing[@]} -eq 1 ] && [ "${missing[0]}" = 1.9 ]; then
      skeleton="八节（附件题顺延）"
    else
      stage handbook failed
      fail "手册缺章节：${missing[*]}。骨架见 references/manual.md"
      return
    fi
  fi

  # 事实字段：这几项 Skill 有能力查证，缺了就是没写全
  local fact_missing=()
  grep -qE '^#+[[:space:]]*1\.5' "$expected" && ! grep -qE '平台覆盖|flag ?文件位置|Flag ?文件' "$expected" \
    && fact_missing+=("1.5 旗帜信息（平台覆盖方式 / flag 文件位置）")
  grep -qE '^#+[[:space:]]*1\.6' "$expected" && ! grep -qE '端口|账号|地址' "$expected" \
    && fact_missing+=("1.6 题目情况（端口 / 账号 / 地址）")
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
  if [ -f Dockerfile ] && ! printf '%s\n' "$joined" | grep -qE 'docker run[^`]*start\.sh'; then
    stage handbook partial
    partial "手册 1.7 的 docker run 命令没带 /start.sh，平台按 /start.sh 启动容器，手册要和平台一致"
    return
  fi

  # TODO 残留：判断部分没有来源时本来就该留空给人工写，所以不判失败——
  # 但也不能算 passed，否则「手册没写完」和「全部通过」会同时成立。
  todo=$(grep -c 'TODO(人工填写)' "$expected" 2>/dev/null); todo=${todo:-0}
  if [ "$todo" -gt 0 ] 2>/dev/null; then
    stage handbook "todo: $todo"
    partial "手册有 ${todo} 处 TODO(人工填写) 没填（1.2 题目描述、1.4 考察信息、1.8 题目设计、1.9 解题步骤），交付前要么从原始材料搬运整理，要么如实告诉用户哪几节还空着"
    return
  fi
  echo "   手册 $(basename "$expected") ${skeleton}齐全，无待填项"
  stage handbook passed
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
      fail "provenance.verify 是空的。填 passed / environment_failed / incomplete，空着等于没给结论"
      return
    fi
    stage provenance passed
  fi
}

echo "== 检查手册"
assert_handbook
echo "== 检查 provenance"
assert_provenance

# ---------- 交付目录检查：白名单 + 垃圾文件（递归）
echo "== 检查交付目录"
shopt -s nullglob dotglob
EXTRA=()
for entry in "$PROJECT"/*; do
  name=$(basename "$entry")
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
  HARD_EXTRA=()
  for e in "${EXTRA[@]}"; do
    case "$e" in
      # 报告、验证脚本副本、内部工作文件（_PACK_SPEC.md 这类）是习惯性残留，直接判 failed。
      # 根目录 README.md 单独列出：手册在 README/ 目录里。
      verify.sh|*verify.json|verify-report.json|*.pyc|__pycache__|.venv|_*|README.md) HARD_EXTRA+=("$e");;
    esac
  done
  if [ ${#HARD_EXTRA[@]} -gt 0 ]; then
    DELIVERY=failed
    fail "交付目录里有不该出现的文件：${HARD_EXTRA[*]}。交付目录只留 Skill 白名单里的内容，报告写到系统临时目录，内部工作文件放到交付目录之外"
  else
    DELIVERY=partial
    partial "交付目录有多余文件：${EXTRA[*]}。确认它们是不是交付物，不是就删掉"
  fi
fi
if [ ${#JUNK[@]} -gt 0 ]; then
  [ "$DELIVERY" = passed ] && DELIVERY=partial
  partial "交付目录里有垃圾文件：${JUNK[*]}。用 find 加 -delete 清掉，用 Finder 打开过目录后要重扫"
fi
[ "$DELIVERY" = passed ] && echo "   干净"
stage delivery "$DELIVERY"

# ---------- 启动脚本的静态检查
if [ -f start.sh ]; then
  if grep -q $'\r' start.sh; then
    fail "start.sh 是 CRLF 换行，容器里会报 bad interpreter，转成 LF 后再验证"; finish
  fi
  head -n1 start.sh | grep -q '^#!' || { fail "start.sh 第一行没有 #!，平台执行 /start.sh 会报 exec format error"; finish; }
  [ -x start.sh ] || hint "本机的 start.sh 没有执行位。镜像里由 Dockerfile 的 chmod 决定，确认 Dockerfile 里有 chmod 555"
  # 只为四叶草平台出的题不需要环境变量兼容段，照抄模板会把别的平台的合同带进交付物。
  if grep -qE 'GZCTF_FLAG|DASFLAG' start.sh; then
    stage hygiene partial
    partial "start.sh 里有 GZCTF_FLAG / DASFLAG 兼容段。只为四叶草平台出的题不需要加，确认这道题真的要在那些平台跑，否则删掉"
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
# solve 引用了第三方库却没写安装命令时，换台干净机器就会失败。
if [ -f solve/solve.py ] \
   && grep -qE '^[[:space:]]*(import|from)[[:space:]]+(requests|numpy|PIL|z3|fpylll|sage|pwn|Crypto|gmpy2)\b' solve/solve.py \
   && ! grep -q 'pip install' solve/solve.py; then
  stage hygiene partial
  partial "solve/solve.py 引用了第三方库，但文件开头没有注释写明 pip install 命令，换台机器就跑不起来"
fi

# 跑一次解题命令，带超时。结果写进 SOLVE_SRC，超时时置 SOLVE_TIMED_OUT=1。
FIRST_HOSTPORT=""; SOLVE_ENV=(); SOLVE_SRC=0; SOLVE_TIMED_OUT=0
run_solve() {
  ( cd "$PROJECT" && env HOST=127.0.0.1 PORT="$FIRST_HOSTPORT" "${SOLVE_ENV[@]+"${SOLVE_ENV[@]}"}" \
      sh -c "$SOLVE" ) >"$SOLVELOG" 2>&1 &
  local spid=$! t0
  t0=$(date +%s)
  while kill -0 "$spid" 2>/dev/null && [ $(( $(date +%s) - t0 )) -lt "$SOLVE_TIMEOUT" ]; do sleep 1; done
  if kill -0 "$spid" 2>/dev/null; then
    # SIGTERM 不一定收得掉卡住的解题脚本，再补一刀 KILL，否则它会一直挂着。
    kill "$spid" 2>/dev/null
    sleep 2
    kill -KILL "$spid" 2>/dev/null
    wait "$spid" 2>/dev/null
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
  if [ -f "${PROJECT}/solve/solve.py" ] || [ -d "${PROJECT}/附件" ]; then
    echo "== 附件题（没有 Dockerfile，跳过容器验证）"
    ATT=("${PROJECT}/附件"/*)
    if [ ${#ATT[@]} -eq 0 ]; then
      partial "附件/ 是空的，确认选手该拿到哪些文件"
    else
      echo "   附件 ${#ATT[@]} 个"
      for a in "${ATT[@]}"; do echo "   - $(basename "$a")"; done
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
        SOLVED=$(grep -oE '[A-Za-z0-9_]+\{[^}]{4,}\}' "$SOLVELOG" | head -1)
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
if grep -qiE '^[[:space:]]*(COPY|ADD)[[:space:]]+(--[^[:space:]]+[[:space:]]+)*\./?[[:space:]]' Dockerfile; then
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
if ! docker build --platform "$PLATFORM" -t "$IMAGE" . >"$BUILDLOG" 2>&1; then
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

# ---------- 写入测试 Flag：命令和平台一致，以 root 用 sh 重定向写入
# 以 root 重定向总能写成功，所以"写不进去"不能当判据；先看题目有没有 Flag 合同。
NO_FLAG_CONTRACT=0
if [ ! -f "$YAML" ] || { [ -z "$YAML_FLAGPATH" ] && ! grep -qE '^[[:space:]]*flag:' "$YAML"; }; then
  NO_FLAG_CONTRACT=1
fi
if [ ! -f flag ] && ! grep -qiE '^[[:space:]]*(COPY|ADD).*flag([[:space:]]|$)' Dockerfile; then
  NO_FLAG_CONTRACT=1
fi

# 静态 Flag 题：平台不写 Flag，只比对选手提交的字符串，写 Flag 这一步没有意义。
STATIC_FLAG=0
case "$YAML_FLAG_MODE" in static) STATIC_FLAG=1;; esac

TESTFLAG="flag{verify_$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')}"
TESTFLAG2="flag{rotate_$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')}"
write_flag() { # $1 = 要写入的值
  docker exec -u 0 "$CONTAINER" sh -c 'printf "%s\n" "$1" > "$2"' sh "$1" "$FLAGPATH" 2>/dev/null
}
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
      echo "   回读一致（${MODE}）"; stage flag_write passed
    fi
  else
    stage flag_write failed
    fail "平台无法写入 ${FLAGPATH}（镜像里没有 sh，或目录不存在）"
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
    none) PORTS_OK=0; fail "端口 $p 在 ${START_TIMEOUT} 秒内没有开始监听"; show_logs; continue;;
    unknown) hint "读不到容器内的监听表，端口 $p 只能从宿主机探测，TCP 结果可能不准";;
  esac
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${HP}${PROBE_PATH}" 2>/dev/null)
  [ "$PROBE_PATH" = / ] || echo "   探测路径 ${PROBE_PATH}"
  if [ -n "$CODE" ] && [ "$CODE" != 000 ]; then
    echo "   HTTP $CODE"
    [ "$CODE" -ge 500 ] && partial "端口 $p 返回 HTTP ${CODE}，服务可能有报错"
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
