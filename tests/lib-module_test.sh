#!/usr/bin/env bash
# lib-module.sh 外部 theme-str 数组注入测试 (source + mock rofi, 无弹窗)
# 运行: bash tests/lib-module_test.sh

SCRIPT="$HOME/.dwm/rofi/scripts/lib-module.sh"
UTIL="$HOME/.dwm/rofi/scripts/util.sh"
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
# 回归守卫: 断言 logfile 中 marker 的前一行是独立 -theme-str
# 回归场景: ${arr[@]/#/-theme-str} 会把前缀拼进元素 (-theme-strwindow{} 单参数), rofi 无法解析
prev_is_theme_str() { # logfile marker
    local line=$(grep -nF "$2" "$1" | head -1 | cut -d: -f1)
    [[ -n "$line" ]] || return 1
    line=$((line - 1))
    [[ "$line" -ge 1 ]] || return 1
    awk "NR==$line" "$1" | grep -qx -- '-theme-str'
}

# ---- mock rofi: 每行记录一个参数到 $ROFI_LOG ----
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
ROFI_LOG="$TEST_DIR/rofi.args"
cat >"$FAKE_BIN/rofi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$ROFI_LOG"
echo ""
EOF
chmod +x "$FAKE_BIN/rofi"
export PATH="$FAKE_BIN:$PATH" ROFI_LOG

# ---- source ----
export ROFI_DIR="$HOME/.dwm/rofi"
export MODULE_THEME="$TEST_DIR/style.rasi"
cat >"$MODULE_THEME" <<'EOF'
* { USE_ICON = NO; }
EOF
source "$UTIL"
source "$SCRIPT"

# 通用: 调用前清空参数日志
clr() { : >"$ROFI_LOG"; }

# 定位辅助: 输出参数行号 (1-based), 无则 0
ln_of() { # logfile pattern
    grep -nE "$2" "$1" | head -1 | cut -d: -f1 || echo 0
}

# ---- 前置: 未设置数组 → 无外部片段 ----
clr
printf '' | _module_rofi >/dev/null
assert_cond "主菜单: 未设置 MODULE_THEME_STR → 无外部 -theme-str 片段" \
    "! grep -qF 'EXTERNAL_MENU' \"\$ROFI_LOG\""

clr
module_sub_rofi "Sub" >/dev/null
assert_cond "子菜单: 未设置 MODULE_SUB_THEME_STR → 无外部片段" \
    "! grep -qF 'EXTERNAL_SUB' \"\$ROFI_LOG\""

clr
module_input "Input" >/dev/null
assert_cond "输入框: 未设置 MODULE_INPUT_THEME_STR → 无外部片段" \
    "! grep -qF 'EXTERNAL_INPUT' \"\$ROFI_LOG\""

clr
module_multi_rofi "Multi" >/dev/null
assert_cond "多选: 未设置 MODULE_MULTI_THEME_STR → 无外部片段" \
    "! grep -qF 'EXTERNAL_MULTI' \"\$ROFI_LOG\""

# ---- 主菜单: 数组逐条展开 + 位置 (内置之后, -theme 之前) ----
export MODULE_THEME_STR=(
    'window {background-color: #000; EXTERNAL_MENU_A;}'
    'listview {EXTERNAL_MENU_B;}'
)
clr
printf '' | _module_rofi >/dev/null
n_ext=$(grep -cE 'EXTERNAL_MENU' "$ROFI_LOG")
assert_cond "主菜单: 数组 2 元素逐条展开为 2 个 -theme-str" "[ \"\$n_ext\" = 2 ]"
assert_cond "主菜单: 元素内容完整保留" \
    "grep -qF 'window {background-color: #000; EXTERNAL_MENU_A;}' \"\$ROFI_LOG\""
# 关键回归: 外部片段前一行必须是独立 -theme-str (前缀不得粘连进元素)
assert_cond "主菜单: 每个外部片段前一行是独立 -theme-str" \
    "prev_is_theme_str \"\$ROFI_LOG\" 'EXTERNAL_MENU_A' && prev_is_theme_str \"\$ROFI_LOG\" 'EXTERNAL_MENU_B'"
# 位置: 每个外部 theme-str 的下一行必为 -theme-str, 且整体在内置 listview 之后、-theme 之前
l_builtin=$(ln_of "$ROFI_LOG" "^listview {columns:")
l_theme=$(ln_of "$ROFI_LOG" "^-theme$")
l_ext1=$(ln_of "$ROFI_LOG" "EXTERNAL_MENU_A")
l_ext2=$(ln_of "$ROFI_LOG" "EXTERNAL_MENU_B")
assert_cond "主菜单: 外部片段在内置 listview 之后" \
    "[ \"\$l_ext1\" -gt \"\$l_builtin\" ] && [ \"\$l_ext2\" -gt \"\$l_builtin\" ]"
assert_cond "主菜单: 外部片段在 -theme 之前" \
    "[ \"\$l_ext1\" -lt \"\$l_theme\" ] && [ \"\$l_ext2\" -lt \"\$l_theme\" ]"
unset MODULE_THEME_STR

# ---- 子菜单 ----
export MODULE_SUB_THEME_STR=('window {EXTERNAL_SUB;}')
clr
module_sub_rofi "Sub" >/dev/null
assert_cond "子菜单: 外部片段传入" "grep -qF 'EXTERNAL_SUB' \"\$ROFI_LOG\""
l_builtin=$(ln_of "$ROFI_LOG" "^listview {columns: 1;}")
l_theme=$(ln_of "$ROFI_LOG" "^-theme$")
l_ext=$(ln_of "$ROFI_LOG" "EXTERNAL_SUB")
assert_cond "子菜单: 外部片段在内置 listview 之后、-theme 之前" \
    "[ \"\$l_ext\" -gt \"\$l_builtin\" ] && [ \"\$l_ext\" -lt \"\$l_theme\" ]"
unset MODULE_SUB_THEME_STR

# ---- 输入框 ----
export MODULE_INPUT_THEME_STR=('window {EXTERNAL_INPUT;}')
clr
module_input "Input" >/dev/null
assert_cond "输入框: 外部片段传入" "grep -qF 'EXTERNAL_INPUT' \"\$ROFI_LOG\""
l_theme=$(ln_of "$ROFI_LOG" "^-theme$")
l_ext=$(ln_of "$ROFI_LOG" "EXTERNAL_INPUT")
assert_cond "输入框: 外部片段在 -theme 之前" "[ \"\$l_ext\" -lt \"\$l_theme\" ]"
unset MODULE_INPUT_THEME_STR

# ---- 多选 ----
export MODULE_MULTI_THEME_STR=('window {EXTERNAL_MULTI;}')
clr
module_multi_rofi "Multi" >/dev/null
assert_cond "多选: 外部片段传入" "grep -qF 'EXTERNAL_MULTI' \"\$ROFI_LOG\""
l_builtin=$(ln_of "$ROFI_LOG" "^listview {columns: 1;}")
l_theme=$(ln_of "$ROFI_LOG" "^-theme$")
l_ext=$(ln_of "$ROFI_LOG" "EXTERNAL_MULTI")
assert_cond "多选: 外部片段在内置 listview 之后、-theme 之前" \
    "[ \"\$l_ext\" -gt \"\$l_builtin\" ] && [ \"\$l_ext\" -lt \"\$l_theme\" ]"
unset MODULE_MULTI_THEME_STR

# ---- 隔离性: 主菜单不响应其他入口的变量 ----
export MODULE_SUB_THEME_STR=('window {SHOULD_NOT_LEAK;}')
clr
printf '' | _module_rofi >/dev/null
assert_cond "隔离: 主菜单不响应 MODULE_SUB_THEME_STR" \
    "! grep -qF 'SHOULD_NOT_LEAK' \"\$ROFI_LOG\""
unset MODULE_SUB_THEME_STR

if ((FAIL)); then
    echo "== 有失败用例 =="
    exit 1
fi
echo "== 全部通过 =="
