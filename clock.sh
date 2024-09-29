#!/bin/bash

#
# Clock.sh
#
# format: <minute> <hour> <day> <month> <week> /home/<name>/clock.sh [WORK|HOME|DIET|STUDY] <Message>
# Use `crontab -e` to add alarm clock items

# Because this script is called by the cronie service, it needs to export DBUS_SESSION_BUS_ADDRESS
# If DBUS_SESSION_BUS_ADDRESS is invalid, use `echo $DBUS_SESSION_BUS_ADDRESS` to get new DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
# Displayed screen
export DISPLAY=:0

LEVEL="normal"
ICON=""
TAG="clock"

case "$1" in
"WORK")
	ICON=" "
	;;
"HOME")
	ICON=" "
	;;
"STUDY")
	ICON=" "
	;;
"DIET")
	ICON="󰩰 "
	;;
"PLAN")
	LEVEL="low"
	ICON=" "
	TAG="note"
	;;
*)
	echo "$1"
	;;
esac

canberra-gtk-play -i audio-volume-change

# send notification
notify-send -i preferences-system-time-symbolic -h string:x-dunst-stack-tag:$msgTag -u "$LEVEL" "$ICON  $(date +"%H:%M")" "$2"
