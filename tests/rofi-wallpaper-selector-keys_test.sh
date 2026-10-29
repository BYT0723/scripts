#!/usr/bin/env bash
# rofi/scripts/wallpaper.sh select_marker_wallpaper Alt+1/2/3 回归测试:
#   Alt+1 xdg-open 目录 / Alt+2 复制绝对路径(无换行) / Alt+3 确认后 rm -rf
#   动作后循环重显, Enter 原流程不变, ESC/空输出安全返回
# 沿 rofi-wallpaper-random-type_test.sh 先例: awk 提取函数 + mock rofi/外部命令
# 运行: bash tests/rofi-wallpaper-selector-keys_test.sh

DWM="$HOME/.dwm"
TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$TEST_DIR/fakeroot/tools" "$TEST_DIR/bin"

FAIL=0
check() { # desc cond
    if eval "$2"; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        FAIL=1
    fi
}

# ---- fixture: 单一条目 web 池 (序号恒为 0, 无歧义) ----
FIX="$TEST_DIR/pool"
mkdir -p "$FIX/111"
echo "<html></html>" >"$FIX/111/index.html"
printf '{"title":"t111","preview":"preview.jpg","file":"index.html","type":"web"}' >"$FIX/111/project.json"
echo "fake" >"$FIX/111/preview.jpg"
printf '{"monitors":{"TESTMON":{"random_web_dir":"%s"}}}' "$FIX" >"$HOME/.config/dwm/wallpaper.json"
MONITOR="TESTMON"
WORK_DIR="$TEST_DIR/fakeroot"
cat >"$TEST_DIR/fakeroot/tools/wallpaper.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$WALLPAPER_CALLS"
EOF
chmod +x "$TEST_DIR/fakeroot/tools/wallpaper.sh"
export WALLPAPER_CALLS="$TEST_DIR/wallpaper.calls"

# ---- mock 外部命令 ----
cat >"$TEST_DIR/bin/rofi" <<'EOF'
#!/usr/bin/env bash
n=$(cat "$ROFI_STATE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$ROFI_STATE"
printf '%s' "$(sed -n "${n}p" "$ROFI_SEQ")"
exit "$(sed -n "${n}p" "$ROFI_RC")"
EOF
cat >"$TEST_DIR/bin/xclip" <<'EOF'
#!/usr/bin/env bash
cat >"$CLIP_FILE"
EOF
cat >"$TEST_DIR/bin/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$XDG_LOG"
EOF
chmod +x "$TEST_DIR/bin"/*
export PATH="$TEST_DIR/bin:$PATH"
export ROFI_STATE="$TEST_DIR/rofi.n" CLIP_FILE="$TEST_DIR/clip" XDG_LOG="$TEST_DIR/xdg.log"

source "$DWM/rofi/scripts/util.sh"
source "$DWM/rofi/scripts/lib-module.sh"
source "$DWM/tools/wallpaper-lib.sh"
system-notify() { printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$TEST_DIR/notify.log"; }
module_confirm() { [[ "${MODULE_CONFIRM_RET:-Yes}" == "Yes" ]]; }

awk '/^select_marker_wallpaper\(\) \{/{f=1} f{print} f && /^\}$/{exit}' \
    "$DWM/rofi/scripts/wallpaper.sh" >"$TEST_DIR/fn.sh"
# shellcheck disable=SC1090
source "$TEST_DIR/fn.sh"

reset_case() {
    rm -f "$TEST_DIR/rofi.n" "$TEST_DIR/notify.log" "$TEST_DIR/wallpaper.calls" "$TEST_DIR/xdg.log" "$TEST_DIR/clip"
    : >"$TEST_DIR/notify.log"
}
set_seq() { # seq-file rc-file: 行一一对应 rofi 每次调用的输出与退出码
    printf '%s\n' "$1" >"$TEST_DIR/rofi.seq"
    printf '%s\n' "$2" >"$TEST_DIR/rofi.rc"
    export ROFI_SEQ="$TEST_DIR/rofi.seq" ROFI_RC="$TEST_DIR/rofi.rc"
    rm -f "$TEST_DIR/rofi.n"
}
rofi_calls() { cat "$TEST_DIR/rofi.n" 2>/dev/null || echo 0; }

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# ---- A: Enter 选中应用 (回归现行为) ----
reset_case
set_seq "0" "0"
select_marker_wallpaper "Web" random_web_dir web
check "Enter: 调 tools/wallpaper.sh file 选中目录" 'grep -q "file $FIX/111" "$TEST_DIR/wallpaper.calls"'
check "Enter: 只弹一次选择器" '[ "$(rofi_calls)" = 1 ]'

# ---- B: Alt+1 xdg-open 后重显, ESC 退出 ----
reset_case
set_seq "0
" "10
1"
select_marker_wallpaper "Web" random_web_dir web
check "Alt+1: xdg-open 参数为条目目录" 'grep -qx "$FIX/111" "$TEST_DIR/xdg.log"'
check "Alt+1: 不触发应用壁纸" '[[ ! -f $TEST_DIR/wallpaper.calls ]]'
check "Alt+1: 重显后 ESC 退出 (共 2 次)" '[ "$(rofi_calls)" = 2 ]'

# ---- C: Alt+2 复制绝对路径 (无换行) 后重显 ----
reset_case
set_seq "0
" "11
1"
select_marker_wallpaper "Web" random_web_dir web
check "Alt+2: 剪贴板恰为绝对路径无换行" 'cmp -s <(printf "%s" "$FIX/111") "$TEST_DIR/clip"'
check "Alt+2: 有 notify 反馈" 'grep -q "Copied" "$TEST_DIR/notify.log"'
check "Alt+2: 重显后 ESC 退出" '[ "$(rofi_calls)" = 2 ]'

# ---- D: Alt+3 确认 Yes 真删 ----
reset_case
mkdir -p "$FIX/222"
echo "<html></html>" >"$FIX/222/index.html"
printf '{"title":"t222","preview":"preview.jpg","file":"index.html","type":"web"}' >"$FIX/222/project.json"
echo "fake" >"$FIX/222/preview.jpg"
MODULE_CONFIRM_RET="Yes"
set_seq "1
" "12
1"
select_marker_wallpaper "Web" random_web_dir web
# 序号 1 对应第二行: 断言 111/222 恰删其一且总数减一
left=$(find "$FIX" -mindepth 1 -maxdepth 1 -type d | wc -l)
check "Alt+3 Yes: 删掉恰好一个目录" '[ "$left" = 1 ]'
check "Alt+3 Yes: 有删除 notify" 'grep -q "Deleted" "$TEST_DIR/notify.log"'
check "Alt+3 Yes: 不触发应用壁纸" '[[ ! -f $TEST_DIR/wallpaper.calls ]]'

# ---- E: Alt+3 确认 No 保留 ----
reset_case
mkdir -p "$FIX/111" "$FIX/222"
echo "<html></html>" >"$FIX/111/index.html"
echo "<html></html>" >"$FIX/222/index.html"
printf '{"title":"t111","preview":"preview.jpg","file":"index.html","type":"web"}' >"$FIX/111/project.json"
printf '{"title":"t222","preview":"preview.jpg","file":"index.html","type":"web"}' >"$FIX/222/project.json"
echo "fake" >"$FIX/111/preview.jpg"
echo "fake" >"$FIX/222/preview.jpg"
MODULE_CONFIRM_RET="No"
set_seq "0
" "12
1"
select_marker_wallpaper "Web" random_web_dir web
check "Alt+3 No: 目录保留" '[[ -d "$FIX/111" && -d "$FIX/222" ]]'
check "Alt+3 No: 无删除 notify" '! grep -q "Deleted" "$TEST_DIR/notify.log"'
MODULE_CONFIRM_RET="Yes"

# ---- F: custom key 下空输出则重显不崩 ----
reset_case
set_seq "
" "10
1"
select_marker_wallpaper "Web" random_web_dir web
check "空输出: 无动作但重显" '[[ ! -f $TEST_DIR/xdg.log ]] && [ "$(rofi_calls)" = 2 ]'

# ---- G: ESC 直接返回 ----
reset_case
set_seq "" "1"
select_marker_wallpaper "Web" random_web_dir web
check "ESC: 无动作单次返回" '[[ ! -f $TEST_DIR/xdg.log && ! -f $TEST_DIR/wallpaper.calls ]] && [ "$(rofi_calls)" = 1 ]'

exit $FAIL
