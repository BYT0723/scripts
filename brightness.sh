#!/bin/bash
#
# Required
# light
#
# Remember to add yourself to the video user group
# https://wiki.archlinux.org/title/Backlight#light

msgTag="brightness"

case "$1" in
'up')
	light -A 1
	;;
'down')
	light -U 1
	;;
esac

notify-send -c tools -i display-brightness-symbolic -h string:x-dunst-stack-tag:$msgTag "$(printf "%.0f" $(light -G))"
# # support progress bar
# notify-send -c tools -i display-brightness-symbolic -h string:x-dunst-stack-tag:$msgTag -h int:value:"$(printf "%.0f" $(light -G))" "$(printf "%.0f" $(light -G))"
