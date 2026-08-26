# xwallpaper 渲染层：所有壁纸统一由 xwallpaper 渲染。
# 保留函数签名 (set_wallpaper_to_screen/monitor/group) 供 wallpaper.sh 调用，
# 内部不再使用 xwinwrap/mpv/nsxiv/surf/feh。
# xw_set / xw_clear / xw_apply 定义于 wallpaper-lib.sh (共享给 rofi 脚本)。

set_wallpaper_to_screen() {
    local filepath="$@"

    local screen_size
    screen_size=$(get_screen_size) || return

    xw_clear_all

    xw_apply "$(detect_file_type "$filepath")" "$screen_size" \
        "Screen" "$filepath" || return
}

set_wallpaper_to_monitor() {
    local monitor_index=${1}
    shift
    local filepath="$@"

    [ -z "$monitor_index" ] && return

    read monitor_index width height x y < <(get_monitor_info_by_index "$monitor_index")
    local mon_name
    mon_name=$(xrandr --listactivemonitors 2>/dev/null | awk -v i="$monitor_index" 'NR>1 && $1+0==i {print $NF; exit}')

    clean_target "mon" "$monitor_index"

    xw_clear_screen_and_restore

    xw_apply "$(detect_file_type "$filepath")" "${width}x${height}+${x}+${y}" \
        "$mon_name" "$filepath" || return
}

set_wallpaper_to_group() {
    local group="$1"
    shift
    local filepath="$@"

    local dims
    dims=$(get_group_dim "$group" 2>/dev/null) || return 1
    local w h x y
    read w h x y <<<"$dims"

    local gs="${group// /_}"
    local target="grp_${gs}"

    # group 与其成员 monitor 互斥：先清掉成员 monitor 的独立窗口
    local mon_name
    while IFS= read -r mon_name; do
        [ -z "$mon_name" ] && continue
        xw_clear "$mon_name"
    done < <(get_group_members "$group")

    clean_target "grp" "$group"

    xw_clear_screen_and_restore

    xw_apply "$(detect_file_type "$filepath")" "${w}x${h}+${x}+${y}" \
        "$target" "$filepath" || return 1
}
