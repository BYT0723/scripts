#!/usr/bin/env bash
# wallpaper light/dark 主题目录回归测试 (Task 1):
#   1. light → 返回 base key
#   2. dark 已配 → 返回 ${base}_dark (image + video)
#   3. dark 缺失/空串 → fallback base
#   4. random_wallpaper 按主题选目录
# 运行: bash tests/wallpaper-theme_test.sh

LIB="$HOME/.dwm/tools/wallpaper-lib.sh"
WALLPAPER_SH="$HOME/.dwm/tools/wallpaper.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm" "$HOME/.cache/wallpaper"

BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# ---- mock xwallpaper/xrandr ----
export XW_MOCK_STATE="$TEST_DIR/xw"
mkdir -p "$XW_MOCK_STATE"
export XW_MOCK_LOG="$TEST_DIR/xw.log"
: >"$XW_MOCK_LOG"
cat >"$BIN/xwallpaper" <<'EOF'
#!/usr/bin/env bash
echo "xwallpaper $*" >>"$XW_MOCK_LOG"
case "$*" in
*--list*) exit 0 ;;
*state*) exit 0 ;;
*set*)
    name=""; prev=""
    for a in "$@"; do [ "$prev" = "--name" ] && name="$a"; prev="$a"; done
    path="${@: -1}"
    printf 'image\t%s\t0\n' "$path" >"$XW_MOCK_STATE/${name// /_}.win"
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

cat >"$HOME/.config/dwm/wallpaper.json" <<EOF
{
  "monitors": {
    "eDP": {
      "random": 1,
      "random_type": "image",
      "random_image_dir": "$TEST_DIR/light/img",
      "random_image_dir_dark": "$TEST_DIR/dark/img",
      "random_video_dir": "$TEST_DIR/light/vid",
      "random_video_dir_dark": "",
      "random_depth": 3,
      "duration": 30
    },
    "HDMI-A-0": {
      "random": 1,
      "random_type": "image",
      "random_image_dir": "$TEST_DIR/light/img",
      "random_depth": 3,
      "duration": 30
    }
  },
  "groups": {}
}
EOF

set -- # 避免误触发 wallpaper.sh 底部分派（source lib 时无分派，无需但保持与旧测试一致）
# shellcheck disable=SC1090
source "$LIB"
# random_wallpaper 定义在 wallpaper.sh，提取函数避免执行底部 case 分派
eval "$(awk '/^random_wallpaper\(\) \{/,/^}$/' "$WALLPAPER_SH")"

fail=0
check() { # desc, cond
    if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

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
case "$f" in "$TEST_DIR/light/img/"*) ok=0;; *) ok=1;; esac
check "light random_wallpaper 出自 light 目录" "[ $ok -eq 0 ]"

exit "$fail"
