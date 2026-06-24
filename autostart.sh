#!/bin/bash

WORK_DIR=$(dirname $(realpath "$0"))
TOOLS_DIR="$WORK_DIR/tools"

# conky 是否自启动
CONKY_AUTOSTART=0

# 显示器布局初始化
[ -n "$(command -v autorandr)" ] && autorandr --change

# 启动应用
# $1 policy           string [check/restart]
# $2 application_name string
# $3 command          string
launch() {
	local policy=${1:-"check"} name=$2
	shift 2
	local cmd=$@
	local pf="/tmp/dwm-status/autostart-launch-$name.pid"
	local pid

	# read pid + verify alive
	[ -f "$pf" ] && pid=$(cat "$pf")
	[ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null || pid=""

	case "$policy" in
	check)
		[ -z "$pid" ] || return 0
		;;
	restart)
		[ -n "$pid" ] && kill "$pid" 2>/dev/null
		;;
	esac

	$cmd &>/dev/null &
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
	launch check picom "picom --config ${XDG_CONFIG_HOME:-$HOME/.config}/dwm/picom.conf"
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
	# 音频控制
	launch check easyeffects "easyeffects --service-mode --hide-window"
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
