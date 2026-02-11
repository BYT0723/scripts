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
		-matching fuzzy -i \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

run_rofi() {
	build_menu | rofi_cmd
}

run_cmd() {
	chosen="$1"

	for entry in "${links[@]}"; do
		IFS="|" read -r icon name url <<<"$entry"

		icon=$(trim "$icon")
		name=$(trim "$name")
		url=$(trim "$url")

		echo "'$chosen' == '$icon $name'"

		match="$icon  $name"

		if [[ "$chosen" == "$match" ]]; then
			xdg-open "$url"
			exit
		fi
	done
}

chosen="$(run_rofi)"
[ -n "$chosen" ] && run_cmd "$chosen"
