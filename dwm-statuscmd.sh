#!/bin/bash
#
TOOLS_DIR="$(dirname $0)/tools"
ROFI_SCRIPT_DIR="$(dirname $0)/rofi/scripts"
terminal="WINIT_X11_SCALE_FACTOR=1 alacritty"
float_terminal="WINIT_X11_SCALE_FACTOR=1 alacritty --config-file $HOME/.config/alacritty/alacritty-float.toml -o 'font.size=12'"

#  Handle the statusBar click event
#  see file config.h variable statuscmds

cmdType=$1
# 1 left button
# 2 middle button
# 3 right button
buttonType=$2

dateHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
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
		eval "$terminal -e htop"
		;;
	esac
}

netSpeedHandler() {
	buttonType=$1
	case "$buttonType" in
	1) ;;
	2) ;;
	3)
		eval "$terminal -e speedtest"
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
		killall mpd
		;;
	3)
		eval "$float_terminal -e rmpc"
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
		eval "$terminal -e ncpamixer"
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
		notify-send -i mail-unread-symbolic "新邮件" "$(notmuch search --output=files tag:unread | cut -d/ -f5 | sort | uniq -c | awk '{print "[" $2 "] \t" $1 "封新邮件"}')"
		;;
	2) ;;
	3)
		eval "$terminal -e aerc"
		if [ $(ps ax | grep mail.sh | wc -l) -le 1 ]; then
			bash $TOOLS_DIR/mail.sh &
		fi
		;;
	esac
}

rssHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		notify-send -i rss "$(newsboat -x print-unread)"
		;;
	2) ;;
	3)
		eval "$terminal -e newsboat"
		;;
	esac
}

# route by $cmdType
case "$cmdType" in
date)
	dateHandler $2
	;;
battery)
	batteryHandler $2
	;;
volume)
	volumeHandler $2
	;;
disk-root)
	diskHandler $2
	;;
memory)
	memoryHandler $2
	;;
cpu)
	cpuHandler $2
	;;
netSpeed)
	netSpeedHandler $2
	;;
mpd)
	mpdHandler $2
	;;
weather)
	weatherHandler $2
	;;
mail)
	mailHandler $2
	;;
rss)
	rssHandler $2
	;;
esac
