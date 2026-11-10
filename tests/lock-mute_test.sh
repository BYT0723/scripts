#!/usr/bin/env bash
# tools/lock.sh 锁屏静音回归测试:
#   A. 状态快照在 _lock_before 现取 (powermenu 先 source 再点菜单, 顶层取会过期)
#   B. 静音走 pulse 层, 覆盖全部 sink (含 easyeffects_sink / USB DAC / HDMI),
#      不再依赖 `amixer set Master off` (只打中 ALSA 默认控制卡)
#   C. 已静音的 sink 不重复处理, 解锁只还原本次改过的
# 运行: bash tests/lock-mute_test.sh

TOOLS_DIR="$(cd "$(dirname "$0")/../tools" && pwd)"
TEST_DIR=$(mktemp -d)
BIN="$TEST_DIR/bin"
MUTE_DIR="$TEST_DIR/mute"
LOG="$TEST_DIR/log"
MPD_FILE="$TEST_DIR/mpd"
mkdir -p "$BIN" "$MUTE_DIR"
export MUTE_DIR LOG MPD_FILE
export PATH="$BIN:$PATH"

cat >"$BIN/pactl" <<'EOF'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$LOG"
case "$1" in
    list)
        printf '%s\n' \
            "63 s_internal PipeWire s32le 2ch 48000Hz RUNNING" \
            "70 s_fosi PipeWire s32le 2ch 44100Hz IDLE" \
            "98 easyeffects_sink PipeWire float32le 2ch 48000Hz RUNNING" \
            "89642 s_hdmi PipeWire s32le 2ch 48000Hz SUSPENDED"
        ;;
    get-sink-mute) printf 'Mute: %s\n' "$(cat "$MUTE_DIR/$2" 2>/dev/null || echo no)" ;;
    set-sink-mute)
        if [ "$3" = 1 ]; then echo yes >"$MUTE_DIR/$2"; else echo no >"$MUTE_DIR/$2"; fi
        ;;
esac
EOF

cat >"$BIN/mpc" <<'EOF'
#!/bin/bash
printf 'mpc %s\n' "$*" >>"$LOG"
if [ "$1" = status ]; then
    printf 'Artist - Title\n[%s]  #1/1  0:00/3:00\n' "$(cat "$MPD_FILE")"
else
    if [ "$(cat "$MPD_FILE")" = playing ]; then echo paused >"$MPD_FILE"; else echo playing >"$MPD_FILE"; fi
fi
EOF

# amixer 只记录调用: 修复后不应再出现
printf '#!/bin/bash\nprintf "amixer %%s\\n" "$*" >>"$LOG"\n' >"$BIN/amixer"
chmod +x "$BIN/pactl" "$BIN/mpc" "$BIN/amixer"

for n in pkill pgrep find shuf notify-send xset xrandr; do
    printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"$LOG"\nexit 0\n' "$n" >"$BIN/$n"
    chmod +x "$BIN/$n"
done
# i3lock 复刻 i3lock-color 行为: 默认 fork (父进程立刻退出), 带 -n 时留在前台
cat >"$BIN/i3lock" <<'EOF'
#!/bin/bash
printf 'i3lock %s\n' "$*" >>"$LOG"
hold=${I3LOCK_HOLD:-0.4}
case " $* " in
    *" -n "*) sleep "$hold" ;;
    *) ( sleep "$hold" ) & exit 0 ;;
esac
EOF
chmod +x "$BIN/i3lock"
# pgrep -x i3lock 必须返回非 0, 否则 source lock.sh 会直接 exit
printf '#!/bin/bash\nprintf "pgrep %%s\\n" "$*" >>"$LOG"\nexit 1\n' >"$BIN/pgrep"
chmod +x "$BIN/pgrep"

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
count() { grep -c "$1" "$LOG" 2>/dev/null || true; }
mute_of() { cat "$MUTE_DIR/$1" 2>/dev/null || echo no; }

echo playing >"$MPD_FILE"
for s in s_internal s_fosi easyeffects_sink; do echo no >"$MUTE_DIR/$s"; done
echo yes >"$MUTE_DIR/s_hdmi" # 用户本来就静音的 sink

# shellcheck source=../tools/lock.sh
source "$TOOLS_DIR/lock.sh"

# ---- A. 快照时机 ----
check "A1: source 阶段不取 mpd 快照" '[ "$(count "^mpc status$")" -eq 0 ]'
_lock_before
check "A2: _lock_before 现取快照" '[ "$(count "^mpc status$")" -eq 1 ]'

# ---- B. pulse 层静音 ----
check "B1: 播放中暂停 mpd" '[ "$(cat "$MPD_FILE")" = paused ] && [ "$(count "^mpc -q toggle$")" -eq 1 ]'
check "B2: 全部未静音的 sink 都被静音" '[ "$(mute_of s_internal)" = yes ] && [ "$(mute_of s_fosi)" = yes ] && [ "$(mute_of easyeffects_sink)" = yes ]'
check "B3: 已静音的 sink 不重复处理 (hdmi)" '[ "$(count "^pactl set-sink-mute s_hdmi")" -eq 0 ] && [ "$(mute_of s_hdmi)" = yes ]'
check "B4: 只记录本次改过的 sink (实际 ${#muted_sinks[@]})" '[ "${#muted_sinks[@]}" -eq 3 ]'
check "B5: 不再调用 amixer" '[ "$(count "^amixer ")" -eq 0 ]'

# ---- C. 解锁还原 ----
_lock_after
check "C1: 只还原本次静音的 sink" '[ "$(mute_of s_internal)" = no ] && [ "$(mute_of s_fosi)" = no ] && [ "$(mute_of easyeffects_sink)" = no ]'
check "C2: 用户原本静音的不动" '[ "$(mute_of s_hdmi)" = yes ]'
check "C3: 恢复 mpd 播放" '[ "$(cat "$MPD_FILE")" = playing ]'
check "C4: 全程无 amixer" '[ "$(count "^amixer ")" -eq 0 ]'

# ---- E. 锁屏器存活期间不得提前恢复 (i3lock 默认 fork 的陷阱) ----
: >"$LOG"
for s in s_internal s_fosi easyeffects_sink; do echo no >"$MUTE_DIR/$s"; done
echo playing >"$MPD_FILE"
export I3LOCK_HOLD=3
( lock ) &
lpid=$!
sleep 1.6
check "E1: i3lock 存活期间保持静音" '[ "$(mute_of s_internal)" = yes ] && [ "$(mute_of s_fosi)" = yes ]'
check "E2: i3lock 存活期间 DPMS 未提前归零" '! grep -qE "^xset dpms 0 0 0$" "$LOG"'
check "E3: i3lock 走 -n (nofork), wait 才能等到解锁" 'grep -qE "^i3lock -n " "$LOG"'
wait "$lpid"
check "E4: 解锁后恢复静音" '[ "$(mute_of s_internal)" = no ]'
unset I3LOCK_HOLD

# ---- F. SIGTERM (loginctl unlock-session / 外部 kill) 也要还原 ----
: >"$LOG"
for s in s_internal s_fosi easyeffects_sink; do echo no >"$MUTE_DIR/$s"; done
echo playing >"$MPD_FILE"
export I3LOCK_HOLD=5
( lock ) &
lpid=$!
sleep 1.5
check "F1: 锁屏中已静音" '[ "$(mute_of s_internal)" = yes ]'
kill -TERM "$lpid"
sleep 1
check "F2: SIGTERM 后恢复静音" '[ "$(mute_of s_internal)" = no ] && [ "$(mute_of s_fosi)" = no ]'
check "F3: SIGTERM 后收回 DPMS" 'grep -qE "^xset dpms 0 0 0$" "$LOG"'
check "F4: SIGTERM 后恢复 xwallpaperd 渲染" 'grep -qE "^pkill -CONT -x xwallpaperd$" "$LOG"'
check "F5: mpd 只 toggle 两次 (还原幂等, 不重复暂停)" '[ "$(count "^mpc -q toggle$")" -eq 2 ]'
wait "$lpid" 2>/dev/null
unset I3LOCK_HOLD

# ---- D. 静态守卫: 源码里不再用 amixer 静音 ----
check "D1: lock.sh 不再 amixer set Master (忽略注释)" '! sed "s/#.*//" "$TOOLS_DIR/lock.sh" | grep -q "amixer set Master"'
check "D2: 静音走 pactl set-sink-mute" 'grep -q "pactl set-sink-mute" "$TOOLS_DIR/lock.sh"'

if [ "$fail" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
    exit 1
fi
