#!/usr/bin/env bash
# handle_property 回归测试 (slider/color/file):
#   A. 无 user properties (image/video) → 通知后返回, 无 set-property
#   B. 单 slider + OK → 逐值实时 set, 保持最终值
#   C. 单 slider + 取消 → 恢复原值
#   D. 多属性 → 经 module_sub_rofi 选中后再调
#   E. min/max 来自 project.json, 缺失时 fallback 0..100
#   F. 单 color + OK → set 十六进制, 无恢复
#   G. color + 取消 → 恢复原三元组
#   H. 仅 bool/combo → 通知, 无 set
#   I. 单 file + OK → set 路径, 起始于壁纸目录
#   J. file + 取消 → 恢复原值
#   K. 多属性列表中 color 显示为 hex; set 时 hex 转回三元组 (scene 只认 triple)
# 运行: bash tests/wallpaper-property_test.sh

DWM="$HOME/.dwm"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm"
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# ---- mock xwallpaper: --state / --list-properties / --set-property ----
# --set-property 会回写 props 文件 (模拟 daemon 状态变更, 供 M 测试列表刷新)
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
    kv=""
    for a in "$@"; do case "$a" in *=*) kv="$a";; esac; done
    n="${kv%%=*}"; v="${kv#*=}"
    if [ -n "$n" ] && [ -f "$XW_MOCK_STATE/props" ]; then
        awk -F'\t' -v OFS='\t' -v n="$n" -v v="$v" '$1==n {$3=v} 1' \
            "$XW_MOCK_STATE/props" >"$XW_MOCK_STATE/props.tmp" &&
            mv "$XW_MOCK_STATE/props.tmp" "$XW_MOCK_STATE/props"
    fi
    exit 0
    ;;
esac
exit 0
EOF

# ---- mock yad: 按场景输出部分值; 退出码由 YAD_RC 控制 ----
cat >"$BIN/yad" <<'EOF'
#!/usr/bin/env bash
echo "yad $*" >>"$XW_MOCK_LOG"
printf '%s' "$YAD_OUT"
exit "${YAD_RC:-0}"
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

XW_MOCK_LOG="$TEST_DIR/xw.log"
export XW_MOCK_LOG XW_MOCK_STATE="$TEST_DIR/state"
mkdir -p "$XW_MOCK_STATE"
SEL_FLAG="$TEST_DIR/sel.done"
reset_state() { : >"$XW_MOCK_LOG"; : >"$TEST_DIR/rofi_in.txt"; rm -f "$SEL_FLAG"; }

source "$DWM/tools/wallpaper-lib.sh"
source "$DWM/tools/wallpaper-render.sh"

# 被测函数提取 (rofi 脚本顶层含 module_loop, 仅提取 handle_property + helper)
eval "$(awk '/^(prop_tunables|prop_range|prop_color_hex|prop_hex_to_rgb|prop_commit_once|handle_property|_apply_property)\(\) \{/{f=1} f{print} f && /^}/{f=0}' "$DWM/rofi/scripts/wallpaper.sh")"

module_sub_rofi() { echo "rofi $*" >>"$XW_MOCK_LOG"; cat >>"$TEST_DIR/rofi_in.txt"; [ -e "$SEL_FLAG" ] && return; touch "$SEL_FLAG"; printf '%s' "$MOCK_PICK"; }
system-notify() { echo "notify $*" >>"$XW_MOCK_LOG"; }

fail=0
check() {
    if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

# ---- A: 无 props → 通知, 无 set ----
reset_state
printf '' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=1
printf 'HDMI-1\timage\t/a.png\t0\n' >"$XW_MOCK_STATE/state"
MONITOR="HDMI-1" MOCK_PICK="" handle_property
check "A: 无 props 时不 set" '! grep -q "set-property" "$XW_MOCK_LOG"'
check "A: 有通知" 'grep -q "notify" "$XW_MOCK_LOG"'

# ---- B: 单 slider + OK → 实时 set 最终值 ----
reset_state
printf 'volume\tslider\t35\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
mkdir -p "$XW_MOCK_STATE/wall"; printf '{"general":{"properties":{"volume":{"min":0,"max":100}}}}' >"$XW_MOCK_STATE/wall/project.json"
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='40
50
' YAD_RC=0
MONITOR="DP-1" MOCK_PICK="" handle_property
check "B: 逐值 set 40" 'grep -q "set-property volume=40" "$XW_MOCK_LOG"'
check "B: 逐值 set 50" 'grep -q "set-property volume=50" "$XW_MOCK_LOG"'
check "B: OK 后不恢复 35" '! grep -q "set-property volume=35" "$XW_MOCK_LOG"'
check "B: yad 取到正确 range" 'grep -q "min-value=0" "$XW_MOCK_LOG" && grep -q "max-value=100" "$XW_MOCK_LOG"'

# ---- C: 取消 → 恢复原值 ----
reset_state
printf 'volume\tslider\t35\n' >"$XW_MOCK_STATE/props"
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='80
' YAD_RC=1
MONITOR="DP-1" MOCK_PICK="" handle_property
check "C: 取消时恢复原值 35" 'grep -q "set-property volume=35" "$XW_MOCK_LOG"'

# ---- D: 多 slider 经 rofi 选择 ----
reset_state
printf 'volume\tslider\t35\nroleScale\tslider\t100\n' >"$XW_MOCK_STATE/props"
printf '{"general":{"properties":{"volume":{"min":0,"max":100},"roleScale":{"min":50,"max":200}}}}' >"$XW_MOCK_STATE/wall/project.json"
export YAD_OUT='120
' YAD_RC=0
MONITOR="DP-1" MOCK_PICK="roleScale" handle_property
check "D: 选中项被调节" 'grep -q "set-property roleScale=120" "$XW_MOCK_LOG"'
check "D: 未选中项不动" '! grep -q "set-property volume=" "$XW_MOCK_LOG"'

# ---- E: 无 project.json range → fallback 0..100 ----
reset_state
printf 'volume\tslider\t35\n' >"$XW_MOCK_STATE/props"
rm -f "$XW_MOCK_STATE/wall/project.json"
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='60
' YAD_RC=0
MONITOR="DP-1" MOCK_PICK="" handle_property
check "E: fallback min 0" 'grep -q "min-value=0" "$XW_MOCK_LOG"'
check "E: fallback max 100" 'grep -q "max-value=100" "$XW_MOCK_LOG"'

# ---- F: 单 color + OK → set 三元组 (yad 给 hex, 统一转回 triple; scene 只认 triple) ----
reset_state
printf 'schemecolor\tcolor\t0.168627 0.168627 0.168627\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='#ff0000
' YAD_RC=0
MONITOR="DP-1" MOCK_PICK="" handle_property
check "F: color OK 时 set 三元组" 'grep -q "set-property schemecolor=1.000000 0.000000 0.000000" "$XW_MOCK_LOG"'
check "F: color OK 后不恢复原值" '! grep -q "set-property schemecolor=0.168627" "$XW_MOCK_LOG"'
check "F: yad color 带初始色" 'grep -q -- "--color" "$XW_MOCK_LOG" && grep -q "init-color=#2b2b2b" "$XW_MOCK_LOG"'

# ---- G: color + 取消 → 恢复原三元组 ----
reset_state
printf 'schemecolor\tcolor\t0.168627 0.168627 0.168627\n' >"$XW_MOCK_STATE/props"
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='#00ff00
' YAD_RC=1
MONITOR="DP-1" MOCK_PICK="" handle_property
check "G: color 取消时恢复原值" 'grep -q "set-property schemecolor=0.168627 0.168627 0.168627" "$XW_MOCK_LOG"'

# ---- H: 仅 bool/combo → 通知, 无 set ----
reset_state
printf 'autohide\tbool\ttrue\nfit\tcombo\tcontain\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
MONITOR="DP-1" MOCK_PICK="" handle_property
check "H: 非可调类型时不 set" '! grep -q "set-property" "$XW_MOCK_LOG"'
check "H: 有通知" 'grep -q "notify" "$XW_MOCK_LOG"'

# ---- I: 单 file + OK → set 路径, 无恢复 ----
reset_state
printf 'bgImage\tfile\t\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='/tmp/bg.png
' YAD_RC=0
MONITOR="DP-1" MOCK_PICK="" handle_property
check "I: file OK 时 set 路径" 'grep -q "set-property bgImage=/tmp/bg.png" "$XW_MOCK_LOG"'
check "I: file OK 后不恢复空值" '! grep -q "set-property bgImage=$" "$XW_MOCK_LOG"'
check "I: yad file 起始于壁纸目录" 'grep -q -- "--file" "$XW_MOCK_LOG" && grep -q "filename=.*wall" "$XW_MOCK_LOG"'

# ---- J: file + 取消 → 恢复原值 ----
reset_state
printf 'bgImage\tfile\t/old/bg.png\n' >"$XW_MOCK_STATE/props"
export YAD_OUT='/tmp/bg.png
' YAD_RC=1
MONITOR="DP-1" MOCK_PICK="" handle_property
check "J: file 取消时恢复原值" 'grep -q "set-property bgImage=/old/bg.png" "$XW_MOCK_LOG"'

# ---- K: 多属性列表中 color 显示为 hex, slider 保持原值 ----
reset_state
printf 'volume\tslider\t35\nschemecolor\tcolor\t0.168627 0.168627 0.168627\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='#ff0000
' YAD_RC=0
MONITOR="DP-1" MOCK_PICK="schemecolor" handle_property
check "K: 列表中 color 显示 hex" 'grep -q "#2b2b2b" "$TEST_DIR/rofi_in.txt"'
check "K: 列表中 slider 保持原值" 'grep -q " 35" "$TEST_DIR/rofi_in.txt"'
check "K: 列表中无原始三元组" '! grep -q "0.168627 0.168627 0.168627" "$TEST_DIR/rofi_in.txt"'
check "K: 选中 color 正常 set 三元组" 'grep -q "set-property schemecolor=1.000000 0.000000 0.000000" "$XW_MOCK_LOG"'

# ---- L: 多属性调完回到选择层, ESC 才回主菜单 ----
reset_state
printf 'volume\tslider\t35\nschemecolor\tcolor\t0.100000 0.200000 0.300000\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='40
' YAD_RC=0
MONITOR="DP-1" MOCK_PICK="volume" handle_property
check "L: 选择层出现两次 (调完回退)" '[ "$(grep -c "^rofi " "$XW_MOCK_LOG")" = 2 ]'
check "L: yad 只调一次" '[ "$(grep -c "^yad " "$XW_MOCK_LOG")" = 1 ]'
check "L: 选中项已应用" 'grep -q "set-property volume=40" "$XW_MOCK_LOG"'

# ---- M: 调完后选择列表值刷新 ----
reset_state
printf 'volume\tslider\t35\nschemecolor\tcolor\t0.100000 0.200000 0.300000\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='50
' YAD_RC=0
MONITOR="DP-1" MOCK_PICK="volume" handle_property
check "M: 第二次列表显示新值" 'grep -q "volume *50" "$TEST_DIR/rofi_in.txt"'
check "M: set 已落盘" 'grep -q "set-property volume=50" "$XW_MOCK_LOG"'

exit $fail
