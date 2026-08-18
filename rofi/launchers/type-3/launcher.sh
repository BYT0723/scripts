#!/usr/bin/env bash

## Author : Aditya Shakya (adi1090x)
## Github : @adi1090x
#
## Rofi   : Launcher (Modi Drun, Run, File Browser, Window)
#
## Available Styles
#
## style-1     style-2     style-3     style-4     style-5
## style-6     style-7     style-8     style-9     style-10

dir="$HOME/.dwm/rofi/launchers/type-3"
theme='style-5'

## Run
rofi \
	-modes "combi,quicklinks:$(realpath $(dirname $0))/quicklinks-mode.sh" \
	-combi-modes "window,drun,run" \
	-show-icons \
	-display-combi " " \
	-display-window " " \
	-display-drun " " \
	-display-run " " \
	-theme-str 'configuration {display-quicklinks: "󰖟 ";}' \
	-window-format "{c} {t}" \
	-show combi \
	-theme ${dir}/${theme}.rasi
