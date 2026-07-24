#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

width=500
theme_str="2-2"

while getopts "w:f:d:" opt; do
	case $opt in
	w) width=$OPTARG ;;
	f) font=$OPTARG ;;
	d) default=$OPTARG ;;
	?)
		echo "Usage: $0 [-w width] [-f font] [-d default] [prompt] [mesg]"
		exit 1
		;;
	esac
done

shift $((OPTIND - 1))

prompt=${1:-"Input"}
mesg=${2:-"help message"}
theme="$ROFI_DIR/applets/type-$(echo $theme_str | cut -d'-' -f1)/style-$(echo $theme_str | cut -d'-' -f2).rasi"

# Rofi CMD
rofi_cmd() {
	rofi \
		-theme-str 'window {width: '$width'px;}' \
		${font:+-theme-str "* {font: \"$font\";}"} \
		-theme-str 'mainbox { children: ["message", "inputbar"];}' \
		-theme-str 'inputbar {children: [ "prompt", "entry"];}' \
		-theme-str 'entry {padding:10px;background-color:inherit;text-color:inherit;placeholder: "'$default'";}' \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		-theme ${theme}
}

rofi_cmd
