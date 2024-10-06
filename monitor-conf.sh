#!/bin/sh

# Setting
# Lightdm: session-setup-script=/home/walter/.dwm/monitor-conf.sh

xrandr \
	--output eDP --primary --mode 3200x2000 --rate 120 --rotate normal --scale 0.8x0.8 \
	--output HDMI-A-0 --mode 2560x1440 --rate 144 --left-of eDP
