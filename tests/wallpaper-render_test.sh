#!/usr/bin/env bash
# wallpaper-render.sh 迁移测试: mock xwallpaper (有状态), 断言命令构造 + 状态流转
# latest 状态已迁移至 xwallpaper: 本测试验证脚本不再写缓存文件,
# 而是依赖 xwallpaper 的 set / clear --keep / restore / --list。
# 运行: bash tests/wallpaper-render_test.sh

SCRIPT="$HOME/.dwm/tools/wallpaper.sh"
RENDER="$HOME/.dwm/tools/wallpaper-render.sh"
LIB="$HOME/.dwm/tools/wallpaper-lib.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# ---- 隔离环境 ----
export HOME="$TEST_DIR/home"
export XDG_RUNTIME_DIR="$TEST_DIR/runtime"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
mkdir -p "$HOME/.config/dwm" "$HOME/.cache/wallpaper"

# ---- mock 外部命令 ----
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# 有状态 mock: 用 $XW_MOCK_STATE 目录模拟 xwallpaper 的窗口状态
#   *.win  = 活跃窗口 (内容 type\tpath\trot)
#   *.keep = clear --keep 保留的 last (restore 恢复为 .win)
cat >"$BIN/xwallpaper" <<'EOF'
#!/usr/bin/env bash
echo "xwallpaper $*" >>"$XW_MOCK_LOG"
DIR="$XW_MOCK_STATE"
mkdir -p "$DIR"
name=""; prev=""
case "$*" in
  *--list*)
    for f in "$DIR"/*.win; do
      [ -f "$f" ] || continue
      n="${f##*/}"; n="${n%.win}"
      printf '%s\n' "$n"
    done
    ;;
  *state*)
    for f in "$DIR"/*.win; do
      [ -f "$f" ] || continue
      n="${f##*/}"; n="${n%.win}"
      IFS=$'\t' read -r t p r <"$f"
      printf '%s\t%s\t%s\t%s\n' "$n" "$t" "$p" "$r"
    done
    ;;
  *set*)
    for a in "$@"; do
      [ "$prev" = "--name" ] && name="$a"
      prev="$a"
    done
    [ -z "$name" ] && exit 0
    type="image"; case "$*" in *--video*) type="video";; *--web*) type="web";; esac
    rot=0; prev=""
    for a in "$@"; do [ "$prev" = "--rotate" ] && rot="$a"; prev="$a"; done
    path="${@: -1}"
    printf '%s\t%s\t%s\n' "$type" "$path" "$rot" >"$DIR/${name// /_}.win"
    ;;
  *--keep*)
    for a in "$@"; do [ "$prev" = "-m" ] && name="$a"; prev="$a"; done
    [ -f "$DIR/${name// /_}.win" ] && mv "$DIR/${name// /_}.win" "$DIR/${name// /_}.keep"
    ;;
  *clear*)
    for a in "$@"; do [ "$prev" = "-m" ] && name="$a"; prev="$a"; done
    rm -f "$DIR/${name// /_}.win" "$DIR/${name// /_}.keep"
    ;;
  *restore*)
    for f in "$DIR"/*.keep; do
      [ -f "$f" ] || continue
      mv "$f" "${f%.keep}.win"
    done
    ;;
esac
exit 0
EOF

# 模拟双 monitor: eDP 1920x1080+0+0, HDMI 1920x1080+1920+0
cat >"$BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--listactivemonitors"* ]]; then
    echo "Monitors: 2"
    echo " 0: +*eDP 1920/344x1080/194+0+0  eDP"
    echo " 1: +HDMI 1920/344x1080/194+1920+0  HDMI"
else
    echo "screen 0: 1920x1080 344x194 0"
fi
exit 0
EOF

chmod +x "$BIN/xwallpaper" "$BIN/xrandr"
export PATH="$BIN:$PATH"

# ---- mock jq (默认配置创建) ----
if ! command -v jq >/dev/null 2>&1; then
    cat >"$BIN/jq" <<'EOF'
#!/usr/bin/env bash
echo '{}'
EOF
    chmod +x "$BIN/jq"
fi

# 预置配置, 避免 lib.sh 里 mkdir/jq 依赖
echo '{"monitors":{},"groups":{}}' >"$HOME/.config/dwm/wallpaper.json"

# ---- source (仅 lib + render, 不含 wallpaper.sh 的主逻辑) ----
source "$LIB"
source "$RENDER"

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
assert_has() { # haystack needle msg
    if [[ "$1" == *"$2"* ]]; then
        echo "ok: $3"
    else
        echo "FAIL: $3"
        echo "  haystack: $(printf '%q' "$1")"
        echo "  needle  : $(printf '%q' "$2")"
        FAIL=1
    fi
}
state_has() { # name msg  -- 断言 state 目录存在该窗口
    if [ -f "$XW_MOCK_STATE/$1.win" ]; then
        echo "ok: $2"
    else
        echo "FAIL: $2 ($1.win 不存在)"
        FAIL=1
    fi
}
state_lacks() { # name msg
    if [ ! -f "$XW_MOCK_STATE/$1.win" ]; then
        echo "ok: $2"
    else
        echo "FAIL: $2 ($1.win 应已清除)"
        FAIL=1
    fi
}

last_call() {
    tail -1 "$XW_MOCK_LOG" 2>/dev/null || echo ""
}
reset_log() {
    XW_MOCK_LOG="$TEST_DIR/xw_calls.log"
    XW_MOCK_STATE="$TEST_DIR/xw_state"
    : >"$XW_MOCK_LOG"
    rm -rf "$XW_MOCK_STATE"
    mkdir -p "$XW_MOCK_STATE"
    export XW_MOCK_LOG XW_MOCK_STATE
}
reset_log

# ---- Task 1: 图片壁纸到 monitor ----
echo "== image to monitor =="
set_wallpaper_to_monitor 0 "$TEST_DIR/img.png"
assert_has "$(last_call)" 'set --image -g 1920x1080+0+0 --name eDP' "image monitor rect+name"
state_has "eDP" "image latest state written by xwallpaper"

# ---- Task 2: 视频壁纸到 monitor (rotate + keybinds + fps) ----
echo "== video to monitor with rotate =="
reset_log
echo "p cycle pause" >"$HOME/.config/dwm/wallpaper.keys"
cat >"$HOME/.config/dwm/wallpaper.json" <<'EOF'
{"monitors":{},"groups":{},"render":{"video":{"fps":30}}}
EOF
WALLPAPER_ROTATION=90 set_wallpaper_to_monitor 0 "$TEST_DIR/clip.mp4"
assert_has "$(last_call)" '--video' "video type"
assert_has "$(last_call)" '--mute' "video muted by default"
assert_has "$(last_call)" '--rotate 90' "rotate passed"
assert_has "$(last_call)" '--fps 30' "fps from render.video.fps"
assert_has "$(last_call)" '--keybinds' "keybinds flag present"
assert_has "$(last_call)" '--name eDP' "video monitor name"
assert_has "$(cat "$XW_MOCK_STATE/eDP.win" 2>/dev/null)" "video" "video state type"
assert_has "$(cat "$XW_MOCK_STATE/eDP.win" 2>/dev/null)" "90" "video state rotation"

# ---- Task 3: 无 rotate 时视频不带 --rotate ----
echo "== video without rotate =="
reset_log
rm -f "$HOME/.config/dwm/wallpaper.keys"
WALLPAPER_ROTATION= set_wallpaper_to_monitor 0 "$TEST_DIR/clip.mp4"
local_call="$(last_call)"
assert_has "$local_call" '--video' "video still works"
assert_has "$local_call" '--mute' "video muted without rotate too"
if [[ "$local_call" == *"--rotate"* ]]; then
    echo "FAIL: 空 rotate 不应传 --rotate"
    FAIL=1
else
    echo "ok: 空 rotate 未传 --rotate"
fi

# ---- Task 4: Screen 全屏 ----
echo "== image to screen =="
reset_log
set_wallpaper_to_screen "$TEST_DIR/img.png"
assert_has "$(last_call)" 'set --image' "screen image"
assert_has "$(last_call)" '--name Screen' "screen target name"
state_has "Screen" "screen window state"

# ---- Task 5: 网页壁纸 ----
echo "== page to monitor =="
reset_log
set_wallpaper_to_monitor 0 "$TEST_DIR/page.html"
assert_has "$(last_call)" '--web' "page type -> --web"
assert_has "$(last_call)" '--name eDP' "page monitor name"

# ---- Task 6: group ----
echo "== video to group =="
echo '{"monitors":{},"groups":{"dual":{"enabled":true,"members":["eDP"]}}}' >"$HOME/.config/dwm/wallpaper.json"
reset_log
WALLPAPER_ROTATION= set_wallpaper_to_group dual "$TEST_DIR/clip.mp4"
call="$(last_call)"
assert_has "$call" 'set --video' "group video"
assert_has "$call" '--mute' "group video muted"
assert_has "$call" '--name grp_dual' "group target name"
assert_has "$call" '-g 1920x1080+0+0' "group rect"
if [[ "$call" == *"--fps"* ]]; then
    echo "FAIL: 未配置 fps 时不应传 --fps"
    FAIL=1
else
    echo "ok: 未配置 fps 未传 --fps"
fi
state_has "grp_dual" "group window state"

# ---- Task 7: screen 后设置 monitor 清除 screen ----
echo "== monitor after screen clears screen =="
reset_log
set_wallpaper_to_screen "$TEST_DIR/img.png"
state_has "Screen" "screen active"
set_wallpaper_to_monitor 0 "$TEST_DIR/img.png"
assert_has "$(cat "$XW_MOCK_LOG")" 'clear -m Screen' "monitor set clears screen window"
if [[ "$(cat "$XW_MOCK_LOG")" == *'clear --keep -m eDP'* ]]; then
    echo "FAIL: eDP 未 active 不应被 clear --keep (仅清实际存在窗口)"
    FAIL=1
else
    echo "ok: 未 active 的 eDP 不被 clear --keep"
fi
state_lacks "Screen" "screen window removed after monitor set"
state_has "eDP" "monitor applied after screen"

# ---- Task 8: screen 后设置 group 清除 screen ----
echo "== group after screen clears screen =="
reset_log
set_wallpaper_to_screen "$TEST_DIR/img.png"
set_wallpaper_to_group dual "$TEST_DIR/clip.mp4"
assert_has "$(cat "$XW_MOCK_LOG")" 'clear -m Screen' "group set clears screen window"
state_lacks "Screen" "screen window removed after group set"
state_has "grp_dual" "group applied after screen"

# ---- Task 9: screen 清除后其它 monitor 恢复 last (restore) ----
echo "== other monitor restored after screen removed =="
echo '{"monitors":{},"groups":{}}' >"$HOME/.config/dwm/wallpaper.json"
reset_log
set_wallpaper_to_monitor 0 "$TEST_DIR/img.png"
set_wallpaper_to_monitor 1 "$TEST_DIR/img.png"
set_wallpaper_to_screen "$TEST_DIR/img.png"
set_wallpaper_to_monitor 0 "$TEST_DIR/img2.png"
assert_has "$(cat "$XW_MOCK_LOG")" 'restore' "restore invoked after screen cleared"
state_has "HDMI" "hdmi last restored after screen removed"
state_has "eDP" "monitor applied after restore"

echo
if [ "$FAIL" = "1" ]; then
    echo "RESULT: FAIL"
    exit 1
else
    echo "RESULT: PASS"
    exit 0
fi
