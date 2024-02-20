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

printTitle() {
	case "$1" in
	"WORK")
		echo " "
		;;
	"HOME")
		echo " "
		;;
	"STUDY")
		echo " "
		;;
	"DIET")
		echo "󰩰 "
		;;
	"PLAN")
		echo " "
		;;
	*)
		echo "$1"
		;;
	esac
}

canberra-gtk-play -i audio-volume-change

# send notification
notify-send -i preferences-system-time-symbolic -u critical "$(printTitle $1)  $(date +"%H:%M")" "$2"
