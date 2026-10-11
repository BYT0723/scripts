#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"
MODULE_NAME=" Wallpaper"
MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_MAX_LINES=8

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/tools/wallpaper-lib.sh"
source "$WORK_DIR/tools/wallpaper-render.sh"

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
random_type|󱧶|Type|cmd:t=$(getConfig -m "$MONITOR" random_type); case "$t" in video) echo "";; web) echo "";; *) echo "";; esac
random_duration|󰔟|Duration|cmd:getConfig -m "$MONITOR" duration
fps||FPS|cmd:get_video_render_config "$MONITOR" fps
random_images_path||Images Path|
random_videos_path||Videos Path|
random_web_path||Web Path|
random_images_path_dark||Images Path (Dark)|
random_videos_path_dark||Videos Path (Dark)|
random_web_path_dark||Web Path (Dark)|
MODULES
handle_next() { ("$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" next &) }
# web 用 rofi 图文选择器 (标题+预览缩略图): yazi 顶层只见数字 id,
# 名字在 project.json:title 里, 预览在 preview 字段/preview.* 里。image/video 保留 yazi 大图预览。
select_web_wallpaper() {
    local dir depth files
    dir=$(get_theme_dir "$MONITOR" random_web_dir)
    depth=$(getConfig random_depth)
    if ! files=$(find_wallpapers "$dir" "$depth" ".*/index\.html"); then
        return 1
    fi

    local menu map menu_nul
    menu=$(mktemp)
    map=$(mktemp)
    menu_nul=$(mktemp)
    trap 'rm -f "$menu" "$map" "$menu_nul"' RETURN

    local d f id title preview icon meta p
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        d=$(dirname "$f")
        id=$(basename "$d")
        title="$id"
        preview=""
        if [ -f "$d/project.json" ]; then
            meta=$(jq -r '[.title // empty, .preview // empty] | @tsv' "$d/project.json" 2>/dev/null)
            IFS=$'\t' read -r title preview <<<"$meta"
            [ -z "$title" ] && title="$id"
        fi
        title=$(printf '%s' "$title" | tr '\t\n\r' '   ')
        icon=""
        [ -n "$preview" ] && [ -f "$d/$preview" ] && icon="$d/$preview"
        if [ -z "$icon" ]; then
            for p in preview.gif preview.png preview.jpg preview.jpeg preview.webp; do
                if [ -s "$d/$p" ]; then icon="$d/$p"; break; fi
            done
        fi
        # NUL 字节 bash 变量装不下: 行尾先写 \001 占位, 喂 rofi 前统一 tr 成 NUL (同 windows-selector)
        printf '%s (%s)\001icon\x1f%s\x1f\n' "$title" "$id" "$icon" >>"$menu"
        printf '%s\n' "$d" >>"$map"
    done <<<"$files"
    tr '\001' '\000' <"$menu" >"$menu_nul"

    local sel
    # 网格主题 (双列卡片 + 128px 大缩略图): inputbar 只有 entry, prompt 经 -p 设置
    sel=$(rofi -dmenu -i -p "Web" -format i -no-custom -show-icons \
        -theme "$ROFI_DIR/launchers/type-3/style-6.rasi" \
        -theme-str 'listview {columns: 4; lines: 4; flow: horizontal; }' \
        -theme-str 'window {width: 800px;}' \
        -hover-select -me-select-entry '' -me-accept-entry '' -me-accept-custom MousePrimary <"$menu_nul" 2>/dev/null) || return 0
    case "$sel" in '' | *[!0-9]*) return 0 ;; esac
    local picked
    picked=$(sed -n "$((sel + 1))p" "$map")
    [ -n "$picked" ] || return 0
    "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" file "$picked"
}
handle_select() {
    if [ "$(getConfig -m "$MONITOR" random_type)" = "web" ]; then
        select_web_wallpaper
    else
        "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" select
    fi
}
handle_random_switch() { toggleConf wallpaper random number "$MONITOR"; }
handle_random_type() {
    local cur chosen conf
    cur=$(getConfig -m "$MONITOR" random_type)
    chosen=$(printf 'image\nvideo\nweb' | module_sub_rofi "Random type" "current: $cur")
    case "$chosen" in image | video | web) ;; *) return ;; esac
    [ "$chosen" = "$cur" ] && return
    conf="$HOME/.config/dwm/wallpaper.json"
    jq --arg m "$MONITOR" --arg v "$chosen" '.monitors[$m].random_type = $v' \
        "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
}
handle_random_duration() { set_numeric_config "$MONITOR" duration "Duration" "Wallpaper change interval in minutes (≥ 1)" 1; }
handle_fps() {
    # setter 仅在写入新值时返回 0 (取消/非法/未改变直接返回)；有改变才重建 video 壁纸
    set_video_render_config "$MONITOR" fps "FPS" "Video frame rate limit (0 = unlimited, ≥ 0)" 0 &&
        reapply_video_wallpaper "$MONITOR"
}
handle_random_images_path() { pick_config_dir "$MONITOR" random_image_dir; }
handle_random_videos_path() { pick_config_dir "$MONITOR" random_video_dir; }
handle_random_web_path() { pick_config_dir "$MONITOR" random_web_dir; }
handle_random_images_path_dark() { pick_config_dir "$MONITOR" random_image_dir_dark; }
handle_random_videos_path_dark() { pick_config_dir "$MONITOR" random_video_dir_dark; }
handle_random_web_path_dark() { pick_config_dir "$MONITOR" random_web_dir_dark; }

while module_loop; do :; done
