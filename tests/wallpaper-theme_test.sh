#!/usr/bin/env bash
# wallpaper light/dark 主题目录回归测试:
#   Task 1: get_theme_dir + random_wallpaper 按主题选目录
#     1. light → 返回 base key
#     2. dark 已配 → 返回 ${base}_dark (image + video)
#     3. dark 缺失/空串 → fallback base
#     4. random_wallpaper 按主题选目录
#   Task 2: theme_wallpaper 批量切换
#     5. --theme dark/light 切单 monitor 到对应目录
#     6. 组员 monitor 被 skip，组窗口 grp_<名> 被切
#     7. Screen 激活时只切 Screen
#     8. 单 target 失效不中断整批
# 运行: bash tests/wallpaper-theme_test.sh

LIB="$HOME/.dwm/tools/wallpaper-lib.sh"
WALLPAPER_SH="$HOME/.dwm/tools/wallpaper.sh"
RENDER_SH="$HOME/.dwm/tools/wallpaper-render.sh"
THEME_SH="$HOME/.dwm/tools/theme.sh"
ROFI_WALLPAPER_SH="$HOME/.dwm/rofi/scripts/wallpaper.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm" "$HOME/.cache/wallpaper"

BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# ---- mock xwallpaper（有状态）/xrandr ----
export XW_MOCK_STATE="$TEST_DIR/xw"
mkdir -p "$XW_MOCK_STATE"
export XW_MOCK_LOG="$TEST_DIR/xw.log"
: >"$XW_MOCK_LOG"
cat >"$BIN/xwallpaper" <<'EOF'
#!/usr/bin/env bash
echo "xwallpaper $*" >>"$XW_MOCK_LOG"
DIR="$XW_MOCK_STATE"
mkdir -p "$DIR"
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
    name=""; prev=""
    for a in "$@"; do [ "$prev" = "--name" ] && name="$a"; prev="$a"; done
    path="${@: -1}"
    printf 'image\t%s\t0\n' "$path" >"$DIR/${name// /_}.win"
    ;;
esac
exit 0
EOF
cat >"$BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
case "$1" in
--listactivemonitors)
    echo "Monitors: 1"
    echo " 0: +*eDP 1920/336x1080/210+0+0  eDP"
    ;;
*) exit 0 ;;
esac
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

# ---- 灯光目录素材 ----
mkdir -p "$TEST_DIR/light/img" "$TEST_DIR/dark/img" "$TEST_DIR/light/vid"
touch "$TEST_DIR/light/img/a.jpg" "$TEST_DIR/light/img/b.jpg"
touch "$TEST_DIR/dark/img/c.jpg"
touch "$TEST_DIR/light/vid/v.mp4"

write_conf() { printf '%s\n' "$1" >"$HOME/.config/dwm/wallpaper.json"; }
base_conf() {
    write_conf "{
  \"monitors\": {
    \"eDP\": {
      \"random\": 1,
      \"random_type\": \"image\",
      \"random_image_dir\": \"$TEST_DIR/light/img\",
      \"random_image_dir_dark\": \"$TEST_DIR/dark/img\",
      \"random_video_dir\": \"$TEST_DIR/light/vid\",
      \"random_video_dir_dark\": \"\",
      \"random_depth\": 3,
      \"duration\": 30
    },
    \"HDMI-A-0\": {
      \"random\": 1,
      \"random_type\": \"image\",
      \"random_image_dir\": \"$TEST_DIR/light/img\",
      \"random_depth\": 3,
      \"duration\": 30
    }
  },
  \"groups\": {}
}"
}

base_conf

set -- # 避免误触发 wallpaper.sh 底部分派（source lib 时无分派，无需但保持与旧测试一致）
# shellcheck disable=SC1090
source "$LIB"
# shellcheck disable=SC1090
source "$RENDER_SH"
# wallpaper.sh 底部有 case 分派不能直接 source，按函数名提取
eval "$(awk '/^(random_wallpaper|get_wallpaper_rotation|apply_wallpaper|theme_wallpaper)\(\) \{/,/^}$/' "$WALLPAPER_SH")"

fail=0
check() { # desc, cond
    if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}
reset_state() { rm -f "$XW_MOCK_STATE"/*.win; }

# ---- 1. light → base ----
echo "light" >"$HOME/.local/state/dwm/current-theme"
check "light image → base" "[ \"\$(get_theme_dir eDP random_image_dir)\" = \"$TEST_DIR/light/img\" ]"
check "light video → base" "[ \"\$(get_theme_dir eDP random_video_dir)\" = \"$TEST_DIR/light/vid\" ]"

# ---- 2. dark 已配 → dark ----
echo "dark" >"$HOME/.local/state/dwm/current-theme"
check "dark image → dark" "[ \"\$(get_theme_dir eDP random_image_dir)\" = \"$TEST_DIR/dark/img\" ]"

# ---- 3. dark 缺失/空串 → fallback ----
check "dark video 空串 → fallback light" "[ \"\$(get_theme_dir eDP random_video_dir)\" = \"$TEST_DIR/light/vid\" ]"
check "dark 未配 key → fallback light" "[ \"\$(get_theme_dir HDMI-A-0 random_image_dir)\" = \"$TEST_DIR/light/img\" ]"

# ---- 4. random_wallpaper 按主题选目录 ----
echo "dark" >"$HOME/.local/state/dwm/current-theme"
f=$(random_wallpaper eDP)
check "dark random_wallpaper 出自 dark 目录" "[ \"$f\" = \"$TEST_DIR/dark/img/c.jpg\" ]"
echo "light" >"$HOME/.local/state/dwm/current-theme"
f=$(random_wallpaper eDP)
case "$f" in "$TEST_DIR/light/img/"*) ok=0 ;; *) ok=1 ;; esac
check "light random_wallpaper 出自 light 目录" "[ $ok -eq 0 ]"

# ---- 5. theme_wallpaper 切单 monitor ----
base_conf
reset_state
theme_wallpaper dark
check "theme dark → eDP 切到 dark" "grep -q \"$TEST_DIR/dark/img/c.jpg\" \"$XW_MOCK_STATE/eDP.win\""
reset_state
theme_wallpaper light
check "theme light → eDP 切到 light" "grep -q \"$TEST_DIR/light/img/\" \"$XW_MOCK_STATE/eDP.win\""
reset_state
echo "dark" >"$HOME/.local/state/dwm/current-theme"
theme_wallpaper auto
check "theme auto 跟随 current-theme(dark)" "grep -q \"$TEST_DIR/dark/img/c.jpg\" \"$XW_MOCK_STATE/eDP.win\""

# ---- 6. 组员 skip，组窗口被切 ----
write_conf "{
  \"monitors\": {
    \"eDP\": {\"random\": 1, \"random_type\": \"image\", \"random_image_dir\": \"$TEST_DIR/light/img\", \"random_image_dir_dark\": \"$TEST_DIR/dark/img\", \"random_depth\": 3, \"duration\": 30},
    \"G1\": {\"random\": 1, \"random_type\": \"image\", \"random_image_dir\": \"$TEST_DIR/light/img\", \"random_image_dir_dark\": \"$TEST_DIR/dark/img\", \"random_depth\": 3, \"duration\": 30}
  },
  \"groups\": {\"G1\": {\"enabled\": true, \"members\": [\"eDP\"]}}
}"
reset_state
theme_wallpaper dark
check "组员 eDP 被 skip" "[ ! -f \"$XW_MOCK_STATE/eDP.win\" ]"
check "组窗口 grp_G1 被切到 dark" "grep -q \"$TEST_DIR/dark/img/c.jpg\" \"$XW_MOCK_STATE/grp_G1.win\""

# ---- 7. Screen 激活只切 Screen ----
base_conf
reset_state
printf 'image\t%s\t0\n' "$TEST_DIR/light/img/a.jpg" >"$XW_MOCK_STATE/Screen.win"
write_conf "{
  \"monitors\": {
    \"eDP\": {\"random\": 1, \"random_type\": \"image\", \"random_image_dir\": \"$TEST_DIR/light/img\", \"random_image_dir_dark\": \"$TEST_DIR/dark/img\", \"random_depth\": 3, \"duration\": 30},
    \"Screen\": {\"random\": 1, \"random_type\": \"image\", \"random_image_dir\": \"$TEST_DIR/light/img\", \"random_image_dir_dark\": \"$TEST_DIR/dark/img\", \"random_depth\": 3, \"duration\": 30}
  },
  \"groups\": {}
}"
theme_wallpaper dark
check "Screen 被切到 dark" "grep -q \"$TEST_DIR/dark/img/c.jpg\" \"$XW_MOCK_STATE/Screen.win\""
check "Screen 模式下 eDP 不动" "[ ! -f \"$XW_MOCK_STATE/eDP.win\" ]"

# ---- 8. 单 target 失效不中断 ----
write_conf "{
  \"monitors\": {
    \"eDP\": {\"random\": 1, \"random_type\": \"image\", \"random_image_dir\": \"/nonexistent-dir-xyz\", \"random_depth\": 3, \"duration\": 30}
  },
  \"groups\": {}
}"
reset_state
rc=0
theme_wallpaper dark || rc=$?
check "单 target 失效仍退出 0" "[ $rc -eq 0 ]"

# ---- 9. theme hook + rofi 接线存在性 ----
check "theme _do_theme_change hook 壁纸跟随（后台）" "grep -q 'wallpaper.sh.*--theme.*&' \"$THEME_SH\""
check "rofi 有 Images Dark 入口" "grep -q 'random_images_path_dark' \"$ROFI_WALLPAPER_SH\""
check "rofi 有 Videos Dark 入口" "grep -q 'random_videos_path_dark' \"$ROFI_WALLPAPER_SH\""

exit "$fail"
