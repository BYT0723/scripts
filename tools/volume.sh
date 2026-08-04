#!/bin/bash

source "$(dirname "$0")/../utils/notify.sh"

[ -z "$(command -v amixer)" ] && system-notify critical "Tool Not Found" "please install amixer" && exit

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

read -r volume status < <(amixer get Master | awk 'END{split($0,a,"[][]"); gsub(/%/,"",a[2]); print a[2], a[4]}')

[ "$status" == "off" ] && icon="audio-volume-muted-symbolic" || true

notify-send -c tools -i $icon -h string:x-dunst-stack-tag:volume -h int:value:"${volume}" "${volume}"
