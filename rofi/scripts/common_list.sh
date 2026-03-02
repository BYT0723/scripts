#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

theme_str="2-2"
font="JetBrains Mono Nerd Font 16"
width=600
element_font="JetBrains Mono Nerd Font 20"

while getopts "t:f:F:w:" opt; do
	case $opt in
	t) theme_str=$OPTARG ;;
	f) font=$OPTARG ;;
	F) element_font=$OPTARG ;;
	w) width=$OPTARG ;;
	?)
		echo "Usage: $0 [-w width] [-t theme] [-f font] [-ef element_font] [prompt] [mesg]"
		exit 1
		;;
	esac
done

# 把已经解析的参数移除
shift $((OPTIND - 1))

prompt=${1:-"Setting"}
mesg=${2:-"Setting Something..."}
theme="$ROFI_DIR/applets/type-$(echo $theme_str | cut -d'-' -f1)/style-$(echo $theme_str | cut -d'-' -f2).rasi"

# Rofi CMD
rofi_cmd() {
	rofi -theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str 'window {width: '$width'px;}' \
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
