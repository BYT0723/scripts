#!/bin/bash

#
#  Handle the statusBar click event
#  see file config.h variable statuscmds
#
#
TOOLS_DIR="$(dirname $0)/tools"
ROFI_SCRIPT_DIR="$(dirname $0)/rofi/scripts"
terminal="kitty"
float_terminal="kitty --class float-term -o font_size=10 -o initial_window_width=120c -o initial_window_height=36c"

source "$(dirname "$0")/utils/notify.sh"

dateHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		[ -z "$(command -v cal)" ] && system-notify normal "Tool Not Found" "please install cal" && return
		notify-send \
			-t 60000 \
			-c status \
			-h string:x-dunst-stack-tag:calendar \
			-h string:body-markup:no \
			"Calendar" \
			"$(LANG=en_US.UTF-8 cal -s | sed -E "s|($(date +%e))|<b><u>\1</u></b>|")"
		;;
	2) ;;
	3)
		[ -z "$(command -v ccal)" ] && system-notify normal "Tool Not Found" "please install ccal" && return
		notify-send \
			-t 60000 \
			-c status \
			-h string:x-dunst-stack-tag:calendar-lunar \
			"Calendar (Lunar)" \
			"<span font_family='LXGW WenKai Mono'>$(LANG=en_US.UTF-8 ccal -u | sed 's/\x1b\[[1-9;]*m/<b><u>/g' | sed 's|\x1b\[[0;]*m|</u></b>|g')</span>"
		;;
	esac
}

batteryHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		notify-send -c status -i battery -h string:x-dunst-stack-tag:batteryInformation "Battery" "$(acpi -i)"
		;;
	2) ;;
	3)
		screen_saver_timeout=$(xset q | grep "timeout" | awk '{print $2}')
		dpms_state=$(xset q | grep "DPMS" | tail -n 1 | awk '{print $3}')
		# Display Power Management
		# `xset -dpms`      : Turn off DPMS
		# `xset s off -dpms`: Disable DPMS and prevent screen from blanking
		# https://wiki.archlinux.org/title/Display_Power_Management_Signaling#Runtime_settings
		notify-send -c status -i display "DPMS" -h string:x-dunst-stack-tag:dpms "\
ScreenSaver: $([ $screen_saver_timeout -gt 0 ] && echo "Enabled" || echo "Disabled")\n\
DPMS:        $dpms_state"
		;;
	4)
		"$TOOLS_DIR"/brightness.sh up
		;;
	5)
		"$TOOLS_DIR"/brightness.sh down
		;;
	esac
}

diskHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		notify-send \
			-c status \
			-h string:x-dunst-stack-tag:diskInformation \
			"💾 Storage" \
			"$(LANG=en_US.UTF-8 df -h -x tmpfs -x devtmpfs)"
		;;
	2) ;;
	3) ;;
	esac
}

memoryHandler() {
	buttonType=$1
	case "$buttonType" in
	1) ;;
	2) ;;
	3) ;;
	esac
}

cpuHandler() {
	buttonType=$1
	case "$buttonType" in
	1) ;;
	2) ;;
	3)
		[ ! -z "$(command -v htop)" ] && eval "$terminal -e htop" && return
		[ ! -z "$(command -v btop)" ] && eval "$terminal -e btop" && return
		[ ! -z "$(command -v top)" ] && eval "$terminal -e top" && return
		system-notify normal "Tool Not Found" "please install one of btop,htop,top"
		;;
	esac
}

netSpeedHandler() {
	buttonType=$1
	case "$buttonType" in
	1) ;;
	2) ;;
	3)
		[ ! -z "$(command -v speedtest)" ] && eval "$terminal -e speedtest" && return
		system-notify normal "Tool Not Found" "please install speedtest-cli"
		;;
	esac
}

mpdHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		"$ROFI_SCRIPT_DIR"/mpd.sh
		;;
	2)
		mpd --kill
		;;
	3)
		[ ! -z "$(command -v rmpc)" ] && eval "$float_terminal -e rmpc" && return
		system-notify normal "Tool Not Found" "please install rmpc"
		;;
	esac
}

weatherHandler() {
	buttonType=$1
	local language=$(echo $LANG | awk -F '_' '{print $1}')
	case "$buttonType" in
	1)
		notify-send \
			-c status \
			-h string:x-dunst-stack-tag:currentWeather \
			"Weather" \
			"$(curl -H 'Accept-Language:'$language 'wttr.in/?T0' | sed 's|\\|\\\\|g')"
		;;
	2)
		xdg-open https://wttr.in/?T
		;;
	3) ;;
	esac
}

volumeHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		"$TOOLS_DIR"/volume.sh toggle
		;;
	2) ;;
	3)
		[ ! -z "$(command -v ncpamixer)" ] && eval "$float_terminal -e ncpamixer" && return
		system-notify normal "Tool Not Found" "please install ncpamixer"
		;;
	4)
		"$TOOLS_DIR"/volume.sh up
		;;
	5)
		"$TOOLS_DIR"/volume.sh down
		;;
	esac
}

mailHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		notify-send -i mail-unread-symbolic "New Mail" "$(notmuch search --output=files tag:unread | cut -d/ -f5 | sort | uniq -c | awk '{print "[" $2 "] \t" $1 " Unread"}')"
		;;
	2) ;;
	3)
		if [ ! -z "$(command -v aerc)" ]; then
			eval "$terminal -e aerc"
			[ -z "$(pgrep -f "bash $TOOLS_DIR/mail.sh")" ] && bash $TOOLS_DIR/mail.sh &
			return
		fi
		system-notify normal "Tool Not Found" "please install aerc"
		;;
	esac
}

rssHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		[ ! -z "$(command -v newsboat)" ] && notify-send -i rss "$(newsboat -x print-unread)" && return
		system-notify normal "Tool Not Found" "please install newsboat"
		;;
	2) ;;
	3)
		[ ! -z "$(command -v newsboat)" ] && eval "$terminal -e newsboat" && return
		system-notify normal "Tool Not Found" "please install newsboat"
		;;
	esac
}

cmdIndex=$1
shift

# next param: button type
# 1 left button
# 2 middle button
# 3 right button

case "$cmdIndex" in
1)
	dateHandler $@
	;;
2)
	batteryHandler $@
	;;
3)
	volumeHandler $@
	;;
6)
	diskHandler $@
	;;
7)
	memoryHandler $@
	;;
8)
	cpuHandler $@
	;;
11)
	netSpeedHandler $@
	;;
10)
	mpdHandler $@
	;;
9)
	weatherHandler $@
	;;
12)
	mailHandler $@
	;;
13)
	rssHandler $@
	;;
esac
