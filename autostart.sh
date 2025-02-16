#!/bin/bash

dir=$(dirname $0)

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

	# screen manager (屏保和DPMS)
	if [ -z "$(pgrep -f screen.sh)" ]; then
		/bin/bash $dir/screen.sh &
	fi
fi

# 启动通知
if [ -z "$(pgrep dunst)" ]; then
	dunst &
fi

# 音频控制
if [ -z "$(pgrep easyeffects)" ]; then
	easyeffects --gapplication-service &
fi

# 状态栏
if [ -z "$(pgrep -f dwm-status.sh)" ]; then
	/bin/bash $dir/dwm-status.sh &
fi

# 壁纸
/bin/bash $dir/wallpaper.sh -r &

# picom (window composer) 窗口合成
if [ -z "$(pgrep picom)" ]; then
	picom --config $dir/configs/picom.conf -b
	# picom --config $dir/configs/picom.conf -b --experimental-backends
fi

# polkit (require lxsession or lxsession-gtk3) 鉴权
if [ -z "$(pgrep lxpolkit)" ]; then
	lxpolkit &
fi

# network manager 网络管理bar icon
if [ -z "$(pgrep nm-applet)" ]; then
	nm-applet &
fi

# auto mount
if [ -z "$(pgrep udiskie)" ]; then
	udiskie -sn &
fi

# input method
if [ -z "$(pgrep fcitx5)" ]; then
	fcitx5 -d
fi
