#!/usr/bin/env bash
# rofi/scripts/wallpaper.sh web/scene 选择器末尾 yazi 目录入口回归测试:
#   末条为 "Browse directory (yazi)" (__YAZI__), Enter 经 yazi 选目录 (文件取上层),
#   web 要 index.html / scene 要 scene.pkg|json, 非法 notify 留 selector, 取消回 selector,
#   Alt+1/2/3 落在末条忽略重显。image/video 不受影响 (沿用 tools/wallpaper.sh -m select)。
# 沿 rofi-wallpaper-selector-keys_test.sh 先例: awk 提取函数 + mock rofi/yazi/外部命令
# 注意: 序号断言依赖单一条目池 (sentinel 恒为序号 1); 多行序列用字面换行 (同 selector-keys 先例)。
# 运行: bash tests/rofi-wallpaper-selector-yazi_test.sh

DWM="$(cd "$(dirname "$0")/.." && pwd)"
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

# ---- fixture: 单一条目池 (sentinel 序号恒为 1) ----
WEBPOOL="$TEST_DIR/webpool"
mkdir -p "$WEBPOOL/111"
echo "<html></html>" >"$WEBPOOL/111/index.html"
SCENEPOOL="$TEST_DIR/scenepool"
mkdir -p "$SCENEPOOL/333"
echo '{"title":"s"}' >"$SCENEPOOL/333/scene.json"
mkdir -p "$TEST_DIR/good-web"
echo "<html></html>" >"$TEST_DIR/good-web/index.html"
mkdir -p "$TEST_DIR/good-scene"
echo '{"title":"s"}' >"$TEST_DIR/good-scene/scene.json"
mkdir -p "$TEST_DIR/baddir"
echo "nothing" >"$TEST_DIR/baddir/note.txt"
printf '{"monitors":{"TESTMON":{"random_web_dir":"%s","random_scene_dir":"%s"}}}' "$WEBPOOL" "$SCENEPOOL" >"$HOME/.config/dwm/wallpaper.json"
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
# yazi mock: 记录起始目录, 按 $YAZI_CHOSEN 写 chooser (沿 portable-paths 先例)
cat >"$TEST_DIR/bin/yazi" <<'EOF'
#!/usr/bin/env bash
start=""
chooser=""
for a in "$@"; do
    case "$a" in
    --chooser-file=*) chooser="${a#--chooser-file=}" ;;
    --chooser-file) ;;
    -*) ;;
    *) [ -z "$start" ] && start="$a" ;;
    esac
done
printf '%s\n' "$start" >>"$YAZI_START_LOG"
chosen=$(cat "$YAZI_CHOSEN" 2>/dev/null)
[ -n "$chosen" ] && printf '%s\n' "$chosen" >"$chooser"
exit 0
EOF
chmod +x "$TEST_DIR/bin"/*
export PATH="$TEST_DIR/bin:$PATH"
export ROFI_STATE="$TEST_DIR/rofi.n" CLIP_FILE="$TEST_DIR/clip" XDG_LOG="$TEST_DIR/xdg.log"
export YAZI_START_LOG="$TEST_DIR/yazi-start.log" YAZI_CHOSEN="$TEST_DIR/yazi-chosen"
export TERMINAL=env

source "$DWM/rofi/scripts/util.sh"
source "$DWM/rofi/scripts/lib-module.sh"
source "$DWM/tools/wallpaper-lib.sh"
system-notify() { printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$TEST_DIR/notify.log"; }
module_confirm() { [[ "${MODULE_CONFIRM_RET:-Yes}" == "Yes" ]]; }

awk '/^select_yazi_directory\(\) \{/{f=1} f{print} f && /^\}$/{exit}' \
    "$DWM/rofi/scripts/wallpaper.sh" >"$TEST_DIR/fn.sh"
awk '/^select_marker_wallpaper\(\) \{/{f=1} f{print} f && /^\}$/{exit}' \
    "$DWM/rofi/scripts/wallpaper.sh" >>"$TEST_DIR/fn.sh"
# shellcheck disable=SC1090
source "$TEST_DIR/fn.sh"

reset_case() {
    rm -f "$TEST_DIR/rofi.n" "$TEST_DIR/notify.log" "$TEST_DIR/wallpaper.calls" "$TEST_DIR/xdg.log" "$TEST_DIR/clip" "$TEST_DIR/yazi-start.log"
    : >"$TEST_DIR/notify.log"
    : >"$TEST_DIR/yazi-start.log"
}
set_seq() { # $1 输出序列 $2 退出码序列: 行一一对应 rofi 每次调用 (字面换行分隔)
    printf '%s\n' "$1" >"$TEST_DIR/rofi.seq"
    printf '%s\n' "$2" >"$TEST_DIR/rofi.rc"
    export ROFI_SEQ="$TEST_DIR/rofi.seq" ROFI_RC="$TEST_DIR/rofi.rc"
    rm -f "$TEST_DIR/rofi.n"
}
rofi_calls() { cat "$TEST_DIR/rofi.n" 2>/dev/null || echo 0; }

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# ---- A: 末条 Enter → yazi 合法 web 目录直接应用 ----
reset_case
printf '%s\n' "$TEST_DIR/good-web" >"$YAZI_CHOSEN"
set_seq "1" "0"
select_marker_wallpaper "Web" random_web_dir '.*/index\.html'
check "A: yazi 合法目录触发 file 应用" 'grep -q "file $TEST_DIR/good-web" "$TEST_DIR/wallpaper.calls"'
check "A: 只弹一次选择器" '[ "$(rofi_calls)" = 1 ]'

# ---- B: yazi 取消 (空输出) → 回 selector, ESC 退出 ----
reset_case
: >"$YAZI_CHOSEN"
set_seq "1
" "0
1"
select_marker_wallpaper "Web" random_web_dir '.*/index\.html'
check "B: 取消不应用壁纸" '[[ ! -f $TEST_DIR/wallpaper.calls ]]'
check "B: 重显后 ESC 退出 (共 2 次)" '[ "$(rofi_calls)" = 2 ]'

# ---- C: 非法目录 (无 marker) → notify, 不应用, 回 selector ----
reset_case
printf '%s\n' "$TEST_DIR/baddir" >"$YAZI_CHOSEN"
set_seq "1
" "0
1"
select_marker_wallpaper "Web" random_web_dir '.*/index\.html'
check "C: 非法目录不应用" '[[ ! -f $TEST_DIR/wallpaper.calls ]]'
check "C: 有非法反馈 notify" 'grep -qi "index.html\|not a\|invalid" "$TEST_DIR/notify.log"'
check "C: 重显后 ESC 退出" '[ "$(rofi_calls)" = 2 ]'

# ---- D: Alt+1 落在末条 → 忽略重显, 无 xdg-open ----
reset_case
printf '%s\n' "$TEST_DIR/good-web" >"$YAZI_CHOSEN"
set_seq "1
" "10
1"
select_marker_wallpaper "Web" random_web_dir '.*/index\.html'
check "D: Alt+1 不打开外部程序" '[[ ! -f $TEST_DIR/xdg.log ]]'
check "D: Alt+1 不应用壁纸" '[[ ! -f $TEST_DIR/wallpaper.calls ]]'
check "D: 重显后 ESC 退出" '[ "$(rofi_calls)" = 2 ]'

# ---- E: scene 合法目录应用 ----
reset_case
printf '%s\n' "$TEST_DIR/good-scene" >"$YAZI_CHOSEN"
set_seq "1" "0"
select_marker_wallpaper "Scene" random_scene_dir '.*/scene\.(pkg|json)'
check "E: scene 合法目录触发 file 应用" 'grep -q "file $TEST_DIR/good-scene" "$TEST_DIR/wallpaper.calls"'

# ---- F: scene 选文件取上层 (yazi 返回文件) ----
reset_case
printf '%s\n' "$TEST_DIR/good-scene/scene.json" >"$YAZI_CHOSEN"
set_seq "1" "0"
select_marker_wallpaper "Scene" random_scene_dir '.*/scene\.(pkg|json)'
check "F: 文件输入归一到目录后应用" 'grep -q "file $TEST_DIR/good-scene" "$TEST_DIR/wallpaper.calls"'

# ---- G: 旧行为不变: 首条 Enter 直接应用, 不调 yazi ----
reset_case
set_seq "0" "0"
select_marker_wallpaper "Web" random_web_dir '.*/index\.html'
check "G: 首条 Enter 仍直接应用" 'grep -q "file $WEBPOOL/111" "$TEST_DIR/wallpaper.calls"'
check "G: 未调 yazi" '[[ ! -s $TEST_DIR/yazi-start.log ]]'

exit $FAIL
