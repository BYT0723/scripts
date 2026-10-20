#!/usr/bin/env bash
# prop_reset / handle_property_reset 回归测试:
#   R1. 无 tunables (image/video) → 通知后返回, 无 clear-properties
#   R2. 确认 Yes → 调 --clear-properties -m MONITOR, 成功通知
#   R3. 确认 No → 不调 clear-properties
#   R4. clear 失败 → critical 通知
#   R5. 多属性选择循环内含 Reset 行, 选中后走 clear
# 运行: bash tests/wallpaper-property-reset_test.sh

DWM="$HOME/.dwm"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm"
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# ---- mock xwallpaper ----
cat >"$BIN/xwallpaper" <<'EOF'
#!/usr/bin/env bash
echo "xwallpaper $*" >>"$XW_MOCK_LOG"
case "$*" in
*--state*)
    cat "$XW_MOCK_STATE/state" 2>/dev/null
    ;;
*--list-properties*)
    cat "$XW_MOCK_STATE/props" 2>/dev/null
    exit "${XW_PROPS_RC:-0}"
    ;;
*--set-property*)
    exit 0
    ;;
*--clear-properties*)
    exit "${XW_CLEAR_RC:-0}"
    ;;
esac
exit 0
EOF

# ---- mock yad (本文件不走 slider, 仅占位) ----
cat >"$BIN/yad" <<'EOF'
#!/usr/bin/env bash
echo "yad $*" >>"$XW_MOCK_LOG"
exit 0
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

XW_MOCK_LOG="$TEST_DIR/xw.log"
export XW_MOCK_LOG XW_MOCK_STATE="$TEST_DIR/state"
mkdir -p "$XW_MOCK_STATE"
SEL_FLAG="$TEST_DIR/sel.done"
reset_state() { : >"$XW_MOCK_LOG"; : >"$TEST_DIR/rofi_in.txt"; : >"$TEST_DIR/rofi_last.txt"; rm -f "$SEL_FLAG"; }

source "$DWM/tools/wallpaper-lib.sh"
source "$DWM/tools/wallpaper-render.sh"

# 被测函数提取 (rofi 脚本顶层含 module_loop, 仅提取 property 相关;
#   注意 handle_property_reset 是单行函数, 提取器须单行闭合, 否则会吞掉文件尾
#   真实执行 `while module_loop`)
eval "$(awk '/^(prop_tunables|prop_combo_options|prop_range|prop_color_hex|prop_hex_to_rgb|prop_commit_once|prop_label|prop_wall_dir|prop_reset|handle_property_reset|handle_property|_apply_property)\(\) \{/ { if (/\}[ \t]*$/) { print; next } else { f=1; buf=$0 "\n"; next } } f { buf=buf $0 "\n" } /^\}/ { if (f) { printf "%s", buf; f=0; buf="" } }' "$DWM/rofi/scripts/wallpaper.sh")"

module_sub_rofi() {
    echo "rofi $*" >>"$XW_MOCK_LOG"
    cat >"$TEST_DIR/rofi_last.txt"
    cat "$TEST_DIR/rofi_last.txt" >>"$TEST_DIR/rofi_in.txt"
    [ -e "$SEL_FLAG" ] && return
    touch "$SEL_FLAG"
    if [ "$MOCK_PICK" = "__RESET__" ]; then
        grep -m1 "Reset" "$TEST_DIR/rofi_last.txt"
    else
        printf '%s' "$MOCK_PICK"
    fi
}
module_confirm() { echo "confirm $*" >>"$XW_MOCK_LOG"; return "${MOCK_CONFIRM_RC:-0}"; }
module_input() { echo "input $*" >>"$XW_MOCK_LOG"; printf '%s' "$MOCK_INPUT"; }
system-notify() { echo "notify $*" >>"$XW_MOCK_LOG"; }

fail=0
check() {
    if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

# ---- R0: 注册表 entry 与 handler 接线 ----
check "R0: 注册表含 property_reset entry" 'grep -q "^property_reset|.*|Reset Property|" "$DWM/rofi/scripts/wallpaper.sh"'
check "R0: handle_property_reset 已定义" 'declare -F handle_property_reset >/dev/null'

# ---- R1: 无 props → 通知, 无 clear, 返回非 0 ----
reset_state
printf '' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=1
printf 'HDMI-1\timage\t/a.png\t0\n' >"$XW_MOCK_STATE/state"
MONITOR="HDMI-1" MOCK_CONFIRM_RC=0 prop_reset
rc=$?
check "R1: 无 props 时返回非 0" '[ "$rc" != 0 ]'
check "R1: 无 props 时不 clear" '! grep -q "clear-properties" "$XW_MOCK_LOG"'
check "R1: 有通知" 'grep -q "notify" "$XW_MOCK_LOG"'

# ---- R2: 确认 Yes → clear, 成功通知 ----
reset_state
printf 'volume\tslider\t35\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0 XW_CLEAR_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
mkdir -p "$XW_MOCK_STATE/wall"
MONITOR="DP-1" MOCK_CONFIRM_RC=0 prop_reset
check "R2: 调 clear-properties -m MONITOR" 'grep -q "xwallpaper --clear-properties -m DP-1" "$XW_MOCK_LOG"'
check "R2: 成功通知" 'grep -q "notify.*Properties reset" "$XW_MOCK_LOG"'
check "R2: 有确认框" 'grep -q "^confirm " "$XW_MOCK_LOG"'

# ---- R3: 确认 No → 不 clear ----
reset_state
printf 'volume\tslider\t35\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_CONFIRM_RC=1 prop_reset
check "R3: 取消时不 clear" '! grep -q "clear-properties" "$XW_MOCK_LOG"'
check "R3: 取消时无成功通知" '! grep -q "Properties reset" "$XW_MOCK_LOG"'

# ---- R4: clear 失败 → critical 通知 ----
reset_state
printf 'volume\tslider\t35\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0 XW_CLEAR_RC=1
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_CONFIRM_RC=0 prop_reset
check "R4: 失败走 critical 通知" 'grep -q "notify critical.*Reset failed" "$XW_MOCK_LOG"'

# ---- R5: 多属性循环内 Reset 行可选中并 clear ----
reset_state
printf 'volume\tslider\t35\nschemecolor\tcolor\t0.100000 0.200000 0.300000\n' >"$XW_MOCK_STATE/props"
export XW_PROPS_RC=0 XW_CLEAR_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="__RESET__" MOCK_CONFIRM_RC=0 handle_property
check "R5: 选择菜单含 Reset 行" 'grep -q "Reset" "$TEST_DIR/rofi_in.txt"'
check "R5: 选中 Reset 后调 clear" 'grep -q "xwallpaper --clear-properties -m DP-1" "$XW_MOCK_LOG"'

exit $fail
