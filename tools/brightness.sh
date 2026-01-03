#!/bin/bash
#
# Required
# brightnessctl
#
msgTag="brightness"

source "$(dirname $0)/../utils/notify.sh"

[ -z "$(command -v brightnessctl)" ] && system-notify critical "Tool Not Found" "please install brightnessctl" && exit

case "$1" in
'up')
	brightnessctl s +2%
	;;
'down')
	brightnessctl s 2%-
	;;
esac

curr=$(printf "%.0f" $(echo "$(brightnessctl g)*100/$(brightnessctl m)" | bc))

notify-send -c tools -i display-brightness-symbolic -h string:x-dunst-stack-tag:$msgTag -h int:value:"$curr" "$curr"
