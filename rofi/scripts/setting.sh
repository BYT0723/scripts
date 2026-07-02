#!/usr/bin/env bash

TERM=${TERMINAL:-kitty}

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

SDDM_SCRIPT="$(realpath $WORK_DIR)/tools/sddm.sh"

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
		"󰍂 SDDM"
	)
	sddmOpt=(
		"Set Theme"
		"Preview"
		"Set Config"
		"Edit Config"
		"Install Themes"
	)
else
	firstOpt=(
		"SDDM"
	)
	sddmOpt=(
		"Set Theme"
		"Preview"
		"Set Config"
		"Edit Config"
		"Install Themes"
	)
fi

declare -A optId
optId[${firstOpt[0]}]="--opt1"

optId[${sddmOpt[0]}]="--sddmOpt1"
optId[${sddmOpt[1]}]="--sddmOpt2"
optId[${sddmOpt[2]}]="--sddmOpt3"
optId[${sddmOpt[3]}]="--sddmOpt4"
optId[${sddmOpt[4]}]="--sddmOpt5"

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
		mesg="Current Theme: $(eval "$WORK_DIR/tools/sddm.sh cur_theme")"
		opts=("${sddmOpt[@]}")
		;;
	${optId[${sddmOpt[0]}]})
		prompt='SDDM Themes'
		mesg="Available SDDM Themes"
		opts=("$(eval "bash $SDDM_SCRIPT list_theme")")
		;;
	${optId[${sddmOpt[2]}]})
		prompt='SDDM Theme Configs'
		mesg="Available SDDM Theme Configs"
		opts=("$(eval "bash $SDDM_SCRIPT list_cfg")")
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
		[ -z "$chosen" ] && return
		pkexec "$SDDM_SCRIPT" set_theme $chosen
		return
		;;
	${optId[${sddmOpt[1]}]})
		eval "$SDDM_SCRIPT preview"
		return
		;;
	${optId[${sddmOpt[2]}]})
		chosen="$(run_rofi $1)"
		[ -z "$chosen" ] && return
		pkexec "$SDDM_SCRIPT" set_cfg $chosen
		return
		;;
	${optId[${sddmOpt[3]}]})
		"$TERM" -e sudo -E nvim "$(eval "$SDDM_SCRIPT cur_cfg_path")"
		return
		;;
	${optId[${sddmOpt[4]}]})
		"$TERM" -e /bin/bash -c "$SDDM_SCRIPT install; echo; read -p 'Press enter to close...'"
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
