#!/usr/bin/env /bin/bash

WORK_DIR=$(dirname "$(dirname "$0")")

source "$WORK_DIR/utils/notify.sh"

#
# Focus: Do not use spaces in paths and filenames, unexpected consequences may occur
#

source "$(dirname "$0")/wallpaper-lib.sh"
source "$(dirname "$0")/wallpaper-render.sh"

# return random wallpaper filepath for given monitor
random_wallpaper() {
    local monitor="$1"
    local depth=$(getConfig -m "$monitor" random_depth)
    local random_type=$(getConfig -m "$monitor" random_type)
    local dir=""
    local pattern=""

    case "$random_type" in
    "video")
        dir=$(getConfig -m "$monitor" random_video_dir)
        pattern=".*\.(mp4|avi|mkv)"
        ;;
    "image")
        dir=$(getConfig -m "$monitor" random_image_dir)
        pattern=".*\.(jpeg|jpg|png)"
        ;;
    *)
        error "Unknown random type: $random_type"
        return
        ;;
    esac

    # Use find_wallpapers to get all matching files
    local files
    if ! files=$(find_wallpapers "$dir" "$depth" "$pattern"); then
        # Error already printed by find_wallpapers
        return
    fi

    # Convert newline-separated list to array
    local file_array=()
    mapfile -t file_array <<<"$files"

    # Exclude current wallpaper to avoid showing the same one again
    local cache_file=""
    local monitor_index=$(xrandr --listactivemonitors 2>/dev/null | awk -v name="$monitor" 'NR>1 && $NF==name {gsub(":","",$1); print $1; exit}')
    if [ -n "$monitor_index" ]; then
        cache_file="${wallpaper_latest}_${monitor_index}"
    elif has_group "$monitor"; then
        cache_file="${wallpaper_latest}_grp_${monitor// /_}"
    elif [ "$monitor" = "Screen" ]; then
        cache_file="$wallpaper_full_latest"
    fi

    if [ -n "$cache_file" ] && [ -f "$cache_file" ]; then
        local current_file=$(head -1 "$cache_file" | cut -d'|' -f1)
        local filtered=()
        local f
        for f in "${file_array[@]}"; do
            [ "$f" != "$current_file" ] && filtered+=("$f")
        done
        if [ ${#filtered[@]} -gt 0 ]; then
            file_array=("${filtered[@]}")
        fi
    fi

    # Randomly select one file
    local count=${#file_array[@]}
    local random_index=$((RANDOM % count))
    echo "${file_array[$random_index]}"
}

select_wallpaper() {
    local monitor="$1"
    local dir
    local tmp=$(mktemp)

    case "$(getConfig -m "$monitor" random_type)" in
    video) dir=$(getConfig -m "$monitor" random_video_dir) ;;
    image) dir=$(getConfig -m "$monitor" random_image_dir) ;;
    *)
        rm -f "$tmp"
        return 1
        ;;
    esac

    YAZI_CONFIG_HOME=$HOME/.config/yazi_wallpaper $TERM yazi "$dir" --chooser-file="$tmp"

    echo "$(cat $tmp)"
    rm -f "$tmp"
}

# ---- Get rotation for video wallpaper (cached or preview) ----
get_wallpaper_rotation() {
    local file="$1"
    local name="$2"
    local monitors_list="$3"
    local force_preview="$4"
    local rotation=""

    if [[ $(detect_file_type "$file") == "video" ]] && command -v ffprobe >/dev/null 2>&1; then
        local vid_dim=$(get_video_dim "$file")
        if [ -n "$vid_dim" ]; then
            read vid_w vid_h <<<"$vid_dim"
            read mon_w mon_h <<<"$(get_monitor_dim "$name")"
            if orientation_mismatch "$mon_w" "$mon_h" "$vid_w" "$vid_h"; then
                if ! $force_preview; then
                    local cached=$(awk -F'|' -v f="$file" -v m="$name" '$1 == f && $2 == m {print $3; exit}' "$rotation_cache" 2>/dev/null)
                    [ -n "$cached" ] && rotation="$cached"
                fi
                if [ -z "$rotation" ]; then
                    rotation=$(preview_rotation "$file")
                    awk -F'|' -v f="$file" -v m="$name" '!($1 == f && $2 == m)' "$rotation_cache" 2>/dev/null >"$rotation_cache.tmp"
                    echo "$file|$name|$rotation" >>"$rotation_cache.tmp"
                    mv "$rotation_cache.tmp" "$rotation_cache"
                fi
            fi
        fi
    fi
    echo "$rotation"
}

# ---- Apply wallpaper file to a given monitor ----
apply_wallpaper() {
    local force_preview=false
    [ "$1" = "-f" ] && force_preview=true && shift
    local name="$1"
    shift
    local file="$@"
    local monitors_list
    monitors_list=$(xrandr --listactivemonitors 2>/dev/null)

    WALLPAPER_ROTATION=$(get_wallpaper_rotation "$file" "$name" "$monitors_list" "$force_preview")

    if has_group "$name"; then
        set_wallpaper_to_group "$name" "$file" && return
    fi

    if [[ "$name" != "Screen" ]]; then
        local grp=$(group_for_monitor "$name")
        [ -n "$grp" ] && error "Monitor '$name' belongs to group '$grp'. Disable the group first or use '-m $grp'." && return 1
    fi

    if [[ "$name" == "Screen" ]]; then
        set_wallpaper_to_screen "$file" && return
    fi

    local monitor_index
    monitor_index=$(echo "$monitors_list" | awk -v n="$name" 'NR>1 && $NF==n {sub(":","",$1); print $1}')
    [ -n "$monitor_index" ] && set_wallpaper_to_monitor "$monitor_index" "$file"
}

set_latest() {
    if [ -f "$wallpaper_full_latest" ]; then
        IFS='|' read -r fp rot <"$wallpaper_full_latest"
        WALLPAPER_ROTATION="$rot"
        set_wallpaper_to_screen "$fp" && return
    fi

    restore_latest_monitor_group
}

# wallpaper launch_wallpaper
launch_wallpaper() {
    sleep $wallpaper_launch_delay

    # kill last daemon
    script=$(readlink -f "$0")
    pgrep -f "$script" | grep -vx "$$" | xargs -r kill

    set_latest

    declare -A last_update
    local check_interval=60

    local was_locked=false

    while true; do
        sleep $check_interval
        local now=$(date +%s)

        if pgrep -x i3lock >/dev/null; then
            was_locked=true
            continue
        fi

        # Reset all timers on unlock to avoid mass wallpaper change
        if $was_locked; then
            was_locked=false
            for k in "${!last_update[@]}"; do
                last_update[$k]=$now
            done
        fi

        # screen 全屏模式: 与 monitor/group 互斥, daemon 暂停轮换直到退出 screen 模式
        [ -f "$wallpaper_full_latest" ] && continue

        while read -r target; do
            is_group_member "$target" && continue
            [ "$(getConfig -m "$target" random)" -eq 1 ] || continue

            if [ -z "${last_update[$target]}" ]; then
                last_update[$target]=$now
                continue
            fi

            local dur=$(getConfig -m "$target" duration)
            local last="${last_update[$target]}"
            [ $((now - last)) -lt $((dur * 60)) ] && continue

            file=$(random_wallpaper "$target")
            [ -n "$file" ] && apply_wallpaper "$target" "$file" && last_update[$target]=$now
        done < <(
            xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}'
            while IFS= read -r grp; do
                [ "$(get_group_enabled "$grp")" != "true" ] && continue
                get_group_dim "$grp" >/dev/null 2>&1 || continue
                echo "$grp"
            done < <(group_names)
        )
    done
}

# 操作符
op=$1

case "$op" in
'-r' | '--run') launch_wallpaper ;;
'-m')
    shift
    monitor="$1"
    shift
    action="$1"
    case "$action" in
    next)
        file=$(random_wallpaper "$monitor")
        fflag=""
        ;;
    select)
        file=$(select_wallpaper "$monitor")
        fflag="-f"
        ;;
    *) exit 1 ;;
    esac
    [ -n "$file" ] && apply_wallpaper $fflag "$monitor" "$file"
    ;;
'-h' | '--help') echo_help ;;
*)
    echo -e "\033[31mbad operator\033[0m"
    echo_help
    ;;
esac

exit 0
