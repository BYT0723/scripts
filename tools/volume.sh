#!/bin/bash

source "$(dirname "$0")/../utils/notify.sh"

[ -z "$(command -v amixer)" ] && system-notify critical "Tool Not Found" "please install amixer" && exit

exec 9>"/run/user/$UID/volume-control.lock"
flock -x 9

case "$1" in
'toggle') amixer sset Master toggle ;;
'up') amixer -qM set Master 2%+ ;;
'down') amixer -qM set Master 2%- ;;
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
