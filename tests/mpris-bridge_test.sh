#!/usr/bin/env bash
# mpd.sh MPRIS 桥同步测试 (source + mock, 无 MPD/rofi/D-Bus)
# 运行: bash tests/mpris-bridge_test.sh

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$TEST_ROOT/rofi/scripts/mpd.sh"
STATUSCMD="$TEST_ROOT/dwm-statuscmd.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

FAIL=0
assert_eq() { # got want msg
    if [[ "$1" == "$2" ]]; then
        echo "ok: $3"
    else
        echo "FAIL: $3"
        echo "  got : $(printf '%q' "$1")"
        echo "  want: $(printf '%q' "$2")"
        FAIL=1
    fi
}
assert_cond() { # msg cond
    if eval "$2"; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        FAIL=1
    fi
}

# ---- 隔离 HOME ----
export HOME="$TEST_DIR/home"
export XDG_CACHE_HOME="$TEST_DIR/cache"
mkdir -p "$HOME" "$XDG_CACHE_HOME"

# ---- 搭 mock ROFI_DIR 结构 ----
MOCK_ROFI="$TEST_DIR/rofi"
mkdir -p "$MOCK_ROFI/scripts" "$MOCK_ROFI/applets/type-2" "$MOCK_ROFI/images"
cp "$SCRIPT" "$MOCK_ROFI/scripts/mpd.sh"
cat >"$MOCK_ROFI/scripts/util.sh" <<'EOF'
icon() { echo ""; }
EOF
cat >"$MOCK_ROFI/scripts/lib-module.sh" <<'EOF'
module_parse() { :; }
module_loop() { :; }
EOF

# ---- FAKE_BIN: 日志型 mock ----
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
export MOCK_STATE_DIR="$TEST_DIR/state"
mkdir -p "$MOCK_STATE_DIR"
export MPD_LOG="$TEST_DIR/mpd.log" PGREP_LOG="$TEST_DIR/pgrep.log"
export PKILL_LOG="$TEST_DIR/pkill.log" BRIDGE_LOG="$TEST_DIR/bridge.log"
export NOTIFY_LOG="$TEST_DIR/notify.log"
: >"$MPD_LOG" >"$PGREP_LOG" >"$PKILL_LOG" >"$BRIDGE_LOG" >"$NOTIFY_LOG"

cat >"$FAKE_BIN/mpc" <<'EOF'
#!/usr/bin/env bash
up() { [[ -f "${MOCK_STATE_DIR:-/nonexistent}/mpd_up" ]]; }
case "$*" in
"status") up && printf 'volume: 80%%\n[playing] #1/1 0:00/0:00 (0%%)\n' || exit 1 ;;
*"status %state%"*) up && echo "playing" || exit 1 ;;
*"status %repeat%"* | *"status %random%"* | *"status %single%"*) up && echo "off" || exit 1 ;;
*"%currenttime%/%totaltime%"*) up && echo "0:00/0:00" || exit 1 ;;
*"-f %title% current"* | *"-f %artist% current"* | *"-f %file% current"*) up && echo "" || exit 1 ;;
*) exit 0 ;;
esac
EOF
cat >"$FAKE_BIN/mpd" <<'EOF'
#!/usr/bin/env bash
printf 'mpd %s\n' "$*" >>"$MPD_LOG"
touch "$MOCK_STATE_DIR/mpd_up"
EOF
cat >"$FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >>"$PGREP_LOG"
[[ " ${MOCK_PGREP_RUNNING:-} " == *" $2 "* ]]
EOF
cat >"$FAKE_BIN/pkill" <<'EOF'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >>"$PKILL_LOG"
exit 0
EOF
cat >"$FAKE_BIN/mpdris2-rs" <<'EOF'
#!/usr/bin/env bash
printf 'mpdris2-rs %s\n' "$*" >>"$BRIDGE_LOG"
EOF
cat >"$FAKE_BIN/mpdris2" <<'EOF'
#!/usr/bin/env bash
printf 'mpdris2 %s\n' "$*" >>"$BRIDGE_LOG"
EOF
cat >"$FAKE_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >>"$NOTIFY_LOG"
EOF
chmod +x "$FAKE_BIN"/*
export PATH="$FAKE_BIN:$PATH"

# ---- 场景 PATH (hermetic): 被测脚本只能看到这里的桥 ----
# 本机 /usr/bin 自带 mpdris2-rs, chmod 盖不住它穿透 command -v, 故 source 时用窄 PATH
SCEN_BIN="$TEST_DIR/scenbin"
mkdir -p "$SCEN_BIN"
for _n in mpc mpd pgrep pkill notify-send; do ln -s "$FAKE_BIN/$_n" "$SCEN_BIN/$_n"; done
ln -s "$(command -v head)" "$SCEN_BIN/head"
ln -s "$(command -v dirname)" "$SCEN_BIN/dirname" # 被测脚本顶层 ROFI_DIR 解析必需
ln -s "$(command -v bash)" "$SCEN_BIN/bash"
ln -s "$(command -v env)" "$SCEN_BIN/env"
for _n in touch rm mkdir; do ln -s "$(command -v "$_n")" "$SCEN_BIN/$_n"; done # mock 与 EXIT trap 用的 harness 工具 (非桥逻辑, 不影响隔离性)
link_bridges() { # names... (空参=无桥)
    rm -f "$SCEN_BIN/mpdris2-rs" "$SCEN_BIN/mpdris2"
    for _b in "$@"; do ln -s "$FAKE_BIN/$_b" "$SCEN_BIN/$_b"; done
}

reset_state() { # [running]
    rm -f "$MOCK_STATE_DIR/mpd_up"
    MOCK_PGREP_RUNNING="${1:-}"
    export MOCK_PGREP_RUNNING
    : >"$MPD_LOG" >"$PGREP_LOG" >"$PKILL_LOG" >"$BRIDGE_LOG" >"$NOTIFY_LOG"
    link_bridges # 默认无桥, 各场景显式 link
}

run_mpd_menu() {
    PATH="$SCEN_BIN" source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null
    wait 2>/dev/null
}

# ---- S1: MPD 由菜单拉起时桥同步启动 (mpdris2-rs 优先) ----
reset_state
link_bridges mpdris2-rs mpdris2
run_mpd_menu
assert_cond "S1: mpd 被拉起" '[ -f "$MOCK_STATE_DIR/mpd_up" ]'
assert_eq "$(cat "$BRIDGE_LOG")" "mpdris2-rs " "S1: mpdris2-rs 被启动一次"

# ---- S2: 桥已在运行则不重复启动 ----
reset_state "mpdris2-rs"
touch "$MOCK_STATE_DIR/mpd_up"
link_bridges mpdris2-rs mpdris2
run_mpd_menu
assert_eq "$(cat "$BRIDGE_LOG")" "" "S2: 桥已跑时零启动"

# ---- S2b: 无 rs 时回退 mpdris2 ----
reset_state
touch "$MOCK_STATE_DIR/mpd_up"
link_bridges mpdris2
run_mpd_menu
assert_eq "$(cat "$BRIDGE_LOG")" "mpdris2 " "S2b: 回退启动 mpdris2"

# ---- S3: 双缺失通知且菜单继续 ----
reset_state
touch "$MOCK_STATE_DIR/mpd_up"
run_mpd_menu
assert_cond "S3: 通知提示安装其一" 'grep -q "mpdris2" "$NOTIFY_LOG"'
assert_eq "$status" "playing" "S3: 通知后菜单逻辑继续 (status 可用)"

# ---- S4: kill 路径同步杀桥 ----
kill_line="$(grep -F 'ST_MPD,$middle' "$STATUSCMD")"
assert_cond "S4: kill 行含 pkill mpdris2-rs" '[[ "$kill_line" == *"pkill -x mpdris2-rs"* ]]'
assert_cond "S4: kill 行含 pkill mpdris2" '[[ "$kill_line" == *"pkill -x mpdris2"* ]]'
assert_cond "S4: mpd --kill 仍在串首" '[[ "$kill_line" == *"mpd --kill"* ]]'
kill_action="$(printf '%s' "$kill_line" | sed -n "s/.*middle\]='\(.*\)'/\1/p")"
: >"$MPD_LOG" >"$PKILL_LOG"
PATH="$FAKE_BIN:$PATH" eval "$kill_action" # mock 优先: 防真 mpd --kill 误伤用户 daemon
assert_cond "S4: eval 关掉 mpd" 'grep -q "^mpd --kill" "$MPD_LOG"'
assert_cond "S4: eval 杀 mpdris2-rs" 'grep -q "pkill -x mpdris2-rs" "$PKILL_LOG"'
assert_cond "S4: eval 杀 mpdris2" 'grep -q "pkill -x mpdris2$" "$PKILL_LOG"'

if [[ "$FAIL" -eq 0 ]]; then echo "ALL PASS"; else echo "FAILURES PRESENT"; fi
exit "$FAIL"
