#!/usr/bin/env bash
# wallpaper daemon 重启幂等回归测试:
#   热重启 (dwm SIGHUP) 会重跑 autostart.sh → `wallpaper.sh -r`。
#   launch_wallpaper 曾无条件 pkill xwallpaperd 再起新实例, 窗口销毁重建多闪一次。
#   现 ensure_xwallpaperd: daemon 存活直接复用 (零 pkill/零启动), 仅死亡才拉起。
#   1. daemon 存活 → 无 pkill、无启动, 返回 0
#   2. daemon 死亡 → 拉起 xwallpaperd, 返回 0
# 运行: bash tests/wallpaper-restart_test.sh

LIB="$HOME/.dwm/tools/wallpaper-lib.sh"
WALLPAPER_SH="$HOME/.dwm/tools/wallpaper.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm" "$HOME/.cache/wallpaper"
printf '{"monitors": {}, "groups": {}}\n' >"$HOME/.config/dwm/wallpaper.json"

BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

export DAEMON_ALIVE_FLAG="$TEST_DIR/alive"
export MOCK_LOG="$TEST_DIR/mock.log"
: >"$MOCK_LOG"
cat >"$BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-x" ] && [ "$2" = "xwallpaperd" ]; then
    [ -f "$DAEMON_ALIVE_FLAG" ] && exit 0 || exit 1
fi
exit 1
EOF
cat >"$BIN/pkill" <<'EOF'
#!/usr/bin/env bash
echo "pkill $*" >>"$MOCK_LOG"
exit 0
EOF
cat >"$BIN/xwallpaperd" <<'EOF'
#!/usr/bin/env bash
echo "xwallpaperd started" >>"$MOCK_LOG"
exit 0
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

set --
# shellcheck disable=SC1090
source "$LIB"
# 只取 ensure  helper, 不触发 wallpaper.sh 底部分派, 不启动无限循环的 launch_wallpaper
eval "$(awk '/^ensure_xwallpaperd\(\) \{/,/^}$/' "$WALLPAPER_SH")"

fail=0
check() {
    if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

# ---- 1. daemon 存活 → 复用, 零 pkill/零启动 ----
touch "$DAEMON_ALIVE_FLAG"
: >"$MOCK_LOG"
ensure_xwallpaperd
rc=$?
check "存活时返回 0" "[ $rc -eq 0 ]"
check "存活时无 pkill" "! grep -q '^pkill' \"$MOCK_LOG\""
check "存活时不起新 daemon" "! grep -q 'xwallpaperd started' \"$MOCK_LOG\""

# ---- 2. daemon 死亡 → 拉起 ----
rm -f "$DAEMON_ALIVE_FLAG"
: >"$MOCK_LOG"
ensure_xwallpaperd
rc=$?
check "死亡时返回 0" "[ $rc -eq 0 ]"
check "死亡时拉起 daemon" "grep -q 'xwallpaperd started' \"$MOCK_LOG\""

# ---- 3. launch_wallpaper 经 ensure 复用 (静态守卫: 无裸 pkill xwallpaperd) ----
check "launch 体内无裸 pkill xwallpaperd" "! awk '/^launch_wallpaper\\(\\) \\{/,/^}$/' \"$WALLPAPER_SH\" | grep -q 'pkill -x xwallpaperd'"
check "launch 经 ensure 拉起" "grep -q 'ensure_xwallpaperd' \"$WALLPAPER_SH\""

exit "$fail"
