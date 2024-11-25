#!/bin/bash
#
dir=$(dirname $0)

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
		# bash $dir/notify.sh cal -s -y
		notify-send -c status -h string:x-dunst-stack-tag:datetime "$(cal -s)"
		;;
	2) ;;
	3)
		# bash $dir/notify.sh ccal -u
		notify-send -c status -h string:x-dunst-stack-tag:datetime "$(ccal -u)"
		;;
	esac
}

batteryHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		# bash $dir/notify.sh acpi -i
		notify-send -c status -h string:x-dunst-stack-tag:batteryInformation "$(acpi -i)"
		;;
	2)
		echo 2 or 3
		;;
	3)
		echo default
		;;
	4)
		$(dirname $0)/brightness.sh up
		;;
	5)
		$(dirname $0)/brightness.sh down
		;;
	esac
}

diskHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		# bash $dir/notify.sh df -h
		notify-send -c status -h string:x-dunst-stack-tag:diskInformation "$(df -h)"
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
		alacritty -e htop
		;;
	esac
}

netSpeedHandler() {
	buttonType=$1
	case "$buttonType" in
	1) ;;
	2) ;;
	3)
		alacritty -e speedtest
		;;
	esac
}

mpdHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		mpc toggle
		;;
	2)
		killall mpd
		;;
	3)
		$(dirname $0)/mpd.sh
		;;
	esac
}

weatherHandler() {
	buttonType=$1
	local language=$(echo $LANG | awk -F '_' '{print $1}')
	case "$buttonType" in
	1)
		notify-send -c status -h string:x-dunst-stack-tag:currentWeather "$(curl -H 'Accept-Language:'$language 'wttr.in/?T0')"
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
		$(dirname $0)/volume.sh toggle
		;;
	2) ;;
	3)
		alacritty -e ncpamixer
		;;
	4)
		$(dirname $0)/volume.sh up
		;;
	5)
		$(dirname $0)/volume.sh down
		;;
	esac
}

mailHandler() {
	buttonType=$1
	case "$buttonType" in
	1)
		notify-send -i mail-unread-symbolic "$(notmuch search --output=files tag:unread | cut -d/ -f5 | sort | uniq -c | awk '{print "[" $2 "] \t" $1 "封新邮件"}')"
		;;
	2) ;;
	3)
		aerc
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
esac
