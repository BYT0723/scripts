#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

# Import Current Theme
type="$ROFI_DIR/applets/type-2"
style='style-2.rasi'
theme="$type/$style"

font="JetBrains Mono Nerd Font 16"
element_font="JetBrains Mono Nerd Font 24"
prompt=${1:-"Setting"}
mesg=${2:-"Setting Something..."}

# Rofi CMD
rofi_cmd() {
	rofi -theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str 'window {width: 600px;}' \
		-theme-str "* {font: \"$font\";}" \
		-theme-str "element-text {font: \"$element_font\";}" \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-monitor -4 \
		-theme ${theme} \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

rofi_cmd
