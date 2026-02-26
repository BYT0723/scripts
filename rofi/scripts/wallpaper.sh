#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

# Import Current Theme
type="$ROFI_DIR/applets/type-1"
style='style-3.rasi'
theme="$type/$style"

source "$(dirname "$0")"/util.sh

if [[ ("$theme" == *'type-1'*) || ("$theme" == *'type-3'*) || ("$theme" == *'type-5'*) ]]; then
	list_col='1'
	list_row='6'
elif [[ ("$theme" == *'type-2'*) || ("$theme" == *'type-4'*) ]]; then
	list_col='6'
	list_row='1'
fi

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/dwm"

# 配置文件路径
declare -A confPath
confPath["wallpaper"]="$CONFIG_HOME/wallpaper.conf"

# Options
layout=$(cat ${theme} | grep 'USE_ICON' | cut -d'=' -f2)

if [[ "$layout" == 'NO' ]]; then
	firstOpt=(
		"Next"
		"Select"
		"Random                          $(icon toggle conf wallpaper random number)"
		"Random Type                  $(getConfig wallpaper random_type)"
	)
else
	firstOpt=(
		"Next"
		"Select"
		"$(icon toggle conf wallpaper random number)"
		"$(getConfig wallpaper random_type)"
	)
fi

declare -A optId
optId[${firstOpt[0]}]="--opt1"
optId[${firstOpt[1]}]="--opt2"
optId[${firstOpt[2]}]="--opt3"
optId[${firstOpt[3]}]="--opt4"

# Rofi CMD
rofi_cmd() {
	rofi -theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-monitor -4 \
		-theme ${theme} \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

# Pass variables to rofi dmenu
run_rofi() {
	prompt='Wallpaper'
	mesg="Setting Wallpaper"
	opts=("${firstOpt[@]}")

	for ((i = 0; i < ${#opts[@]}; i++)); do
		if [[ $i > 0 ]]; then
			msg=$msg"\n"
		fi
		msg=$msg${opts[$i]}
	done
	echo -e "$msg" | rofi_cmd
}

# Execute Command
run_cmd() {
	case "$1" in
	${optId[${firstOpt[0]}]})
		$WORK_DIR/tools/wallpaper.sh -n
		;;
	${optId[${firstOpt[1]}]})
		$WORK_DIR/tools/wallpaper.sh -S
		;;
	${optId[${firstOpt[2]}]})
		toggleConf wallpaper random number
		;;
	${optId[${firstOpt[3]}]})
		toggleConf wallpaper random_type wallpaper_type
		;;
	*)
		chosen="$(run_rofi $1)"
		if [[ "$chosen" == "" ]]; then
			exit
		fi
		run_cmd ${optId[$chosen]}
		;;
	esac
}

# Actions
chosen="$(run_rofi)"
if [[ "$chosen" == "" ]]; then
	exit
fi
run_cmd ${optId[$chosen]}

exit
