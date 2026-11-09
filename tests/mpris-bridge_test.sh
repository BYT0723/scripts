#!/usr/bin/env bash
# mpd.sh MPRIS 桥同步测试 (source + mock, 无 MPD/rofi/D-Bus/systemd)
# 运行: bash tests/mpris-bridge_test.sh
# 行为: 启动/停止经 systemctl --user 管理 mpd.service / mpdris2-rs.service (幂等);
# 通知模板由 repo 生成为 mpdris2-rs.service drop-in, 改了才 reload+restart;
# mpdris2 (python 版) 已移除, 仅支持 mpdris2-rs。

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

# ---- 隔离 HOME / XDG (drop-in 生成到隔离的 config 目录) ----
export HOME="$TEST_DIR/home"
export XDG_CACHE_HOME="$TEST_DIR/cache"
export XDG_CONFIG_HOME="$TEST_DIR/config"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
OVERRIDE="$XDG_CONFIG_HOME/systemd/user/mpdris2-rs.service.d/override.conf"

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
export SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
export NOTIFY_LOG="$TEST_DIR/notify.log"
: >"$SYSTEMCTL_LOG" >"$NOTIFY_LOG"

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
cat >"$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$SYSTEMCTL_LOG"
[[ "$*" == *"start mpd.service"* ]] && touch "$MOCK_STATE_DIR/mpd_up"
exit 0
EOF
cat >"$FAKE_BIN/mpdris2-rs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$FAKE_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >>"$NOTIFY_LOG"
EOF
chmod +x "$FAKE_BIN"/*
export PATH="$FAKE_BIN:$PATH"

# ---- 场景 PATH (hermetic): 被测脚本只能看到这里的二进制 ----
# 本机 /usr/bin 自带 mpdris2-rs, chmod 盖不住它穿透 command -v, 故 source 时用窄 PATH
SCEN_BIN="$TEST_DIR/scenbin"
mkdir -p "$SCEN_BIN"
for _n in mpc systemctl notify-send; do ln -s "$FAKE_BIN/$_n" "$SCEN_BIN/$_n"; done
ln -s "$(command -v head)" "$SCEN_BIN/head"
ln -s "$(command -v dirname)" "$SCEN_BIN/dirname" # 被测脚本顶层 ROFI_DIR 解析必需
ln -s "$(command -v bash)" "$SCEN_BIN/bash"
ln -s "$(command -v env)" "$SCEN_BIN/env"
for _n in touch rm mkdir; do ln -s "$(command -v "$_n")" "$SCEN_BIN/$_n"; done # mock 与 EXIT trap 用的 harness 工具 (非桥逻辑, 不影响隔离性)
link_bridge() { # 有参=有 mpdris2-rs, 空参=缺失
    rm -f "$SCEN_BIN/mpdris2-rs"
    for _b in "$@"; do ln -s "$FAKE_BIN/$_b" "$SCEN_BIN/$_b"; done
}

reset_state() { # [mpd_up] — 重置 MPD/日志/桥链接, 保留已生成的 drop-in
    rm -f "$MOCK_STATE_DIR/mpd_up"
    [[ "${1:-}" == "up" ]] && touch "$MOCK_STATE_DIR/mpd_up"
    : >"$SYSTEMCTL_LOG" >"$NOTIFY_LOG"
    link_bridge # 默认无桥, 各场景显式 link
}

reset_config() { # 清掉已生成的 drop-in (模拟首次运行 / 恢复备份后)
    rm -rf "$XDG_CONFIG_HOME/systemd"
}

run_mpd_menu() {
    PATH="$SCEN_BIN" source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null
    wait 2>/dev/null
}

# ---- S1: MPD 由菜单拉起时经 systemctl 启动; 首次生成 drop-in + reload/restart ----
reset_config
reset_state
link_bridge mpdris2-rs
run_mpd_menu
assert_cond "S1: mpd 被拉起" '[ -f "$MOCK_STATE_DIR/mpd_up" ]'
assert_cond "S1: systemctl 启动 mpd" 'grep -q "systemctl --user start mpd.service" "$SYSTEMCTL_LOG"'
assert_cond "S1: 生成 user drop-in" '[ -f "$OVERRIDE" ]'
assert_cond "S1: drop-in 重置 ExecStart" 'grep -qx "ExecStart=" "$OVERRIDE"'
assert_cond "S1: 模板写入 argv (% 转义为 %%)" \
    'grep -qF "ExecStart=/usr/bin/mpdris2-rs" "$OVERRIDE" && grep -qF "%%state%%" "$OVERRIDE" && grep -qF "%%title%%" "$OVERRIDE"'
assert_cond "S1: 正文换行保留为 \\n" 'grep -qF "\n%%artist%%" "$OVERRIDE"'
assert_cond "S1: reload 后 restart 桥" \
    'grep -q "systemctl --user daemon-reload" "$SYSTEMCTL_LOG" && grep -q "systemctl --user restart mpdris2-rs.service" "$SYSTEMCTL_LOG"'

# ---- S2: 模板未变则不重写/reload/restart, 桥 start 幂等下发 ----
reset_state up
link_bridge mpdris2-rs
run_mpd_menu
assert_cond "S2: 不重复 start mpd" '! grep -q "start mpd.service" "$SYSTEMCTL_LOG"'
assert_cond "S2: 模板未变不 daemon-reload" '! grep -q "daemon-reload" "$SYSTEMCTL_LOG"'
assert_cond "S2: 桥 start 照发 (systemd 幂等)" 'grep -q "systemctl --user start mpdris2-rs.service" "$SYSTEMCTL_LOG"'
assert_cond "S2: 不 restart 桥" '! grep -q "restart mpdris2-rs" "$SYSTEMCTL_LOG"'

# ---- S3: 缺失 mpdris2-rs 通知且菜单继续 ----
reset_state up
run_mpd_menu
assert_cond "S3: 通知提示安装 mpdris2-rs" 'grep -q "mpdris2-rs" "$NOTIFY_LOG"'
assert_cond "S3: 缺失时不调 systemctl 桥" '! grep -q "mpdris2-rs.service" "$SYSTEMCTL_LOG"'
assert_eq "$status" "playing" "S3: 通知后菜单逻辑继续 (status 可用)"

# ---- S4: kill 路径经 systemctl 停桥+停 MPD (先桥后面) ----
kill_line="$(grep -F 'ST_MPD,$middle' "$STATUSCMD")"
assert_cond "S4: kill 行停 mpdris2-rs" '[[ "$kill_line" == *"systemctl --user stop mpdris2-rs.service"* ]]'
assert_cond "S4: kill 行停 mpd" '[[ "$kill_line" == *"mpd.service"* ]]'
assert_cond "S4: 不再用 mpd --kill" '[[ "$kill_line" != *"mpd --kill"* ]]'
assert_cond "S4: 不再 pkill 桥" '[[ "$kill_line" != *"pkill"* ]]'
kill_action="$(printf '%s' "$kill_line" | sed -n "s/.*middle\]='\(.*\)'/\1/p")"
: >"$SYSTEMCTL_LOG"
PATH="$FAKE_BIN:$PATH" eval "$kill_action" # mock 优先: PATH 前置使 systemctl 走 mock, 不碰用户真服务
assert_cond "S4: eval 停掉桥与 MPD" 'grep -q "systemctl --user stop mpdris2-rs.service mpd.service" "$SYSTEMCTL_LOG"'

# ---- S5: drop-in 内容漂移 → 重写 + daemon-reload + restart ----
reset_state up
link_bridge mpdris2-rs
printf '[Service]\n' >"$OVERRIDE"
run_mpd_menu
assert_cond "S5: 漂移的 drop-in 被重建" 'grep -qF "%%title%%" "$OVERRIDE"'
assert_cond "S5: 变更后 reload + restart" \
    'grep -q "daemon-reload" "$SYSTEMCTL_LOG" && grep -q "restart mpdris2-rs.service" "$SYSTEMCTL_LOG"'

if [[ "$FAIL" -eq 0 ]]; then echo "ALL PASS"; else echo "FAILURES PRESENT"; fi
exit "$FAIL"
