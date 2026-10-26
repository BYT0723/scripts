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

    local mon_name
    mon_name=$(xrandr --listactivemonitors 2>/dev/null | awk -v i="$monitor_index" 'NR>1 && $1+0==i {print $NF; exit}')
    [ -z "$mon_name" ] && return

    # 若该 monitor 属于某组, 清组窗口 (组与成员互斥); mon_name 自身靠同名 set reload
    local grp
    grp=$(group_for_monitor "$mon_name" all)
    [ -n "$grp" ] && xw_clear "grp_${grp// /_}"

    xw_clear_screen_and_restore

    # 单 monitor 用 -m 按输出名设置, daemon 在布局变化时原生跟随新几何
    xw_apply "$(detect_file_type "$filepath")" -m \
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

    # confname 用组名 (config 键), 非窗口名 grp_<组名>
    xw_apply "$(detect_file_type "$filepath")" "${w}x${h}+${x}+${y}" \
        "$target" "$filepath" "$group" || return 1
}

# video-render (fps/volume) 改动后重建当前视频壁纸。
# xwallpaperd 内 mpv 仅在创建时读取 --fps/--volume, 同名 set 只走 reload 不重建,
# 故必须 clear + 重设同一文件才能生效。
# 用法: reapply_video_wallpaper <target> (monitor 名 / 组名 / Screen)
# 仅当 target 当前壁纸为 video 时重建 (rotation 按 --state 第 4 列透传);
# 其它类型或无窗口时 no-op 返回 0。
reapply_video_wallpaper() {
    local target="$1"
    [ -z "$target" ] && return 1
    local win="$target"
    has_group "$target" && win="grp_${target// /_}"

    local line
    line=$(xwallpaper --state 2>/dev/null | awk -F'\t' -v n="$win" '$1==n {print; exit}')
    [ -n "$line" ] || return 0
    local _name _type path rot
    IFS=$'\t' read -r _name _type path rot <<<"$line"
    [ "$_type" = "video" ] || return 0
    [ -n "$path" ] || return 0

    xw_clear "$win"
    if has_group "$target"; then
        WALLPAPER_ROTATION="$rot" set_wallpaper_to_group "$target" "$path"
    elif [ "$target" = "Screen" ]; then
        WALLPAPER_ROTATION="$rot" set_wallpaper_to_screen "$path"
    else
        local idx
        idx=$(xrandr --listactivemonitors 2>/dev/null | awk -v n="$target" 'NR>1 && $NF==n {sub(":", "", $1); print $1; exit}')
        [ -n "$idx" ] || return 1
        WALLPAPER_ROTATION="$rot" set_wallpaper_to_monitor "$idx" "$path"
    fi
}
