#!/bin/bash

dir=$(dirname $0)

# statusBar
/bin/bash $dir/dwm-status.sh &

# wallpaper
/bin/bash $dir/wallpaper.sh -r &

# picom (window composer)
if [ -z "$(pgrep picom)" ]; then
	# picom --config $dir/configs/picom.conf -b
	picom --config $dir/configs/picom.conf -b --experimental-backends
fi

# polkit (require lxsession or lxsession-gtk3)
if [ -z "$(pgrep lxpolkit)" ]; then
	lxpolkit &
fi

# autolock (screen locker)
if [ -z "$(pgrep xautolock)" ]; then
	xautolock -time 30 -locker slock -detectsleep &
fi

if [ -z "$(pgrep mate-power-manager)" ]; then
	mate-power-manager &
fi

if [ -z "$(pgrep nm-applet)" ]; then
	nm-applet &
fi

if [ -z "$(pgrep volumeicon)" ]; then
	volumeicon &
fi

if [ -z "$(pgrep udiskie)" ]; then
	udiskie -sn &
fi

if [ -z "$(pgrep fcitx5)" ]; then
	fcitx5 -d
fi
