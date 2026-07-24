#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_WIDTH=500

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/tools/wallpaper-lib.sh"

# ---- Monitor Selection ----
get_monitor_list() {
	local monitors_list=$(xrandr --listactivemonitors 2>/dev/null)

	if [ "$(echo "$monitors_list" | wc -l)" = 2 ]; then
		echo "$monitors_list" | awk 'END{print $NF}'
		return
	fi

	local screen_dim=$(get_screen_size | sed 's/+.*//')
	printf "ALL\n%-28s %s\n" "Screen" "$screen_dim"
	echo "$monitors_list" | awk 'NR>1 {
		gsub("/[0-9]+", "", $3)
		split($3,a,"+")
		split(a[1],b,"x")
		printf "%-28s %sx%s\n", $NF, b[1], b[2]
	}'
}

monitor_selection() {
	get_monitor_list | module_sub_rofi "  Monitor" "Select a monitor for wallpaper" | awk '{print $1}'
}

# ---- Main ----
MONITOR=$(monitor_selection)
[ -z "$MONITOR" ] && exit 0

MODULE_NAME=" Wallpaper"
MODULE_MESG="Monitor: $MONITOR"

module_parse <<MODULES
next|󰑐|Next||
select|󰆍|Select||
random_switch|󰛌|Random||cmd:icon toggle conf wallpaper random number "$MONITOR"
random_type|󰨠|Type||cmd:[[ $(getConfig -m "$MONITOR" random_type) == "video" ]] && echo "" || echo ""
random_duration|󰔟|Duration||cmd:getConfig -m "$MONITOR" duration
random_depth|󰒻|Depth||cmd:getConfig -m "$MONITOR" random_depth
random_images_path|󰉻|Images||
random_videos_path|󰉽|Videos||
MODULES
_pick_config_dir() {
	local key="$1"
	local w_conf="$HOME/.config/dwm/wallpaper.json"
	local json_path=".defaults"
	[ "$MONITOR" != "ALL" ] && json_path=".monitors[\"$MONITOR\"]"
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

_w_conf_path() {
	local w_conf="$HOME/.config/dwm/wallpaper.json"
	local json_path=".defaults"
	[ "$MONITOR" != "ALL" ] && json_path=".monitors[\"$MONITOR\"]"
	echo "$w_conf" "$json_path"
}

handle_next() { "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" next; }
handle_select() { "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" select; }
handle_random_switch() { toggleConf wallpaper random number "$MONITOR"; }
handle_random_type() { toggleConf wallpaper random_type wallpaper_type "$MONITOR"; }

handle_random_duration() {
	local w_conf json_path
	read w_conf json_path <<<"$(_w_conf_path)"
	local cur=$(getConfig -m "$MONITOR" duration)
	local new=$(bash "$ROFI_DIR"/scripts/common_input.sh \
		-w 600 -d "$cur" \
		"Duration (min)" "Number, must be > 0")
	[ -n "$new" ] && [ "$new" -gt 0 ] 2>/dev/null &&
		jq "${json_path}.duration = $new" "$w_conf" >"$w_conf.tmp" && mv "$w_conf.tmp" "$w_conf"
}

handle_random_depth() {
	local w_conf json_path
	read w_conf json_path <<<"$(_w_conf_path)"
	local cur=$(getConfig -m "$MONITOR" random_depth)
	local new=$(bash "$ROFI_DIR"/scripts/common_input.sh \
		-w 600 -d "$cur" \
		"Depth" "Number, must be 1-10")
	[ -n "$new" ] && [ "$new" -ge 1 ] 2>/dev/null && [ "$new" -le 10 ] 2>/dev/null &&
		jq "${json_path}.random_depth = $new" "$w_conf" >"$w_conf.tmp" && mv "$w_conf.tmp" "$w_conf"
}

handle_random_images_path() { _pick_config_dir random_image_dir; }
handle_random_videos_path() { _pick_config_dir random_video_dir; }

module_loop
