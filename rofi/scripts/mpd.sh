#!/usr/bin/env bash

## Author  : Aditya Shakya (adi1090x)
## Github  : @adi1090x
#
## Applets : MPD (music)

ROFI_DIR="$(dirname "$(dirname "$0")")"

# Import Current Theme
type="$ROFI_DIR/applets/type-2"
style='style-3.rasi'
theme="$type/$style"

# Theme Elements
status=$(mpc status "%state%")
repeat_state=$(mpc status "%repeat%")
random_state=$(mpc status "%random%")
textboxPromptColon="  | "
if [[ -z "$status" ]]; then
	prompt='Offline'
	mesg="MPD is Offline"
else
	prompt="$(mpc -f "%title% - %artist%" current)"
	mesg="$(mpc status "%currenttime%/%totaltime%  墳 %volume%")"
fi

if [[ ("$theme" == *'type-1'*) || ("$theme" == *'type-3'*) || ("$theme" == *'type-5'*) ]]; then
	list_col='1'
	list_row='9'
elif [[ ("$theme" == *'type-2'*) || ("$theme" == *'type-4'*) ]]; then
	list_col='9'
	list_row='1'
fi

# Options
layout=$(cat ${theme} | grep 'USE_ICON' | cut -d'=' -f2)
if [[ "$layout" == 'NO' ]]; then
	option_power="⏻ Start Local MPD"
	if [[ ${status} == "playing" ]]; then
		option_1=" Pause"
	else
		option_1=" Play"
	fi
	option_2=" Stop"
	option_3=" Previous"
	option_4=" Next"
	option_5=" Down"
	option_6=" Up"
	option_7=" Repeat"
	option_8=" Random"
else
	option_power="⏻"
	if [[ ${status} == "playing" ]]; then
		option_1=""
	else
		option_1=""
	fi
	option_2=""
	option_3=""
	option_4=""
	option_5=" "
	option_6=" "
	option_7=""
	option_8=""
fi

# Toggle Actions
active=''
urgent=''
# Repeat
if [[ ${repeat_state} == "on" ]]; then
	active="-a 6"
elif [[ ${repeat_state} == "off" ]]; then
	urgent="-u 6"
else
	option_7=" Parsing Error"
fi
# Random
if [[ ${random_state} == "on" ]]; then
	[ -n "$active" ] && active+=",7" || active="-a 7"
elif [[ ${random_state} == "off" ]]; then
	[ -n "$urgent" ] && urgent+=",7" || urgent="-u 7"
else
	option_8=" Parsing Error"
fi

# Rofi CMD
rofi_cmd() {
	rofi -theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		${active} ${urgent} \
		-markup-rows \
		-monitor -4 \
		-theme ${theme} \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

# Pass variables to rofi dmenu
run_rofi() {
	if [[ -z "$status" ]]; then
		echo -e "$option_power" | rofi_cmd
	else
		echo -e "$option_1\n$option_2\n$option_3\n$option_4\n$option_5\n$option_6\n$option_7\n$option_8" | rofi_cmd
	fi
}

musicMsgTag="music_info"
musicVolumnMsgTag="music_volumn_info"

# Execute Command
run_cmd() {
	if [[ "$1" == '--on' ]]; then
		mpd
	elif [[ "$1" == '--opt1' ]]; then
		mpc -q toggle
		[[ $status == "playing" ]] && icon="media-playback-start-symbolic" || icon="media-playback-pause-symbolic"
		notify-send -c mpd -i $icon -h string:x-dunst-stack-tag:$musicMsgTag "$(mpc -f "%title% - %artist%" current)"
	elif [[ "$1" == '--opt2' ]]; then
		mpc -q stop
	elif [[ "$1" == '--opt3' ]]; then
		mpc -q prev
		[[ $status == "playing" ]] && icon="media-playback-start-symbolic" || icon="media-playback-pause-symbolic"
		notify-send -c mpd -i $icon -h string:x-dunst-stack-tag:$musicMsgTag "$(mpc -f "%title% - %artist%" current)"
	elif [[ "$1" == '--opt4' ]]; then
		mpc -q next
		[[ $status == "playing" ]] && icon="media-playback-start-symbolic" || icon="media-playback-pause-symbolic"
		notify-send -c mpd -i $icon -h string:x-dunst-stack-tag:$musicMsgTag "$(mpc -f "%title% - %artist%" current)"
	elif [[ "$1" == '--opt5' ]]; then
		mpc volume -20
		mpc status '%volume%'
		current=$(mpc volume | cut -d':' -f2 | cut -d' ' -f2 | cut -d'%' -f1)
		notify-send -c mpd -h string:x-dunst-stack-tag:$musicVolumnMsgTag -h int:value:"${current}" "MPD Volume: $current"
	elif [[ "$1" == '--opt6' ]]; then
		mpc volume +20
		current=$(mpc volume | cut -d':' -f2 | cut -d' ' -f2 | cut -d'%' -f1)
		notify-send -c mpd -h string:x-dunst-stack-tag:$musicVolumnMsgTag -h int:value:"${current}" "MPD Volume: $current"
	elif [[ "$1" == '--opt7' ]]; then
		mpc -q repeat
	elif [[ "$1" == '--opt8' ]]; then
		mpc -q random
	fi
}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
$option_power)
	run_cmd --on
	;;
$option_1)
	run_cmd --opt1
	;;
$option_2)
	run_cmd --opt2
	;;
$option_3)
	run_cmd --opt3
	;;
$option_4)
	run_cmd --opt4
	;;
$option_5)
	run_cmd --opt5
	;;
$option_6)
	run_cmd --opt6
	;;
$option_7)
	run_cmd --opt7
	;;
$option_8)
	run_cmd --opt8
	;;
esac
