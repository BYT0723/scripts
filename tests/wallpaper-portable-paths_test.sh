#!/usr/bin/env bash
# wallpaper 路径可移植回归测试:
#   读侧: expand_path 支持 ~ / $HOME / ${HOME} / 任意 $VAR, ~other 不展开
#   写侧: shrink_path 把 $HOME 前缀压缩为 ~ (HOME 外原样, 前缀陷阱不压缩)
#   集成: find_wallpapers 吃 "~" 目录; select_wallpaper 传给 yazi 的起始目录已展开;
#         pick_config_dir 存盘为 ~ 开头
# 运行: bash tests/wallpaper-portable-paths_test.sh

LIB="$HOME/.dwm/tools/wallpaper-lib.sh"
WALLPAPER_SH="$HOME/.dwm/tools/wallpaper.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm" "$HOME/.cache/wallpaper"

BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# ---- mock yazi: 记录起始目录, 按场景写 chooser ----
export YAZI_START_LOG="$TEST_DIR/yazi-start.log"
export YAZI_CHOSEN="$TEST_DIR/yazi-chosen"
: >"$YAZI_START_LOG"
: >"$YAZI_CHOSEN"
cat >"$BIN/yazi" <<'EOF'
#!/usr/bin/env bash
# 用法: yazi <start-dir> --chooser-file=<tmp>
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
chmod +x "$BIN/yazi"
export PATH="$BIN:$PATH"
# 让 "$TERM yazi ..." 透传到 yazi mock: TERM=env → env yazi ...
export TERMINAL=env

# shellcheck disable=SC1090
source "$LIB"

fail=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc (expected [$expected], got [$actual])"
        fail=$((fail + 1))
    fi
}

# ---- 读侧 expand_path ----
check "expand ~/a" "$HOME/a" "$(expand_path "~/a")"
check "expand bare ~" "$HOME" "$(expand_path "~")"
check "expand \$HOME/a" "$HOME/a" "$(expand_path '$HOME/a')"
check "expand \${HOME}/a" "$HOME/a" "$(expand_path '${HOME}/a')"
export WALLPAPER_TEST_VAR="$TEST_DIR/custom"
check "expand \$VAR" "$TEST_DIR/custom/a" "$(expand_path '$WALLPAPER_TEST_VAR/a')"
check "absolute unchanged" "/tmp/x" "$(expand_path "/tmp/x")"
check "~other not expanded" "~other/a" "$(expand_path "~other/a")"

# ---- 写侧 shrink_path ----
check "shrink HOME" "~" "$(shrink_path "$HOME")"
check "shrink HOME/a" "~/a" "$(shrink_path "$HOME/a")"
check "shrink outside unchanged" "/tmp/x" "$(shrink_path "/tmp/x")"
check "shrink prefix trap" "$HOME-other/a" "$(shrink_path "$HOME-other/a")"

# ---- round-trip ----
check "round-trip" "$HOME/a" "$(expand_path "$(shrink_path "$HOME/a")")"

# ---- 集成: find_wallpapers 吃 ~ ----
mkdir -p "$HOME/walls"
touch "$HOME/walls/a.jpg"
found=$(find_wallpapers "~/walls" 3 '.*\.(jpeg|jpg|png)' 2>/dev/null)
check "find_wallpapers ~" "$HOME/walls/a.jpg" "$found"

# ---- 集成: select_wallpaper 起始目录已展开 ----
# wallpaper.sh 底部分发无 source 守卫, 只提取函数 eval, 避免顶层 exit 影响本 shell
eval "$(awk '/^select_wallpaper\(\) \{/,/^\}/' "$WALLPAPER_SH")"
mkdir -p "$HOME/sel" && touch "$HOME/sel/picked.jpg"
jq -n --arg h "$HOME" \
    '{monitors: {eDP: {random_type: "image", random_image_dir: "~/sel"}}, groups: {}}' \
    >"$HOME/.config/dwm/wallpaper.json"
printf '%s\n' "$HOME/sel/picked.jpg" >"$YAZI_CHOSEN"
: >"$YAZI_START_LOG"
picked=$(select_wallpaper eDP)
check "select yazi start expanded" "$HOME/sel" "$(cat "$YAZI_START_LOG")"
check "select returns file" "$HOME/sel/picked.jpg" "$picked"

# ---- 集成: pick_config_dir 存盘为 ~ ----
printf '%s\n' "$HOME/walls/a.jpg" >"$YAZI_CHOSEN"
pick_config_dir eDP random_image_dir
saved=$(jq -r '.monitors.eDP.random_image_dir' "$HOME/.config/dwm/wallpaper.json")
check "pick saves ~" "~/walls" "$saved"

if [ "$fail" -ne 0 ]; then
    echo "RESULT: FAIL ($fail)"
    exit 1
fi
echo "RESULT: PASS"
