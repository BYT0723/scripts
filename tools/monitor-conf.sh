#!/bin/sh

# Setting
# Lightdm: session-setup-script=/home/<username>/.dwm/tools/monitor-conf.sh

# 屏幕布局
cmd="xrandr --output eDP --primary --mode 3200x2000 --rate 120.00 --rotate normal"

if xrandr | grep -q "HDMI-A-0 connected"; then
	cmd="xrandr --output eDP --primary --mode 1920x1200 --rate 144.00 --rotate normal --scale 1.2x1.2"
	cmd+=" --output HDMI-A-0 --mode 2560x1440 --rate 144.00 --rotate normal --left-of eDP"
fi

eval "$cmd"
