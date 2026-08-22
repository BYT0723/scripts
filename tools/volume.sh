#!/bin/bash

source "$(dirname "$0")/../utils/notify.sh"

[ -z "$(command -v amixer)" ] && system-notify critical "Tool Not Found" "please install amixer" && exit

case "$1" in
'toggle') amixer sset Master toggle ;;
'up') amixer -qM set Master 2%+ umute ;;
'down') amixer -qM set Master 2%- umute ;;
esac

read -r volume status < <(amixer get Master | awk 'END{split($0,a,"[][]"); gsub(/%/,"",a[2]); print a[2], a[4]}')

if [[ "$status" == "off" ]]; then
    icon="audio-volume-muted-symbolic"
elif [[ $volume -gt 66 ]]; then
    icon="audio-volume-high-symbolic"
elif [[ $volume -gt 33 ]]; then
    icon="audio-volume-medium-symbolic"
else
    icon="audio-volume-low-symbolic"
fi

notify-send -c tools -i $icon -h string:x-dunst-stack-tag:volume -h int:value:"${volume}" "${volume}"
