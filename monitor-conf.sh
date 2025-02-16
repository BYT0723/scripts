#!/bin/sh

# Setting
# Lightdm: session-setup-script=/home/walter/.dwm/monitor-conf.sh

# 屏幕布局
cmd="xrandr --output eDP --primary --mode 3200x2000 --rate 120 --rotate normal --scale 0.8x0.8"

if xrandr | grep -q "HDMI-A-0 connected"; then
	cmd+=" --output HDMI-A-0 --mode 2560x1440 --rate 120 --rotate normal --left-of eDP"
fi

eval "$cmd"
