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
	-icon-theme $(grep -oP 'gtk-icon-theme-name="\K[^"]+' ~/.gtkrc-2.0) \
	-show combi \
	-monitor -4 \
	-theme ${dir}/${theme}.rasi \
	-hover-select -me-select-entry '' -me-accept-entry MousePrimary
