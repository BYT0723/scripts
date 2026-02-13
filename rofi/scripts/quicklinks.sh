#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

source "$(dirname "$0")"/util.sh

# Import Current Theme
type="$ROFI_DIR/launchers/type-1"
style='style-5.rasi'
theme="$type/$style"
font="JetBrains Mono Nerd Font 16"
mesg="Using '$(xdg-settings get default-web-browser | cut -d . -f 1)' Open Link"

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dwm/quicklinks.conf"

mapfile -t links < <(
	grep -v '^\s*#' "$CONFIG" | grep -v '^\s*$'
)

build_menu() {
	for entry in "${links[@]}"; do
		IFS='|' read -r icon name url <<<"$entry"

		name=$(trim "$name")

		echo "$icon $name"
	done
}

# Rofi CMD
rofi_cmd() {
	rofi \
		-dmenu \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str "* {font: \"$font\";}" \
		-theme-str 'configuration {show-icons:false;}' \
		-theme-str 'window {width: 600px;}' \
		-p "$prompt" \
		-markup-rows \
		-theme ${theme} \
		-mesg "$mesg" \
		-i \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

run_rofi() {
	build_menu | rofi_cmd
}

google_search=https://www.google.com/search?q=
bing_search=https://cn.bing.com/search?q=
search_engine=$google_search

run_cmd() {
	local chosen="$1"

	for entry in "${links[@]}"; do
		IFS="|" read -r icon name url <<<"$entry"

		name=$(trim "$name")

		if [[ "$chosen" == "$icon $name" ]]; then
			chosen=$(trim "$url")
			break
		fi
	done

	# Direct URL
	if is_url "$chosen"; then
		[[ "$chosen" =~ ^https?:// ]] || chosen="https://$chosen"
		xdg-open "$chosen"
		exit
	fi

	xdg-open "$search_engine$chosen"
}

chosen="$(run_rofi)"
[ -n "$chosen" ] && run_cmd "$chosen"
