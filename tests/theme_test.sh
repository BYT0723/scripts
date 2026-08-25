#!/usr/bin/env bash
# theme.sh auto_daemon 回归测试:
#   A. 挂起(suspend)期间 sleep 计时暂停, 唤醒后应短轮询及时重算并切换主题,
#      而非睡完剩余秒数(延迟数小时)
#   B. 锁屏期间阻塞切换, 解锁后立即切换
# 运行: bash tests/theme_test.sh

SCRIPT="$HOME/.dwm/tools/theme.sh"
TEST_DIR=$(mktemp -d)
DAEMON=""

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm/cache"
echo '{"auto":{"enabled":true,"sun_rise_offset":0,"sun_set_offset":0}}' >"$HOME/.config/dwm/theme.json"
echo dark >"$HOME/.local/state/dwm/current-theme"

# 预写 sun-times 缓存: 今天 09:00 日出, 18:00 日落 (缓存命中免网络)
TODAY=$(/usr/bin/date +%F)
SR=$(/usr/bin/date -d "$TODAY 09:00" +%s)
SS=$(/usr/bin/date -d "$TODAY 18:00" +%s)
SR2=$(/usr/bin/date -d "$( /usr/bin/date -d "$TODAY +1 day" +%F) 09:00" +%s)
printf '%s|%s|%s|%s\n' "$TODAY" "$SR" "$SS" "$SR2" >"$HOME/.local/state/dwm/cache/sun-times"

# 可推进的时间/锁屏状态 (文件驱动, 后台 daemon 才能感知变化)
MOCK_NOW_FILE="$TEST_DIR/mock_now"
MOCK_TODAY_FILE="$TEST_DIR/mock_today"
MOCK_LOCK_FILE="$TEST_DIR/mock_locked"
echo "$SR" >"$MOCK_NOW_FILE"   # 初始 09:00
echo "$TODAY" >"$MOCK_TODAY_FILE"
echo 0 >"$MOCK_LOCK_FILE"

set_now() { echo "$1" >"$MOCK_NOW_FILE"; }
set_locked() { echo "$1" >"$MOCK_LOCK_FILE"; }

# ---- mock 外部命令 ----
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

cat >"$BIN/date" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "+%s" ]; then cat "$MOCK_NOW_FILE"
elif [ "$1" = "+%F" ]; then cat "$MOCK_TODAY_FILE"
else cat "$MOCK_NOW_FILE"; fi
EOF

cat >"$BIN/sleep" <<'EOF'
#!/usr/bin/env bash
echo "sleep $1" >>"$MOCK_LOG"
EOF

cat >"$BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-x" ] && [ "$2" = "i3lock" ] || exit 1
[ "$(cat "$MOCK_LOCK_FILE")" = "1" ] && { echo i3lock; exit 0; }
exit 1
EOF

cat >"$BIN/pkill" <<'EOF'
#!/usr/bin/env bash
echo "pkill $*" >>"$MOCK_LOG"
EOF

for c in xrdb dunstctl killall xsettingsd fcitx5; do
    cat >"$BIN/$c" <<EOF
#!/usr/bin/env bash
echo "$c \$*" >>"\$MOCK_LOG"
EOF
done
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
export MOCK_LOG="$TEST_DIR/log" \
    MOCK_NOW_FILE="$MOCK_NOW_FILE" MOCK_TODAY_FILE="$MOCK_TODAY_FILE" MOCK_LOCK_FILE="$MOCK_LOCK_FILE"

source "$SCRIPT"

# 重定义, 避免污染真实配置/通知/桌面 (须模拟写 current-theme, 否则每轮重复切换)
_do_theme_change() { echo "theme_change $1" >>"$MOCK_LOG"; echo "$1" >"$HOME/.local/state/dwm/current-theme"; }
tool-notify() { echo "notify $*" >>"$MOCK_LOG"; }

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}

cleanup() {
    [ -n "$DAEMON" ] && kill "$DAEMON" 2>/dev/null
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

auto_daemon >/dev/null 2>&1 &
DAEMON=$!

# ---- 场景 A: 挂起唤醒后及时纠正 ----
# 07:00 (sunrise 前): desired=dark, cur=dark → 不切, 轮询等待
set_now "$(/usr/bin/date -d "$TODAY 07:00" +%s)"
/bin/sleep 0.3
check "挂起前不长时间 sleep (每次轮询 ≤60s)" \
    "! grep -Eq '^sleep [0-9]{4,}' \"\$MOCK_LOG\" && grep -q '^sleep 60$' \"\$MOCK_LOG\""

# 模拟挂起 5h 后 15:00 唤醒: 已过 sunrise 切换点, 唤醒后应立即重算切换 dark→light
set_now "$(/usr/bin/date -d "$TODAY 15:00" +%s)"
/bin/sleep 0.3
check "挂起唤醒后重算并切换 (dark→light)" "grep -q '^theme_change light$' \"\$MOCK_LOG\""
check "当前主题已更新为 light" "[ \"\$(cat \"\$HOME/.local/state/dwm/current-theme\")\" = light ]"

# ---- 场景 B: 锁屏阻塞切换, 解锁后立即切换 ----
: >"$MOCK_LOG"
echo dark >"$HOME/.local/state/dwm/current-theme"
set_now "$(/usr/bin/date -d "$TODAY 09:05" +%s)"
set_locked 1
/bin/sleep 0.3
check "锁屏期间阻塞等待 (sleep 5 轮询 i3lock)" "grep -q '^sleep 5$' \"\$MOCK_LOG\""
check "锁屏期间不切换" "! grep -q '^theme_change' \"\$MOCK_LOG\""

set_locked 0
/bin/sleep 0.3
check "解锁后立即切换 (dark→light)" "grep -q '^theme_change light$' \"\$MOCK_LOG\""

exit $fail