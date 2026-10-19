#!/usr/bin/env bash
# handle_property 回归测试 (slider/color/file):
#   A. 无 user properties (image/video) → 通知后返回, 无 set-property
#   B. 单 slider + OK → 逐值实时 set, 保持最终值
#   C. 单 slider + 取消 → 恢复原值
#   D. 多属性 → 经 module_sub_rofi 选中后再调
#   E. min/max 来自 project.json, 缺失时 fallback 0..100
#   F. 单 color + OK → set 十六进制, 无恢复
#   G. color + 取消 → 恢复原三元组
#   H. 多属性中的 bool → 一键翻转, combo 不动
#   N/O. 单 bool true/false/1 → 翻转, 无 yad/rofi
#   P/Q/R. 单 combo 对象/字符串/数字 options → rofi 选 label 设 value
#   S. combo 无 options → 回退自由输入
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
eval "$(awk '/^(prop_tunables|prop_combo_options|prop_range|prop_color_hex|prop_hex_to_rgb|prop_commit_once|prop_label|handle_property|_apply_property)\(\) \{/{f=1} f{print} f && /^}/{f=0}' "$DWM/rofi/scripts/wallpaper.sh")"

module_sub_rofi() { echo "rofi $*" >>"$XW_MOCK_LOG"; cat >>"$TEST_DIR/rofi_in.txt"; [ -e "$SEL_FLAG" ] && return; touch "$SEL_FLAG"; printf '%s' "$MOCK_PICK"; }
module_input() { echo "input $*" >>"$XW_MOCK_LOG"; printf '%s' "$MOCK_INPUT"; }
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

# ---- H: 多属性中的 bool → 一键翻转, combo 不动 ----
reset_state
printf 'autohide\tbool\ttrue\nfit\tcombo\tcontain\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="autohide" handle_property
check "H: bool 被翻转为 false" 'grep -q "set-property autohide=false" "$XW_MOCK_LOG"'
check "H: 未选中 combo 不动" '! grep -q "set-property fit=" "$XW_MOCK_LOG"'

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

# ---- N: 单 bool true → 一键翻转为 false, 无 yad/rofi ----
reset_state
printf 'enablevoice\tbool\ttrue\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="" MOCK_INPUT="" handle_property
check "N: bool true→false" 'grep -q "set-property enablevoice=false" "$XW_MOCK_LOG"'
check "N: 不调 yad" '! grep -q "^yad " "$XW_MOCK_LOG"'
check "N: 不调 rofi" '! grep -q "^rofi " "$XW_MOCK_LOG"'

# ---- O: 单 bool false/1 → 翻转为 true ----
reset_state
printf 'enablevoice\tbool\tfalse\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="" MOCK_INPUT="" handle_property
check "O: bool false→true" 'grep -q "set-property enablevoice=true" "$XW_MOCK_LOG"'
reset_state
printf 'enablevoice\tbool\t1\n' >"$XW_MOCK_STATE/props"
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="" MOCK_INPUT="" handle_property
check "O: bool 1→false" 'grep -q "set-property enablevoice=false" "$XW_MOCK_LOG"'

# ---- P: 单 combo (对象 options) → rofi 选 label, set 对应 value ----
reset_state
printf 'bg_size\tcombo\tauto\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
mkdir -p "$XW_MOCK_STATE/wall"
cat >"$XW_MOCK_STATE/wall/project.json" <<'JSON'
{"general":{"properties":{"bg_size":{"type":"combo","value":"auto","options":[{"label":"铺满/Cover","value":"cover"},{"label":"包含/Contain","value":"contain"},{"label":"拉伸/Stretch","value":"100% 100%"},{"label":"原始大小/Auto","value":"auto"}]}}}}
JSON
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="铺满/Cover" MOCK_INPUT="" handle_property
check "P: combo 选中 set value" 'grep -q "set-property bg_size=cover" "$XW_MOCK_LOG"'
check "P: 菜单显示 text 全串" 'grep -q "原始大小/Auto" "$TEST_DIR/rofi_in.txt"'
check "P: 菜单无括号 value 后缀" '! grep -q "(cover)" "$TEST_DIR/rofi_in.txt"'
check "P: 当前值标 ✓" 'grep -q "✓" "$TEST_DIR/rofi_in.txt"'

# ---- Q: combo 纯字符串 options → value 为序号索引 ----
reset_state
printf 'alignment\tcombo\t0\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
cat >"$XW_MOCK_STATE/wall/project.json" <<'JSON'
{"general":{"properties":{"alignment":{"type":"combo","value":0,"options":["居中","左上","右上","左下","右下"]}}}}
JSON
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="左上" MOCK_INPUT="" handle_property
check "Q: 字符串 options 选中 set 索引" 'grep -q "set-property alignment=1" "$XW_MOCK_LOG"'

# ---- R: combo 数字 value → 原样 set 数字串 ----
reset_state
printf 'gridSize\tcombo\t160\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
cat >"$XW_MOCK_STATE/wall/project.json" <<'JSON'
{"general":{"properties":{"gridSize":{"type":"combo","value":160,"options":[{"label":"120x120","value":120},{"label":"160x160","value":160},{"label":"320x320","value":320}]}}}}
JSON
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="320x320" MOCK_INPUT="" handle_property
check "R: 数字 value 正常 set" 'grep -q "set-property gridSize=320" "$XW_MOCK_LOG"'

# ---- S: combo 无 options → 回退自由输入 ----
reset_state
printf 'foo\tcombo\ta\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
cat >"$XW_MOCK_STATE/wall/project.json" <<'JSON'
{"general":{"properties":{"foo":{"type":"combo","value":"a"}}}}
JSON
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="" MOCK_INPUT="custom" handle_property
check "S: 无 options 时走自由输入" 'grep -q "^input " "$XW_MOCK_LOG"'
check "S: 输入值被 set" 'grep -q "set-property foo=custom" "$XW_MOCK_LOG"'

# ---- T2: prop_label 取 text 全串 ----
reset_state
mkdir -p "$TEST_DIR/labelwall"
cat >"$TEST_DIR/labelwall/project.json" <<'JSON'
{"general":{"properties":{"audioIntensity":{"type":"slider","value":1,"text":"音频响应强度 / Audio Intensity"},"plain":{"type":"slider","value":1}}}}
JSON
check "T2: 显示 text 全串（不切分）" '[ "$(prop_label "$TEST_DIR/labelwall" audioIntensity)" = "音频响应强度 / Audio Intensity" ]'
check "T2: 无 text 回退 name" '[ "$(prop_label "$TEST_DIR/labelwall" plain)" = "plain" ]'
check "T2: 无 project.json 回退 name" '[ "$(prop_label "$TEST_DIR/nonexist" audioIntensity)" = "audioIntensity" ]'

# ---- T3: 列表显示 text 全串，set 仍用英文 name ----
reset_state
printf 'volume\tslider\t35\nroleScale\tslider\t100\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
mkdir -p "$XW_MOCK_STATE/wall"
cat >"$XW_MOCK_STATE/wall/project.json" <<'JSON'
{"general":{"properties":{"volume":{"type":"slider","value":35,"min":0,"max":100,"text":"音量 / Volume"},"roleScale":{"type":"slider","value":100,"min":50,"max":200,"text":"角色缩放 / Role Scale"}}}}
JSON
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
export YAD_OUT='120
' YAD_RC=0
T3_LINE=$(printf '%-26s %12s' "角色缩放 / Role Scale" "100")
MONITOR="DP-1" MOCK_PICK="$T3_LINE" handle_property
check "T3: 列表显示 text 全串" 'grep -Fq "角色缩放 / Role Scale" "$TEST_DIR/rofi_in.txt"'
check "T3: 列表不显示英文 name" '! grep -q "roleScale" "$TEST_DIR/rofi_in.txt"'
check "T3: set 仍用英文 name" 'grep -q "set-property roleScale=120" "$XW_MOCK_LOG"'

# ---- T4: combo 显示 label 全串 ----
reset_state
printf 'bg_size\tcombo\tauto\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
cat >"$XW_MOCK_STATE/wall/project.json" <<'JSON'
{"general":{"properties":{"bg_size":{"type":"combo","value":"auto","text":"背景尺寸 / Background Size","options":[{"label":"铺满/Cover","value":"cover"},{"label":"包含/Contain","value":"contain"},{"label":"原始大小/Auto","value":"auto"}]}}}}
JSON
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="铺满/Cover" MOCK_INPUT="" handle_property
check "T4: combo 选中 set value" 'grep -q "set-property bg_size=cover" "$XW_MOCK_LOG"'
check "T4: 菜单显示 label 全串" 'grep -Fq "原始大小/Auto" "$TEST_DIR/rofi_in.txt"'
check "T4: 无括号 value 后缀" '! grep -q "(cover)" "$TEST_DIR/rofi_in.txt"'

# ---- T5: label 碰撞时才加 " (value)" 后缀区分 ----
reset_state
printf 'mode\tcombo\ta\n' >"$XW_MOCK_STATE/props"; export XW_PROPS_RC=0
cat >"$XW_MOCK_STATE/wall/project.json" <<'JSON'
{"general":{"properties":{"mode":{"type":"combo","value":"a","text":"模式 / Mode","options":[{"label":"相同/Same","value":"a"},{"label":"相同/Same","value":"b"},{"label":"其他/Other","value":"c"}]}}}}
JSON
printf 'DP-1\tweb\t%s\t0\n' "$XW_MOCK_STATE/wall" >"$XW_MOCK_STATE/state"
MONITOR="DP-1" MOCK_PICK="相同/Same (b)" MOCK_INPUT="" handle_property
check "T5: 碰撞项带 value 后缀" 'grep -Fq "相同/Same (b)" "$TEST_DIR/rofi_in.txt"'
check "T5: 唯一 label 无后缀" 'grep -Fq "其他/Other" "$TEST_DIR/rofi_in.txt" && ! grep -Fq "其他/Other (" "$TEST_DIR/rofi_in.txt"'
check "T5: 选中碰撞项 set 对应 value" 'grep -q "set-property mode=b" "$XW_MOCK_LOG"'

exit $fail
