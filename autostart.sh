#!/bin/bash

WORK_DIR=$(dirname $(realpath "$0"))
TOOLS_DIR="$WORK_DIR/tools"

# conky 是否自启动
CONKY_AUTOSTART=1

# 显示器布局初始化
[ -n "$(command -v autorandr)" ] && autorandr --change

# 应用启动/重启助手 (与 tools/theme.sh 共用)
source "$WORK_DIR/utils/launch.sh"

desktop_setting() {
    # 状态栏信息
    /bin/bash $WORK_DIR/dwm-status.sh reboot
    # 窗口合成器 picom (window composer)
    launch check picom "picom --config $HOME/.config/dwm/picom.conf"
    # wallpaper management (xwallpaper daemon + bash random deamon)
    /bin/bash "$TOOLS_DIR"/wallpaper.sh -r &
    # systray sni
    launch check snixembed "snixembed"
    # 启动通知
    launch check dunst "dunst"
    # polkit (require lxsession or lxsession-gtk3) 鉴权
    launch check lxpolkit "lxpolkit"
    # batsignal
    launch check batsignal "batsignal -I battery"
    # XSETTINGS 守护 (GTK 主题/字体广播, Firefox 亮暗跟随依赖)
    launch check xsettingsd "xsettingsd"
}

application_launch() {
    # network manager 网络管理 systray icon
    launch restart nm-applet "nm-applet"
    # pluseaudio systray icon
    launch restart pasystray "pasystray"
    # input method
    fcitx5 -r &
    # launch restart fcitx5 "fcitx5"
    # auto mount
    launch restart udiskie "udiskie -sn"
    # 屏保
    launch restart screen "/bin/bash $TOOLS_DIR/screen.sh"
    # 自动主题切换 (auto=false 时立即退出)
    launch restart theme-auto "/bin/bash $TOOLS_DIR/theme.sh auto"
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
check_autorandr_xsetup
