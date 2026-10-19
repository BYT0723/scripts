#!/usr/bin/env bash
# steam-workshop.sh — steamcmd 创意工坊下载核心 (无 rofi 依赖, 可 CLI/单测)
#   sw_parse_itemid <url-or-id>  → stdout itemid
#   sw_fetch_page <url-or-id>    → stdout 工坊页面 HTML (纯数字 ID 自动拼 URL)
#   sw_parse_appid <page>        → stdout appid
#   sw_parse_field <page> <marker> → stdout 标记文本 (HTML 转义解码)
#   sw_parse_appname <page>      → stdout app 名 (可空)
#   sw_parse_title <page>        → stdout 资源名 (可空)
#   sw_page_gated <page>         → 登录门返回 0 (匿名不可见条目)
#   sw_short_error                → steamcmd 全量输出摘一行人类可读错误
#   sw_resolve_appid <url-or-id> → stdout appid (先 ?appid= 参数, 后抓页面)
#   sw_api_info <itemid>         → stdout "appid|app名|资源名" (免 key WebAPI, 登录门条目可用; 需 jq)
#   sw_api_time <itemid>         → stdout "appid|time_updated" (更新检查用; 需 jq)
#   sw_check_updates <root> [appdir] → stdout 状态行 (UPDATE|appid|itemid|path / CURRENT|itemid|path / SKIP|itemid|path|reason); 无候选或根非法返回 1
#   sw_item_info <url-or-id>     → stdout "appid|app名|资源名" (页面 → WebAPI → 失败)
#   sw_list_users                → stdout "AccountName|PersonaName" 行 (按 Timestamp 倒序)
#   sw_safe_app <appname> <appid>  → stdout 扁平首层目录名 (应用名去空格/非法字符, 为空回退 appid)
#   sw_download <appid> <itemid> [user] [appname] → stdout 扁平落盘路径 <隔离根>/<应用>/<itemid>; rc=0 成功, 2=需终端登录, 1=其他失败
#     隔离根经 +force_install_dir 写入 (见 STEAMCMD_INSTALL_DIR)，缺省 ~/Downloads/steamcmd (自动 mkdir -p)

STEAM_LOGINUSERS="${STEAM_LOGINUSERS:-$HOME/.local/share/Steam/config/loginusers.vdf}"
# 隔离根: steamcmd +force_install_dir 的值 (非最终内容目录)。
# 最终落盘为 <隔离根>/steamapps/workshop/content/<appid>/<itemid>，
# 不同 appid 各占子目录、互不混；Steam 客户端卸载不触及此处。
# STEAMCMD_INSTALL_DIR 优先，兼容 STEAM_WORKSHOP_DIR，缺省 ~/Downloads/steamcmd。
STEAMCMD_INSTALL_DIR="${STEAMCMD_INSTALL_DIR:-${STEAM_WORKSHOP_DIR:-$HOME/Downloads/steamcmd}}"

sw_parse_itemid() {
    local in="$1" id=""
    if [[ "$in" =~ ^[0-9]{4,}$ ]]; then
        id="$in"
    elif [[ "$in" =~ [\?\&]id=([0-9]+) ]]; then
        id="${BASH_REMATCH[1]}"
    fi
    if [[ -z "$id" ]]; then
        return 1
    fi
    echo "$id"
}

sw_fetch_page() {
    local in="$1" url="$in"
    [[ "$url" =~ ^[0-9]+$ ]] && url="https://steamcommunity.com/sharedfiles/filedetails/?id=$url"
    curl -sSL --max-time 20 --proto '=https' "$url" 2>/dev/null
}

sw_parse_appid() {
    grep -o 'data-appid="[0-9]*"' <<<"$1" | head -1 | grep -o '[0-9]*'
}

sw_parse_field() { # page marker → 文本 (HTML 转义解码)
    local val
    val=$(grep -o "$2\">[^<]*" <<<"$1" | head -1 | sed 's/.*">//')
    sw_decode_entities "$val"
}

sw_parse_appname() {
    sw_parse_field "$1" 'apphub_AppName ellipsis'
}

sw_parse_title() {
    sw_parse_field "$1" 'workshopItemTitle'
}

sw_decode_entities() {
    sed -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&#39;/'/g" <<<"$1" | tr '|' ' ' | tr -d '\n'
}

sw_page_gated() { # page → 登录门则返回 0 (受限/隐藏条目, 匿名不可见)
    grep -qi 'you must be logged in to view this item' <<<"$1"
}

sw_short_error() { # steamcmd 全量输出 → 一行人类可读错误 (无则输出空)
    local text="${1:-}" err=""
    [[ -z "$text" && ! -t 0 ]] && text=$(cat)
    err=$(grep -oi 'cached credentials not found\.' <<<"$text" | head -1)
    [[ -z "$err" ]] && err=$(grep -o 'ERROR.*' <<<"$text" | head -1)
    [[ -z "$err" ]] && err=$(grep -oi 'steam guard.*' <<<"$text" | head -1)
    err="${err:0:100}"
    [[ -n "$err" ]] && echo "$err"
}

sw_resolve_appid() {
    local in="$1"
    if [[ "$in" =~ [\?\&]appid=([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    local page="" appid=""
    page=$(sw_fetch_page "$in") || return 1
    appid=$(sw_parse_appid "$page")
    if [[ -z "$appid" ]]; then
        return 1
    fi
    echo "$appid"
}

sw_api_info() {
    local itemid="$1" resp="" appid="" title="" appname=""
    command -v jq >/dev/null || return 1
    resp=$(curl -sSL --max-time 20 --proto '=https' -X POST \
        'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' \
        --data-urlencode 'itemcount=1' --data-urlencode "publishedfileids[0]=$itemid" 2>/dev/null) || return 1
    appid=$(jq -r '.response.publishedfiledetails[0] | select(.result == 1) | .consumer_app_id' <<<"$resp")
    if [[ -z "$appid" || "$appid" == "null" ]]; then
        return 1
    fi
    title=$(jq -r '.response.publishedfiledetails[0] | select(.result == 1) | .title // ""' <<<"$resp")
    appname=$(curl -sSL --max-time 10 --proto '=https' \
        "https://store.steampowered.com/api/appdetails?appids=$appid" 2>/dev/null \
        | jq -r --arg id "$appid" '.[$id] | select(.success == true) | .data.name // ""')
    echo "$appid|$(sw_decode_entities "$appname")|$(sw_decode_entities "$title")"
}

sw_api_time() { # itemid → "appid|time_updated" (更新检查用)
    local itemid="$1" resp="" appid="" updated=""
    command -v jq >/dev/null || return 1
    [[ "$itemid" =~ ^[0-9]+$ ]] || return 1
    resp=$(curl -sSL --max-time 20 --proto '=https' -X POST \
        'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' \
        --data-urlencode 'itemcount=1' --data-urlencode "publishedfileids[0]=$itemid" 2>/dev/null) || return 1
    appid=$(jq -r '.response.publishedfiledetails[0] | select(.result == 1) | .consumer_app_id' <<<"$resp")
    updated=$(jq -r '.response.publishedfiledetails[0] | select(.result == 1) | .time_updated' <<<"$resp")
    [[ "$appid" =~ ^[0-9]+$ && "$updated" =~ ^[0-9]+$ ]] || return 1
    echo "$appid|$updated"
}

sw_check_updates() { # root [appdir] → 待更新/现状/跳过行
    local root="$1" scope="${2:-}"
    [[ -d "$root" ]] || return 1
    local -a cand=() # "appid|itemid|path" (appid 可空)
    local d itemid parent appid
    while IFS= read -r -d '' d; do
        itemid=$(basename "$d")
        [[ "$itemid" =~ ^[0-9]+$ ]] || continue
        parent=$(basename "$(dirname "$d")")
        appid=""
        if [[ "$parent" =~ _([0-9]+)$ ]]; then
            appid="${BASH_REMATCH[1]}"
        elif [[ "$parent" =~ ^[0-9]+$ ]]; then
            appid="$parent"
        fi
        if [[ -n "$scope" && "$parent" != "$scope" ]]; then
            continue
        fi
        cand+=("$appid|$itemid|$d")
    done < <(find "$root" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null \
        | LC_ALL=C sort -z | grep -zvzF "$root/steamapps/")
    if [[ -z "$scope" && -d "$root/steamapps/workshop/content" ]]; then
        while IFS= read -r -d '' d; do
            itemid=$(basename "$d")
            [[ "$itemid" =~ ^[0-9]+$ ]] || continue
            appid=$(basename "$(dirname "$d")")
            [[ "$appid" =~ ^[0-9]+$ ]] || continue
            cand+=("$appid|$itemid|$d")
        done < <(find "$root/steamapps/workshop/content" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | LC_ALL=C sort -z)
    fi
    [[ ${#cand[@]} -gt 0 ]] || return 1
    local entry known time_info api_appid updated mtime
    local -a out=()
    for entry in "${cand[@]}"; do
        IFS='|' read -r known itemid d <<<"$entry"
        if ! time_info=$(sw_api_time "$itemid"); then
            out+=("SKIP|$itemid|$d|api-failed")
            continue
        fi
        IFS='|' read -r api_appid updated <<<"$time_info"
        [[ -n "$known" ]] && api_appid="$known"
        mtime=$(stat -c %Y "$d" 2>/dev/null) || {
            out+=("SKIP|$itemid|$d|stat-failed")
            continue
        }
        if ((updated > mtime)); then
            out+=("UPDATE|$api_appid|$itemid|$d")
        else
            out+=("CURRENT|$itemid|$d")
        fi
    done
    printf '%s\n' "${out[@]}" | LC_ALL=C sort
    return 0
}

sw_item_info() {
    local in="$1" page="" appid="" itemid=""
    [[ "$in" =~ [\?\&]appid=([0-9]+) ]] && {
        echo "${BASH_REMATCH[1]}||"
        return 0
    }
    page=$(sw_fetch_page "$in" 2>/dev/null)
    if [[ -n "$page" ]]; then
        appid=$(sw_parse_appid "$page")
        if [[ -n "$appid" ]]; then
            echo "$appid|$(sw_parse_appname "$page")|$(sw_parse_title "$page")"
            return 0
        fi
    fi
    itemid=$(sw_parse_itemid "$in") || return 1
    sw_api_info "$itemid"
}

sw_list_users() {
    [[ -f "$STEAM_LOGINUSERS" ]] || return 1
    local out
    out=$(awk -F'"' '
        $2 ~ /^[0-9]{17,}$/ { if (acc != "") print ts" "acc"|"pers; acc=""; pers=""; ts=0; next }
        $2 == "AccountName" { acc=$4 }
        $2 == "PersonaName" { pers=$4 }
        $2 == "Timestamp" { ts=$4 }
        END { if (acc != "") print ts" "acc"|"pers }
    ' "$STEAM_LOGINUSERS" | sort -rn | cut -d' ' -f2-)
    if [[ -z "$out" ]]; then
        return 1
    fi
    echo "$out"
}

sw_safe_app() { # appname appid → 扁平首层目录名
    local app="$1" id="$2"
    app=$(printf '%s' "$app" | sed 's/[[:space:]]\+//g; s/[^A-Za-z0-9._-]/_/g; s/__*/_/g; s/^_//; s/_$//')
    [[ "$app" == "." || "$app" == ".." ]] && app=""
    if [[ -z "$app" ]]; then
        app=$(printf '%s' "$id" | sed 's/[^A-Za-z0-9._-]/_/g')
        [[ -z "$app" || "$app" == "." || "$app" == ".." ]] && app="unknown"
    fi
    printf '%s' "$app"
}

sw_download() {
    local appid="$1" itemid="$2" user="${3:-anonymous}" appname="${4:-}"
    [[ "$appid" =~ ^[0-9]+$ && "$itemid" =~ ^[0-9]+$ ]] || return 1
    local -a login_arg=(+login anonymous)
    [[ "$user" != "anonymous" ]] && login_arg=(+login "$user")

    local install_dir="${STEAMCMD_INSTALL_DIR:-${STEAM_WORKSHOP_DIR:-$HOME/Downloads/steamcmd}}"
    mkdir -p "$install_dir" 2>/dev/null || return 1

    local log rc=0 path=""
    log=$(mktemp)
    steamcmd +force_install_dir "$install_dir" "${login_arg[@]}" +workshop_download_item "$appid" "$itemid" +quit >"$log" 2>&1
    rc=$?

    path=$(grep -o 'Success\. Downloaded item [0-9]* to "[^"]*"' "$log" | head -1 | sed 's/.* to "//; s/"$//')
    if [[ $rc -eq 0 && -n "$path" && -e "$path" ]]; then
        local safe flat_leaf flat_parent flat_dir
        safe=$(sw_safe_app "$appname" "$appid")
        flat_leaf="$safe"
        [[ "$safe" != "$appid" ]] && flat_leaf="${safe}_${appid}"
        flat_parent="$install_dir/$flat_leaf"
        flat_dir="$flat_parent/$itemid"
        if [[ "$path" != "$flat_dir" ]]; then
            mkdir -p "$flat_parent" 2>/dev/null || { cat "$log" >&2; rm -f "$log"; return 1; }
            rm -rf "$flat_dir" 2>/dev/null
            if mv "$path" "$flat_dir" 2>/dev/null; then
                path="$flat_dir"
            fi
        fi
        echo "$path"
    elif grep -qiE 'invalid password|steam guard|not logged on|access denied|no subscription|logon failure|rate limit' "$log"; then
        rc=2
    else
        rc=1
    fi
    [[ $rc -ne 0 ]] && cat "$log" >&2
    rm -f "$log"
    return $rc
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
    parse) shift; sw_parse_itemid "$@" ;;
    appid) shift; sw_resolve_appid "$@" ;;
    info) shift; sw_item_info "$@" ;;
    users) shift; sw_list_users "$@" ;;
    download) shift; sw_download "$@" ;;
    *)
        echo "usage: $0 {parse|appid|info|users|download} ..." >&2
        exit 1
        ;;
    esac
fi
