#!/bin/bash

WORK_DIR=$(dirname "$0")
TOOLS_DIR="$WORK_DIR/tools"

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
	while true; do
		[ "$(pgrep -f "$1")" = "" ] && eval "$2" || true
		# 每分钟
		sleep 60
	done
}

xorg_setting() {
	# Set Xorg
	if [ ! -z "$(pgrep Xorg)" ]; then
		# Set Xorg Keyboard Configuration
		if [ ! -z "$(command -v setxkbmap)" ]; then
			# For other keymaps, see: `/usr/share/X11/xkb/rules/base.lst`
			setxkbmap -option "caps:swapescape,altwin:swap_lalt_lwin" # setxkbmap need `xorg-xkb-utils` package
		fi
		if [ ! -z "$(command -v xset)" ]; then
			xset r rate 250 35
		fi
	fi
	# 壁纸(不使用launch_monitor是因为wallpaper每次启动都要使用新的instance, 移除旧的实例)
	# wallpaper.sh内部实现了
	/bin/bash "$TOOLS_DIR"/wallpaper.sh -r &
	# 屏保
	launch_monitor "[sc]reen.sh" "/bin/bash $TOOLS_DIR/screen.sh &" &
	# 状态栏信息
	launch_monitor "[d]wm-status.sh" "/bin/bash $WORK_DIR/dwm-status.sh &" &
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
	# 音频控制
	launch easyeffects "easyeffects --gapplication-service &"
	# auto mount
	launch udiskie "udiskie -sn &"
	# polkit (require lxsession or lxsession-gtk3) 鉴权
	launch lxpolkit "lxpolkit &"
	# conky (system monitor)
	launch conky "conky -U -d"
}

xorg_setting
application_launch
