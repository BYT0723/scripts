#!/usr/bin/env bash
# rofi/scripts/theme.sh handle_monitor_brightness 回归测试:
#   A. 拖动滑块后 OK → 实时设置亮度 + 保存硬件实际亮度到 theme.json
#   B. 取消 (ESC) → 恢复原亮度, 不写入配置
#   C. DDC monitor 拖动 → drain 丢弃积压只调用一次 setvcp
#   函数为 while 循环 (可连续调节多显示器), module_sub_rofi 用文件标记
#   "第一次选 monitor, 之后返回空模拟 ESC 退出循环"
#
# 背景: 原实现用 coproc + wait "$YAD_PID" 取退出码, 但 bash 在读完全部
# coproc 输出后可能清理 YAD_PID (wait 时为空 → 退出码误判走恢复分支);
# 且 while read 最后一次读到 EOF 时会把 $value 清空 (循环外 $value 必空)。
# 重构为 FIFO + 后台 pid ($!), 并在循环内用 $last 记录最终值。
#
# 因 rofi/scripts/theme.sh 顶层有 module_loop 阻塞, 无法整体 source,
# 这里用 awk 提取目标函数 + 手动 source 其依赖脚本。
# 运行: bash tests/rofi-theme-monitor-brightness_test.sh

DWM="$HOME/.dwm"
TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm"

# ---- mock 外部命令 ----
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

cat >"$BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
case "$1" in
--listactivemonitors)
    echo "Monitors: 1"
    echo " 0: +*eDP 2304/336x1440/210+0+0  eDP"
    ;;
--props)
    echo "DisplayPort-0 connected primary 2560x1440+1080+0"
    echo "	CONNECTOR_ID: 15"
    ;;
esac
EOF

cat >"$BIN/brightnessctl" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ]; then
    echo "class,subsys,sysfs,30%,10%"
    exit 0
fi
echo "brightnessctl $*" >>"$MOCK_LOG"
EOF

cat >"$BIN/yad" <<'EOF'
#!/usr/bin/env bash
printf '40\n30\n'
exit 0
EOF

cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
export MOCK_LOG="$TEST_DIR/log"
: >"$MOCK_LOG"

source "$DWM/rofi/scripts/util.sh"
source "$DWM/rofi/scripts/lib-module.sh"
source "$DWM/tools/theme.sh"

awk '/^handle_monitor_brightness\(\) \{/{f=1} f{print} f && /^\}$/{exit}' \
    "$DWM/rofi/scripts/theme.sh" >"$TEST_DIR/handler.txt"
eval "$(cat "$TEST_DIR/handler.txt")"

get_cur() { cat "$HOME/.local/state/dwm/current-theme" 2>/dev/null; }
# module_sub_rofi 在命令替换的管道子 shell 中运行, 变量不共享,
# 用文件记录"已选过一次"(第一次返回 monitor, 之后返回空模拟 ESC 退出循环)
SEL_FLAG="$TEST_DIR/sel.flag"
module_sub_rofi() {
    [ -e "$SEL_FLAG" ] && return
    touch "$SEL_FLAG"
    printf '󰍹 eDP 50'
}

printf 'light\n' >"$HOME/.local/state/dwm/current-theme"
printf '{"light":{}}\n' >"$HOME/.config/dwm/theme.json"

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}
reset_log() { : >"$MOCK_LOG"; }

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# ---- A: 拖动滑块后 OK → 实时设置 + 保存硬件实际亮度 ----
handle_monitor_brightness
check "循环收到实时值 (set 40% 和 30%)" "grep -q 'set 40%' \$MOCK_LOG && grep -q 'set 30%' \$MOCK_LOG"
check "OK 后保存硬件实际值 30" "[ \"\$(jq -r '.light.brightness.eDP' \"\$HOME/.config/dwm/theme.json\")\" = 30 ]"

# ---- B: 取消 (yad 无输出, exit 1) → 恢复原亮度, 不写入配置 ----
cat >"$BIN/yad" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
rm -f "$SEL_FLAG"
printf '{"light":{}}\n' >"$HOME/.config/dwm/theme.json"
reset_log
handle_monitor_brightness
check "取消分支恢复原亮度 50" "grep -q 'set 50%' \$MOCK_LOG"
check "取消分支不写入配置" "[ \"\$(jq -r '.light.brightness.eDP // \"none\"' \"\$HOME/.config/dwm/theme.json\")\" = none ]"

# ---- C: DDC monitor 拖动 → drain 丢弃积压, setvcp 只调用一次最新值 ----
rm -f "$SEL_FLAG"
module_sub_rofi() {
    [ -e "$SEL_FLAG" ] && return
    touch "$SEL_FLAG"
    printf '󰍹 DisplayPort-0 50'
}
cat >"$BIN/yad" <<'EOF'
#!/usr/bin/env bash
printf '40\n30\n20\n'
exit 0
EOF
cat >"$BIN/ddcutil" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "detect" ]; then
    echo "Display 1"
    echo "  I2C bus: /dev/i2c-9"
    echo "  drm_connector_id: 15"
    exit 0
fi
echo "ddcutil $*" >>"$MOCK_LOG"
EOF
chmod +x "$BIN/ddcutil"
printf '{"light":{}}\n' >"$HOME/.config/dwm/theme.json"
reset_log
handle_monitor_brightness
check "DDC 拖动: 丢弃积压只调用 1 次 setvcp" "[ \"\$(grep -c setvcp \"\$MOCK_LOG\")\" = 1 ]"
check "DDC 拖动: 应用的是最新值 20" "grep -q 'setvcp 10 20\$' \"\$MOCK_LOG\""

exit $fail
