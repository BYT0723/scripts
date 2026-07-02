#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

type="$ROFI_DIR/launchers/type-1"
style='style-5.rasi'
theme="$type/$style"
font="JetBrains Mono Nerd Font 16"

NEW_LINK=" New Link"
CONFIG="$HOME/.config/dwm/quicklinks.json"

# ---- parse links ----
declare -A _url_map
_menu=""

_load() {
	while IFS=$'\t' read -r key url; do
		_url_map["$key"]="$url"
		_menu+="${_menu:+$'\n'}$key"
	done < <(jq -r '.links[] | "\((if (.icon // "") == "" then " " else .icon end)) \(.name)\t\(.url)"' "$CONFIG")
}

_load

# ---- rofi ----
rofi_cmd() {
	rofi -dmenu -i \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str "* {font: \"$font\";}" \
		-theme-str 'configuration {show-icons:false;}' \
		-theme-str 'window {width: 600px;}' \
		-p "Quicklinks" \
		-mesg "Using Default Browser Open Link" \
		-markup-rows \
		-theme "${theme}" \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

_is_url() {
	[[ "$1" =~ ^https?:// ]] && return 0
	[[ "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,} ]] && return 0
	return 1
}

QUICKLINKS_EDITOR=${QUICKLINKS_EDITOR:-"kitty nvim"}
SEARCH="https://www.google.com/search?q="

run_cmd() {
	local chosen="$1"

	[[ "$chosen" == "$NEW_LINK" ]] && {
		$QUICKLINKS_EDITOR "$CONFIG"
		return
	}

	local url="${_url_map[$chosen]}"
	if [[ -n "$url" ]]; then
		xdg-open "$url"
		return
	fi

	if _is_url "$chosen"; then
		[[ "$chosen" =~ ^https?:// ]] || chosen="https://$chosen"
		xdg-open "$chosen"
		return
	fi

	xdg-open "${SEARCH}${chosen}"
}

chosen=$(echo "$_menu" | rofi_cmd)
[ -n "$chosen" ] && run_cmd "$chosen"
