#!/usr/bin/env bash

## Author  : Aditya Shakya (adi1090x)
## Github  : @adi1090x
#
## Applets : Quick Links

if [ -z "$(command -v rofi)" ]; then
    notify-send "please install rofi"
    exit 0
fi

ROFI_DIR="$(dirname "$(dirname "$0")")"

# Import Current Theme
type="$ROFI_DIR/launchers/type-3"
style='style-6.rasi'
theme="$type/$style"

max_cols=6
max_rows=3

# Theme Elements
prompt='Windows'
mesg="Search a window by title or class"

count=$(wmctrl -l | wc -l)
rows=$(((count + max_cols - 1) / max_cols))
((rows > max_rows)) && rows=$max_rows

# Rofi CMD
rofi_cmd() {
    rofi -modi window -show window \
        -show-icon \
        -p "$prompt" \
        -mesg "$mesg" \
        -theme ${theme} \
        -window-format "{t}" \
        -theme-str 'window {width: 1000px;}' \
        -theme-str 'listview {columns: '$max_cols'; lines: '$rows'; flow: horizontal;}' \
        -hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

rofi_cmd
