#!/usr/bin/env bash

## Author  : Aditya Shakya (adi1090x)
## Github  : @adi1090x
#
## Applets : Quick Links

if [ -z "$(command -v rofi)" ]; then
	notify-send "please install rofi"
	exit 0
fi

if [ -z "$(rofi -h | grep emoji)" ]; then
	notify-send "please install rofi-emoji"
	exit 0
fi

ROFI_DIR="$(dirname "$(dirname "$0")")"

# Import Current Theme
type="$ROFI_DIR/launchers/type-3"
style='style-4.rasi'
theme="$type/$style"
efonts="Twemoji 40"

# Theme Elements
prompt='Emoji'
mesg="Search a emoji"

# Rofi CMD
rofi_cmd() {
	rofi -modi emoji -show emoji \
		-theme-str "element-text {font: \"$efonts\";}" \
		-theme-str "element-icon {size: 0px;}" \
		-theme-str "configuration { display-emoji: \" \";}" \
		-emoji-mode $1 \
		-emoji-format '{emoji}' \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-theme ${theme} \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

case "$1" in
"-o")
	rofi_cmd stdout
	;;
*)
	rofi_cmd insert
	;;
esac
