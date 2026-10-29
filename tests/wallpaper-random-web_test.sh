#!/usr/bin/env bash
# wallpaper web 随机源回归测试:
#   1. web 抽中含 project.json (type=web) 的目录（含 file=wallpaper.html 反例）
#   2. 排除当前后不重复
#   3. 空池（无 project.json）报错非零
#   4. dark 未配 web_dark → fallback base
# 运行: bash tests/wallpaper-random-web_test.sh

LIB="$HOME/.dwm/tools/wallpaper-lib.sh"
WALLPAPER_SH="$HOME/.dwm/tools/wallpaper.sh"
ROFI_WALLPAPER_SH="$HOME/.dwm/rofi/scripts/wallpaper.sh"
UTIL_SH="$HOME/.dwm/rofi/scripts/util.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm" "$HOME/.cache/wallpaper"

BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

# ---- mock xwallpaper（有状态）----
export XW_MOCK_STATE="$TEST_DIR/xw"
mkdir -p "$XW_MOCK_STATE"
cat >"$BIN/xwallpaper" <<'EOF'
#!/usr/bin/env bash
DIR="$XW_MOCK_STATE"
mkdir -p "$DIR"
case "$*" in
*state*)
    for f in "$DIR"/*.win; do
        [ -f "$f" ] || continue
        n="${f##*/}"; n="${n%.win}"
        IFS=$'\t' read -r t p r <"$f"
        printf '%s\t%s\t%s\t%s\n' "$n" "$t" "$p" "$r"
    done
    ;;
esac
exit 0
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

# ---- web 壁纸池 fixture ----
mkdir -p "$TEST_DIR/web/a" "$TEST_DIR/web/b" "$TEST_DIR/web/empty" "$TEST_DIR/web/dark" "$TEST_DIR/web/custom"
echo "<html></html>" >"$TEST_DIR/web/a/index.html"
echo "<html></html>" >"$TEST_DIR/web/b/index.html"
echo "<html></html>" >"$TEST_DIR/web/dark/index.html"
echo "<html></html>" >"$TEST_DIR/web/custom/wallpaper.html"
printf '{"title":"a","preview":"preview.jpg","file":"index.html","type":"web"}' >"$TEST_DIR/web/a/project.json"
printf '{"title":"b","preview":"preview.jpg","file":"index.html","type":"web"}' >"$TEST_DIR/web/b/project.json"
printf '{"title":"d","preview":"preview.jpg","file":"index.html","type":"web"}' >"$TEST_DIR/web/dark/project.json"
printf '{"title":"c","preview":"preview.jpg","file":"wallpaper.html","type":"web"}' >"$TEST_DIR/web/custom/project.json"
echo "not a wallpaper" >"$TEST_DIR/web/empty/x.txt"

write_conf() { printf '%s\n' "$1" >"$HOME/.config/dwm/wallpaper.json"; }
base_conf() {
    write_conf "{
  \"monitors\": {
    \"eDP\": {
      \"random\": 1,
      \"random_type\": \"web\",
      \"random_web_dir\": \"$TEST_DIR/web\",
      \"random_depth\": 3,
      \"duration\": 30
    }
  },
  \"groups\": {}
}"
}

base_conf

set -- # 避免误触发 wallpaper.sh 底部分派
# shellcheck disable=SC1090
source "$LIB"
# wallpaper.sh 底部有 case 分派不能直接 source，按函数名提取
eval "$(awk '/^(random_wallpaper|select_wallpaper)\(\) \{/,/^}$/' "$WALLPAPER_SH")"

fail=0
check() { # desc, cond
    if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

# ---- 1. 抽中含 project.json (type=web) 的目录 ----
echo "light" >"$HOME/.local/state/dwm/current-theme"
ok=1
for _ in $(seq 1 20); do
    f=$(random_wallpaper eDP)
    case "$f" in
    "$TEST_DIR/web/a" | "$TEST_DIR/web/b" | "$TEST_DIR/web/dark" | "$TEST_DIR/web/custom") ;;
    *) ok=0; break ;;
    esac
    project_entry "$f" web >/dev/null 2>&1 || { ok=0; break; }
done
check "web 20 次抽取全为合法 web 目录（含 wallpaper.html 反例）" "[ $ok -eq 1 ]"

# ---- 2. 排除当前 ----
printf 'web\t%s\t0\n' "$TEST_DIR/web/a" >"$XW_MOCK_STATE/eDP.win"
ok=1
for _ in $(seq 1 10); do
    f=$(random_wallpaper eDP)
    [ "$f" != "$TEST_DIR/web/a" ] || { ok=0; break; }
done
check "当前=a 时不再抽中 a" "[ $ok -eq 1 ]"
rm -f "$XW_MOCK_STATE"/eDP.win

# ---- 3. 空池报错 ----
write_conf "{
  \"monitors\": {
    \"eDP\": {
      \"random\": 1,
      \"random_type\": \"web\",
      \"random_web_dir\": \"$TEST_DIR/web/empty\",
      \"random_depth\": 3,
      \"duration\": 30
    }
  },
  \"groups\": {}
}"
random_wallpaper eDP >/dev/null 2>&1
check "空池（无 project.json）返回非零" "[ $? -ne 0 ]"

# ---- 4. dark fallback base ----
base_conf
echo "dark" >"$HOME/.local/state/dwm/current-theme"
check "dark 未配 web_dark → fallback base" "[ \"\$(get_theme_dir eDP random_web_dir)\" = \"$TEST_DIR/web\" ]"

# ---- 5. rofi 接线 ----
check "rofi 有 Web Path 入口" "grep -q 'random_web_path' \"$ROFI_WALLPAPER_SH\""
check "rofi 有 Web Path (Dark) 入口" "grep -q 'random_web_path_dark' \"$ROFI_WALLPAPER_SH\""
check "rofi Type 为三选一 selector" "grep -q \"printf 'image\" \"$ROFI_WALLPAPER_SH\""
check "rofi Type 三态图标映射" "grep '^random_type|' \"$ROFI_WALLPAPER_SH\" | grep -q 'video) echo' && grep '^random_type|' \"$ROFI_WALLPAPER_SH\" | grep -q 'web) echo'"
check "无残留 wallpaper_type 引用" "! grep -q 'wallpaper_type' \"$ROFI_WALLPAPER_SH\" \"$UTIL_SH\""

exit "$fail"
