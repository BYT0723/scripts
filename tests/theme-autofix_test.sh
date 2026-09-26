#!/usr/bin/env bash
# theme.sh auto_daemon autofix 回归测试 (P0/P1 修复设防):
#   D. 脏缓存(非数字) → sleep 30 短轮询, 不切换、不 SIGHUP、不热循环无 sleep
#   E. auto.enabled 缺失/不可读 → sleep 10 重试不退出, 恢复后继续工作
#   F. 脏 API 响应 → 不写 poison 缓存, 保留 .fetching throttle 锁
#   G. 静态: _do_theme_change 链所有 & 后台必须 9>&- (不继承 flock FD);
#      auto on 已有实例(锁被占)时不 spawn、不写死 pid
# 运行: bash tests/theme-autofix_test.sh

SCRIPT="$HOME/.dwm/tools/theme.sh"
TEST_DIR=$(mktemp -d)
DAEMON=""

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm/cache"
echo '{"auto":{"enabled":true,"sun_rise_offset":0,"sun_set_offset":0}}' >"$HOME/.config/dwm/theme.json"
echo dark >"$HOME/.local/state/dwm/current-theme"

TODAY=$(/usr/bin/date +%F)
SR=$(/usr/bin/date -d "$TODAY 09:00" +%s)
SS=$(/usr/bin/date -d "$TODAY 18:00" +%s)
SR2=$(/usr/bin/date -d "$(/usr/bin/date -d "$TODAY +1 day" +%F) 09:00" +%s)
CACHE="$HOME/.local/state/dwm/cache/sun-times"
FETCH_LOCK="$CACHE.fetching"
printf '%s|%s|%s|%s\n' "$TODAY" "$SR" "$SS" "$SR2" >"$CACHE"

MOCK_NOW_FILE="$TEST_DIR/mock_now"
MOCK_TODAY_FILE="$TEST_DIR/mock_today"
MOCK_LOCK_FILE="$TEST_DIR/mock_locked"
echo "$SR" >"$MOCK_NOW_FILE"
echo "$TODAY" >"$MOCK_TODAY_FILE"
echo 0 >"$MOCK_LOCK_FILE"

set_now() { echo "$1" >"$MOCK_NOW_FILE"; }

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

# 默认 curl 失败 (模拟断网); 场景 F 按需改写
cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in
    *ipinfo.io*) echo "31.23,121.47"; exit 0 ;;
    *open-meteo*) printf '%s' "$CURL_API_BODY"; exit 0 ;;
    esac
done
exit 1
EOF

cat >"$BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
echo "notify-send $*" >>"$MOCK_LOG"
EOF

for c in xrdb dunstctl killall xsettingsd fcitx5 xrandr brightnessctl ddcutil; do
    cat >"$BIN/$c" <<EOF
#!/usr/bin/env bash
echo "$c \$*" >>"\$MOCK_LOG"
EOF
done
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
export THEME_LOCK="$TEST_DIR/theme-auto.lock"
export CURL_API_BODY=""
export MOCK_LOG="$TEST_DIR/log" \
    MOCK_NOW_FILE="$MOCK_NOW_FILE" MOCK_TODAY_FILE="$MOCK_TODAY_FILE" MOCK_LOCK_FILE="$MOCK_LOCK_FILE"

source "$SCRIPT"

_do_theme_change() { echo "theme_change $1" >>"$MOCK_LOG"; echo "$1" >"$HOME/.local/state/dwm/current-theme"; }
tool-notify() { echo "notify $*" >>"$MOCK_LOG"; }
system-notify() { echo "notify $*" >>"$MOCK_LOG"; }

fail=0
check() {
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

stop_daemon() {
    [ -n "$DAEMON" ] && kill "$DAEMON" 2>/dev/null
    [ -n "$DAEMON" ] && wait "$DAEMON" 2>/dev/null
    DAEMON=""
}
start_daemon() {
    auto_daemon >/dev/null 2>&1 &
    DAEMON=$!
}

# ---- 场景 D: 脏缓存(非数字) ----
stop_daemon
printf '%s|%s|%s|%s\n' "$TODAY" "abc" "def" "ghi" >"$CACHE"
echo dark >"$HOME/.local/state/dwm/current-theme"
set_now "$(/usr/bin/date -d "$TODAY 15:00" +%s)" # 白天, cur=dark: 旧代码 desired 坍缩 dark? 否→
: >"$MOCK_LOG"
start_daemon
/bin/sleep 0.3
check "D1 脏缓存时短轮询 (sleep 30), 不忙循环" "grep -q '^sleep 30\$' \"\$MOCK_LOG\""
check "D2 脏缓存时不切换" "! grep -q '^theme_change' \"\$MOCK_LOG\""
check "D3 脏缓存时无 SIGHUP" "! grep -q 'SIGHUP' \"\$MOCK_LOG\""
stop_daemon

# 脏缓存 + cur=light: 旧代码 desired 坍缩 dark → 每轮翻转+SIGHUP 风暴; 新代码应零切换
printf '%s|%s|%s|%s\n' "$TODAY" "abc" "def" "ghi" >"$CACHE"
echo light >"$HOME/.local/state/dwm/current-theme"
: >"$MOCK_LOG"
start_daemon
/bin/sleep 0.3
check "D4 脏缓存+cur=light 仍不切换 (无 SIGHUP 风暴)" \
    "! grep -q '^theme_change' \"\$MOCK_LOG\" && ! grep -q 'SIGHUP' \"\$MOCK_LOG\""
stop_daemon

# ---- 场景 E: enabled 缺失 → 重试不退出 ----
printf '%s|%s|%s|%s\n' "$TODAY" "$SR" "$SS" "$SR2" >"$CACHE"
echo '{"auto":{}}' >"$HOME/.config/dwm/theme.json"
echo dark >"$HOME/.local/state/dwm/current-theme"
set_now "$(/usr/bin/date -d "$TODAY 07:00" +%s)"
: >"$MOCK_LOG"
start_daemon
/bin/sleep 0.3
check "E1 enabled 缺失时 sleep 10 重试" "grep -q '^sleep 10\$' \"\$MOCK_LOG\""
check "E2 enabled 缺失时 daemon 存活 (未退出)" "kill -0 \"\$DAEMON\" 2>/dev/null"
# 恢复配置 → 应继续工作 (15:00 切 light)
echo '{"auto":{"enabled":true,"sun_rise_offset":0,"sun_set_offset":0}}' >"$HOME/.config/dwm/theme.json"
set_now "$(/usr/bin/date -d "$TODAY 15:00" +%s)"
/bin/sleep 0.3
check "E3 配置恢复后继续切换 (dark→light)" "grep -q '^theme_change light\$' \"\$MOCK_LOG\""
stop_daemon

# ---- 场景 F: 脏 API 响应 ----
rm -f "$CACHE" "$FETCH_LOCK"
echo dark >"$HOME/.local/state/dwm/current-theme"
set_now "$(/usr/bin/date -d "$TODAY 07:00" +%s)"
export CURL_API_BODY='this is not json'
: >"$MOCK_LOG"
start_daemon
/bin/sleep 0.5
check "F1 脏 API 不写 poison 缓存" "[ ! -f \"$CACHE\" ]"
check "F2 脏 API 保留 throttle 锁 (不 30s hammer)" "[ -f \"$FETCH_LOCK\" ]"
check "F3 脏 API 时不切换" "! grep -q '^theme_change' \"\$MOCK_LOG\""
stop_daemon
export CURL_API_BODY=""

# ---- 场景 G: 静态守卫 ----
# _do_theme_change 调用链 (set_fcitx5_theme/set_gtk_theme/_do_theme_change) 内所有行尾
# 单个 & 后台 (排除 && 续行) 必须带 9>&-, 否则孤儿进程继承 flock FD 9 致新 daemon 秒退
check "G1 后台 spawn 均带 9>&- (不继承 flock FD)" \
    "[ -z \"\$(awk '/^set_fcitx5_theme\\(\\)|^set_gtk_theme\\(\\)|^_do_theme_change\\(\\)/,/^}/' \"$SCRIPT\" | grep -E '(^|[^\&])&\\)?[[:space:]]*(#.*)?\$' | grep -v '9>&-')\" ]"
check "G2 auto_daemon 的 sleep 均带 9>&-" \
    "[ -z \"\$(awk '/^auto_daemon\\(\\)/,/^}/' \"$SCRIPT\" | grep -E '^[[:space:]]*sleep' | grep -v '9>&-')\" ]"

# ---- 场景 H: auto on 锁被占时不 spawn ----
HOLD_LOCK="$TEST_DIR/hold.lock"
export THEME_LOCK="$HOLD_LOCK"
flock -n "$HOLD_LOCK" /bin/sleep 30 &
HOLDER=$!
/bin/sleep 0.2
PF="/tmp/dwm-status/autostart-launch-theme-auto.pid"
PF_HAD=0; PF_SAVED=""
if [ -f "$PF" ]; then PF_HAD=1; PF_SAVED=$(cat "$PF"); rm -f "$PF"; fi
# (真实 pf 暂移开: 否则 live daemon 的 pid 会让新旧代码都提前 exit 0, 测不到 flock 探针路径)
PF_BEFORE=""; [ -f "$PF" ] && PF_BEFORE=$(cat "$PF")
: >"$MOCK_LOG"
bash "$SCRIPT" auto on >/dev/null 2>&1
ON_STATUS=$?
PF_AFTER=""; [ -f "$PF" ] && PF_AFTER=$(cat "$PF")
check "H1 锁被占时 auto on 退出 0" "[ \"$ON_STATUS\" = \"0\" ]"
check "H2 锁被占时不复写 pid 文件 (无死 pid)" "[ \"$PF_BEFORE\" = \"$PF_AFTER\" ]"
kill "$HOLDER" 2>/dev/null
wait "$HOLDER" 2>/dev/null
# 还原真实 pid 文件 (旧代码 bug 会新建污染它)
rm -f "$PF"
if [ "$PF_HAD" = "1" ]; then echo "$PF_SAVED" >"$PF"; fi
export THEME_LOCK="$TEST_DIR/theme-auto.lock"

exit $fail
