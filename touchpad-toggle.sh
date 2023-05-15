#!/bin/bash

msgTag="touchpad"

status=$(synclient -l | grep -c 'TouchpadOff.*=.*0')

# Toggle TouchPad
synclient TouchpadOff=$status

if [ $status -eq 1 ]; then
    msg="Locked"
    icon='touchpad-disabled-symbolic'
else
    msg="Unlocked"
    icon='input-touchpad-symbolic'
fi

# notify
notify-send -c tools -i $icon -h string:x-dunst-stack-tag:$msgTag "$msg"
