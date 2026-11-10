#!/usr/bin/env bash
# tools/screen.sh 单实例/自重启用回归测试:
#   A. _takeover: 杀掉 argv 恰为 [/bin/bash, <self>] 的旧 daemon; 不碰 `screen.sh notifier` 子命令
#   B. 自重启用用 exec: pid 不变 (launch 的 pid 文件不会失真), 且始终只有一个实例
# 运行: bash tests/screen-single-instance_test.sh

TOOLS_DIR="$(cd "$(dirname "$0")/../tools" && pwd)"
SCREEN="$TOOLS_DIR/screen.sh"
TEST_DIR=$(mktemp -d)
BIN="$TEST_DIR/bin"
LOG="$TEST_DIR/log"
XSS_ALIVE="$TEST_DIR/xss.alive"
LOCK_ALIVE="$TEST_DIR/lock.alive"
DIM_ALIVE="$TEST_DIR/dim.alive"
mkdir -p "$BIN"
export LOG XSS_ALIVE LOCK_ALIVE DIM_ALIVE

cat >"$BIN/_mock" <<'EOF'
#!/bin/bash
app=${0##*/}
printf '%s\n' "$app $*" >>"$LOG"
case "$app" in
    pgrep)
        case "$*" in
            *xss-lock*) [ -f "$XSS_ALIVE" ] && exit 0 || exit 1 ;;
            *i3lock*) [ -f "$LOCK_ALIVE" ] && exit 0 || exit 1 ;;
            *notifier*) [ -f "$DIM_ALIVE" ] && exit 0 || exit 1 ;;
        esac
        exit 1
        ;;
    xss-lock) : >"$XSS_ALIVE"; exit 0 ;;
    pkill) exit 0 ;;
    pactl) echo "test-sink"; exit 0 ;;
    parec) exit 0 ;;
    ffmpeg) echo "max_volume: -inf dB"; exit 0 ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$BIN/_mock"
for n in xset xss-lock pgrep pkill pactl parec ffmpeg notify-send xrandr; do ln -sf _mock "$BIN/$n"; done

DAEMON_PID=""
cleanup() {
    [ -n "$DAEMON_PID" ] && kill -KILL "$DAEMON_PID" 2>/dev/null
    [ -n "$FAKE_DAEMON" ] && kill -KILL "$FAKE_DAEMON" 2>/dev/null
    [ -n "$FAKE_NOTIFIER" ] && kill -KILL "$FAKE_NOTIFIER" 2>/dev/null
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

fail=0
check() { # $1=用例名 $2=断言表达式 (eval 后 0 为通过)
    if eval "$2" >/dev/null 2>&1; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}
count() { grep -c "$1" "$LOG" 2>/dev/null || true; }
wait_count() { # $1=pattern $2=期望条数
    local i=0
    while [ "$i" -lt 150 ]; do
        [ "$(count "$1")" -ge "$2" ] && return 0
        sleep 0.02
        i=$((i + 1))
    done
    return 1
}

# ---- A. _takeover: 只杀旧 daemon, 不动 notifier ----
FAKE_DIR="$TEST_DIR/inst"
mkdir -p "$FAKE_DIR"
printf 'sleep 300\n' >"$FAKE_DIR/screen.sh"
bash "$FAKE_DIR/screen.sh" &
FAKE_DAEMON=$!
bash "$FAKE_DIR/screen.sh" notifier &
FAKE_NOTIFIER=$!
sleep 0.1
# 以"后启动的实例"身份调用 _takeover (同一 jiffy 时按 pid 判新旧)
bash -c 'source "$1" || exit 1; SELF="$2"; _takeover' _ "$SCREEN" "$FAKE_DIR/screen.sh"
sleep 0.3
check "A1: _takeover 杀掉更早启动的旧 daemon" '! kill -0 "$FAKE_DAEMON" 2>/dev/null'
check "A2: 不误杀 notifier 子命令" 'kill -0 "$FAKE_NOTIFIER" 2>/dev/null'

# ---- B. 自重启用用 exec: pid 不变 ----
LIVE_DIR="$TEST_DIR/repo"
mkdir -p "$LIVE_DIR/tools" "$LIVE_DIR/utils"
cp "$SCREEN" "$LIVE_DIR/tools/screen.sh"
cp "$TOOLS_DIR/../utils/notify.sh" "$LIVE_DIR/utils/notify.sh"
: >"$LOG"
rm -f "$XSS_ALIVE" "$LOCK_ALIVE" "$DIM_ALIVE"
PATH="$BIN:$PATH" SCREEN_TICK=0.2 SCREEN_ARM_FILE="$TEST_DIR/arm.fp" \
    bash "$LIVE_DIR/tools/screen.sh" &
DAEMON_PID=$!
wait_count '^xset s 570 30$' 1
check "B1: daemon 已武装" '[ "$(count "^xset s 570 30$")" -ge 1 ]'

printf '\n# touch %s\n' "restart-case" >>"$LIVE_DIR/tools/screen.sh" # 触发 md5 自重启
wait_count '^xset s 570 30$' 2
check "B2: 自重启已发生" '[ "$(count "^xset s 570 30$")" -ge 2 ]'
check "B3: 自重启保持 pid (exec, launch 的 pid 记录不失真)" 'kill -0 "$DAEMON_PID" 2>/dev/null'
check "B4: 自重启后仍只有一个实例 (实际 $(pgrep -cf "$LIVE_DIR/tools/screen.sh"))" \
    '[ "$(pgrep -cf "$LIVE_DIR/tools/screen.sh")" -eq 1 ]'

if [ "$fail" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
    exit 1
fi
