#!/usr/bin/env bash
# dunst-menu.sh 回归测试 (dunst action dmenu → rofi)
# 运行: bash tests/dunst-menu_test.sh
#
# dunst 通过 stdin 喂 action/URL 行, 读取 stdout 作为选择; 脚本必须
# 原样回传被选中的原始行 (行尾 [id,key] 是 dunst 派发 action 的依据)。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/rofi/scripts/dunst-menu.sh"
THEME="$ROOT/rofi/applets/type-2/style-2.rasi"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

FAIL=0
assert_eq() { # msg expected actual
    if [[ "$2" == "$3" ]]; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        printf '  expected: %q\n  actual:   %q\n' "$2" "$3"
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
arg_logged() { grep -qxF -- "$1" "$ROFI_LOG"; }

# ---- mock rofi: 记录 argv + stdin, 按 ROFI_FAKE_CHOICE 输出序号 ----
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
export ROFI_LOG="$TEST_DIR/rofi.args"
export ROFI_STDIN="$TEST_DIR/rofi.stdin"
cat >"$FAKE_BIN/rofi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$ROFI_LOG"
cat >"$ROFI_STDIN"
[[ -n "${ROFI_FAKE_CHOICE-}" ]] && printf '%s\n' "$ROFI_FAKE_CHOICE"
exit "${ROFI_FAKE_RC:-0}"
EOF
chmod +x "$FAKE_BIN/rofi"
export PATH="$FAKE_BIN:$PATH"

reset_mock() {
    : >"$ROFI_LOG"
    : >"$ROFI_STDIN"
    export ROFI_FAKE_RC=0
    unset ROFI_FAKE_CHOICE
}

# ---- 1. 空 stdin: 不启动 rofi, 退出 0 ----
reset_mock
out=$(printf '' | "$SCRIPT" 2>"$TEST_DIR/stderr")
rc=$?
assert_eq "empty stdin rc" 0 "$rc"
assert_cond "empty stdin -> rofi not spawned" '[[ ! -s "$ROFI_LOG" ]]'
assert_cond "empty stdin -> no stderr" '[[ ! -s "$TEST_DIR/stderr" ]]'

# ---- 2. 主题/参数: type-2/style-2 + dmenu/format i/no-custom ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '#Open (Title) [3,default]' | "$SCRIPT" >/dev/null 2>&1
assert_cond "theme is applets/type-2/style-2.rasi" 'arg_logged "$THEME"'
assert_cond "uses -dmenu" 'arg_logged -dmenu'
assert_cond "uses -format" 'arg_logged -format'
assert_cond "format outputs index" 'arg_logged i'
assert_cond "uses -no-custom" 'arg_logged -no-custom'
assert_cond "menu width 800px" 'grep -qxF "window {width: 800px;}" "$ROFI_LOG"'
assert_cond "element padding 20px 5px" 'grep -qxF "element {padding: 20px 5px;}" "$ROFI_LOG"'
assert_cond "element-text mono font 12" 'grep -qxF "element-text {font: \"JetBrains Mono Nerd Font 12\";}" "$ROFI_LOG"'
assert_cond "inputbar has prompt only (no entry)" 'grep -qxF "inputbar {children: [ \"textbox-prompt-colon\"];}" "$ROFI_LOG"'

# ---- 3. 显示: label + 裸 key (无括号), 丢弃通知 summary ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '#Open (Title) [3,default]' | "$SCRIPT" >/dev/null 2>&1
assert_eq "action display is label + bare key" "Open default" "$(cat "$ROFI_STDIN")"

# ---- 3b. label 是图标字形时保留 (播放器等) ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '#⏭ (Now playing) [2,next]' | "$SCRIPT" >/dev/null 2>&1
assert_eq "icon label is kept" "⏭ next" "$(cat "$ROFI_STDIN")"

# ---- 3c. summary 内含括号也不影响 (丢弃整段 summary) ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '#Open (New message (3)) [2,default]' | "$SCRIPT" >/dev/null 2>&1
assert_eq "summary with parens ignored" "Open default" "$(cat "$ROFI_STDIN")"

# ---- 4. URL 行原样显示 ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' 'https://example.com/a' | "$SCRIPT" >/dev/null 2>&1
assert_eq "url display unchanged" "https://example.com/a" "$(cat "$ROFI_STDIN")"

# ---- 5. 选中序号 → 原样回传对应原始行 (含 [id,key]) ----
reset_mock
export ROFI_FAKE_CHOICE=1
out=$(printf '%s\n' '#Open (Title) [3,default]' '#Mark as read (Title) [3,mark]' | "$SCRIPT")
assert_eq "selection maps back to raw line" "#Mark as read (Title) [3,mark]" "$out"

# ---- 6. 混合 action + URL: 序号映射不错位 ----
reset_mock
export ROFI_FAKE_CHOICE=2
out=$(printf '%s\n' '#Open (Title) [3,default]' 'https://example.com/a' '#Read (Title) [3,mark]' | "$SCRIPT")
assert_eq "selection after url keeps raw line" "#Read (Title) [3,mark]" "$out"

# ---- 6b. 空 label: 只显示 key ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '# (Same summary) [2,next]' '# (Same summary) [2,default]' | "$SCRIPT" >/dev/null 2>&1
assert_eq "empty label shows key only" "next
default" "$(cat "$ROFI_STDIN")"

# ---- 6c. 同通知 action label 重复: key 可区分 ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '#Open (S) [2,default]' '#Open (S) [2,next]' | "$SCRIPT" >/dev/null 2>&1
assert_eq "duplicate label distinguished by key" "Open default
Open next" "$(cat "$ROFI_STDIN")"

# ---- 6d. 跨通知 label+key 都相同: 再追加 #id ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '#Open (S) [2,default]' '#Open (S) [3,default]' | "$SCRIPT" >/dev/null 2>&1
assert_eq "duplicate key across notifications appends id" "Open default #2
Open default #3" "$(cat "$ROFI_STDIN")"

# ---- 7. 取消: 无 stdout, 退出 0 ----
reset_mock
export ROFI_FAKE_RC=1
out=$(printf '%s\n' '#Open (Title) [3,default]' | "$SCRIPT" 2>"$TEST_DIR/stderr")
rc=$?
assert_eq "cancel rc" 0 "$rc"
assert_eq "cancel stdout empty" "" "$out"
assert_cond "cancel no stderr" '[[ ! -s "$TEST_DIR/stderr" ]]'

# ---- 8. -p 覆盖 prompt, 缺省 Actions ----
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '#Open (Title) [3,default]' | "$SCRIPT" -p Custom >/dev/null 2>&1
assert_cond "-p prompt passed to rofi" 'arg_logged Custom'
assert_cond "-p prompt shown in inputbar" 'grep -qxF "textbox-prompt-colon {str: \"Custom\";}" "$ROFI_LOG"'
reset_mock
export ROFI_FAKE_CHOICE=0
printf '%s\n' '#Open (Title) [3,default]' | "$SCRIPT" >/dev/null 2>&1
assert_cond "default prompt Actions" 'arg_logged Actions'

echo
if [[ $FAIL -ne 0 ]]; then
    echo "FAILED"
    exit 1
fi
echo "ALL PASS"
