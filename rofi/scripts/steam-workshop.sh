#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_NAME="󰉋 Steam Workshop"
MODULE_MESG="Download workshop item via steamcmd"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/utils/notify.sh"

source "$WORK_DIR/tools/steam-workshop.sh"

CLIP_URL=""
if command -v xclip &>/dev/null; then
    CLIP_RAW=$(xclip -selection clipboard -o 2>/dev/null)
    CLIP_URL=$(grep -oE 'https?://[^[:space:]"]*steamcommunity\.com[^[:space:]"]*' <<<"$CLIP_RAW" | head -1)
    [[ -z "$CLIP_URL" ]] && CLIP_URL=$(grep -oE 'https?://[^[:space:]]+' <<<"$CLIP_RAW" | head -1)
fi

# ------- helpers -------

_pick_user() {
    local users n sel
    users=$(sw_list_users)
    if [[ -z "$users" ]]; then
        echo "anonymous"
        return 0
    fi
    n=$(wc -l <<<"$users")
    if [[ "$n" -eq 1 ]]; then
        cut -d'|' -f1 <<<"$users"
        return 0
    fi
    sel=$(printf '%s\n' "$(awk -F'|' '{print $1" — "$2}' <<<"$users")" "anonymous" | module_sub_rofi "󰉋 Steam User" "Select login user")
    [[ -z "$sel" ]] && return 1
    [[ "$sel" == "anonymous" ]] && {
        echo "anonymous"
        return 0
    }
    echo "${sel%% *}"
}

_download() {
    local appid="$1" itemid="$2" user="$3" label="$4"

    system-notify low "Steam Workshop" "Downloading\n$label"

    (
        local rc=0 out err msg
        out=$(sw_download "$appid" "$itemid" "$user" 2>&1) || rc=$?
        if [[ $rc -eq 0 ]]; then
            act=$(notify-send -u normal " Steam Workshop" "Done\n$label\n$out" -A open="Open folder" 2>/dev/null)
            [[ "$act" == "open" || "$act" == "0" ]] && xdg-open "$out"
        elif [[ $rc -eq 2 ]]; then
            msg="Login required"
            err=$(sw_short_error <<<"$out")
            [[ -n "$err" ]] && msg="$msg\n$err"
            system-notify critical "Steam Workshop" "$msg\nRun in terminal: steamcmd +login $user +quit"
        else
            system-notify critical "Steam Workshop" "Failed (rc=$rc)\n$label"
        fi
    ) &
}

_go() {
    local url="$1" itemid info appid appname title label user
    itemid=$(sw_parse_itemid "$url") || {
        system-notify critical "Steam Workshop" "Invalid URL or ID\n$url"
        return
    }
    if info=$(sw_item_info "$url"); then
        IFS='|' read -r appid appname title <<<"$info"
    else
        mesg="Could not detect AppID for item $itemid, enter manually"
        if sw_page_gated "$(sw_fetch_page "$url" 2>/dev/null)"; then
            mesg="Login-gated item (anonymous can't see it), enter AppID manually"
        fi
        appid=$(module_input "AppID" "$mesg")
        [[ -z "$appid" ]] && return
        appname=""
        title=""
    fi
    label="${title:-item $itemid}"
    [[ ${#label} -gt 65 ]] && label="${label:0:62}..."
    [[ -n "$appname" ]] && label="$label — $appname"
    user=$(_pick_user) || return
    _download "$appid" "$itemid" "$user" "$label"
}

# ------- handlers -------

handle_input() {
    local url
    url=$(module_input "Workshop URL" "Enter workshop link or numeric ID" "${CLIP_URL:-}")
    [[ -z "$url" ]] && return
    _go "$url"
}

handle_clipboard() {
    [[ -z "$CLIP_URL" ]] && return
    _go "$CLIP_URL"
}

# ------- main -------

_menu="input|󰋩|Input URL|"$'\n'
[[ -n "$CLIP_URL" ]] && _menu+="clipboard|󰅐|Clipboard|"$'\n'

module_parse <<<"$_menu"

module_loop
