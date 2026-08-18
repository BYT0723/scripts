#!/bin/bash

msgTag="touchpad"

status() { synclient -l | grep -c 'TouchpadOff.*=.*0'; }
toggle() {
	local s=$(status)
	# Toggle TouchPad
	synclient TouchpadOff=$s

	if [ $s -eq 1 ]; then
		msg="Locked"
		icon='touchpad-disabled-symbolic'
	else
		msg="Unlocked"
		icon='input-touchpad-symbolic'
	fi

	# notify
	notify-send -c tools -i $icon -h string:x-dunst-stack-tag:$msgTag "$msg"
}

case "$1" in
"status") status ;;
"toggle") toggle ;;
*) ;;
esac
