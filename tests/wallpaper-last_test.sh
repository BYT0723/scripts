#!/usr/bin/env bash
# wallpaper light/dark 记忆回归测试 (方案 A):
#   1. save/get 按 target+mode 独立读写
#   2. 缺失/损坏时 get 为空、save 可恢复
#   3. theme_wallpaper 优先恢复记忆 (pin c.jpg 后即使有 d.jpg 也不 random)
#   4. 记忆文件不存在 → 回退 random
#   5. light/dark 互相独立，来回切换恢复各自上次
# 运行: bash tests/wallpaper-last_test.sh

LIB="$HOME/.dwm/tools/wallpaper-lib.sh"
WALLPAPER_SH="$HOME/.dwm/tools/wallpaper.sh"
RENDER_SH="$HOME/.dwm/tools/wallpaper-render.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm" "$HOME/.cache/wallpaper"

BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

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

mkdir -p "$TEST_DIR/light/img" "$TEST_DIR/dark/img"
touch "$TEST_DIR/light/img/a.jpg" "$TEST_DIR/light/img/b.jpg"
touch "$TEST_DIR/dark/img/c.jpg" "$TEST_DIR/dark/img/d.jpg"

printf '{\n  "monitors": {\n    "eDP": {\n      "random": 1,\n      "random_type": "image",\n      "random_image_dir": "%s",\n      "random_image_dir_dark": "%s",\n      "random_depth": 3,\n      "duration": 30\n    }\n  },\n  "groups": {}\n}\n' \
    "$TEST_DIR/light/img" "$TEST_DIR/dark/img" >"$HOME/.config/dwm/wallpaper.json"

set --
# shellcheck disable=SC1090
source "$LIB"
# shellcheck disable=SC1090
source "$RENDER_SH"
eval "$(awk '/^(random_wallpaper|get_wallpaper_rotation|apply_wallpaper|theme_wallpaper)\(\) \{/,/^}$/' "$WALLPAPER_SH")"

fail=0
check() {
    if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

# ---- 1. save/get 独立 ----
save_last_wallpaper "eDP" "dark" "$TEST_DIR/dark/img/c.jpg"
save_last_wallpaper "eDP" "light" "$TEST_DIR/light/img/a.jpg"
check "dark 读回 c" "[ \"\$(get_last_wallpaper eDP dark)\" = \"$TEST_DIR/dark/img/c.jpg\" ]"
check "light 读回 a" "[ \"\$(get_last_wallpaper eDP light)\" = \"$TEST_DIR/light/img/a.jpg\" ]"
check "未知 target 为空" "[ -z \"\$(get_last_wallpaper HDMI dark)\" ]"

# ---- 2. 损坏文件可恢复 ----
echo "not-json{{{" >"$HOME/.local/state/dwm/wallpaper-last.json"
check "损坏时 get 为空" "[ -z \"\$(get_last_wallpaper eDP dark)\" ]"
save_last_wallpaper "eDP" "dark" "$TEST_DIR/dark/img/c.jpg"
check "损坏后 save 恢复" "[ \"\$(get_last_wallpaper eDP dark)\" = \"$TEST_DIR/dark/img/c.jpg\" ]"

# ---- 3. theme_wallpaper 优先用记忆 ----
save_last_wallpaper "eDP" "dark" "$TEST_DIR/dark/img/c.jpg"
rm -f "$XW_MOCK_STATE"/*.win
theme_wallpaper dark
check "pin c 后 theme dark 仍是 c" "grep -q \"$TEST_DIR/dark/img/c.jpg\" \"$XW_MOCK_STATE/eDP.win\""

# ---- 4. 记忆文件被删 → 回退 random ----
save_last_wallpaper "eDP" "dark" "/nonexistent/missing.jpg"
rm -f "$XW_MOCK_STATE"/*.win
theme_wallpaper dark
check "stale 记忆回退到 dark 目录" "grep -q \"$TEST_DIR/dark/img/\" \"$XW_MOCK_STATE/eDP.win\""

# ---- 5. light/dark 独立记忆 ----
save_last_wallpaper "eDP" "light" "$TEST_DIR/light/img/a.jpg"
save_last_wallpaper "eDP" "dark" "$TEST_DIR/dark/img/c.jpg"
rm -f "$XW_MOCK_STATE"/*.win
theme_wallpaper light
check "切 light 恢复 a" "grep -q \"$TEST_DIR/light/img/a.jpg\" \"$XW_MOCK_STATE/eDP.win\""
rm -f "$XW_MOCK_STATE"/*.win
theme_wallpaper dark
check "切回 dark 恢复 c" "grep -q \"$TEST_DIR/dark/img/c.jpg\" \"$XW_MOCK_STATE/eDP.win\""

# ---- 6. 幂等: 当前已是目标时不 set (同名 set 即 reload, 白闪一次) ----
save_last_wallpaper "eDP" "dark" "$TEST_DIR/dark/img/c.jpg"
rm -f "$XW_MOCK_STATE"/*.win
printf 'image\t%s\t0\n' "$TEST_DIR/dark/img/c.jpg" >"$XW_MOCK_STATE/eDP.win"
: >"$XW_MOCK_LOG"
theme_wallpaper dark
check "已是 c 时 theme dark 不发 set" "! grep -q ' set ' \"$XW_MOCK_LOG\""
check "已是 c 时状态不动" "grep -q \"$TEST_DIR/dark/img/c.jpg\" \"$XW_MOCK_STATE/eDP.win\""
# 反例: 当前是 d, 记忆是 c → 必须 set
printf 'image\t%s\t0\n' "$TEST_DIR/dark/img/d.jpg" >"$XW_MOCK_STATE/eDP.win"
: >"$XW_MOCK_LOG"
theme_wallpaper dark
check "当前 d 记忆 c 时发 set 切到 c" "grep -q ' set ' \"$XW_MOCK_LOG\" && grep -q \"$TEST_DIR/dark/img/c.jpg\" \"$XW_MOCK_STATE/eDP.win\""

exit "$fail"
