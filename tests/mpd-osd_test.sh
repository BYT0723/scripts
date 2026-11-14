#!/usr/bin/env bash
# mpd.sh OSD Lyrics 开关测试 (source + mock, 无 MPD/rofi/D-Bus)
# 运行: bash tests/mpd-osd_test.sh

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$TEST_ROOT/rofi/scripts/mpd.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

FAIL=0
assert_cond() { # msg cond
    if eval "$2"; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        FAIL=1
    fi
}

# ---- 隔离 HOME/XDG ----
export HOME="$TEST_DIR/home"
export XDG_CONFIG_HOME="$TEST_DIR/config"
export XDG_CACHE_HOME="$TEST_DIR/cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

# ---- mock ROFI_DIR 结构 ----
MOCK_ROFI="$TEST_DIR/rofi"
mkdir -p "$MOCK_ROFI/scripts" "$MOCK_ROFI/applets/type-5" "$MOCK_ROFI/images"
cp "$SCRIPT" "$MOCK_ROFI/scripts/mpd.sh"

cat >"$MOCK_ROFI/scripts/util.sh" <<'EOF'
icon() { echo ""; }
EOF

cat >"$MOCK_ROFI/scripts/lib-module.sh" <<'EOF'
module_parse() { :; }
module_loop() { :; }
EOF

cat >"$MOCK_ROFI/applets/type-5/style-2.rasi" <<'EOF'
* { USE_ICON = NO; }
EOF

FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
export BUSCTL_LOG="$TEST_DIR/busctl.log"
export SET_LOG="$TEST_DIR/set.log"
export SETSID_LOG="$TEST_DIR/setsid.log"
export NOTIFY_LOG="$TEST_DIR/notify.log"
export EVENT_LOG="$TEST_DIR/event.log"
export STATUS_COUNT="$TEST_DIR/status.count"

# mpc: 固定状态; %file% 为空 → 不触发封面拉取
cat >"$FAKE_BIN/mpc" <<'EOF'
#!/usr/bin/env bash
case "$*" in
"status %state%") echo playing ;;
"status %repeat%") echo on ;;
"status %random%") echo off ;;
"status %single%") echo off ;;
"-f %title% current") echo "Title" ;;
"-f %artist% current") echo "Artist" ;;
"-f %file% current") echo "" ;;
"status %currenttime%/%totaltime%") echo "1:00/3:00" ;;
*) exit 0 ;;
esac
EOF

# 进程存在性由测试变量驱动
cat >"$FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "${MOCK_OSD_RUNNING:-0}" == "1" ]]
EOF

# D-Bus Config 服务: GetBool 返回 MOCK_OSD_STATE; status 按次数模拟 Daemon 就绪
cat >"$FAKE_BIN/busctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BUSCTL_LOG"
if [[ "$*" == *" status "* ]]; then
    printf 'status\n' >>"$EVENT_LOG"
    n=$(cat "$STATUS_COUNT" 2>/dev/null || echo 0)
    n=$((n + 1))
    printf '%s\n' "$n" >"$STATUS_COUNT"
    [[ "$n" -ge "${MOCK_DAEMON_READY_AFTER:-1}" ]]
    exit
fi
case "$*" in
*" GetBool "*)
    printf 'b %s\n' "${MOCK_OSD_STATE:-true}"
    ;;
*" SetBool "*)
    printf '%s\n' "$*" >>"$SET_LOG"
    printf 'set %s\n' "${!#}" >>"$EVENT_LOG"
    [[ "${MOCK_BUSCTL_FAIL:-0}" == "1" ]] && exit 1
    ;;
esac
exit 0
EOF

cat >"$FAKE_BIN/setsid" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SETSID_LOG"
printf 'setsid %s\n' "$*" >>"$EVENT_LOG"
exit 0
EOF

printf '#!/usr/bin/env bash\nexit 0\n' >"$FAKE_BIN/osdlyrics"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$NOTIFY_LOG"\n' >"$FAKE_BIN/notify-send"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FAKE_BIN/systemctl"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FAKE_BIN/mpdris2-rs"
chmod +x "$FAKE_BIN"/*

export PATH="$FAKE_BIN:$PATH"
# shellcheck disable=SC2068
source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null

# ---- 1. 状态读取 ----
export MOCK_OSD_RUNNING=1 MOCK_OSD_STATE=true
assert_cond "状态: 运行中且 OSD 开 → _osd_on 返回 0" "_osd_on"

export MOCK_OSD_STATE=false
assert_cond "状态: 运行中且 OSD 关 → _osd_on 返回非 0" "! _osd_on"

# 未运行时不触碰 Config 服务 (避免自动激活 ini_config daemon)
export MOCK_OSD_RUNNING=0
: >"$BUSCTL_LOG"
_osd_on || true
assert_cond "状态: 进程未运行 → 不调用 busctl" "! grep -q 'GetBool' \"\$BUSCTL_LOG\""

# ---- 2. 菜单高亮 ----
export MOCK_OSD_RUNNING=1 MOCK_OSD_STATE=true
source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null
assert_cond "菜单: OSD 开 → active 含索引 7" "[[ \",\$MODULE_ACTIVE,\" == *',7,'* ]]"
assert_cond "菜单: OSD 关 → urgent 不含索引 7" "[[ \",\$MODULE_URGENT,\" != *',7,'* ]]"

export MOCK_OSD_STATE=false
source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null
assert_cond "菜单: OSD 关 → active 不含索引 7" "[[ \",\$MODULE_ACTIVE,\" != *',7,'* ]]"
assert_cond "菜单: OSD 关 → 不高亮 (普通态)" "[[ \",\$MODULE_URGENT,\" != *',7,'* ]]"

# ---- 3. handler: 运行中翻转 ----
export MOCK_OSD_RUNNING=1 MOCK_OSD_STATE=true
: >"$SET_LOG"
handle_osd_lyrics
assert_cond "handler: OSD 开 → SetBool false" "grep -q 'SetBool sb General/display-mode-osd false' \"\$SET_LOG\""

export MOCK_OSD_STATE=false
: >"$SET_LOG"
handle_osd_lyrics
assert_cond "handler: OSD 关 → SetBool true" "grep -q 'SetBool sb General/display-mode-osd true' \"\$SET_LOG\""

# ---- 4. handler: 未运行 → 先拉起, 等 Daemon 就绪后再开 OSD ----
export MOCK_OSD_RUNNING=0 MOCK_OSD_STATE=false MOCK_DAEMON_READY_AFTER=3
: >"$SET_LOG"
: >"$SETSID_LOG"
: >"$EVENT_LOG"
: >"$STATUS_COUNT"
handle_osd_lyrics
assert_cond "handler: 未运行 → 先拉起 osdlyrics" "head -1 \"\$EVENT_LOG\" | grep -q '^setsid'"
assert_cond "handler: 等待 Daemon 3 次探测" "[[ \"\$(cat \"\$STATUS_COUNT\")\" == 3 ]]"
assert_cond "handler: Daemon 就绪后 SetBool true" "grep -q '^set true\$' \"\$EVENT_LOG\""
assert_cond "handler: SetBool 在启动之后" \
    "[[ \"\$(head -1 \"\$EVENT_LOG\")\" == setsid* ]] && [[ \"\$(tail -1 \"\$EVENT_LOG\")\" == 'set true' ]]"
export MOCK_DAEMON_READY_AFTER=1

# ---- 5. 失败路径 ----
export MOCK_OSD_RUNNING=1 MOCK_OSD_STATE=true MOCK_BUSCTL_FAIL=1
: >"$NOTIFY_LOG"
handle_osd_lyrics
assert_cond "失败: SetBool 失败 → 通知" "grep -q 'Failed to toggle' \"\$NOTIFY_LOG\""

export MOCK_BUSCTL_FAIL=0
export MOCK_OSD_RUNNING=0
# 临时遮蔽 command -v osdlyrics, 模拟未安装 (PATH 里仍有真实 osdlyrics)
command() {
    [[ "$1" == "-v" && "$2" == "osdlyrics" ]] && return 1
    builtin command "$@"
}
: >"$NOTIFY_LOG"
handle_osd_lyrics
unset -f command
assert_cond "失败: 未安装 osdlyrics → 通知" "grep -q 'osdlyrics not found' \"\$NOTIFY_LOG\""

echo
if [[ "$FAIL" == "0" ]]; then
    echo "ALL PASS"
else
    echo "SOME FAILED"
    exit 1
fi
