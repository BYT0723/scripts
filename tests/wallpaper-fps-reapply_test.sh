#!/usr/bin/env bash
# handle_fps 回归测试:
#   A. 有效输入且值改变 + 当前为 video → 写配置 + clear + 重设 (新 --fps 生效)
#   B. 非法输入 (非整数/负数/小数/空) → 不写配置, 不重建
#   C. 值未改变 → 不重建 (避免无谓闪烁)
#   D. 当前为 image / 无窗口 → 只写配置, 不重建
#   E. group video → clear grp_<组名> + 按组名重设
#   F. rotation 保留 (state 第 4 列透传 --rotate)
#
# 背景: xwallpaperd 内 mpv 仅在创建时读取 --fps, 同名 set 走 reload
# 不会重建 mpv, 故 fps 改变后必须 clear + 重设同一文件。
# 运行: bash tests/wallpaper-fps-reapply_test.sh

DWM="$HOME/.dwm"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.cache/wallpaper"
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# ---- mock xwallpaper (有状态, 同 wallpaper-render_test.sh) ----
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
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

XW_MOCK_LOG="$TEST_DIR/xw_calls.log"
XW_MOCK_STATE="$TEST_DIR/xw_state"
export XW_MOCK_LOG XW_MOCK_STATE
reset_state() {
    : >"$XW_MOCK_LOG"
    rm -rf "$XW_MOCK_STATE"
    mkdir -p "$XW_MOCK_STATE"
}

source "$DWM/tools/wallpaper-lib.sh"
source "$DWM/tools/wallpaper-render.sh"

# rofi 脚本顶层含交互式 monitor_selection, 无法整体 source, 仅提取 handle_fps
# (结束模式用 /^}/ 而非 /^\}$/: 单行函数没有独占 `}` 行, 后者会吞掉文件尾的
# `while module_loop` 并 eval 执行, 拉起真 rofi 阻塞测试)
eval "$(awk '/^handle_fps\(\) \{/{f=1} f{print} f && /^}/{exit}' "$DWM/rofi/scripts/wallpaper.sh")"

# module_input 由 rofi 弹窗改为测试注入
module_input() { printf '%s' "$MOCK_NEW"; }

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}
fps_of() { jq -r '.monitors["eDP"]["video-render"].fps // "none"' "$HOME/.config/dwm/wallpaper.json"; }

seed_conf() { # fps
    cat >"$HOME/.config/dwm/wallpaper.json" <<EOF
{"monitors":{"eDP":{"random_type":"video","video-render":{"fps":$1}}},"groups":{}}
EOF
}
seed_video_win() { # path rot
    printf 'video\t%s\t%s\n' "$1" "$2" >"$XW_MOCK_STATE/eDP.win"
}

# ---- A: 有效输入 + video → 写配置 + clear + 重设 ----
seed_conf 30; reset_state; seed_video_win "/v.mp4" "0"
MONITOR="eDP" MOCK_NEW=15 handle_fps
check "A: 配置更新为 15" '[ "$(fps_of)" = 15 ]'
check "A: clear 当前窗口" 'grep -q "clear -m eDP" "$XW_MOCK_LOG"'
check "A: 重设带新 --fps 15" 'grep -Fq -- "--fps 15" "$XW_MOCK_LOG"'
check "A: 重设同一文件" 'grep -q "/v.mp4" "$XW_MOCK_LOG"'

# ---- B: 非法输入 → 不写不重建 ----
for bad in "abc" "-5" "12.5" ""; do
    seed_conf 30; reset_state; seed_video_win "/v.mp4" "0"
    MONITOR="eDP" MOCK_NEW="$bad" handle_fps
    check "B($bad): 配置保持 30" '[ "$(fps_of)" = 30 ]'
    check "B($bad): 无 clear" '! grep -q "clear" "$XW_MOCK_LOG"'
    check "B($bad): 无 set" '! grep -q " set " "$XW_MOCK_LOG"'
done

# ---- C: 值未变 → 不重建 ----
seed_conf 30; reset_state; seed_video_win "/v.mp4" "0"
MONITOR="eDP" MOCK_NEW=30 handle_fps
check "C: 相同值不 clear" '! grep -q "clear" "$XW_MOCK_LOG"'

# ---- D1: 当前 image → 只写配置 ----
seed_conf 30; reset_state
printf 'image\t%s\t%s\n' "/a.png" "0" >"$XW_MOCK_STATE/eDP.win"
MONITOR="eDP" MOCK_NEW=15 handle_fps
check "D1: image 时配置仍更新" '[ "$(fps_of)" = 15 ]'
check "D1: image 时不重建" '! grep -q "clear" "$XW_MOCK_LOG" && ! grep -q " set " "$XW_MOCK_LOG"'

# ---- D2: 无窗口 → 只写配置 ----
seed_conf 30; reset_state
MONITOR="eDP" MOCK_NEW=15 handle_fps
check "D2: 无窗口时配置仍更新" '[ "$(fps_of)" = 15 ]'
check "D2: 无窗口时不重建" '! grep -q "clear" "$XW_MOCK_LOG" && ! grep -q " set " "$XW_MOCK_LOG"'

# ---- E: group video ----
cat >"$HOME/.config/dwm/wallpaper.json" <<'EOF'
{"monitors":{"dual":{"video-render":{"fps":30}}},"groups":{"dual":{"enabled":true,"members":["eDP"]}}}
EOF
reset_state
printf 'video\t%s\t%s\n' "/g.mp4" "0" >"$XW_MOCK_STATE/grp_dual.win"
MONITOR="dual" MOCK_NEW=24 handle_fps
check "E: 组配置更新" '[ "$(jq -r ".monitors.dual[\"video-render\"].fps" "$HOME/.config/dwm/wallpaper.json")" = 24 ]'
check "E: clear 组窗口" 'grep -q "clear -m grp_dual" "$XW_MOCK_LOG"'
check "E: 组重设带新 fps" 'grep -Fq -- "--fps 24" "$XW_MOCK_LOG" && grep -q "grp_dual" "$XW_MOCK_LOG"'

# ---- F: rotation 保留 ----
seed_conf 30; reset_state; seed_video_win "/v.mp4" "90"
MONITOR="eDP" MOCK_NEW=15 handle_fps
check "F: 重设透传 --rotate 90" 'grep -Fq -- "--rotate 90" "$XW_MOCK_LOG"'

# ---- G: Screen video ----
cat >"$HOME/.config/dwm/wallpaper.json" <<'EOF'
{"monitors":{"Screen":{"video-render":{"fps":30}}},"groups":{}}
EOF
reset_state
printf 'video\t%s\t%s\n' "/s.mp4" "0" >"$XW_MOCK_STATE/Screen.win"
MONITOR="Screen" MOCK_NEW=20 handle_fps
check "G: Screen 配置更新" '[ "$(jq -r ".monitors.Screen[\"video-render\"].fps" "$HOME/.config/dwm/wallpaper.json")" = 20 ]'
check "G: clear Screen" 'grep -q "clear -m Screen" "$XW_MOCK_LOG"'
check "G: Screen 重设带新 fps" 'grep -Fq -- "--fps 20" "$XW_MOCK_LOG" && grep -q -- "--name Screen" "$XW_MOCK_LOG"'

exit $fail
