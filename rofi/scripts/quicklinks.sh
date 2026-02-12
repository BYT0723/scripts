#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

# Import Current Theme
type="$ROFI_DIR/launchers/type-1"
style='style-5.rasi'
theme="$type/$style"
font="JetBrains Mono Nerd Font 16"
mesg="Using '$(xdg-settings get default-web-browser | cut -d . -f 1)' Open Link"

CONFIG="$(dirname $ROFI_DIR)/configs/quicklinks.conf"

mapfile -t links < <(
	grep -v '^\s*#' "$CONFIG" | grep -v '^\s*$'
)

trim() {
	local s="$*"
	# 去前导空白
	s="${s#"${s%%[![:space:]]*}"}"
	# 去尾随空白
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

is_url() {
	[[ "$1" =~ ^https?:// ]] && return 0
	[[ "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,} ]] && return 0
	return 1
}

build_menu() {
	for entry in "${links[@]}"; do
		IFS='|' read -r icon name url <<<"$entry"

		icon=$(trim "$icon")
		name=$(trim "$name")
		url=$(trim "$url")

		echo "$icon  $name"
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
	chosen="$1"

	for entry in "${links[@]}"; do
		IFS="|" read -r icon name url <<<"$entry"

		icon=$(trim "$icon")
		name=$(trim "$name")
		url=$(trim "$url")

		if [[ "$chosen" == "$icon  $name" ]]; then
			xdg-open "$url"
			exit
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
