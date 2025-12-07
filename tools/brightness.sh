#!/bin/bash
#
# Required
# light
#
# Remember to add yourself to the video user group
# https://wiki.archlinux.org/title/Backlight#light
#
msgTag="brightness"

source "$(dirname $0)/../utils/notify.sh"

[ -z "$(command -v light)" ] && system-notify critical "Tool Not Found" "please install light-git from archlinuxcn" && exit

curr=$(printf '%.0f' $(light -G))

case "$1" in
'up')
	light -S $(echo "$curr+2" | bc)
	;;
'down')
	light -S $(echo "$curr-2" | bc)
	;;
esac

# notify-send -c tools -i display-brightness-symbolic -h string:x-dunst-stack-tag:$msgTag "$(printf "%.0f" $(light -G))"
# # support progress bar
notify-send -c tools -i display-brightness-symbolic -h string:x-dunst-stack-tag:$msgTag -h int:value:"$(printf "%.0f" $(light -G))" "$(printf "%.0f" $(light -G))"
