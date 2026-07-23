#!/bin/bash

#
# Clock.sh
#
# format: <minute> <hour> <day> <month> <week> /home/<name>/clock.sh -l <level> -c [WORK|HOME|DIET|STUDY] <Message>
# Use `crontab -e` to add alarm clock items

LEVEL="critical"
CATEGORY=""
TAG=""

while getopts "l:c:" opt; do
	case $opt in
	l) LEVEL=$OPTARG ;;
	c) CATEGORY=$OPTARG ;;
	?) exit 1 ;;
	esac
done

shift $((OPTIND - 1))

MESG=${1:-""}
TAG="x-custom-clock-$(echo "$CATEGORY|$MESG" | md5sum | cut -d' ' -f1)"

declare -A icons

icons["WORK"]="  "
icons["HOME"]="  "
icons["STUDY"]="  "
icons["DIET"]="󰩰  "
icons["PLAN"]="  "

[ -n "${icons["$CATEGORY"]}" ] && ICON="${icons["$CATEGORY"]}"

(canberra-gtk-play -i audio-volume-change >/dev/null 2>&1 &)

### Send Notification
# Because this script is called by the cronie service, it needs to export DBUS_SESSION_BUS_ADDRESS
# If DBUS_SESSION_BUS_ADDRESS is invalid, use `echo $DBUS_SESSION_BUS_ADDRESS` to get new DBUS_SESSION_BUS_ADDRESS
DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-"unix:path=/run/user/1000/bus"} \
	DISPLAY=${DISPLAY:-:0} \
	timeout 1 notify-send -i preferences-system-time-symbolic -h string:x-dunst-stack-tag:$TAG -u "$LEVEL" "$ICON$(date +"%H:%M")" "$MESG"
