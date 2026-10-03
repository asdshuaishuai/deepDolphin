#!/bin/bash
# AI 通道端到端验证。
#
# 【为什么判据里不能只有纯函数测试】
# 纯函数判据能验证「请求体拼得对不对」「响应解得对不对」，
# 但**验证不到真实的那一段**：curl 怎么调、密钥走不走文件、
# 临时文件读写顺序对不对、响应体到底有没有落盘。
#
# 那一段在实测里已经咬过两次：
#   1. `String.fromUtf8([单字节])` 拼多字节序列 → 抛
#      `Invalid utf8 byte sequence`。症状是**任何含中文的提示词都发不出去**，
#      而纯函数判据全绿（它们只测 ASCII）。
#   2. 先删临时文件再读响应体 → 客户端报「AI 响应不是 JSON」，
#      而服务端明明返回了 200 和正确内容。
# 两个都是「逻辑读起来完全对、只发一次真请求才炸」。
#
# 所以这条脚本起一个**会逐项校验请求体**的假 provider，
# 用真 curl 走完整条路。校验不过就返回标记串让判据红。
#
# 用法：bash scripts/ai-e2e.sh
# ⚠ 不用 `set -u`：仓颉 `envsetup.sh` 会读 `DYLD_LIBRARY_PATH`，
# 而它在自己没设过的环境里是未定义的，`set -u` 直接把 source 打断。
# `set -o pipefail` 留着 —— 那条管的是管道退出码，是真有用的。
set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

export CANGJIE_HOME="${CANGJIE_HOME:-$HOME/.local/share/cangjie/current}"
# shellcheck disable=SC1091
source "$CANGJIE_HOME/envsetup.sh"
if [[ -d "$HOME/.local/share/sdks/MacOSX.minimal/latest" ]]; then
  export SDKROOT="$HOME/.local/share/sdks/MacOSX.minimal/latest"
fi

PLAIN_PORT=18741
AGENT_PORT=18742
PLAIN_LOG=/tmp/deepdolphin-mock-plain.log
AGENT_LOG=/tmp/deepdolphin-mock-agent.log
PLAIN_ERR=/tmp/deepdolphin-mock-plain.err
AGENT_ERR=/tmp/deepdolphin-mock-agent.err

cleanup() {
  # wait 一下再返回：不等的话 shell 会在脚本退出时打印
  # 「Terminated: 15 …」，看起来像出了事故。
  [[ -n "${PLAIN_PID:-}" ]] && { kill "$PLAIN_PID" 2>/dev/null; wait "$PLAIN_PID" 2>/dev/null; }
  [[ -n "${AGENT_PID:-}" ]] && { kill "$AGENT_PID" 2>/dev/null; wait "$AGENT_PID" 2>/dev/null; }
  # ⚠ 判据文件必须恢复，哪怕脚本是在失败路径上退出的。
  # 少这一句的话，一次失败就会把摘掉 @Skip 的判据留在工作区里 ——
  # 之后每次日常 cjpm test 都会去连一个不存在的假 provider。
  [[ -f "${TEST_BACKUP:-}" ]] && restore_test_file
  return 0
}
trap cleanup EXIT

# agent 那条要真引擎，所以引擎必须存在。找不到就**明说并失败**，
# 不静默跳过 —— 静默跳过等于「检查通过」，而实际上一条都没验。
ENGINE="$DIR/../../moonGit/target/release/bin/main"
if [[ ! -x "$ENGINE" ]]; then
  echo "✗ 找不到引擎：$ENGINE" >&2
  echo "  先 cd moonGit && cjpm build" >&2
  exit 2
fi

echo "› 起假 provider（plain :$PLAIN_PORT / agent :$AGENT_PORT）…"
MOCK_MODE=plain MOCK_PORT=$PLAIN_PORT MOCK_LOG=$PLAIN_LOG python3 tests/mock_agent.py >"$PLAIN_ERR" 2>&1 &
PLAIN_PID=$!
MOCK_MODE=agent MOCK_PORT=$AGENT_PORT MOCK_LOG=$AGENT_LOG python3 tests/mock_agent.py >"$AGENT_ERR" 2>&1 &
AGENT_PID=$!
sleep 2

# ⚠⚠ 必须**真的确认服务在监听**。
# 这个脚本的第一版没有这一步，于是：端口被上一次残留的进程占着 →
# 两个新进程 bind 失败退出（OSError: Address already in use）→
# 判据打到了**残留的旧服务**上，照样全绿 →
# 脚本最后打印「✓ AI 通道端到端通过」，而实际这次一条都没验。
# 「构建/检查对自己的成败说谎」正是本项目反复修的那族缺陷，
# 写检查脚本时最容易自己又犯一遍。
for pair in "$PLAIN_PORT:$PLAIN_PID" "$AGENT_PORT:$AGENT_PID"; do
  PORT_N="${pair%%:*}"; PID_N="${pair##*:}"
  if ! kill -0 "$PID_N" 2>/dev/null; then
    echo "✗ 假 provider 没起来（端口 $PORT_N 可能被占用）：" >&2
    ERR_FILE="$PLAIN_ERR"; [[ "$PORT_N" == "$AGENT_PORT" ]] && ERR_FILE="$AGENT_ERR"
    sed 's/^/    /' "$ERR_FILE" 2>/dev/null | tail -5 >&2
    exit 1
  fi
  # 再从客户端侧探一次：能连上才算真的在监听
  if ! curl -sS --max-time 3 -o /dev/null "http://127.0.0.1:$PORT_N/ping" 2>/dev/null; then
    # /ping 返回非 200 也算「在监听」——我们要的是 TCP 通了，不是 200
    if ! nc -z 127.0.0.1 "$PORT_N" 2>/dev/null; then
      echo "✗ 端口 $PORT_N 上没有服务在监听" >&2
      exit 1
    fi
  fi
done

# 摘掉两条端到端判据上的 @Skip，跑完**无条件**恢复。
#
# 为什么不留成「日常跳过」：一个永远不跑的判据等于没有判据。
# 为什么用 sed 而不是让判据自己判环境：自己判环境的话，
# 缺环境时会安静地 return，cjpm test 照样报 75 个全绿 ——
# 而实际有两条什么都没验。摘标记 + 验证 TCS 行存在，
# 才是「它真的跑了」的证据。
TEST_FILE="$DIR/src/ai_test.cj"
TEST_BACKUP="$(mktemp -t deepdolphin-ai-test)"
cp "$TEST_FILE" "$TEST_BACKUP"
restore_test_file() {
  cp "$TEST_BACKUP" "$TEST_FILE"
  rm -f "$TEST_BACKUP"
}
sed -i '' '/^@Skip \/\/ 端到端：/d' "$TEST_FILE"
if grep -q '^@Skip // 端到端：' "$TEST_FILE"; then
  echo "✗ 没能摘掉端到端判据的 @Skip —— 判据文件结构变了，脚本要跟着改" >&2
  exit 1
fi

export DD_E2E_PLAIN_PORT=$PLAIN_PORT
export DD_E2E_AGENT_PORT=$AGENT_PORT
export DD_E2E_BIN="$ENGINE"

echo "› 跑判据…"
OUT="$(cjpm test 2>&1)"
CLEAN="$(printf '%s' "$OUT" | sed 's/\x1b\[[0-9;]*m//g')"

# ⚠ 判据结果只在**冒号那一行**上认。
# 原来直接 `grep TEMP_`，而编译器的宏展开源码里满是 `TEMP_` 字样 ——
# 判据**编译失败**时那个 grep 照样命中，脚本于是打印「✓ 端到端通过」。
# 「检查对自己的成败说谎」又犯了一次：两处都改成认准一个精确的锚点。
# Summary 是**四行**（TOTAL / PASSED / FAILED 分布在后两行），
# 只取第一行会连 "FAILED: 0" 一起丢掉 —— 判定就永远不成立。
SUMMARY="$(printf '%s' "$CLEAN" | grep -A3 -E '^Summary: TOTAL:' | tail -4 | tr '\n' ' ')"
printf '%s\n' "$CLEAN" | grep -E '^\s*TCS: TestCase_TEMP_|^E2E-AGENT|Expect Failed:|^Summary: TOTAL:|^\s+(PASSED|FAILED|ERROR):' || true

E2E_FAIL=0
# 1) 编译/运行整体必须成功
if ! printf '%s' "$CLEAN" | grep -q 'cjpm test success'; then
  echo "" >&2
  echo "✗ cjpm test 本身没成功（编译错误或用例失败）—— 上面第一条就是原因" >&2
  E2E_FAIL=1
fi
# 2) Summary 里 0 FAILED / 0 ERROR
if ! printf '%s' "$SUMMARY" | grep -qE 'FAILED: 0'; then
  echo "" >&2
  echo "✗ 判据没有全绿：${SUMMARY:-（根本没跑到 Summary）}" >&2
  E2E_FAIL=1
fi
if ! printf '%s' "$SUMMARY" | grep -qE 'ERROR: 0'; then
  echo "" >&2
  echo "✗ 判据有 ERROR：${SUMMARY:-（根本没跑到 Summary）}" >&2
  E2E_FAIL=1
fi
# 3) 两条端到端判据必须**真的跑过**（TCS 行存在），而不是被悄悄跳过
for t in TEMP_e2eRequestBodySurvivesTheRealCurlRoundTrip TEMP_agentLoopCallsTheRealEngineAndConverges; do
  if ! printf '%s' "$CLEAN" | grep -q "TCS: TestCase_${t},"; then
    echo "" >&2
    echo "✗ 端到端判据 $t 没被跑到" >&2
    E2E_FAIL=1
  fi
done

echo ""
echo "── 假 provider 收到什么 ────────────────────────"
# ⚠ 先 grep 再 sed 缩进。反过来的话 sed 加上 4 个空格后
# `^PATH` 这样的行首锚点就再也匹配不上，输出静默变成空 ——
# 「检查跑完了但什么都没打出来」比报错更难查。
echo "· plain 轮："
grep -E '^(PATH|PLAIN_CORRECT)' "$PLAIN_LOG" 2>/dev/null | cut -c1-200 | sed 's/^/    /' || true
echo "· agent 轮："
grep -E '^(PATH|TOOL_RESULT_LEN)' "$AGENT_LOG" 2>/dev/null | cut -c1-200 | sed 's/^/    /' || true

if [[ "$E2E_FAIL" != "0" ]]; then
  echo ""
  echo "✗ 端到端失败" >&2
  exit 1
fi
echo ""
echo "✓ AI 通道端到端通过（真 curl + 真引擎 + 假 provider）"
