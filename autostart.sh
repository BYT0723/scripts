#!/bin/bash

WORK_DIR=$(dirname $(realpath "$0"))
TOOLS_DIR="$WORK_DIR/tools"

# conky 是否自启动
CONKY_AUTOSTART=0

# 显示器布局初始化
bash $TOOLS_DIR/monitor-conf.sh

# 启动应用
# $1 application name
# $2 command
launch() {
	local name=$1
	shift
	local cmd=$@
	local pf="/tmp/dwm-status/autostart-launch-$name.pid"

	[ -f "$pf" ] && pid=$(cat "$pf")
	if [ ! -z "$pid" ]; then
		kill $pid
		sleep 0.1
	fi
	$cmd &
	echo $! >"$pf"
}

desktop_setting() {
	# 状态栏信息
	/bin/bash $WORK_DIR/dwm-status.sh reboot &
	# conky (system monitor) (conky must be before wallpaper)
	# 如果壁纸在conky之前就会导致壁纸沉入xwinwrap之下，导致无法看到conky窗口(针对video/page壁纸)
	((CONKY_AUTOSTART > 0)) && conky -U -d &
	# 壁纸(不使用launch_monitor是因为wallpaper每次启动都要使用新的instance, 移除旧的实例)
	# wallpaper.sh内部实现了
	/bin/bash "$TOOLS_DIR"/wallpaper.sh -r &
	# 屏保
	/bin/bash $TOOLS_DIR/screen.sh &
}

application_launch() {
	# 窗口合成器 picom (window composer)
	launch picom "picom --config ${XDG_CONFIG_HOME:-$HOME/.config}/dwm/picom.conf"
	# 启动通知
	launch dunst "dunst"
	# network manager 网络管理bar icon
	launch nm-applet "nm-applet"
	# input method
	launch fcitx5 "fcitx5"
	# auto mount
	launch udiskie "udiskie -sn"
	# polkit (require lxsession or lxsession-gtk3) 鉴权
	launch lxpolkit "lxpolkit"
	# 音频控制
	launch easyeffects "easyeffects --service-mode --hide-window"
}

keyboard_setting() {
	bash $TOOLS_DIR/keyboard.sh set option-add "caps:escape"
	bash $TOOLS_DIR/keyboard.sh set option-add "altwin:swap_lalt_lwin"
	bash $TOOLS_DIR/keyboard.sh set delay 250
	bash $TOOLS_DIR/keyboard.sh set rate 35
}

keyboard_setting
desktop_setting
application_launch
