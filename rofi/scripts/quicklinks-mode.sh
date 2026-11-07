#!/usr/bin/env bash
# rofi script mode: quicklinks (rofi -show quicklinks)

ROFI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(dirname "$ROFI_DIR")"

CONFIG="${CONFIG:-$HOME/.config/dwm/quicklinks.json}"
SEARCH_ENGINE="https://www.google.com/search?q="
# 浏览入口 (主菜单仅留 history/bookmarks 入口行, 明细下沉子菜单: 输入 ^/* 过滤到入口 → 回车下钻)
# searcher 不隔离: @ 提示行保留在主菜单 (沿旧行为)
BROWSE_HIST="^ History"
BROWSE_BM="* Bookmarks"
BACK_ROW="← Back"
NEW_LINK=" New"
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
# 浏览器 UA: 部分站点 (如 platform.deepseek.com) 对无 UA 请求返回 429 限流
_UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

# 提取 hostname (纯 bash 参数展开, 零子进程): 去协议/路径/端口/www
# 结果写 $_HOST 全局变量 (避免 $() 命令替换 fork, _load 循环内每行一次; 调用方须先调用后读取)
_host_from_url() {
    local url="$1"
    _HOST=${url#*://}
    _HOST=${_HOST%%/*}
    _HOST=${_HOST%%:*}
    [[ "$_HOST" == www.* ]] && _HOST="${_HOST#www.}"
}

# curl 下载到文件并校验 MIME 为 image/* (失败返回 1)
_dl_icon() { # $1=url $2=输出文件
    curl -fsSL \
        -A "$_UA" \
        --connect-timeout 3 \
        --max-time 5 \
        -o "$2" "$1" 2>/dev/null &&
        [[ "$(file -b --mime-type "$2" 2>/dev/null)" == image/* ]]
}

# 从 HTML 提取 icon link 的 href; 第二参排除子串 (如 apple-touch, 其常为白底大图非期望缩略图)
_icon_href() { # $1=html $2=排除子串
    local links
    links=$(printf '%s' "$1" |
        grep -oEi '<link[^>]+rel=["'\''][^"'\'']*icon[^"'\'']*["'\''][^>]*>')
    [[ -n "${2:-}" ]] && links=$(printf '%s' "$links" | grep -viE "$2")
    printf '%s' "$links" |
        grep -oEi 'href=["'\''][^"'\'']+["'\'']' |
        head -n1 |
        sed -E 's/^href=["'\''](.*)["'\'']$/\1/'
}

# 下载 favicon: ① 页面 HTML 解析真实 favicon (优先标准 rel=icon) → ② 降级链 DuckDuckGo → Google s2 → 站内 /favicon.ico
# file 校验 MIME 为 image/* 才有效; 全部失败写 .fail 标记 (避免反复请求)
_fetch_favicon() {
    local host="$1" tmp html src
    mkdir -p "$ICON_CACHE_DIR" 2>/dev/null || return 1
    tmp=$(mktemp "$ICON_CACHE_DIR/.favicon.XXXXXX") || return 1

    # 1. 从页面 HTML 中寻找 favicon
    html=$(curl -fsSL \
        -A "$_UA" \
        --connect-timeout 3 \
        --max-time 5 \
        "https://$host/" 2>/dev/null) || html=

    if [[ -n "$html" ]]; then
        # 优先标准 rel=icon (排除 apple-touch); 仅含 apple-touch 的站点降级取用
        src=$(_icon_href "$html" apple-touch)
        [[ -n "$src" ]] || src=$(_icon_href "$html")

        if [[ -n "$src" ]]; then
            case "$src" in
            https://* | http://*) ;;
            //*) src="https:$src" ;;
            /*) src="https://$host$src" ;;
            *) src="https://$host/$src" ;;
            esac
            if _dl_icon "$src" "$tmp"; then
                mv "$tmp" "$ICON_CACHE_DIR/$host.png"
                return 0
            fi
        fi
    fi

    # 2. fallback 降级链
    for src in \
        "https://icons.duckduckgo.com/ip3/$host.ico" \
        "https://www.google.com/s2/favicons?domain=$host&sz=64" \
        "https://$host/favicon.ico"; do
        if _dl_icon "$src" "$tmp"; then
            mv "$tmp" "$ICON_CACHE_DIR/$host.png"
            return 0
        fi
    done

    rm -f "$tmp"
    : >"$ICON_CACHE_DIR/$host.png.fail"
    return 1
}

# ---- 默认浏览器检测 ----
# _ff_profile_dir: 输出 firefox profile 绝对目录 (解析 profiles.ini Default=1,
# IsRelative=1 时拼 $HOME/.mozilla/firefox; 失败回退 *.default-release glob); 失败输出空
_ff_profile_dir() {
    # 注意: bash 同行 local 多赋值不按序可见, base/ini 必须分行声明
    local base="$HOME/.mozilla/firefox"
    local ini="$base/profiles.ini"
    local dir="" rec="" path="" isrel="" d=""
    if [[ -f "$ini" ]]; then
        rec=$(awk 'BEGIN{RS=""; FS="\n"} /Default=1/{print; exit}' "$ini" 2>/dev/null)
        if [[ -n "$rec" ]]; then
            path=$(printf '%s' "$rec" | grep -E '^Path=' | head -n1 | cut -d= -f2-)
            isrel=$(printf '%s' "$rec" | grep -E '^IsRelative=' | head -n1 | cut -d= -f2-)
            path=${path%$'\r'}
            isrel=${isrel%$'\r'}
            if [[ -n "$path" ]]; then
                if [[ "$isrel" == "0" ]]; then dir="$path"; else dir="$base/$path"; fi
            fi
        fi
    fi
    if [[ -z "$dir" ]]; then
        for d in "$base"/*.default-release; do
            [[ -d "$d" ]] && {
                dir="$d"
                break
            }
        done
    fi
    [[ -n "$dir" && -d "$dir" ]] && printf '%s' "$dir"
    return 0
}

# _browser_detect: 输出 "firefox|<profile_dir>"; 非 firefox/不可用时输出空 (调用方零行降级)
_browser_detect() {
    local desktop=""
    if command -v xdg-settings >/dev/null 2>&1; then
        desktop=$(xdg-settings get default-web-browser 2>/dev/null)
    fi
    if [[ -z "$desktop" && -n "${BROWSER:-}" ]]; then
        desktop="$(basename "${BROWSER}")"
        [[ "$desktop" != *.desktop ]] && desktop="$desktop.desktop"
    fi
    case "$desktop" in
    [Ff]irefox*) printf 'firefox|%s' "$(_ff_profile_dir)" ;;
    *) return 0 ;;
    esac
    return 0
}

# _ff_query: 只读查 profile 下 places.sqlite, 行内 $'\x1f' 分隔 (url/title/rev_host)
_ff_query() { # $1=profile_dir $2=sql
    local db="$1/places.sqlite"
    [[ -f "$db" ]] || return 0
    command -v sqlite3 >/dev/null 2>&1 || return 0
    sqlite3 -separator $'\x1f' "file:$db?immutable=1" "$2" 2>/dev/null
    return 0
}

# 标题清洗必须在 SQL 层: read 按 \n 逐行读, 含换行的标题会在 bash 侧错位断裂;
# \x1f 为行内分隔符一并清洗 (char(31))
_FF_CLEAN_TITLE="REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(p.title,''), char(10), ' '), char(13), ' '), char(9), ' '), char(31), ' ')"
_FF_CLEAN_BMTITLE="REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(b.title, p.title, ''), char(10), ' '), char(13), ' '), char(9), ' '), char(31), ' ')"

# _ff_history: 输出 "url\x1f恰title\x1frev_host" (frecency 降序, 500 封顶; hidden/visit=0/非 http 过滤)
_ff_history() { # $1=profile_dir
    _ff_query "$1" "SELECT p.url, $_FF_CLEAN_TITLE, COALESCE(p.rev_host,'') FROM moz_places p WHERE p.hidden = 0 AND p.visit_count > 0 AND p.url LIKE 'http%' ORDER BY p.frecency DESC LIMIT 500;"
}

# _ff_bookmarks: 输出 "url\x1f恰title" (全量; type=1 书签, 非 http 过滤)
_ff_bookmarks() { # $1=profile_dir
    _ff_query "$1" "SELECT p.url, $_FF_CLEAN_BMTITLE FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk WHERE b.type = 1 AND p.url LIKE 'http%';"
}

# _ff_best_match: 关键词查历史/书签最佳命中并输出 url (无命中输出空)
# $1=profile_dir $2=hist|bm $3=关键词 (LIKE 转义 % _ \, 单引号双写防注入)
_ff_best_match() {
    local dir="$1" what="$2" esc="$3" cond
    esc=${esc//\\/\\\\}
    esc=${esc//%/\\%}
    esc=${esc//_/\\_}
    esc=${esc//\'/\'\'}
    cond="(p.url LIKE '%$esc%' ESCAPE '\\' OR COALESCE(p.title,'') LIKE '%$esc%' ESCAPE '\\')"
    if [[ "$what" == bm ]]; then
        cond="(p.url LIKE '%$esc%' ESCAPE '\\' OR COALESCE(b.title, p.title, '') LIKE '%$esc%' ESCAPE '\\')"
        _ff_query "$dir" "SELECT p.url FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk WHERE b.type = 1 AND p.url LIKE 'http%' AND $cond ORDER BY p.frecency DESC LIMIT 1;"
    else
        _ff_query "$dir" "SELECT p.url FROM moz_places p WHERE p.hidden = 0 AND p.visit_count > 0 AND p.url LIKE 'http%' AND $cond ORDER BY p.frecency DESC LIMIT 1;"
    fi
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

# 未缓存 host 入 pending (去重 + 跳过已 png/.fail); 依赖 _ensure_icons 内局部 seen/pending (bash 动态作用域)
_collect_host() {
    local h="$1"
    [[ -n "$h" && -z "${seen[$h]:-}" ]] || return 0
    [[ -f "$ICON_CACHE_DIR/$h.png" || -f "$ICON_CACHE_DIR/$h.png.fail" ]] && return 0
    seen[$h]=1
    pending+=("$h")
}

# 收集未缓存 (miss) 的 host, 后台分片并发下载; 已 png/.fail 的跳过
# links 与 searcher 的 host 都收集 (searcher url 无 {key} 时取整个域名)
_ensure_icons() {
    mkdir -p "$ICON_CACHE_DIR" 2>/dev/null || return 0
    local entry host surl
    local -A seen=()
    local -a pending=()
    for entry in "${_links[@]}"; do
        IFS=$'\x1f' read -r _ _ _ host <<<"$entry"
        _collect_host "$host"
    done
    while read -r surl; do
        _host_from_url "$surl"
        _collect_host "$_HOST"
    done < <(jq -r '.searcher[]?.url' "$CONFIG" 2>/dev/null)
    # 浏览器历史/书签 host (由 _load_browser_rows 收集, 恒初始化, 见 _list 调用序)
    local h
    for h in "${_browser_hosts[@]}"; do
        _collect_host "$h"
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

# 浏览器历史/书签行: _hist_rows/_bm_rows 为 "title\x1furl\x1fhost" 三元组,
# _browser_hosts 供 _ensure_icons 预取 favicon; $1 为 _browser_detect 输出
_load_browser_rows() {
    _hist_rows=()
    _bm_rows=()
    _browser_hosts=()
    # 测试缝: QUICKLINKS_NO_BROWSER 非空时跳过 (既有 _list 精确断言保持 hermetic)
    [[ -n "${QUICKLINKS_NO_BROWSER:-}" ]] && return 0
    local kind="${1%%|*}" dir="${1#*|}" url title host
    [[ "$kind" == firefox && -n "$dir" ]] || return 0
    while IFS=$'\x1f' read -r url title _; do
        [[ -n "$url" ]] || continue
        title=${title//$'\n'/ }
        title=${title//$'\r'/ }
        title=${title//$'\t'/ }
        [[ -z "$title" ]] && title="$url"
        _host_from_url "$url"
        host="$_HOST"
        _hist_rows+=("$title"$'\x1f'"$url"$'\x1f'"$host")
        _browser_hosts+=("$host")
    done < <(_ff_history "$dir")
    while IFS=$'\x1f' read -r url title; do
        [[ -n "$url" ]] || continue
        title=${title//$'\n'/ }
        title=${title//$'\r'/ }
        title=${title//$'\t'/ }
        [[ -z "$title" ]] && title="$url"
        _host_from_url "$url"
        host="$_HOST"
        _bm_rows+=("$title"$'\x1f'"$url"$'\x1f'"$host")
        _browser_hosts+=("$host")
    done < <(_ff_bookmarks "$dir")
}

# 打印浏览器行: $1=info 前缀 (hist|/bm|) $2 起=三元组数组
# (子菜单上下文已明确类型, 明细行不再带 ^/* 前缀)
_print_browser_rows() {
    local ns="$1" row title url host
    shift
    for row in "$@"; do
        IFS=$'\x1f' read -r title url host <<<"$row"
        if [[ -f "$ICON_CACHE_DIR/$host.png" ]]; then
            printf '%s — %s\0icon\x1f%s\x1finfo\x1f%s%s\n' "$title" "$host" "$ICON_CACHE_DIR/$host.png" "$ns" "$url"
        else
            printf '%s — %s\0info\x1f%s%s\n' "$title" "$host" "$ns" "$url"
        fi
    done
}

# 列表尾部 header: data 标记当前层级 (main/hist/bm, 经 ROFI_DATA 回传) + 快捷键开关
_list_footer() { # $1=data 标记
    printf '\0data\x1f%s\n' "$1"
    printf '\0use-hot-keys\x1ftrue\n'
}

# _links 为 "name|id|url|host" 四元组, 缓存 hit 时附加图片属性
# 主菜单: links + New 行 + 历史/书签浏览入口 + searcher @ 提示行
# (历史/书签明细下沉子菜单, 避免污染普通查询过滤; searcher 不隔离, 沿旧行为保留 @ 提示)
_list() {
    _ensure_ids
    _load
    # 主菜单不加载浏览器行: _browser_hosts 恒空, _ensure_icons 只预取 links/searcher
    _browser_hosts=()
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
    # 浏览入口: 输入 ^/* 过滤到对应入口 → 回车下钻 (ROFI_INFO=browse-* 输出子菜单 rofi 原地刷新)
    printf '%s\0info\x1fbrowse-hist\n' "$BROWSE_HIST"
    printf '%s\0info\x1fbrowse-bm\n' "$BROWSE_BM"
    # @ 提示: 输入 @ 时 rofi 过滤仅剩 @<name> 行 (links/New/浏览入口均不含 @) → 展示可用 searcher;
    # nonselectable 只展示不可选中, 不影响 RETV=2 自定义输入 (@name 搜索词走 _handle_input)
    local sname surl
    while IFS=$'\t' read -r sname surl; do
        _host_from_url "$surl"
        if [[ -f "$ICON_CACHE_DIR/$_HOST.png" ]]; then
            printf '@%s\0nonselectable\x1ftrue\x1ficon\x1f%s\n' "$sname" "$ICON_CACHE_DIR/$_HOST.png"
        else
            printf '@%s\0nonselectable\x1ftrue\n' "$sname"
        fi
    done < <(jq -r '.searcher[]? | [.name, .url] | @tsv' "$CONFIG" 2>/dev/null)
    _list_footer main
}

# 历史子菜单: back 首行 + 历史明细行 (info 命名空间 hist|url, 不进 links 写库路径)
_list_hist() {
    _load
    _load_browser_rows "$(_browser_detect)"
    _ensure_icons
    printf '%s\0info\x1fback\n' "$BACK_ROW"
    ((${#_hist_rows[@]})) && _print_browser_rows 'hist|' "${_hist_rows[@]}"
    _list_footer hist
}

# 书签子菜单: back 首行 + 书签明细行 (info 命名空间 bm|url)
_list_bm() {
    _load
    _load_browser_rows "$(_browser_detect)"
    _ensure_icons
    printf '%s\0info\x1fback\n' "$BACK_ROW"
    ((${#_bm_rows[@]})) && _print_browser_rows 'bm|' "${_bm_rows[@]}"
    _list_footer bm
}

# 按 id 打开 URL; 外部程序须后台执行 (rofi 会等待脚本 stdout 关闭)
_open_url() {
    [[ -n "${1:-}" ]] || return 0
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
    # 浏览器历史/书签只读 + 导航行: Alt+1 编辑直接 no-op
    case "$id" in hist\|* | bm\|* | browse-* | back) return 0 ;; esac

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
    _edit_loop "$name" "$url" "URL" "Edit Link" &&
        _write_json --arg id "$id" --arg name "$_LINK_NAME" --arg url "$_LINK_URL" \
            '(.links[] | select(.id == $id)) |= {id: .id, name: $name, url: $url}'
}

# Alt+2/Shift+Delete 删除: 按 id 定位, 确认后删除
_delete_link() {
    local id="$1"
    [[ -n "$id" ]] || return 0
    # 浏览器历史/书签只读 + 导航行: 删除直接 no-op
    case "$id" in hist\|* | bm\|* | browse-* | back) return 0 ;; esac
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
    _edit_loop "" "$url" "URL" "New Link" &&
        _write_json --arg id "$(_gen_id "$_LINK_NAME" "$_LINK_URL")" --arg name "$_LINK_NAME" --arg url "$_LINK_URL" \
            '.links += [{name: $name, url: $url, id: $id}]'
}

# New Searcher: 表单录入后追加到 .searcher (name 为唯一键, 无 id)
_new_searcher() { _interact_async _new_searcher_form; }

_new_searcher_form() { # 表单 + 追加写库 (rofi 退出后执行)
    _edit_loop "" "" "URL ({key} 占位)" "New Searcher" || return 1
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
    browse-hist) _list_hist ;;       # 有输出 → rofi 原地刷新为历史子菜单 (不退出)
    browse-bm) _list_bm ;;           # 同上: 书签子菜单
    back) _list ;;                    # 返回主菜单
    hist\|*) _open_url "${ROFI_INFO#hist|}" ;;
    bm\|*) _open_url "${ROFI_INFO#bm|}" ;;
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
    # 子菜单上下文 (ROFI_DATA): 裸词免前缀 (hist→历史最佳, bm→书签最佳);
    # 显式 ^/*/@ 前缀不受影响, 走下方原有分支
    case "${ROFI_DATA:-}" in
    hist)
        case "$text" in ^* | \** | @*) ;; *) text="^$text" ;; esac
        ;;
    bm)
        case "$text" in ^* | \** | @*) ;; *) text="*$text" ;; esac
        ;;
    esac
    # ^历史 / *书签: 剥前缀实时查最佳命中并打开; 无关键词 no-op;
    # 无命中/非 firefox 时落空, 整串(含前缀)走下方的默认搜索引擎 (与 @unknown 一致)
    case "$text" in
    ^* | \**)
        local mark="${text:0:1}" kw="${text:1}" spec dir hit
        if [[ -z "$kw" ]]; then
            return 0
        fi
        spec=$(_browser_detect)
        dir="${spec#*|}"
        if [[ "${spec%%|*}" == firefox && -n "$dir" ]]; then
            if [[ "$mark" == "^" ]]; then
                hit=$(_ff_best_match "$dir" hist "$kw")
            else
                hit=$(_ff_best_match "$dir" bm "$kw")
            fi
            if [[ -n "$hit" ]]; then
                _open_url "$hit"
                return 0
            fi
        fi
        ;;
    esac
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
# 第四参数 title 为对话框标题 (经 FORM_TITLE 传给 form_show, 默认 "Quicklinks")
_edit_loop() {
    local name="$1" url="$2" url_label="${3:-URL}" title="${4:-Quicklinks}"
    while :; do
        local json=$(
            FORM_TITLE="$title" form_show <<EOF
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
