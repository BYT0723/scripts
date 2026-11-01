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
quicklinks="$HOME/.dwm/rofi/scripts/quicklinks-mode.sh"

## Run
rofi \
    -modes "combi,quicklinks:${quicklinks}" \
    -combi-modes "drun,run,ssh" \
    -show-icons \
    -display-combi " " \
    -display-drun " " \
    -display-run " " \
    -display-ssh " " \
    -theme-str 'configuration {display-quicklinks: "󰖟 ";}' \
    -theme-str 'configuration {terminal: "'${TERMINAL:-kitty}'";}' \
    -show combi \
    -theme "${dir}/${theme}.rasi"
