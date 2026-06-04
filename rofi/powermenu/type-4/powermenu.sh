#!/usr/bin/env bash

## Author : Aditya Shakya (adi1090x)
## Github : @adi1090x
#
## Rofi   : Power Menu
#
## Available Styles
#
## style-1   style-2   style-3   style-4   style-5

# Current Theme
dir="$HOME/.dwm/rofi/powermenu/type-4"
theme='style-1'

# CMDs
uptime="$(uptime -p | sed -e 's/up //g')"
host=$(hostnamectl hostname)

# Options
shutdown=''
reboot=''
lock=''
suspend=''
logout=''
yes=''
no=''

# Rofi CMD
rofi_cmd() {
	rofi -dmenu \
		-p "Goodbye ${USER}" \
		-mesg "Uptime: $uptime" \
		-theme ${dir}/${theme}.rasi \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

# Confirmation CMD
confirm_cmd() {
	rofi -dmenu \
		-p 'Confirmation' \
		-mesg 'Are you Sure?' \
		-theme ${dir}/shared/confirm.rasi \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

# Ask for confirmation
confirm_exit() {
	echo -e "$yes\n$no" | confirm_cmd
}

# Pass variables to rofi dmenu
run_rofi() {
	echo -e "$lock\n$suspend\n$logout\n$reboot\n$shutdown" | rofi_cmd
}

# Execute Command
run_cmd() {
	sleep 0.1
	selected="$(confirm_exit)"
	if [[ "$selected" == "$yes" ]]; then
		if [[ $1 == '--shutdown' ]]; then
			systemctl poweroff
		elif [[ $1 == '--reboot' ]]; then
			systemctl reboot
		elif [[ $1 == '--suspend' ]]; then
			mpd_status=$(mpc status | awk 'NR==2 {print $1}')
			volume_status=$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)\].*/\1/')
			[ "$mpd_status" == "[playing]" ] && mpc -q toggle
			[ "$volume_status" == "on" ] && amixer set Master off >>/dev/null
			$HOME/.dwm/tools/lock.sh -n &
			systemctl suspend
			while pgrep -x i3lock >/dev/null; do
				while pgrep -x i3lock >/dev/null && xset q 2>/dev/null | grep -qi "Monitor is.*Standby"; do sleep 1; done
				pgrep -x i3lock >/dev/null || break
				while pgrep -x i3lock >/dev/null && [ "$(xprintidle 2>/dev/null)" -lt 10000 ]; do sleep 1; done
				pgrep -x i3lock >/dev/null || break
				xdotool key Escape 2>/dev/null
				sleep 1
				xset dpms force standby
			done
			wait
			[ "$mpd_status" == "[playing]" ] && mpc -q toggle
			[ "$volume_status" == "on" ] && amixer set Master on >>/dev/null
		elif [[ $1 == '--logout' ]]; then
			if [[ "$DESKTOP_SESSION" == 'dwm' ]]; then
				kill $(pgrep dwm)
			elif [[ "$DESKTOP_SESSION" == 'openbox' ]]; then
				openbox --exit
			elif [[ "$DESKTOP_SESSION" == 'bspwm' ]]; then
				bspc quit
			elif [[ "$DESKTOP_SESSION" == 'i3' ]]; then
				i3-msg exit
			elif [[ "$DESKTOP_SESSION" == 'plasma' ]]; then
				qdbus org.kde.ksmserver /KSMServer logout 0 0 0
			fi
		fi
	else
		exit 0
	fi
}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
$shutdown)
	run_cmd --shutdown
	;;
$reboot)
	run_cmd --reboot
	;;
$lock)
	mpd_status=$(mpc status | awk 'NR==2 {print $1}')
	volume_status=$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)\].*/\1/')
	[ "$mpd_status" == "[playing]" ] && mpc -q toggle
	[ "$volume_status" == "on" ] && amixer set Master off >>/dev/null
	$HOME/.dwm/tools/lock.sh -n &
	sleep 0.5
	xset dpms force standby
	while pgrep -x i3lock >/dev/null; do
		while pgrep -x i3lock >/dev/null && xset q 2>/dev/null | grep -qi "Monitor is.*Standby"; do sleep 1; done
		pgrep -x i3lock >/dev/null || break
		while pgrep -x i3lock >/dev/null && [ "$(xprintidle 2>/dev/null)" -lt 10000 ]; do sleep 1; done
		pgrep -x i3lock >/dev/null || break
		xdotool key Escape 2>/dev/null
		sleep 1
		xset dpms force standby
	done
	wait
	[ "$mpd_status" == "[playing]" ] && mpc -q toggle
	[ "$volume_status" == "on" ] && amixer set Master on >>/dev/null
	;;
$suspend)
	run_cmd --suspend
	;;
$logout)
	run_cmd --logout
	;;
esac
