#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_MAX_LINES=8
MODULE_NAME="☀ Theme"
MODULE_MESG="Manage system theme"
MODULE_SEARCH_BAR=false
ITEM_SPACE_WIDTH=34

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/tools/theme.sh"

THEME_CONF="$HOME/.config/dwm/theme.json"

get_auto_stat() {
	jq -r '.auto // false' "$THEME_CONF" 2>/dev/null
}

get_cur() {
	xrdb -query 2>/dev/null | awk -F': *\t*' '$1=="dwm.col_theme" {print $2}'
}

get_rise() { jq -r '.rise_offset // 0' "$THEME_CONF" 2>/dev/null; }
get_set() { jq -r '.set_offset // 0' "$THEME_CONF" 2>/dev/null; }

get_sun_message() {
	local times sunrise sunset
	times=$(get_sun_times 2>/dev/null) || return 1
	read sunrise sunset _ <<<"$times"
	printf "  %s |   %s" "$(date -d "@$sunrise" +%H:%M)" "$(date -d "@$sunset" +%H:%M)"
}

module_parse <<MODULES
toggle| |Toggle|switch light/dark|str:$(get_cur)
auto|󰃡 |Auto (sunrise/sunset)|toggle auto switching|str:$([ "$(get_auto_stat)" = "true" ] && echo "" || echo "")
rise_offset| |Rise offset|±min after sunrise|str:$(get_rise)m
set_offset| |Set offset|±min after sunset|str:$(get_set)m
conf|󱔏 |Edit config|open theme.json|
MODULES

sun_mesg=$(get_sun_message 2>/dev/null) || true
MODULE_MESG="system theme${sun_mesg:+ | $sun_mesg}"

handle_toggle() {
	local cur mode
	cur=$(get_cur)
	if [ "$cur" = "light" ]; then mode="dark"; else mode="light"; fi
	/bin/bash "$WORK_DIR/tools/theme.sh" apply "$mode"
}
handle_auto() {
	local cur
	cur=$(get_auto_stat)
	if [ "$cur" = "true" ]; then
		/bin/bash "$WORK_DIR/tools/theme.sh" auto off
	else
		/bin/bash "$WORK_DIR/tools/theme.sh" auto on
	fi
}

_handle_offset() {
	local field="$1" prompt="$2" getter="$3"
	local cur val
	cur=$("$getter")
	val="$(module_input "$prompt" "negative = before, positive = after" "$cur")"
	[ -z "$val" ] && return
	[[ "$val" =~ ^-?[0-9]+$ ]] || {
		system-notify normal "Invalid" "must be an integer"
		return
	}
	jq ".$field = $val" "$THEME_CONF" >"${THEME_CONF}.tmp" && mv "${THEME_CONF}.tmp" "$THEME_CONF"
	if [ "$(get_auto_stat)" = "true" ]; then
		pf="/tmp/dwm-status/autostart-launch-theme-auto.pid"
		[ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null
		rm -f "$pf"
		/bin/bash "$WORK_DIR/tools/theme.sh" auto >/dev/null 2>&1 &
	fi
}
handle_rise_offset() { _handle_offset "rise_offset" "Rise offset (min)" get_rise; }
handle_set_offset() { _handle_offset "set_offset" "Set offset (min)" get_set; }
handle_conf() { ${TERMINAL:-kitty} -e ${EDITOR:-nvim} "$THEME_CONF" 2>/dev/null || system-notify normal "Error" "failed to open editor"; }

module_loop
