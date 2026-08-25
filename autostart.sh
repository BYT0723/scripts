#!/bin/bash

WORK_DIR=$(dirname $(realpath "$0"))
TOOLS_DIR="$WORK_DIR/tools"

# conky 是否自启动
CONKY_AUTOSTART=1

# 显示器布局初始化
[ -n "$(command -v autorandr)" ] && autorandr --change

# 启动应用
# $1 policy           string [check/restart]
# $2 application_name string
# $3 command          string
launch() {
    local policy=${1:-"check"} name=$2
    shift 2
    local cmd="$*"
    local dir="/tmp/dwm-status"
    local pf="$dir/autostart-launch-$name.pid"
    local pid

    mkdir -p "$dir"

    # 重入/并发互斥: 同一 name 的检查+启动必须原子, 拿不到锁说明另一实例
    # 正在处理, 直接跳过 (该实例会完成启动)
    {
        flock -n 9 || return 1

        # read pid + verify alive (空 pid/文件不存在时 kill 失败 → 重置为空)
        pid=$(cat "$pf" 2>/dev/null)
        kill -0 "$pid" 2>/dev/null || pid=""

        case "$policy" in
        check)
            [ -z "$pid" ] || return 0
            ;;
        restart)
            [ -n "$pid" ] && kill "$pid" 2>/dev/null
            # 等旧进程退出, 避免新旧实例并存 (最多等 2s)
            for _ in {1..20}; do
                [ -n "$pid" ] || break
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.1
            done
            ;;
        esac

        # 9>&- 关闭子进程的锁 fd, 防止后台进程继承锁导致永不释放
        $cmd &>/dev/null 9>&- &
        echo $! >"$pf"
    } 9>"$dir/autostart-launch-$name.lock"
}

desktop_setting() {
    # 状态栏信息
    /bin/bash $WORK_DIR/dwm-status.sh reboot
    # systray sni
    launch check snixembed "snixembed"
    # 壁纸(不使用launch_monitor是因为wallpaper每次启动都要使用新的instance, 移除旧的实例)
    # wallpaper.sh内部实现了
    launch restart xwallpaper "xwallpaper --daemon"
    /bin/bash "$TOOLS_DIR"/wallpaper.sh -r &
    # 屏保
    launch restart screen "/bin/bash $TOOLS_DIR/screen.sh"
    # 自动主题切换 (auto=false 时立即退出)
    launch restart theme-auto "/bin/bash $TOOLS_DIR/theme.sh auto"
}

application_launch() {
    # 窗口合成器 picom (window composer)
    launch check picom "picom --config $HOME/.config/dwm/picom.conf"
    # XSETTINGS 守护 (GTK 主题/字体广播, Firefox 亮暗跟随依赖)
    launch check xsettingsd "xsettingsd"
    # 启动通知
    launch check dunst "dunst"
    # network manager 网络管理bar icon
    launch restart nm-applet "nm-applet"
    # input method
    launch restart fcitx5 "fcitx5"
    # auto mount
    launch restart udiskie "udiskie -sn"
    # polkit (require lxsession or lxsession-gtk3) 鉴权
    launch check lxpolkit "lxpolkit"
    # conky (system monitor)
    ((CONKY_AUTOSTART > 0)) && /bin/bash $WORK_DIR/dwm-launcher.sh conky start
    # 音频控制 (暂时先关闭，已有独立功放，不需要ee)
    # launch check easyeffects "easyeffects --service-mode --hide-window"
}

keyboard_setting() {
    bash $TOOLS_DIR/keyboard.sh set option-set "caps:escape,altwin:swap_lalt_lwin"
    bash $TOOLS_DIR/keyboard.sh set delay 250
    bash $TOOLS_DIR/keyboard.sh set rate 35
}

check_autorandr_xsetup() {
    local lock=/tmp/dwm-autostart-xsetup-autorandr-checked
    local xsetup=/usr/share/sddm/scripts/Xsetup

    [ -f "$lock" ] && return 0
    trap 'rm -f "$lock"' EXIT

    grep -qF "autorandr --change" "$xsetup" 2>/dev/null && return

    xsetup=/usr/share/sddm/scripts/Xsetup
    action=$(notify-send -u critical -A 'edit,编辑文件' "SDDM Xsetup" "请在 $xsetup 中添加：autorandr --change")
    [[ -n "$action" ]] && pkexec "/bin/sh" "-c" "echo \"autorandr --change\" >>$xsetup"
}

keyboard_setting
desktop_setting
application_launch
check_autorandr_xsetup &
