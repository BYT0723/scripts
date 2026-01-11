#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

SDDM_SCRIPT="$(realpath $WORK_DIR)/tools/sddm.sh"
THEME_PREVIEW="sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/sddm-astronaut-theme/"

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

# Options
layout=$(cat ${theme} | grep 'USE_ICON' | cut -d'=' -f2)

if [[ "$layout" == 'NO' ]]; then
	firstOpt=(
		"SDDM"
	)
	sddmOpt=(
		"Set Theme"
		"Preview Theme"
		"Edit Theme"
		"Install Themes"
	)
else
	firstOpt=(
		"SDDM"
	)
	sddmOpt=(
		"Cur"
		"Preview"
		"Edit"
		"Install"
	)
fi

declare -A optId
optId[${firstOpt[0]}]="--opt1"

optId[${sddmOpt[0]}]="--sddmOpt1"
optId[${sddmOpt[1]}]="--sddmOpt2"
optId[${sddmOpt[2]}]="--sddmOpt3"
optId[${sddmOpt[3]}]="--sddmOpt4"

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
	case "$1" in
	${optId[${firstOpt[0]}]})
		prompt='SDDM'
		mesg="Current Theme: $(eval "$WORK_DIR/tools/sddm.sh cur")"
		opts=("${sddmOpt[@]}")
		;;
	${optId[${sddmOpt[0]}]})
		prompt='SDDM Themes'
		mesg="Available SDDM Themes"
		opts=("$(eval "bash $SDDM_SCRIPT list")")
		;;
	*)
		prompt='Setting'
		mesg="Setting Of System GUI"
		opts=("${firstOpt[@]}")
		;;
	esac

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
	case "$@" in
	${optId[${firstOpt[0]}]})
		chosen="$(run_rofi $1)"
		run_cmd ${optId[$chosen]}
		return
		;;
	${optId[${sddmOpt[0]}]})
		chosen="$(run_rofi $1)"
		pkexec "$SDDM_SCRIPT" set $chosen
		return
		;;
	${optId[${sddmOpt[1]}]})
		eval "$THEME_PREVIEW"
		return
		;;
	${optId[${sddmOpt[2]}]})
		exec "$TERMINAL" -e sudo -E nvim "$(eval "$SDDM_SCRIPT curp")"
		return
		;;
	${optId[${sddmOpt[3]}]})
		exec "$TERMINAL" -e bash -c "$(curl -fsSL https://raw.githubusercontent.com/keyitdev/sddm-astronaut-theme/master/setup.sh)"
		return
		;;
	esac
}

# Actions
chosen="$(run_rofi)"
if [[ "$chosen" == "" ]]; then
	exit
fi

chosen="${chosen//$'\n'/}"

run_cmd "${optId[$chosen]}"

exit
