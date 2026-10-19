#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_NAME="󰉋 Steam Workshop"
MODULE_MESG="Download / update workshop items via steamcmd"

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
    local appid="$1" itemid="$2" user="$3" label="$4" appname="$5"

    system-notify low "Steam Workshop" "Downloading\n$label"

    (
        local rc=0 out err msg act
        out=$(sw_download "$appid" "$itemid" "$user" "$appname" 2>&1) || rc=$?
        if [[ $rc -eq 0 ]]; then
            act=$(notify-send -u normal " Steam Workshop" "Done\n$label\n$out" -A open="Open folder" 2>/dev/null)
            [[ "$act" == "open" || "$act" == "0" ]] && xdg-open "$out"
        elif [[ $rc -eq 2 ]]; then
            msg="Login required"
            err=$(sw_short_error <<<"$out")
            [[ -n "$err" ]] && msg="$msg\n$err"
            system-notify critical "Steam Workshop" "$msg\nRun in terminal: steamcmd +login $user +quit"
        else
            msg="Failed (rc=$rc)"
            err=$(sw_short_error <<<"$out")
            [[ -n "$err" ]] && msg="$msg\n$err"
            system-notify critical "Steam Workshop" "$msg\n$label"
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
        if sw_page_gated "$(sw_fetch_page "$url")"; then
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
    _download "$appid" "$itemid" "$user" "$label" "$appname"
}

# ------- handlers -------

handle_download() {
    local url="$CLIP_URL"
    if ! sw_parse_itemid "$url" >/dev/null 2>&1; then
        url=$(module_input "Workshop URL" "Enter workshop link or numeric ID" "${CLIP_URL:-}")
        [[ -z "$url" ]] && return
    fi
    _go "$url"
}

handle_update() {
    local root="${STEAMCMD_INSTALL_DIR:-$HOME/Downloads/steam-workshop}"
    local sel scope="" lines updates skips user
    if [[ ! -d "$root/steamapps/workshop/content" ]] \
        && ! find "$root" -mindepth 1 -maxdepth 1 -type d ! -name 'steamapps' -print -quit 2>/dev/null | grep -q .; then
        system-notify normal "Steam Workshop" "No downloads yet"$'\n'"$root"
        return
    fi
    sel=$( {
        echo "All Apps"
        find "$root" -mindepth 1 -maxdepth 1 -type d ! -name 'steamapps' -printf '%f\n' 2>/dev/null | LC_ALL=C sort
    } | module_sub_rofi "Steam Workshop" "Select scope to update")
    [[ -z "$sel" ]] && return
    [[ "$sel" != "All Apps" ]] && scope="$sel"
    system-notify low "Steam Workshop" "Checking for updates"$'\n'"$sel"
    if [[ -z "$scope" ]]; then
        lines=$(sw_check_updates "$root") || {
            system-notify normal "Steam Workshop" "No downloads yet"$'\n'"$root"
            return
        }
    else
        lines=$(sw_check_updates "$root" "$scope") || {
            system-notify normal "Steam Workshop" "No downloads yet"$'\n'"$scope"
            return
        }
    fi
    updates=$(grep -c '^UPDATE|' <<<"$lines")
    skips=$(grep -c '^SKIP|' <<<"$lines")
    if [[ "$updates" -eq 0 ]]; then
        system-notify normal "Steam Workshop" "All up to date${skips:+ ($skips skipped)}"
        return
    fi
    module_confirm "Update $updates item(s)${skips:+ ($skips skipped)}?" || return
    user=$(_pick_user) || return
    (
        local summary ok fail fids
        system-notify low "Steam Workshop" "Updating $updates item(s)..."
        summary=$(grep '^UPDATE|' <<<"$lines" | sw_run_updates "$user")
        read -r ok fail fids <<<"$summary"
        if [[ "$fail" -eq 0 ]]; then
            system-notify normal "Steam Workshop" "Update done"$'\n'"$ok updated"
        else
            system-notify critical "Steam Workshop" "Update done"$'\n'"$ok updated, $fail failed: $fids"
        fi
    ) &
}

handle_open() {
    local root="${STEAMCMD_INSTALL_DIR:-$HOME/Downloads/steam-workshop}"
    mkdir -p "$root" 2>/dev/null || {
        system-notify critical "Steam Workshop" "Cannot create directory"$'\n'"$root"
        return
    }
    xdg-open "$root" &>/dev/null &
}

# ------- main -------

_menu="download|󰇚|Download|"$'\n'
_menu+="update|󰑓|Update|"$'\n'
_menu+="open|󰝰|Open Directory|"$'\n'

module_parse <<<"$_menu"

module_loop
