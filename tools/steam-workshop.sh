#!/usr/bin/env bash
# steam-workshop.sh — steamcmd 创意工坊下载核心 (无 rofi 依赖, 可 CLI/单测)
#   sw_parse_itemid <url-or-id>  → stdout itemid
#   sw_fetch_page <url-or-id>    → stdout 工坊页面 HTML (纯数字 ID 自动拼 URL)
#   sw_parse_appid <page>        → stdout appid
#   sw_parse_field <page> <marker> → stdout 标记文本 (HTML 转义解码)
#   sw_page_gated <page>         → 登录门返回 0 (匿名不可见条目)
#   sw_parse_appname <page>      → stdout app 名 (可空)
#   sw_parse_title <page>        → stdout 资源名 (可空)
#   sw_resolve_appid <url-or-id> → stdout appid (先 ?appid= 参数, 后抓页面)
#   sw_item_info <url-or-id>     → stdout "appid|app名|资源名" (appid 必需, 否则失败)
#   sw_list_users                → stdout "AccountName|PersonaName" 行 (按 Timestamp 倒序)
#   sw_download <appid> <itemid> <user> → stdout 实际落盘路径; rc=0 成功, 2=需终端登录, 1=其他失败

STEAM_LOGINUSERS="${STEAM_LOGINUSERS:-$HOME/.local/share/Steam/config/loginusers.vdf}"

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

sw_item_info() {
    local in="$1" page="" appid=""
    [[ "$in" =~ [\?\&]appid=([0-9]+) ]] && {
        echo "${BASH_REMATCH[1]}||"
        return 0
    }
    page=$(sw_fetch_page "$in") || return 1
    appid=$(sw_parse_appid "$page")
    [[ -z "$appid" ]] && return 1
    echo "$appid|$(sw_parse_appname "$page")|$(sw_parse_title "$page")"
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

sw_download() {
    local appid="$1" itemid="$2" user="${3:-anonymous}"
    local -a login_arg=(+login anonymous)
    [[ "$user" != "anonymous" ]] && login_arg=(+login "$user")

    local log rc=0 path=""
    log=$(mktemp)
    steamcmd "${login_arg[@]}" +workshop_download_item "$appid" "$itemid" +quit >"$log" 2>&1
    rc=$?

    path=$(grep -o 'Success\. Downloaded item [0-9]* to "[^"]*"' "$log" | head -1 | sed 's/.* to "//; s/"$//')
    if [[ $rc -eq 0 && -n "$path" && -e "$path" ]]; then
        echo "$path"
        rc=0
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
