#!/usr/bin/env bash
# rofi/scripts/wallpaper.sh handle_random_type 回归测试:
#   web -> image 必须能写回 (曾因 `local ... conf` 遮蔽全局 $conf,
#   bash 动态作用域下 getConfig 读到空 $conf 回退默认值 image,
#   导致 chosen=image 与假 cur=image 命中早退, 永远改不回 image)
# 运行: bash tests/rofi-wallpaper-random-type_test.sh

DWM="$HOME/.dwm"
TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm"

source "$DWM/rofi/scripts/util.sh"
source "$DWM/rofi/scripts/lib-module.sh"
source "$DWM/tools/wallpaper-lib.sh"

awk '/^handle_random_type\(\) \{/{f=1} f{print} f && /^\}$/{exit}' \
    "$DWM/rofi/scripts/wallpaper.sh" >"$TEST_DIR/handler.sh"
# shellcheck disable=SC1090
source "$TEST_DIR/handler.sh"

fail=0
check() {
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# ---- A: web -> image 能写回 ----
echo '{"monitors":{"HDMI-1":{"random_type":"web"}}}' >"$conf"
MONITOR="HDMI-1"
module_sub_rofi() { printf 'image'; }
handle_random_type
check "web->image 写回成功" '[ "$(jq -r ".monitors[\"HDMI-1\"].random_type" "$conf")" = image ]'

# ---- B: 相同值不重写 (mtime 不变) ----
mtime_before=$(stat -c %Y "$conf")
module_sub_rofi() { printf 'image'; }
handle_random_type
mtime_after=$(stat -c %Y "$conf")
check "同值早退不重写" '[ "$mtime_before" = "$mtime_after" ]'

# ---- C: image -> web 能写回 ----
module_sub_rofi() { printf 'web'; }
handle_random_type
check "image->web 写回成功" '[ "$(jq -r ".monitors[\"HDMI-1\"].random_type" "$conf")" = web ]'

# ---- D: ESC/非法输入不写回 ----
echo '{"monitors":{"HDMI-1":{"random_type":"web"}}}' >"$conf"
module_sub_rofi() { printf ''; }
handle_random_type
check "空输入不写回" '[ "$(jq -r ".monitors[\"HDMI-1\"].random_type" "$conf")" = web ]'

exit $fail
