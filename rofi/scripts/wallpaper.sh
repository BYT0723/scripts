#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"
MODULE_NAME=" Wallpaper"
MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_MAX_LINES=8

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/tools/wallpaper-lib.sh"

# ---- Monitor Selection ----
monitor_selection() {
    local list_text=$(get_monitor_list_text)
    local groups=" Groups"

    if [ "$(echo "$list_text" | wc -l)" = 1 ]; then
        echo "$list_text"
        return
    fi

    local chosen=$(printf '%s\n%s\n' "$list_text" "$groups" | module_sub_rofi "  Monitor" "Select a monitor for wallpaper")
    [ -z "$chosen" ] && return

    [[ "$chosen" == "$groups" ]] && echo "__GROUPS__" && return
    echo "$chosen" | awk '{print $2}'
}

handle_group() {
    local new_group=" New (Add)"
    local opts=("$new_group")
    while IFS= read -r grp; do
        [ -z "$grp" ] && continue
        local en_icon="󰔢"
        [ "$(get_group_enabled "$grp")" = "true" ] && en_icon="󰔡"
        opts+=("$en_icon $grp")
    done < <(group_names)

    local chosen=$(printf '%s\n' "${opts[@]}" | module_sub_rofi "󰮄  Wallpaper Groups" "Select or create a group")
    [ -z "$chosen" ] && return

    if [[ "$chosen" == "$new_group" ]]; then
        local monitors=$(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}')
        [ -z "$monitors" ] && {
            error "No monitors detected"
            return
        }
        local selected=$(printf '%s\n' $monitors | module_multi_rofi "󰮄 Select Monitors" "Choose monitors for the group")
        [ -z "$selected" ] && return

        while IFS= read -r mon; do
            [ -z "$mon" ] && continue
            local owner=$(group_for_monitor "$mon" all)
            [ -n "$owner" ] && error "Monitor '$mon' already belongs to group '$owner'" && return
        done <<<"$selected"

        local name=$(module_input "󰮄 Group Name" "Name for the new group")
        [ -z "$name" ] && return

        if has_group "$name"; then
            error "Group '$name' already exists" && return
        fi

        local members_json=$(printf '%s\n' $selected | jq -Rnc '[inputs]')
        jq --arg n "$name" --argjson m "$members_json" \
            '.groups[$n] = {enabled: true, members: $m}' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
        handle_error "info" "Group '$name' created"
    else
        local group_name="${chosen#* }"
        local sub_opts=()
        local en
        en=$(get_group_enabled "$group_name")
        [ "$en" = "true" ] && sub_opts+=("󰔡 Disable") || sub_opts+=("󰔢 Enable")
        sub_opts+=("󰑉 Rename")
        sub_opts+=("󰔨 Edit Members")
        sub_opts+=("󰆴 Delete")

        local action=$(printf '%s\n' "${sub_opts[@]}" | module_sub_rofi "󰮄 $group_name" "Manage group")
        [ -z "$action" ] && return

        case "$action" in
        *Disable)
            jq --arg n "$group_name" '.groups[$n].enabled = false' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            clean_group "$group_name"
            handle_error "info" "Group '$group_name' disabled"
            ;;
        *Enable)
            jq --arg n "$group_name" '.groups[$n].enabled = true' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            handle_error "info" "Group '$group_name' enabled"
            ;;
        *Rename)
            local new_name=$(module_input "󰑉 Rename Group" "Current: $group_name" "$group_name")
            [ -z "$new_name" ] || [ "$new_name" = "$group_name" ] && return
            if has_group "$new_name"; then
                error "Group '$new_name' already exists" && return
            fi
            jq --arg old "$group_name" --arg new "$new_name" \
                '.groups[$new] = .groups[$old] | del(.groups[$old]) | if .monitors[$old] then .monitors[$new] = .monitors[$old] | del(.monitors[$old]) else . end' \
                "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            clean_group "$group_name"
            handle_error "info" "Group renamed to '$new_name'"
            ;;
        *"Edit Members")
            local all_mons=$(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}')
            local cur=$(get_group_members "$group_name" | xargs)
            local selected=$(printf '%s\n' $all_mons | module_multi_rofi "󰮄 Edit Members" "Current: ${cur:-none}")
            [ -z "$selected" ] && return

            while IFS= read -r mon; do
                [ -z "$mon" ] && continue
                local owner=$(group_for_monitor "$mon" all)
                [ -n "$owner" ] && [ "$owner" != "$group_name" ] && error "Monitor '$mon' already belongs to group '$owner'" && return
            done <<<"$selected"

            local members_json=$(printf '%s\n' $selected | jq -Rnc '[inputs]')
            jq --arg n "$group_name" --argjson m "$members_json" \
                '.groups[$n].members = $m' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            clean_group "$group_name"
            handle_error "info" "Group '$group_name' members updated"
            ;;
        *Delete)
            local confirm=$(printf 'Yes\nNo' | module_sub_rofi "󰮄 Delete '$group_name'?" "This cannot be undone")
            [ "$confirm" != "Yes" ] && return
            clean_group "$group_name"
            jq --arg n "$group_name" 'del(.groups[$n])' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            handle_error "info" "Group '$group_name' deleted"
            ;;
        esac
    fi
}

# ---- Main ----
MONITOR=$(monitor_selection)
[ -z "$MONITOR" ] && exit 0

if [[ "$MONITOR" == "__GROUPS__" ]]; then
    handle_group
    exit 0
fi

ensure_monitor_config "$MONITOR"
MODULE_MESG="Monitor: $MONITOR"

module_parse <<'MODULES'
next|󰑐|Next|
select||Select|
random_switch||Random|cmd:icon toggle conf wallpaper random number "$MONITOR"
random_type|󱧶|Type|cmd:[[ $(getConfig -m "$MONITOR" random_type) == "video" ]] && echo "" || echo ""
random_duration|󰔟|Duration|cmd:getConfig -m "$MONITOR" duration
random_depth||Depth|cmd:getConfig -m "$MONITOR" random_depth
random_images_path||Images|
random_videos_path||Videos|
MODULES
handle_next() { ( "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" next & ) ; }
handle_select() { "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" select; }
handle_random_switch() { toggleConf wallpaper random number "$MONITOR"; }
handle_random_type() { toggleConf wallpaper random_type wallpaper_type "$MONITOR"; }
handle_random_duration() { set_numeric_config "$MONITOR" duration "Duration" "Wallpaper change interval in minutes (≥ 1)" 1; }
handle_random_depth() { set_numeric_config "$MONITOR" random_depth "Search Depth" "Max directory depth for wallpaper files (1–10)" 1 10; }
handle_random_images_path() { pick_config_dir "$MONITOR" random_image_dir; }
handle_random_videos_path() { pick_config_dir "$MONITOR" random_video_dir; }

while module_loop; do :; done
