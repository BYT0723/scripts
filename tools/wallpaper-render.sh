# xwallpaper 渲染层：所有壁纸统一由 xwallpaper 渲染。
# 保留函数签名 (set_wallpaper_to_screen/monitor/group) 供 wallpaper.sh 调用，
# 内部不再使用 xwinwrap/mpv/nsxiv/surf/feh。
# xw_set / xw_clear / xw_apply 定义于 wallpaper-lib.sh (共享给 rofi 脚本)。

set_wallpaper_to_screen() {
    local filepath="$@"

    local screen_size
    screen_size=$(get_screen_size) || return

    # 移除非Screen外的所有monitor / group 壁纸
    xw_clear_all_exclude_screen

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

    # 若该 monitor 属于某组, 清组窗口 (组与成员互斥); mon_name 自身靠同名 set reload
    if [ -n "$mon_name" ]; then
        local grp
        grp=$(group_for_monitor "$mon_name" all)
        if [ -n "$grp" ]; then
            xw_clear "grp_${grp// /_}"
        fi
    fi

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
    # grp_<组名> 自身窗口不手动清 — xwallpaper 对同名 set 走 reload
    xw_clear_group_members "$group"

    xw_clear_screen_and_restore

    xw_apply "$(detect_file_type "$filepath")" "${w}x${h}+${x}+${y}" \
        "$target" "$filepath" || return 1
}
