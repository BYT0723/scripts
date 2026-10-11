#!/usr/bin/env bash

SINGLE_MONITOR_ENABLE=0
SINGLE_MONITOR_NAME=eDP-1

declare -A SINGLE_MONITOR_MAP

SINGLE_MONITOR_MAP["eDP-1"]="--primary --mode 3200x2000 --rate 120.00 --rotate normal --scale 0.8x0.8"
SINGLE_MONITOR_MAP["DP-1"]="--primary --mode 2560x1440 --rate 144.00 --rotate normal"
SINGLE_MONITOR_MAP["HDMI-1"]="--primary --mode 2560x1440 --rate 144.00 --rotate normal"

# monitor map
declare -A MONITOR_MAP

MONITOR_MAP["eDP-1"]="--primary --mode 1920x1200 --rate 120.00 --rotate normal --scale 1.2x1.2"
MONITOR_MAP["DP-1"]="--mode 2560x1440 --rate 144.00 --rotate normal --left-of eDP-1"
MONITOR_MAP["HDMI-1"]="--mode 1920x1080 --rate 144.00 --rotate left --left-of DP-1"

current=$(xrandr | grep " connected " | wc -l)

if [[ $current == 1 ]]; then
    name="$(xrandr | grep " connected " | awk '{print $1}')"
    xrandr --output $name ${SINGLE_MONITOR_MAP[$name]}
    exit
fi

cmd=(xrandr)

while read -r monitor; do
    cmd+=(--output "$monitor")

    if ((SINGLE_MONITOR_ENABLE > 0)) && [[ -n $SINGLE_MONITOR_NAME ]] && [[ "$name" != "$SINGLE_MONITOR_NAME" ]]; then
        cmd+=(--off)
    else
        cmd+=(${MONITOR_MAP[$monitor]})
    fi
done < <(xrandr | grep " connected " | awk '{print $1}')

"${cmd[@]}"
