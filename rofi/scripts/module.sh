#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

# Import Current Theme
type="$ROFI_DIR/applets/type-1"
style='style-3.rasi'
theme="$type/$style"

source "$(dirname "$0")"/util.sh

HistoryPopCount=10

if [[ ("$theme" == *'type-1'*) || ("$theme" == *'type-3'*) || ("$theme" == *'type-5'*) ]]; then
	list_col='1'
	list_row='6'
elif [[ ("$theme" == *'type-2'*) || ("$theme" == *'type-4'*) ]]; then
	list_col='6'
	list_row='1'
fi

# 配置文件路径
declare -A confPath
confPath["picom"]="$WORK_DIR/configs/picom.conf"
confPath["wallpaper"]="$WORK_DIR/configs/wallpaper.conf"

# 定义运行命令的Map
declare -A applicationCmd
applicationCmd["picom"]="picom --config $WORK_DIR/configs/picom.conf -b"
# applicationCmd["picom"]="picom --config $dir/configs/picom.conf -b --experimental-backends"

# Options
layout=$(cat ${theme} | grep 'USE_ICON' | cut -d'=' -f2)

if [[ "$layout" == 'NO' ]]; then
	firstOpt=(
		" Picom                         $(icon active app picom)"
		" Network                       $(icon active app NetworkManager)"
		" Bluetooth                     $(icon active service bluetooth)"
		" Notification                  $(icon active app dunst)"
		" Wallpaper                     $(icon active cmd 'wallpaper.sh -r')"
	)
	picomOpt=(
		"蘒 Toggle                       $(icon toggle app picom)"
		"󰗘 Animations                   $(icon toggle conf picom animations bool)"
	)
	notificationOpt=(
		"Pop                            $(dunstctl count history)"
		"CloseAll                       $(dunstctl count displayed)"
	)
	wallpaperOpt=(
		"next"
		"random                         $(icon toggle conf wallpaper random number)"
		"random_type                 $(getConfig wallpaper random_type)"
	)
else
	firstOpt=(
		" $(icon active app picom)"
		" $(icon active app NetworkManager)"
		" $(icon active service bluetooth)"
		" $(icon active app dunst)"
	)
	picomOpt=(
		"蘒$(icon toggle app picom)"
		"󰗘 $(icon conf confPath["picom"] animations bool)"
	)
	notificationOpt=(
		"Pop $(dunstctl count history)"
		"CA $(dunstctl count displayed)"
	)
fi

declare -A optId
optId[${firstOpt[0]}]="--opt1"
optId[${firstOpt[1]}]="--opt2"
optId[${firstOpt[2]}]="--opt3"
optId[${firstOpt[3]}]="--opt4"
optId[${firstOpt[4]}]="--opt5"

optId[${picomOpt[0]}]="--picomOpt1"

optId[${notificationOpt[0]}]="--notificationOpt1"
optId[${notificationOpt[1]}]="--notificationOpt2"

optId[${wallpaperOpt[0]}]="--wallpaperOpt1"
optId[${wallpaperOpt[1]}]="--wallpaperOpt2"
optId[${wallpaperOpt[2]}]="--wallpaperOpt3"

# Rofi CMD
rofi_cmd() {
	rofi -theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
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
	if [[ "$1" == ${optId[${firstOpt[0]}]} ]]; then
		prompt='Picom'
		mesg="Windows Composer"
		opts=("${picomOpt[@]}")
	elif [[ "$1" == ${optId[${firstOpt[1]}]} ]]; then
		prompt='Network'
		mesg=""
		eth="$(nmcli connection show -active | grep -E 'eth' | awk '{print $1}')"
		wifi="$(nmcli connection show -active | grep -E 'wifi' | awk '{print $1}')"
		if [ "$eth" != "" ]; then
			mesg="  $eth"
		fi
		if [[ "$wifi" != "" ]]; then
			if [ "$mesg" != "" ]; then
				mesg="$mesg
  $wifi [Connected]"
			else
				mesg="  $wifi [Connected]"
			fi
		fi
		opts=$(nmcli device wifi list --rescan auto | awk 'NR!=1 {print substr($0,9)}' | awk '{print $8," ",$2}' | awk '!a[$0]++')
	elif [[ "$1" == ${optId[${firstOpt[2]}]} ]]; then
		prompt='Bluetooth'
		connected_device=$(bluetoothctl devices Connected | awk '{print substr($0,25)}')
		if [ "$connected_device" != "" ]; then
			mesg="Connected:
$connected_device"
		else
			mesg="No device connected"
		fi
		opts=$(bluetoothctl devices | awk '{print substr($0,26)}')
	elif [[ "$1" == ${optId[${firstOpt[3]}]} ]]; then
		prompt='Notification'
		mesg="Dunst Notification Manager"
		opts=("${notificationOpt[@]}")
	elif [[ "$1" == ${optId[${firstOpt[4]}]} ]]; then
		prompt='Wallpaper'
		mesg="Setting Wallpaper"
		opts=("${wallpaperOpt[@]}")
	else
		prompt='Module'
		mesg="Manage Module Of System"
		opts=("${firstOpt[@]}")
	fi

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
	${optId[${picomOpt[0]}]})
		toggleApplication picom
		;;
	${optId[${picomOpt[1]}]})
		toggleConf picom animations bool
		;;
	${optId[${notificationOpt[0]}]})
		for ((i = 0; i < $HistoryPopCount; i++)); do
			dunstctl history-pop
		done
		;;
	${optId[${notificationOpt[1]}]})
		dunstctl close-all
		;;
	${optId[${wallpaperOpt[0]}]})
		$WORK_DIR/tools/wallpaper.sh -n
		;;
	${optId[${wallpaperOpt[1]}]})
		toggleConf wallpaper random number
		;;
	${optId[${wallpaperOpt[2]}]})
		toggleConf wallpaper random_type wallpaper_type
		;;
	${optId[${firstOpt[1]}]})
		chosen="$(run_rofi $1)"
		if [[ "$chosen" == "" || "$chosen" == "$(nmcli connection show -active | grep -E 'wifi' | awk '{print $1}')" ]]; then
			exit
		fi
		nmcli device wifi connect $(echo $chosen | awk '{print $2}')
		;;
	${optId[${firstOpt[2]}]})
		chosen="$(run_rofi $1)"
		if [[ "$chosen" == "" ]]; then
			exit
		fi
		bluetoothctl disconnect $(bluetoothctl devices Connected | grep "$chosen" | awk '{print $2}')
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
