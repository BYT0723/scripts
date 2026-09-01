#!/usr/bin/env bash
# monitor-brightness.sh + theme.sh set_monitor_brightness 回归测试:
#   A. brightness 缺失 / 非数字 / >100 → 早退, 不触发任何命令
#   B. 正常设置: brightnessctl 遍历 backlight 设备 + ddcutil 仅对 DDC 显示器设硬件亮度 (无 DDC 面板跳过)
#   C. toggle_monitor 开/关切换 (含 state 目录自动创建)
# 运行: bash tests/monitor-brightness_test.sh

SCRIPT="$HOME/.dwm/tools/theme.sh"
TEST_DIR=$(mktemp -d)

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm"

# ---- mock 外部命令 ----
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

cat >"$BIN/brightnessctl" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-l" ]; then
    echo "Available devices:"
    echo "Device 'amdgpu_bl1' of class 'backlight':"
    echo "	Current brightness: 19984 (32%)"
    echo "	Max brightness: 62451"
    echo ""
    echo "Device 'input33::capslock' of class 'leds':"
    echo "	Current brightness: 0 (0%)"
    echo "	Max brightness: 1"
    exit 0
fi
echo "brightnessctl $*" >>"$MOCK_LOG"
EOF

cat >"$BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
case "$1" in
--listactivemonitors)
    echo "Monitors: 2"
    echo " 0: +*eDP 2304/336x1440/210+0+0  eDP"
    echo " 1: +DisplayPort-0 2560/526x1440/296+1080+0  DisplayPort-0"
    ;;
--props)
    echo "eDP connected primary 2304x1440+0+0 (normal left inverted right x axis y axis) 336mm x 210mm"
    echo "	CONNECTOR_ID: 0xe005"
    echo "DisplayPort-0 connected primary 2560x1440+1080+0 (normal left inverted right x axis y axis) 526mm x 296mm"
    echo "	CONNECTOR_ID: 15"
    ;;
--verbose)
    echo "eDP connected primary 2304x1440+0+0 (normal left inverted right x axis y axis) 336mm x 210mm"
    echo "	Brightness: 1.0"
    echo "DisplayPort-0 connected primary 2560x1440+1080+0 (normal left inverted right x axis y axis) 526mm x 296mm"
    echo "	Brightness: 0.8"
    ;;
--output)
    echo "xrandr $*" >>"$MOCK_LOG"
    ;;
esac
EOF

cat >"$BIN/ddcutil" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "detect" ]; then
    echo "Display 1"
    echo "	I2C bus: /dev/i2c-9"
    echo "	drm_connector_id: 15"
    echo "Display 2"
    echo "	Invalid display"
    exit 0
fi
echo "ddcutil $*" >>"$MOCK_LOG"
EOF

chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
export MOCK_LOG="$TEST_DIR/log"
: >"$MOCK_LOG"

set --   # 清空位置参数, 避免误触发 theme.sh 的 case 分派
source "$SCRIPT"

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}

set_theme() { printf '%s\n' "$1" >"$HOME/.config/dwm/theme.json"; }
reset_log() { : >"$MOCK_LOG"; }

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# ---- A: 早退分支 (不触发任何命令) ----
set_theme '{"light":{}}'
set_monitor_brightness light
check "brightness 缺失 → 无命令调用" "[ ! -s \"\$MOCK_LOG\" ]"

reset_log
set_theme '{"light":{"brightness":"abc"}}'
set_monitor_brightness light
check "brightness 非数字 → 无命令调用" "[ ! -s \"\$MOCK_LOG\" ]"

reset_log
set_theme '{"light":{"brightness":150}}'
set_monitor_brightness light
check "brightness >100 → 无命令调用" "[ ! -s \"\$MOCK_LOG\" ]"

# ---- B: 正常设置 ----
reset_log
set_theme '{"dark":{"brightness":30}}'
set_monitor_brightness dark
check "遍历 backlight 设备设置亮度" "grep -q '^brightnessctl -d amdgpu_bl1 set 30%\$' \"\$MOCK_LOG\""
check "跳过非 backlight 设备 (leds 类)" "! grep -q capslock \"\$MOCK_LOG\""
check "DDC 显示器设置硬件亮度" "grep -q '^ddcutil --bus 9 setvcp 10 30\$' \"\$MOCK_LOG\""
check "仅 DDC 显示器调用 setvcp (无 DDC 面板跳过)" "[ \"\$(grep -c setvcp \"\$MOCK_LOG\")\" = 1 ]"

# ---- C: toggle_monitor ----
reset_log
rm -rf "$HOME/.local/state/dwm/status"
toggle_monitor eDP
check "toggle 开: 自动创建 state 目录并置黑" "[ -f \"\$HOME/.local/state/dwm/status/monitor-eDP\" ] && grep -q '^xrandr --output eDP --brightness 0\$' \"\$MOCK_LOG\""
check "toggle 开: 记录原亮度" "[ \"\$(cat \"\$HOME/.local/state/dwm/status/monitor-eDP\")\" = 1.0 ]"

reset_log
toggle_monitor eDP
check "toggle 关: 恢复亮度并删除 state" "[ ! -f \"\$HOME/.local/state/dwm/status/monitor-eDP\" ] && grep -q '^xrandr --output eDP --brightness 1.0\$' \"\$MOCK_LOG\""

exit $fail
