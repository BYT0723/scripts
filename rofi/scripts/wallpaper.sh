#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

# Import Current Theme
theme="$ROFI_DIR/applets/type-1/style-3.rasi"

source "$(dirname "$0")"/util.sh
source "$WORK_DIR/tools/wallpaper-lib.sh"

if [[ ("$theme" == *'type-1'*) || ("$theme" == *'type-3'*) || ("$theme" == *'type-5'*) ]]; then
	list_col='1'
	list_row='8'
elif [[ ("$theme" == *'type-2'*) || ("$theme" == *'type-4'*) ]]; then
	list_col='8'
	list_row='1'
fi

# ---- Monitor Selection ----
get_monitor_list() {
	local monitors_list=$(xrandr --listactivemonitors 2>/dev/null)

	if [ "$(echo "$monitors_list" | wc -l)" = 2 ]; then
		echo "$monitors_list" | awk 'END{print $NF}'
		return
	fi

	local screen_dim=$(get_screen_size | sed 's/+.*//')
	printf "ALL\n%-22s %s\n" "Screen" "$screen_dim"
	echo "$monitors_list" | awk 'NR>1 {
		gsub("/[0-9]+", "", $3)
		split($3,a,"+")
		split(a[1],b,"x")
		printf "%-22s %sx%s\n", $NF, b[1], b[2]
	}'
}

monitor_selection() {
	get_monitor_list | rofi -theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str 'window {width: 500px;}' \
		-theme-str "* {font: \"JetBrains Mono Nerd Font 16\";}" \
		-dmenu \
		-p "Monitor" \
		-mesg "Select a monitor" \
		-markup-rows \
		-theme "$ROFI_DIR/applets/type-1/style-3.rasi" \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary | awk '{print $1}'
}

# ---- Main ----
MONITOR=$(monitor_selection)
[ -z "$MONITOR" ] && exit 0

# Options
layout=$(awk -F= '/USE_ICON/ {print $2}' "$theme")

random_text="$(icon toggle conf wallpaper random number "$MONITOR")"
rtype_text="$(getConfig -m "$MONITOR" random_type)"
duration_text="$(getConfig -m "$MONITOR" duration)"
depth_text="$(getConfig -m "$MONITOR" random_depth)"

if [[ "$layout" == 'NO' ]]; then
	random_text="Random                          $random_text"
	rtype_text="Type                         $(printf "%5s" "$rtype_text")"
	duration_text="Duration                     $(printf "%5d" "$duration_text")"
	depth_text="Depth                        $(printf "%5d" "$depth_text")"
fi

firstOpt=(
	"Next"
	"Select"
	"$random_text"
	"$rtype_text"
	"$duration_text"
	"$depth_text"
	"Images"
	"Videos"
)

# Rofi CMD
rofi_cmd() {
	rofi -theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-theme "$theme" \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

# Pass variables to rofi dmenu
run_rofi() {
	prompt="Wallpaper"
	mesg="Monitor: $MONITOR"
	printf '%s\n' "${firstOpt[@]}" | rofi_cmd
}

# Execute Command
_pick_config_dir() {
	local key="$1"
	local cur=$(getConfig -m "$MONITOR" "$key")
	local cur_dir=$(expand_path "$cur")
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
	local idx="$1"
	local w_conf="$HOME/.config/dwm/wallpaper.json"
	local json_path=".defaults"
	[ "$MONITOR" != "ALL" ] && json_path=".monitors[\"$MONITOR\"]"

	case "$idx" in
	0) "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" next ;;
	1) "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" select ;;
	2) toggleConf wallpaper random number "$MONITOR" ;;
	3) toggleConf wallpaper random_type wallpaper_type "$MONITOR" ;;
	4)
		local cur=$(getConfig -m "$MONITOR" duration)
		local new=$(bash "$ROFI_DIR"/scripts/common_input.sh \
			-w 600 -d "$cur" \
			"Duration (min)" "Number, must be > 0")
		[ -n "$new" ] && [ "$new" -gt 0 ] 2>/dev/null &&
			jq "${json_path}.duration = $new" "$w_conf" >"$w_conf.tmp" && mv "$w_conf.tmp" "$w_conf"
		;;
	5)
		local cur=$(getConfig -m "$MONITOR" random_depth)
		local new=$(bash "$ROFI_DIR"/scripts/common_input.sh \
			-w 600 -d "$cur" \
			"Depth" "Number, must be 1-10")
		[ -n "$new" ] && [ "$new" -ge 1 ] 2>/dev/null && [ "$new" -le 10 ] 2>/dev/null &&
			jq "${json_path}.random_depth = $new" "$w_conf" >"$w_conf.tmp" && mv "$w_conf.tmp" "$w_conf"
		;;
	6) _pick_config_dir random_image_dir ;;
	7) _pick_config_dir random_video_dir ;;
	esac
}

# Actions
chosen="$(run_rofi)"
[ -z "$chosen" ] && exit 0

idx=-1
for i in "${!firstOpt[@]}"; do
	[ "${firstOpt[$i]}" = "$chosen" ] && idx=$i && break
done
[ "$idx" -ge 0 ] && run_cmd "$idx"

exit
