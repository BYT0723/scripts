#!/bin/bash

msgTag="volume"

case "$1" in
'toggle')
    icon="audio-volume-high-symbolic"
    amixer sset Master toggle
    ;;
'up')
    icon="audio-volume-high-symbolic"
    amixer -qM set Master 2%+ umute
    ;;
'down')
    icon="audio-volume-low-symbolic"
    amixer -qM set Master 2%- umute
    ;;
esac

volume=$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)%\].*/\1/')
status=$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)\].*/\1/')

if [ "$status" == "off" ]; then
    icon="audio-volume-muted-symbolic"
fi

notify-send -c tools -i $icon -h string:x-dunst-stack-tag:$msgTag "${volume}"
