#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_NAME=" Wallpaper"
MODULE_MESG="Monitor: $MONITOR"
MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/tools/wallpaper-lib.sh"

# ---- Monitor Selection ----
monitor_selection() {
	local list_text=$(get_monitor_list_text)

	if [ "$(echo "$list_text" | wc -l)" = 1 ]; then
		echo "$list_text"
		return
	fi

	echo "$list_text" | module_sub_rofi "  Monitor" "Select a monitor for wallpaper" | awk '{print $1}'
}

# ---- Main ----
MONITOR=$(monitor_selection)
[ -z "$MONITOR" ] && exit 0

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
handle_next() { "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" next; }
handle_select() { "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" select; }
handle_random_switch() { toggleConf wallpaper random number "$MONITOR"; }
handle_random_type() { toggleConf wallpaper random_type wallpaper_type "$MONITOR"; }
handle_random_duration() { set_numeric_config "$MONITOR" duration "Duration" "Wallpaper change interval in minutes (≥ 1)" 1; }
handle_random_depth() { set_numeric_config "$MONITOR" random_depth "Search Depth" "Max directory depth for wallpaper files (1–10)" 1 10; }
handle_random_images_path() { pick_config_dir "$MONITOR" random_image_dir; }
handle_random_videos_path() { pick_config_dir "$MONITOR" random_video_dir; }

module_loop
