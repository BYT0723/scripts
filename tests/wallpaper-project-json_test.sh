#!/usr/bin/env bash
# web/scene 经 project.json 解析 preview/file/type 的契约测试 (TDD):
#   project_type <dir>              → 小写 type，无/坏返回非零
#   project_preview <dir>           → 字段优先，回退 preview.*，都无返回非零
#   project_entry <dir> [kind]      → web 认 file 字段(含 wallpaper.html)，
#                                     回退 index.html；scene 互认 scene.json/pkg
#   find_project_dirs <root> <depth> <type> → 只返回含 project.json 且 type 匹配的目录
# 运行: bash tests/wallpaper-project-json_test.sh

DWM="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm" "$HOME/.cache/wallpaper"

set -- # 避免误触发 wallpaper.sh 底部分派
# shellcheck disable=SC1090
source "$DWM/tools/wallpaper-lib.sh"

# ---- fixture ----
POOL="$TEST_DIR/pool"
mkdir -p "$POOL/web-a" "$POOL/web-custom" "$POOL/scene-pkg" "$POOL/scene-json" \
    "$POOL/fallback-preview" "$POOL/no-preview" "$POOL/no-entry" "$POOL/bare" "$POOL/badjson"

# web-a: 标准 web（字段全命中）
printf '{"title":"A","preview":"preview.jpg","file":"index.html","type":"web"}' >"$POOL/web-a/project.json"
echo "<html></html>" >"$POOL/web-a/index.html"
echo "fakejpg" >"$POOL/web-a/preview.jpg"

# web-custom: file=wallpaper.html（3818900270 反例），无 index.html
printf '{"title":"C","preview":"preview.jpg","file":"wallpaper.html","type":"web"}' >"$POOL/web-custom/project.json"
echo "<html></html>" >"$POOL/web-custom/wallpaper.html"
echo "fakejpg" >"$POOL/web-custom/preview.jpg"

# scene-pkg: file=scene.json 但落盘只有 scene.pkg（3497575235 反例）
printf '{"title":"S","preview":"preview.gif","file":"scene.json","type":"Scene"}' >"$POOL/scene-pkg/project.json"
echo '{"pkg":1}' >"$POOL/scene-pkg/scene.pkg"
echo "fakegif" >"$POOL/scene-pkg/preview.gif"

# scene-json: 落盘 scene.json
printf '{"title":"J","preview":"preview.gif","file":"scene.json","type":"scene"}' >"$POOL/scene-json/project.json"
echo '{"scene":1}' >"$POOL/scene-json/scene.json"
echo "fakegif" >"$POOL/scene-json/preview.gif"

# fallback-preview: 无 preview 字段，回退 preview.png
printf '{"title":"F","file":"index.html","type":"Web"}' >"$POOL/fallback-preview/project.json"
echo "<html></html>" >"$POOL/fallback-preview/index.html"
echo "fakepng" >"$POOL/fallback-preview/preview.png"

# no-preview: 无 preview 字段也无 preview.* 文件
printf '{"title":"N","file":"index.html","type":"web"}' >"$POOL/no-preview/project.json"
echo "<html></html>" >"$POOL/no-preview/index.html"

# no-entry: type web 但无入口文件
printf '{"title":"E","preview":"preview.jpg","file":"index.html","type":"web"}' >"$POOL/no-entry/project.json"
echo "fakejpg" >"$POOL/no-entry/preview.jpg"

# bare: 裸 index.html，无 project.json（新逻辑下非法）
echo "<html></html>" >"$POOL/bare/index.html"

# badjson: 损坏的 project.json + 存在的 index.html（回退 marker）
echo "{not json" >"$POOL/badjson/project.json"
echo "<html></html>" >"$POOL/badjson/index.html"
echo "fakepng" >"$POOL/badjson/preview.png"

fail=0
check() { # desc, cond
    if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

# ---- project_type ----
check "type: web 小写" '[ "$(project_type "$POOL/web-a")" = "web" ]'
check "type: Scene 归一化小写" '[ "$(project_type "$POOL/scene-pkg")" = "scene" ]'
check "type: Web 首字母大写归一化" '[ "$(project_type "$POOL/fallback-preview")" = "web" ]'
check "type: 无 project.json 返回非零" '! project_type "$POOL/bare" >/dev/null 2>&1'
check "type: 损坏 json 返回非零" '! project_type "$POOL/badjson" >/dev/null 2>&1'

# ---- project_preview ----
check "preview: 字段命中" '[ "$(project_preview "$POOL/web-a")" = "$POOL/web-a/preview.jpg" ]'
check "preview: 缺字段回退 preview.png" '[ "$(project_preview "$POOL/fallback-preview")" = "$POOL/fallback-preview/preview.png" ]'
check "preview: 损坏 json 回退 preview.png" '[ "$(project_preview "$POOL/badjson")" = "$POOL/badjson/preview.png" ]'
check "preview: 全无返回非零" '! project_preview "$POOL/no-preview" >/dev/null 2>&1'

# ---- project_entry ----
check "entry(web): 标准 index.html" '[ "$(project_entry "$POOL/web-a" web)" = "$POOL/web-a/index.html" ]'
check "entry(web): file=wallpaper.html 反例" '[ "$(project_entry "$POOL/web-custom" web)" = "$POOL/web-custom/wallpaper.html" ]'
check "entry(web): 缺 kind 时按 project.json type 推导" '[ "$(project_entry "$POOL/web-custom")" = "$POOL/web-custom/wallpaper.html" ]'
check "entry(web): 损坏 json 回退 index.html" '[ "$(project_entry "$POOL/badjson" web)" = "$POOL/badjson/index.html" ]'
check "entry(web): 无入口返回非零" '! project_entry "$POOL/no-entry" web >/dev/null 2>&1'
check "entry(scene): file=json 落盘pkg 互认" '[ "$(project_entry "$POOL/scene-pkg" scene)" = "$POOL/scene-pkg/scene.pkg" ]'
check "entry(scene): 落盘 scene.json" '[ "$(project_entry "$POOL/scene-json" scene)" = "$POOL/scene-json/scene.json" ]'
check "entry(scene): 缺 kind 时按 type 推导" '[ "$(project_entry "$POOL/scene-pkg")" = "$POOL/scene-pkg/scene.pkg" ]'
check "entry(scene): 无 marker 返回非零" '! project_entry "$POOL/no-entry" scene >/dev/null 2>&1'

# ---- find_project_dirs ----
web_dirs=$(find_project_dirs "$POOL" 3 web 2>/dev/null | sort)
check "find: web 含标准目录" 'printf "%s\n" "$web_dirs" | grep -qx "$POOL/web-a"'
check "find: web 含 wallpaper.html 目录" 'printf "%s\n" "$web_dirs" | grep -qx "$POOL/web-custom"'
check "find: web 含回退 preview 目录" 'printf "%s\n" "$web_dirs" | grep -qx "$POOL/fallback-preview"'
check "find: web 排除 scene 目录" '! printf "%s\n" "$web_dirs" | grep -qx "$POOL/scene-pkg"'
check "find: web 排除裸 index.html 目录" '! printf "%s\n" "$web_dirs" | grep -qx "$POOL/bare"'
scene_dirs=$(find_project_dirs "$POOL" 3 scene 2>/dev/null | sort)
check "find: scene 含 pkg 互认目录" 'printf "%s\n" "$scene_dirs" | grep -qx "$POOL/scene-pkg"'
check "find: scene 含 json 目录" 'printf "%s\n" "$scene_dirs" | grep -qx "$POOL/scene-json"'
check "find: scene 排除 web 目录" '! printf "%s\n" "$scene_dirs" | grep -qx "$POOL/web-a"'
check "find: type 大小写无关 (WEB)" '[ -n "$(find_project_dirs "$POOL" 3 WEB 2>/dev/null)" ]'
check "find: 无匹配返回非零" '! find_project_dirs "$POOL/bare" 3 web >/dev/null 2>&1'
check "find: 不存在的根返回非零" '! find_project_dirs "$POOL/nonexistent" 3 web >/dev/null 2>&1'

exit "$fail"
