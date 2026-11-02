#!/usr/bin/env bash
# tools/screen.sh + tools/lock.sh 空闲/锁屏/灭屏链路回归测试:
#   A. screen.sh 只有一个空闲权威: xset s 600 0 + noblank + xss-lock, 不再自建 xautolock 计时器
#   B. xss-lock 单实例: 重复 start 不重复拉起
#   C. 媒体抑制 = xset s reset (不拆计时器, 不碰 DPMS)
#   D. 抑制解除后不重新写 xset s 600 (旧实现会立刻触发屏保 → 瞬间黑屏)
#   E. 已锁屏时音频不参与抑制
#   F. lock.sh 只在锁屏期间武装 DPMS, 解锁后归零
#   G. 静态守卫: xprintidle/xdotool/_screen_lock_loop 已随 xss-lock 迁移删除
# 运行: bash tests/screen-lock_test.sh

TOOLS_DIR="$(cd "$(dirname "$0")/../tools" && pwd)"
TEST_DIR=$(mktemp -d)
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

LOG="$TEST_DIR/log"
XSS_ALIVE="$TEST_DIR/xss.alive"
LOCK_ALIVE="$TEST_DIR/lock.alive"
export LOG XSS_ALIVE LOCK_ALIVE
export PATH="$BIN:$PATH"

cat >"$BIN/_mock" <<'EOF'
#!/bin/bash
app=${0##*/} # 不用 basename: 缺包用例的私有 PATH 里没有 /usr/bin
printf '%s\n' "$app $*" >>"$LOG"
case "$app" in
    pgrep)
        case "$*" in
            *xss-lock*) [ -f "$XSS_ALIVE" ] && exit 0 || exit 1 ;;
            *i3lock*) [ -f "$LOCK_ALIVE" ] && exit 0 || exit 1 ;;
        esac
        exit 1
        ;;
    xss-lock) : >"$XSS_ALIVE"; exit 0 ;;
    pactl) echo "test-sink"; exit 0 ;;
    parec) exit 0 ;;
    ffmpeg)
        if [ "${AUDIO_ON:-0}" = 1 ]; then echo "max_volume: -10.0 dB"; else echo "max_volume: -inf dB"; fi
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$BIN/_mock"
for n in xset xss-lock xautolock pgrep pkill parec pactl ffmpeg i3lock notify-send mpc amixer find shuf xprintidle xdotool; do
    ln -sf _mock "$BIN/$n"
done

cleanup() { rm -rf "$TEST_DIR"; }
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

reset_log() { : >"$LOG"; rm -f "$XSS_ALIVE" "$LOCK_ALIVE"; }
count() { grep -c "$1" "$LOG" 2>/dev/null || true; }

export SCREEN_NO_DAEMON=1
# shellcheck source=../tools/screen.sh
source "$TOOLS_DIR/screen.sh"

# ---- A. 单一空闲权威 ----
reset_log
_screensaver_start
wait
check "A1: xset s 600 0 + noblank (cycle=0 → 激活即锁, 不先黑屏)" 'grep -qE "^xset s 600 0$" "$LOG" && grep -qE "^xset s noblank$" "$LOG"'
check "A2: 解锁态 xset dpms 0 0 0 (灭屏只在锁屏期)" 'grep -qE "^xset dpms 0 0 0$" "$LOG"'
check "A3: 拉起 xss-lock 且 locker 为 lock.sh lock" 'grep -qE "^xss-lock -- .*lock\.sh lock$" "$LOG"'
check "A4: 启动时清理旧 xautolock" 'grep -qE "^pkill -x xautolock$" "$LOG"'
check "A5: 不再自建 xautolock 计时器" '! grep -qE "^xautolock " "$LOG"'
check "A6: 武装时归零空闲计数 (防重生即刻锁屏)" 'grep -qE "^xset s reset$" "$LOG"'

# ---- B. xss-lock 单实例 ----
reset_log
_screensaver_start
_screensaver_start
wait
check "B1: 重复 start 只拉起一个 xss-lock (实际 $(count '^xss-lock '))" '[ "$(count "^xss-lock ")" -eq 1 ]'

# ---- C. 抑制 = xset s reset ----
reset_log
_screensaver_start
export AUDIO_ON=1
_inhibit_poke
check "C1: 有音频时重置空闲计数" 'grep -qE "^xset s reset$" "$LOG"'
check "C2: 不再 xset s off (拆计时器是旧 bug)" '! grep -qE "^xset s off" "$LOG"'
check "C3: 不再切换 DPMS 开关" '! grep -qE -- "-dpms|\+dpms" "$LOG"'
check "C4: 抑制期间不碰 xautolock" '! grep -qE "^xautolock " "$LOG"'

# ---- D. 解除抑制后从 0 重新计时 (不重新武装超时) ----
n_reset=$(count '^xset s reset$')
export AUDIO_ON=0
_inhibit_poke
check "D1: 无音频不再 reset" '[ "$(count "^xset s reset$")" -eq "$n_reset" ]'
check "D2: 解除后不重写 xset s 600 (旧实现会瞬间触发)" '[ "$(count "^xset s 600")" -eq 1 ]'

# ---- E. 已锁屏时音频不参与 ----
reset_log
: >"$LOCK_ALIVE"
export AUDIO_ON=1
_inhibit_poke
check "E1: 锁屏中不做抑制 reset" '! grep -qE "^xset s reset$" "$LOG"'

# ---- F. lock.sh 的 DPMS 只在锁屏期间 ----
reset_log
sleep() { :; } # _lock 内的 sleep 1 不阻塞测试
# shellcheck source=../tools/lock.sh
source "$TOOLS_DIR/lock.sh"
_lock_before # 与 lock() 的真实顺序一致 (_lock_after 依赖 _lock_before 复位幂等状态)
_lock
wait
check "F1: 锁屏前武装 DPMS" 'grep -qE "^xset dpms 30 30 30$" "$LOG"'
check "F2: DPMS 武装先于 i3lock" 'awk "/^xset dpms 30 30 30\$/{a=NR} /^i3lock /{b=NR} END{exit !(a && b && a < b)}" "$LOG"'
check "F3: 锁屏后强制 standby" 'grep -qE "^xset dpms force standby$" "$LOG"'
_lock_after
check "F4: 解锁后归零 DPMS" 'grep -qE "^xset dpms 0 0 0$" "$LOG"'

# ---- H. 缺 xss-lock 时不退出, 装上后自动接管 ----
reset_log
# 用一个不含 xss-lock 的私有 PATH 模拟缺包 (系统已装 /usr/bin/xss-lock)
rm -f "$XSS_ALIVE"
NOXSS="$TEST_DIR/bin-noxss"
mkdir -p "$NOXSS"
for n in pkill pgrep xset notify-send; do ln -sf "$BIN/_mock" "$NOXSS/$n"; done
old_path=$PATH
PATH="$NOXSS"
hash -r
warned_xss=0
_screensaver_start
rc=$?
_screensaver_start # 第二轮验证不重复告警
PATH="$old_path"
hash -r
check "H1: 缺包返回非 0 且不武装 xset" '[ "$rc" -ne 0 ] && ! grep -qE "^xset s 600" "$LOG"'
check "H2: 缺包告警一次" '[ "$(count "^notify-send ")" -eq 1 ]'
check "H3: 后续轮次不重复告警" '[ "$(count "^notify-send ")" -eq 1 ]'
ln -sf "$BIN/_mock" "$BIN/xss-lock"
_screensaver_start
wait
check "H4: 装上后下一轮自动拉起" 'grep -qE "^xss-lock -- " "$LOG"'

# ---- J. 锁屏中重生 xss-lock 不得 reset (会解锁) ----
reset_log
: >"$LOCK_ALIVE"
_screensaver_start
wait
check "J1: 锁屏中不 reset 空闲计数" '! grep -qE "^xset s reset$" "$LOG"'
check "J2: 锁屏中仍然拉起 xss-lock" 'grep -qE "^xss-lock -- " "$LOG"'
rm -f "$LOCK_ALIVE"

# ---- I. daemon 每轮补齐异常退出的 xss-lock ----
reset_log
rm -f "$XSS_ALIVE"
export AUDIO_ON=0
(
    n=0
    sleep() { # 第一轮假装 xss-lock 崩溃; 第二轮结束 daemon
        rm -f "$XSS_ALIVE"
        n=$((n + 1))
        [ "$n" -ge 2 ] && exit 0
    }
    daemon
)
wait
check "I1: xss-lock 退出后下一轮自动拉起 (实际 $(count '^xss-lock -- '))" '[ "$(count "^xss-lock -- ")" -ge 2 ]'

# ---- G. 静态守卫 ----
check "G1: lock.sh 不再有 _screen_lock_loop" '! grep -q "_screen_lock_loop" "$TOOLS_DIR/lock.sh"'
check "G2: lock.sh 不再依赖 xprintidle" '! grep -q "xprintidle" "$TOOLS_DIR/lock.sh"'
check "G3: lock.sh 不再依赖 xdotool" '! grep -q "xdotool" "$TOOLS_DIR/lock.sh"'
check "G4: screen.sh 不再 xset s off (忽略注释)" '! sed "s/#.*//" "$TOOLS_DIR/screen.sh" | grep -q "xset s off"'
check "G5: screen.sh 不再起 xautolock" '! sed "s/#.*//" "$TOOLS_DIR/screen.sh" | grep -qE "xautolock -time"'

if [ "$fail" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
    exit 1
fi
