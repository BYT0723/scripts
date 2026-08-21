#!/usr/bin/env bash
# rofi script mode: quicklinks (rofi -show quicklinks)

ROFI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(dirname "$ROFI_DIR")"

CONFIG="${CONFIG:-$HOME/.config/dwm/quicklinks.json}"
SEARCH_ENGINE="https://www.google.com/search?q="
NEW_LINK=" New Link"
NEW_SEARCHER=" New Searcher"
# script mode 下 rofi 存活期间 grab 键盘: 交互前须等待其退出释放 grab (实测 EOF→退出 < 0.4s)
GRAB_RELEASE_WAIT=0.4

source "$WORK_DIR/utils/form.sh"
source "$WORK_DIR/utils/notify.sh"
source "$WORK_DIR/utils/url.sh"
source "$WORK_DIR/utils/string.sh"
source "$ROFI_DIR/scripts/lib-module.sh"

# ---- favicon 缓存 ----
ICON_CACHE_DIR="${ICON_CACHE_DIR:-$HOME/.cache/dwm/quicklinks-icons}"

# 提取 hostname (纯 bash 参数展开, 零子进程): 去协议/路径/端口/www
# 结果写 $_HOST 全局变量 (避免 $() 命令替换 fork, _load 循环内每行一次; 调用方须先调用后读取)
_host_from_url() {
    local url="$1"
    _HOST=${url#*://}
    _HOST=${_HOST%%/*}
    _HOST=${_HOST%%:*}
    [[ "$_HOST" == www.* ]] && _HOST="${_HOST#www.}"
}

# 降级链下载 favicon: DuckDuckGo → Google s2 → 站内 /favicon.ico
# file 校验 MIME 为 image/* 才有效; 全部失败写 .fail 标记 (避免反复请求)
_fetch_favicon() {
    local host="$1" tmp
    mkdir -p "$ICON_CACHE_DIR" 2>/dev/null || return 1
    tmp=$(mktemp "$ICON_CACHE_DIR/.favicon.XXXXXX") || return 1
    local src
    for src in \
        "https://icons.duckduckgo.com/ip3/$host.ico" \
        "https://www.google.com/s2/favicons?domain=$host&sz=64" \
        "https://$host/favicon.ico"; do
        if curl -fsSL --connect-timeout 3 --max-time 5 -o "$tmp" "$src" 2>/dev/null &&
            [[ "$(file -b --mime-type "$tmp" 2>/dev/null)" == image/* ]]; then
            mv "$tmp" "$ICON_CACHE_DIR/$host.png"
            return 0
        fi
    done
    rm -f "$tmp"
    : >"$ICON_CACHE_DIR/$host.png.fail"
    return 1
}

# ---- parse links ----

# 生成链接 id: 优先 uuidgen, 无则 base64(name|url) fallback 并提示安装
_gen_id() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
        return
    fi
    if [[ "${_ID_FALLBACK_NOTIFIED:-}" != 1 ]]; then
        _ID_FALLBACK_NOTIFIED=1
        tool-notify normal "Quicklinks" "未检测到 uuidgen, id 回退为 base64 (建议安装: sudo pacman -S util-linux)"
    fi
    printf '%s|%s' "$1" "$2" | base64 | tr -d '\n'
}

# 补全缺失 id: 正常情况所有链接已有 id, 零写入 (避免每次启动全量重写文件)
# 仅当存在缺 id 的链接 (迁移/异常) 时才全量重生成
_ensure_ids() {
    local total i
    total=$(jq '.links | length' "$CONFIG")
    ((total == 0)) && return 0
    if ! jq -e 'any(.links[]?; (.id // "") == "")' "$CONFIG" >/dev/null 2>&1; then
        return 0
    fi
    for i in $(seq 0 $((total - 1))); do
        local name url
        name=$(jq -r --argjson i "$i" '.links[$i].name' "$CONFIG")
        url=$(jq -r --argjson i "$i" '.links[$i].url' "$CONFIG")
        _write_json --arg id "$(_gen_id "$name" "$url")" --argjson i "$i" '.links[$i].id = $id'
    done
}

_load() {
    _links=()
    while IFS=$'\t' read -r name id url; do
        _host_from_url "$url"
        # 四元组用 \x1f 分隔: name/url 可能含 | (表单不禁止), | 拼接会导致字段错位
        _links+=("$name"$'\x1f'"$id"$'\x1f'"$url"$'\x1f'"$_HOST")
    done < <(jq -r '.links[] | "\(.name)\t\(.id)\t\(.url)"' "$CONFIG")
}

# 收集未缓存 (miss) 的 host, 后台分片并发下载; 已 png/.fail 的跳过
_ensure_icons() {
    mkdir -p "$ICON_CACHE_DIR" 2>/dev/null || return 0
    local entry host
    local -A seen=()
    local -a pending=()
    for entry in "${_links[@]}"; do
        IFS=$'\x1f' read -r _ _ _ host <<<"$entry"
        [[ -n "$host" && -z "${seen[$host]:-}" ]] || continue
        [[ -f "$ICON_CACHE_DIR/$host.png" || -f "$ICON_CACHE_DIR/$host.png.fail" ]] && continue
        seen[$host]=1
        pending+=("$host")
    done
    ((${#pending[@]})) || return 0
    # 分片并发 (每 8 个等一轮), 避免首次全量 miss 时数十个并发 curl 触发限流
    (
        i=0
        for h in "${pending[@]}"; do
            _fetch_favicon "$h" >/dev/null 2>&1 &
            ((++i % 8 == 0)) && wait
        done
        wait
    ) >/dev/null 2>&1 &
}

# _links 为 "name|id|url|host" 四元组, 缓存 hit 时附加图片属性
_list() {
    _ensure_ids
    _load
    _ensure_icons
    local entry name id url host
    for entry in "${_links[@]}"; do
        IFS=$'\x1f' read -r name id url host <<<"$entry"
        # hit 判定内联 (避免 $() 命令替换 fork; fail/miss 输出相同, 无需三态)
        if [[ -f "$ICON_CACHE_DIR/$host.png" ]]; then
            # 多属性必须用 \x1f 连接 (仅行文本后一个 \0): rofi 按 C 字符串解析属性块,
            # 第二个 \0 会把 info 截断在字符串外 → ROFI_INFO 丢失, 选中无反应
            printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "$name" "$ICON_CACHE_DIR/$host.png" "$id"
        else
            # miss/fail fallback: 无图标纯文本行
            printf '%s\0info\x1f%s\n' "$name" "$id"
        fi
    done
    printf '%s\0info\x1fnew\n' "$NEW_LINK"
    printf '%s\0info\x1fnew-searcher\n' "$NEW_SEARCHER"
    printf '\0use-hot-keys\x1ftrue\n'
}

# 按 id 打开 URL; 外部程序须后台执行 (rofi 会等待脚本 stdout 关闭)
_open_url() {
    (xdg-open "$1" >/dev/null 2>&1 &)
}

_open_by_id() {
    local url
    url=$(jq -r --arg id "$1" '.links[] | select(.id == $id) | .url' "$CONFIG")
    [[ -n "$url" ]] || return 0
    _open_url "$url"
}

# 读取剪贴板, trim 首尾空白后必须为严格完整有效 URL (http/https), 否则静默返回非 0
clipboard_url() {
    local clip
    if command -v xclip >/dev/null 2>&1; then
        clip=$(xclip -o -selection clipboard 2>/dev/null)
    elif command -v xsel >/dev/null 2>&1; then
        clip=$(xsel --clipboard --output 2>/dev/null)
    elif command -v wl-paste >/dev/null 2>&1; then
        clip=$(wl-paste 2>/dev/null)
    fi
    [[ -n "$clip" ]] || return 1
    clip=$(trim_str "$clip")
    # valid_url 只校验 host, path 不查; 须整体无空白 (拒绝多行/含空格文本)
    [[ "$clip" != *[[:space:]]* ]] || return 1
    valid_url "$clip" || return 1
    printf '%s' "$clip"
}

# 后台交互包装: script mode 下 rofi 存活期间 grab 键盘, yad/嵌套 rofi 拿不到输入
# → 子 shell sleep 等 rofi 退出释放 grab 后再执行命令, 父脚本立即结束 (stdout EOF 令 rofi 退出)
_interact_async() {
    (
        sleep "$GRAB_RELEASE_WAIT"
        "$@"
    ) >/dev/null 2>&1 &
}

# 原子写回 CONFIG: jq [args...] <expr> 输出到唯一 tmp 再 mv (避免并发写 .tmp 冲突)
_write_json() {
    local tmp
    tmp=$(mktemp "$CONFIG.tmp.XXXXXX") || return 1
    jq "$@" "$CONFIG" >"$tmp" && mv "$tmp" "$CONFIG"
}

# 常用分类图标池: 图标+名称, 候选项间用 ! 分隔 (yad CBE 原生格式)

# Alt+1 编辑: 按 id 定位原条目, 预填当前值, 保存按 id 替换 (保留 id)
_edit_link() {
    local id="$1"
    [[ -n "$id" ]] || return 0

    local cur
    cur=$(jq -c --arg id "$id" '.links[] | select(.id == $id)' "$CONFIG" 2>/dev/null)
    [[ -n "$cur" ]] || return 0

    local name url
    name=$(jq -r '.name' <<<"$cur")
    url=$(jq -r '.url' <<<"$cur")
    _interact_async _edit_form "$id" "$name" "$url"
}

_edit_form() { # 表单录入 + 按 id 替换写库 (rofi 退出后执行)
    local id="$1" name="$2" url="$3"
    _edit_loop "$name" "$url" &&
        _write_json --arg id "$id" --arg name "$_LINK_NAME" --arg url "$_LINK_URL" \
            '(.links[] | select(.id == $id)) |= {id: .id, name: $name, url: $url}'
}

# Alt+2/Shift+Delete 删除: 按 id 定位, 确认后删除
_delete_link() {
    local id="$1"
    [[ -n "$id" ]] || return 0
    local name
    name=$(jq -r --arg id "$id" '.links[] | select(.id == $id) | .name' "$CONFIG")
    [[ -n "$name" ]] || return 0
    _interact_async _delete_form "$id" "$name"
}

_delete_form() { # 确认 + 删除写库 (rofi 退出后执行)
    local id="$1" name="$2"
    module_confirm "删除「$name」？" &&
        _write_json --arg id "$id" 'del(.links[] | select(.id == $id))' &&
        tool-notify normal "Quicklinks" "已删除: $name"
}

# New: 剪贴板有效 URL 预填, 表单校验后追加
_new_link() {
    _interact_async _new_form
}

_new_form() { # 剪贴板预填 + 表单 + 追加写库 (rofi 退出后执行)
    local url
    # clipboard_url 也在此执行: xclip/xsel/wl-paste 读取剪贴板可能阻塞, 不能留在 rofi grab 存活期间
    url=$(clipboard_url)
    _edit_loop "" "$url" &&
        _write_json --arg id "$(_gen_id "$_LINK_NAME" "$_LINK_URL")" --arg name "$_LINK_NAME" --arg url "$_LINK_URL" \
            '.links += [{name: $name, url: $url, id: $id}]'
}

# New Searcher: 表单录入后追加到 .searcher (name 为唯一键, 无 id)
_new_searcher() { _interact_async _new_searcher_form; }

_new_searcher_form() { # 表单 + 追加写库 (rofi 退出后执行)
    _edit_loop "" "" "URL ({key} 占位)" || return 1
    if jq -e --arg n "$_LINK_NAME" \
        'any(.searcher[]?; .name | ascii_downcase == ($n | ascii_downcase))' "$CONFIG" >/dev/null 2>&1; then
        tool-notify critical "Quicklinks" "搜索引擎已存在: $_LINK_NAME"
        return 1
    fi
    _write_json --arg name "$_LINK_NAME" --arg url "$_LINK_URL" \
        '.searcher += [{name: $name, url: $url}]'
}

_dispatch() {
    case "${ROFI_INFO:-}" in
    new) _new_link ;;
    new-searcher) _new_searcher ;;
    *) _open_by_id "${ROFI_INFO:-}" ;;
    esac
}

# 构建搜索引擎 URL: URL 编码搜索词替换 {key}, 无 {key} 则追加到末尾
# 注意: bash 参数展开中花括号会被误解析, {key} 必须转义为 \{key\}
_build_search_url() {
    local base="$1" term="$2" encoded
    encoded=$(printf '%s' "$term" | jq -sRr @uri)
    if [[ "$base" == *'{key}'* ]]; then
        base="${base//\{key\}/$encoded}"
    else
        base="${base}${encoded}"
    fi
    printf '%s' "$base"
}

# 按 name 精确匹配 (忽略大小写) 查找 searcher url, 未命中输出空
_searcher_url_by_name() {
    jq -r --arg n "$1" \
        '.searcher[]? | select(.name | ascii_downcase == ($n | ascii_downcase)) | .url' "$CONFIG" 2>/dev/null |
        head -1
}

# 自定义输入: URL → 补协议打开; 否则搜索引擎
# 搜索解析: 首 token @<name> 精确匹配(忽略大小写)命中 searcher → 用目标引擎; 未命中/无 @ → 默认 searcher[0]
_handle_input() {
    local text="$*"
    [[ -n "$text" ]] || return 0
    if is_url "$text"; then
        [[ "$text" =~ ^https?:// ]] || text="https://$text"
        _open_url "$text"
        return 0
    fi

    local term="$text" url
    # @name 首 token: 仅 @name 无搜索词不打开; 命中 → 用目标引擎, 未命中 → 整串(含 @name)走默认
    if [[ "$text" == @* ]]; then
        local first name
        first="${text%% *}"
        name="${first#@}"
        [[ -n "$name" && "$text" != "$first" ]] || return 0
        url=$(_searcher_url_by_name "$name")
        [[ -n "$url" ]] && term="${text#* }"
    fi

    # 默认引擎: searcher 数组第一个; 数组为空回退 SEARCH_ENGINE
    [[ -n "$url" ]] || url=$(jq -r '.searcher[0]?.url // ""' "$CONFIG" 2>/dev/null)
    if [[ -n "$url" ]]; then
        _open_url "$(_build_search_url "$url" "$term")"
    else
        _open_url "${SEARCH_ENGINE}${term}"
    fi
}

# ---- 表单 (yad form_show) ----

# 弹表单录入链接, 校验失败 notify 并重开; 成功设置 _LINK_NAME/_LINK_URL, 取消返回 1
# 第三参数 url_label 自定义 URL 字段标签 (searcher 表单提示 {key} 占位, 默认 "URL")
_edit_loop() {
    local name="$1" url="$2" url_label="${3:-URL}"
    while :; do
        local json=$(
            form_show <<EOF
name|entry|Name|${name:-}|
url|entry|${url_label}|${url:-}|
EOF
        )
        [[ -z "$json" ]] && return 1

        name=$(jq -r '.name' <<<"$json")
        url=$(jq -r '.url' <<<"$json")
        name=$(trim_str "$name")
        url=$(trim_str "$url")
        if [[ -z "$name" ]]; then
            tool-notify critical "Quicklinks" "链接名称不能为空"
            continue
        fi
        if [[ -z "$url" ]]; then
            tool-notify critical "Quicklinks" "链接 URL 不能为空"
            continue
        fi

        if ! valid_url "$url" && ! valid_url "https://$url"; then
            tool-notify critical "Quicklinks" "链接 URL 无效: $url"
            continue
        fi
        [[ "$url" =~ ^https?:// ]] || url="https://$url"
        break
    done
    _LINK_NAME="$name"
    _LINK_URL="$url"
}

_main() {
    case "${ROFI_RETV:-0}" in
    0) _list ;;
    1) _dispatch ;;
    2) _handle_input "$*" ;;
    3 | 11) _delete_link "${ROFI_INFO:-}" ;;
    10) _edit_link "${ROFI_INFO:-}" ;;
    *) exit 0 ;;
    esac
}

# ---- main (source 时跳过) ----
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # rofi 把自定义输入/选中文本作为命令行参数传入, 须转发给 _main (函数内 $* 为函数自身参数)
    _main "$@"
fi
