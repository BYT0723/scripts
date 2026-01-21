#!/bin/bash

WORK_DIR=$(dirname "$0")
TOOLS_DIR="$WORK_DIR/tools"

bash $TOOLS_DIR/monitor-conf.sh

# 启动应用
# $1 application name
# $2 command
launch() {
	[ "$(pgrep "$1")" = "" ] && eval "$2" || true
}

# 启动并监控脚本
# 防止在修改脚本时出错导致进程退出
# $1 script name
# $2 command
launch_monitor() {
	[ ! -z "$(pgrep -f "$1")" ] && kill $(pgrep -f "$1")
	while true; do
		[ "$(pgrep -f "$1")" = "" ] && eval "$2" || true
		# 每分钟
		sleep 60
	done
}

desktop_setting() {
	# 状态栏信息
	launch_monitor "[d]wm-status.sh" "/bin/bash $WORK_DIR/dwm-status.sh &" &
	# conky (system monitor) (conky must be before wallpaper)
	# 如果壁纸在conky之前就会导致壁纸沉入xwinwrap之下，导致无法看到conky窗口(针对video/page壁纸)
	launch conky "conky -U -d"
	# 壁纸(不使用launch_monitor是因为wallpaper每次启动都要使用新的instance, 移除旧的实例)
	# wallpaper.sh内部实现了
	/bin/bash "$TOOLS_DIR"/wallpaper.sh -r &
	# 屏保
	launch_monitor "[sc]reen.sh" "/bin/bash $TOOLS_DIR/screen.sh &" &
}

application_launch() {
	# 窗口合成器 picom (window composer)
	# picom --config $dir/configs/picom.conf -b --experimental-backends (开启试验功能)
	launch picom "picom --config $WORK_DIR/configs/picom.conf -b"
	# 启动通知
	launch dunst "dunst &"
	# network manager 网络管理bar icon
	launch nm-applet "nm-applet &"
	# input method
	launch fcitx5 "fcitx5 -d"
	# auto mount
	launch udiskie "udiskie -sn &"
	# polkit (require lxsession or lxsession-gtk3) 鉴权
	launch lxpolkit "lxpolkit &"
	# 音频控制
	launch easyeffects "easyeffects --service-mode --hide-window &"
}

keyboard_setting() {
	bash $TOOLS_DIR/keyboard.sh set delay 250
	bash $TOOLS_DIR/keyboard.sh set rate 35
}

desktop_setting
application_launch
keyboard_setting
