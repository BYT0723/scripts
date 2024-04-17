#!/bin/bash

dir=$(dirname $0)

# Set Xorg Keymap
if [ ! -z "$(pgrep Xorg)" ] && [ ! -z "$(command -v setxkbmap)" ]; then
	setxkbmap -option "caps:swapescape,altwin:swap_lalt_lwin" # setxkbmap need `xorg-xkb-utils` package
	# For other keymaps, see: `/usr/share/X11/xkb/rules/base.lst`
fi

# statusBar
if [ -z "$(pgrep -f dwm-status.sh)" ]; then
	/bin/bash $dir/dwm-status.sh &
fi

# wallpaper
/bin/bash $dir/wallpaper.sh -r &

# picom (window composer)
if [ -z "$(pgrep picom)" ]; then
	picom --config $dir/configs/picom.conf -b
	# picom --config $dir/configs/picom.conf -b --experimental-backends
fi

# polkit (require lxsession or lxsession-gtk3)
if [ -z "$(pgrep lxpolkit)" ]; then
	lxpolkit &
fi

# autolock (screen locker)
if [ -z "$(pgrep xautolock)" ]; then
	xautolock -time 30 -locker slock -detectsleep &
fi

# if [ -z "$(pgrep mate-power-manager)" ]; then
# 	mate-power-manager &
# fi
#
# if [ -z "$(pgrep volumeicon)" ]; then
# 	volumeicon &
# fi

if [ -z "$(pgrep nm-applet)" ]; then
	nm-applet &
fi

if [ -z "$(pgrep udiskie)" ]; then
	udiskie -sn &
fi

if [ -z "$(pgrep fcitx5)" ]; then
	fcitx5 -d
fi

# personal note
if [ -z "$(pgrep -f note.sh)" ]; then
	/bin/bash $dir/note.sh &
fi

# Set Xorg Keyboard Configuration
if [ ! -z "$(pgrep Xorg)" ] && [ ! -z "$(command -v xset)" ]; then
	expected_delay=200
	expected_rate=30
	msg=$(xset q | grep 'auto repeat delay') # xset need `xorg-xset` package
	cur_delay=$(echo $msg | awk '{print $4}')
	cur_rate=$(echo $msg | awk '{print $NF}')

	if [ "$cur_delay" -ne "$expected_delay" ] || [ "$cur_rate" -ne "$expected_rate" ]; then
		xset r rate $expected_delay $expected_rate
	fi
fi
