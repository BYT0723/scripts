#!/usr/bin/env bash
# wallpaper-render.sh 迁移测试: mock xwallpaper, 断言命令构造正确
# 运行: bash tests/wallpaper-render_test.sh

SCRIPT="$HOME/.dwm/tools/wallpaper.sh"
RENDER="$HOME/.dwm/tools/wallpaper-render.sh"
LIB="$HOME/.dwm/tools/wallpaper-lib.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
trap 'rm -rf "$TEST_DIR"' EXIT

# ---- 隔离环境 ----
export HOME="$TEST_DIR/home"
export XDG_RUNTIME_DIR="$TEST_DIR/runtime"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
mkdir -p "$HOME/.config/dwm" "$HOME/.cache/wallpaper"

# ---- mock 外部命令 ----
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

cat >"$BIN/xwallpaper" <<'EOF'
#!/usr/bin/env bash
echo "xwallpaper $*" >>"$XW_MOCK_LOG"
# 模拟成功: set 回 ok, 其他回空
exit 0
EOF

# 模拟单 monitor 1920x1080+0+0, 名为 eDP
cat >"$BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--listactivemonitors"* ]]; then
    echo "Monitors: 1"
    echo " 0: +*eDP 1920/344x1080/194+0+0  eDP"
else
    echo "screen 0: 1920x1080 344x194 0"
fi
exit 0
EOF

chmod +x "$BIN/xwallpaper" "$BIN/xrandr"
export PATH="$BIN:$PATH"

# ---- mock jq (默认配置创建) ----
# lib.sh 用 jq -n 创建默认配置; 测试目录已有 .config/dwm, 若配置文件不存在会调用 jq
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

last_call() { # 返回最后一次 xwallpaper 调用
    tail -1 "$XW_MOCK_LOG" 2>/dev/null || echo ""
}
reset_log() {
    XW_MOCK_LOG="$TEST_DIR/xw_calls.log"
    : >"$XW_MOCK_LOG"
    export XW_MOCK_LOG
}
reset_log

# ---- Task 1: 图片壁纸到 monitor ----
echo "== image to monitor =="
set_wallpaper_to_monitor 0 "$TEST_DIR/img.png"
assert_has "$(last_call)" 'set --image -g 1920x1080+0+0 --name eDP' "image monitor rect+name"
# latest 缓存写 filepath (无 rotation)
assert_has "$(cat "${wallpaper_latest}_0" 2>/dev/null)" "$TEST_DIR/img.png" "image latest cached"
if grep -q '|' "${wallpaper_latest}_0" 2>/dev/null; then
    echo "FAIL: image latest 不应含 rotation"
    FAIL=1
else
    echo "ok: image latest 无 rotation"
fi

# ---- Task 2: 视频壁纸到 monitor (rotate + keybinds + fps) ----
echo "== video to monitor with rotate =="
reset_log
# 创建 keybinds 文件
echo "p cycle pause" >"$HOME/.config/dwm/wallpaper.keys"
# 配置 render.video.fps
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
# latest 缓存写 filepath|rotation
assert_has "$(cat "${wallpaper_latest}_0" 2>/dev/null)" "$TEST_DIR/clip.mp4|90" "video latest cached with rotation"

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

# ---- Task 5: 网页壁纸 ----
echo "== page to monitor =="
reset_log
set_wallpaper_to_monitor 0 "$TEST_DIR/page.html"
assert_has "$(last_call)" '--web' "page type -> --web"
assert_has "$(last_call)" '--name eDP' "page monitor name"

# ---- Task 6: group ----
echo "== video to group =="
# group 需要一个成员: 在配置里定义
echo '{"monitors":{},"groups":{"dual":{"enabled":true,"members":["eDP"]}}}' >"$HOME/.config/dwm/wallpaper.json"
reset_log
# mock get_monitor_info 直接由 monitor.sh 用 xrandr 算; get_group_dim 会走 get_monitor_info
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

echo
if [ "$FAIL" = "1" ]; then
    echo "RESULT: FAIL"
    exit 1
else
    echo "RESULT: PASS"
    exit 0
fi
