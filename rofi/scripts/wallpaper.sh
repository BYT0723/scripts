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
	list_row='8'
elif [[ ("$theme" == *'type-2'*) || ("$theme" == *'type-4'*) ]]; then
	list_col='8'
	list_row='1'
fi

CONFIG_HOME="$HOME/.config/dwm"
TERM=${TERMINAL:-"kitty --class float-term -o font_size=8 -o initial_window_width=160c -o initial_window_height=48c"}

# 配置文件路径
declare -A confPath
confPath["wallpaper"]="$CONFIG_HOME/wallpaper.json"

# ---- Monitor Selection ----
get_monitor_list() {
	local monitors_list=$(xrandr --listactivemonitors 2>/dev/null)

	if [ $(echo "$monitors_list" | wc -l) = 2 ]; then
		echo "$monitors_list" | awk 'END{print $NF}'
		return
	fi

	local screen_dim=$(xrandr | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /current/) print $i}' |
		awk '{print $2 $3 $4}' | sed 's/+.*//')
	echo -e "ALL\n$(printf "%-22s %s" "Screen" ${screen_dim})\n$(echo "$monitors_list" | awk 'NR>1 {
		gsub("/[0-9]+", "", $3)
		split($3,a,"+")
		split(a[1],b,"x")
		printf "%-22s %sx%s\n", $NF, b[1], b[2]
	}')"
}

monitor_selection() {
	get_monitor_list | rofi -theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str 'window {width: 500px;}' \
		-theme-str "* {font: \"JetBrains Mono Nerd Font 16\";}" \
		-dmenu \
		-p "Monitor" \
		-mesg "Select a monitor" \
		-markup-rows \
		-monitor -4 \
		-theme "$ROFI_DIR/applets/type-1/style-3.rasi" \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary | awk '{print $1}'
}

# ---- Main ----
MONITOR=$(monitor_selection)
[ -z "$MONITOR" ] && exit 0

# Options
layout=$(cat ${theme} | grep 'USE_ICON' | cut -d'=' -f2)

if [[ "$layout" == 'NO' ]]; then
	firstOpt=(
		"Next"
		"Select"
		"Random                          $(icon toggle conf wallpaper random number $MONITOR)"
		"Type                         $(printf "%5s" $(getConfig wallpaper random_type $MONITOR))"
		"Duration                     $(printf "%5d" $(getConfig wallpaper duration $MONITOR))"
		"Depth                        $(printf "%5d" $(getConfig wallpaper random_depth $MONITOR))"
		"Images"
		"Videos"
	)
else
	firstOpt=(
		"Next"
		"Select"
		"$(icon toggle conf wallpaper random number $MONITOR)"
		"$(getConfig wallpaper random_type $MONITOR)"
		"$(getConfig wallpaper duration $MONITOR)"
		"$(getConfig wallpaper random_depth $MONITOR)"
		"Images"
		"Videos"
	)
fi

declare -A optId
optId[${firstOpt[0]}]="--opt1"
optId[${firstOpt[1]}]="--opt2"
optId[${firstOpt[2]}]="--opt3"
optId[${firstOpt[3]}]="--opt4"
optId[${firstOpt[4]}]="--opt5"
optId[${firstOpt[5]}]="--opt6"
optId[${firstOpt[6]}]="--opt7"
optId[${firstOpt[7]}]="--opt8"

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
	prompt="$(icon active cmd 'wallpaper.sh -r') Wallpaper"
	mesg="Monitor: $MONITOR"
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
_pick_config_dir() {
	local key="$1"
	local cur=$(getConfig wallpaper "$key" "$MONITOR")
	local cur_dir="${cur/#\~/$HOME}"
	[ ! -d "$cur_dir" ] && cur_dir="$HOME"
	local tmp=$(mktemp)
	YAZI_CONFIG_HOME=$HOME/.config/yazi_wallpaper $TERM yazi "$cur_dir" --chooser-file="$tmp"
	local chosen=$(cat "$tmp" 2>/dev/null)
	rm -f "$tmp"
	if [ -n "$chosen" ]; then
		[ -d "$chosen" ] && chosen="$chosen" || chosen=$(dirname "$chosen")
		jq --arg d "$chosen" "${json_path}.${key} = \$d" "$w_conf" >"$w_conf.tmp" && mv "$w_conf.tmp" "$w_conf"
	fi
}

run_cmd() {
	local w_conf="$HOME/.config/dwm/wallpaper.json"
	local json_path=".defaults"
	[ "$MONITOR" != "ALL" ] && json_path=".monitors[\"$MONITOR\"]"

	case "$1" in
	${optId[${firstOpt[0]}]})
		$WORK_DIR/tools/wallpaper.sh -m "$MONITOR" next
		;;
	${optId[${firstOpt[1]}]})
		$WORK_DIR/tools/wallpaper.sh -m "$MONITOR" select
		;;
	${optId[${firstOpt[2]}]})
		toggleConf wallpaper random number "$MONITOR"
		;;
	${optId[${firstOpt[3]}]})
		toggleConf wallpaper random_type wallpaper_type "$MONITOR"
		;;
	${optId[${firstOpt[4]}]})
		local cur=$(getConfig wallpaper duration "$MONITOR")
		local new=$(bash $ROFI_DIR/scripts/common_input.sh \
			-w 600 -d "$cur" \
			"Duration (min)" "Number, must be > 0")
		[ -n "$new" ] && [ "$new" -gt 0 ] 2>/dev/null &&
			jq "${json_path}.duration = $new" "$w_conf" >"$w_conf.tmp" && mv "$w_conf.tmp" "$w_conf"
		;;
	${optId[${firstOpt[5]}]})
		local cur=$(getConfig wallpaper random_depth "$MONITOR")
		local new=$(bash $ROFI_DIR/scripts/common_input.sh \
			-w 600 -d "$cur" \
			"Depth" "Number, must be 1-10")
		[ -n "$new" ] && [ "$new" -ge 1 ] 2>/dev/null && [ "$new" -le 10 ] 2>/dev/null &&
			jq "${json_path}.random_depth = $new" "$w_conf" >"$w_conf.tmp" && mv "$w_conf.tmp" "$w_conf"
		;;
	${optId[${firstOpt[6]}]})
		_pick_config_dir random_image_dir
		;;
	${optId[${firstOpt[7]}]})
		_pick_config_dir random_video_dir
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
