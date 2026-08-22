#!/bin/bash
#
# Required
# brightnessctl
#
source "$(dirname "$0")/../utils/notify.sh"

[ -z "$(command -v brightnessctl)" ] && system-notify critical "Tool Not Found" "please install brightnessctl" && exit

case "$1" in
'up') brightnessctl s +2% ;;
'down') brightnessctl s 2%- ;;
esac

curr=$(printf "%.0f" $(echo "$(brightnessctl g)*100/$(brightnessctl m)" | bc))

if [[ $curr -gt 66 ]]; then
    icon="display-brightness-high-symbolic"
elif [[ $curr -gt 33 ]]; then
    icon="display-brightness-medium-symbolic"
else
    icon="display-brightness-low-symbolic"
fi

notify-send -c tools -i $icon -h string:x-dunst-stack-tag:brightness -h int:value:"$curr" "$curr"
