#!/usr/bin/env bash
# tools/screen.sh notifier 子命令 (xss-lock -n 通知器) 回归测试:
#   A. 压暗: 每个"已启用(带几何)"输出各写一次 --brightness <dim_gamma>;
#      跳过 connected 但未启用的 (eDP-1 无几何) 与 disconnected 输出
#   B. 恢复: SIGHUP (用户活动) / SIGTERM (锁屏前) → 全部写回 1.0, 且只写一次
#   C. 降级: 无 xrandr / 无活动输出 → 返回 0 且不写任何亮度 (绝不影响锁屏)
#   D. 静态守卫: 不混入硬件亮度 (brightnessctl/ddcutil)
# 运行: bash tests/screen-dim_test.sh

TOOLS_DIR="$(cd "$(dirname "$0")/../tools" && pwd)"
SCREEN="$TOOLS_DIR/screen.sh"
TEST_DIR=$(mktemp -d)
BIN="$TEST_DIR/bin"
BIN_OFF="$TEST_DIR/bin-off"
LOG="$TEST_DIR/log"
mkdir -p "$BIN" "$BIN_OFF"
export LOG
export PATH="$BIN:$PATH"

# 真实机器上是 eDP-1(connected 未启用) + DP-1/HDMI-1(启用) + DP-2(断开)
cat >"$BIN/xrandr" <<'EOF'
#!/bin/bash
printf 'xrandr %s\n' "$*" >>"$LOG"
if [ "$1" = "--query" ]; then
    printf '%s\n' \
        'eDP-1 connected (normal left inverted right x axis y axis)' \
        'DP-1 connected primary 2560x1440+1080+280 (0x1) normal' \
        'HDMI-1 connected 1080x1920+0+0 (0xfa) left' \
        'DP-2 disconnected (normal left inverted right x axis y axis)'
fi
exit 0
EOF

cat >"$BIN_OFF/xrandr" <<'EOF'
#!/bin/bash
printf 'xrandr %s\n' "$*" >>"$LOG"
exit 0
EOF
chmod +x "$BIN/xrandr" "$BIN_OFF/xrandr"

DIM_PID=""
cleanup() {
    [ -n "$DIM_PID" ] && kill -KILL "$DIM_PID" 2>/dev/null
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

reset_log() { : >"$LOG"; }
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

start_dim() {
    reset_log
    # SCREEN_NO_DAEMON=1 只是防御: 未实现 notifier 分发时也不会意外起 daemon
    SCREEN_NO_DAEMON=1 /bin/bash "$SCREEN" notifier &
    DIM_PID=$!
    wait_count '^xrandr --output .* --brightness 0\.4$' 2
}

stop_dim() { # $1=signal
    kill -"$1" "$DIM_PID" 2>/dev/null
    wait "$DIM_PID" 2>/dev/null
    DIM_PID=""
}

# ---- A. 压暗 ----
start_dim
check "A1: 已启用输出全部压暗 (DP-1/HDMI-1)" \
    '[ "$(count "^xrandr --output DP-1 --brightness 0.4$")" -eq 1 ] && [ "$(count "^xrandr --output HDMI-1 --brightness 0.4$")" -eq 1 ]'
check "A2: 跳过 connected 但未启用的 eDP-1" '! grep -q "eDP-1" "$LOG"'
check "A3: 跳过 disconnected 输出" '! grep -q "DP-2" "$LOG"'
check "A4: 压暗只写一次每输出" '[ "$(count "xrandr .*--brightness 0\.4")" -eq 2 ]'

# ---- B. 恢复 ----
stop_dim HUP
check "B1: SIGHUP 恢复 1.0" \
    '[ "$(count "^xrandr --output DP-1 --brightness 1.0$")" -eq 1 ] && [ "$(count "^xrandr --output HDMI-1 --brightness 1.0$")" -eq 1 ]'
check "B2: 恢复幂等 (EXIT trap 不重复写)" '[ "$(count "xrandr .*--brightness 1\.0")" -eq 2 ]'

start_dim
stop_dim TERM
check "B3: SIGTERM 恢复 1.0 (锁屏前)" '[ "$(count "xrandr .*--brightness 1\.0")" -eq 2 ]'

# ---- C. 降级 ----
export SCREEN_NO_DAEMON=1
# shellcheck source=../tools/screen.sh
source "$SCREEN"

reset_log
(PATH=/nonexistent; _notifier)
rc=$?
check "C1: 无 xrandr 返回 0 且不写亮度" '[ "$rc" -eq 0 ] && [ ! -s "$LOG" ]'

reset_log
(PATH="$BIN_OFF:$PATH"; _notifier)
rc=$?
check "C2: 无活动输出不压暗" '[ "$rc" -eq 0 ] && ! grep -q -- "--brightness" "$LOG"'

# ---- D. 静态守卫 ----
check "D1: 不混入硬件亮度" '! grep -qE "brightnessctl|ddcutil" "$SCREEN"'
check "D2: 直接执行时有 notifier 子命令分发" 'grep -q "notifier)" "$SCREEN"'
check "D3: notifier 不阻塞信号 (后台 sleep + wait)" \
    'grep -q "sleep 2147483647 &" "$SCREEN" && grep -q "^    wait$" "$SCREEN"'

if [ "$fail" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
    exit 1
fi
