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

# Width flags (对应 style-6.rasi 中的元素尺寸, 宽度按列数自动撑开)
icon_size=128       # element-icon size
element_hpad=10     # element padding 左右 (rasi: 20px 10px)
listview_spacing=10 # listview spacing
mainbox_padding=20  # mainbox padding

# Theme Elements
prompt='Windows'
mesg="Search a window by title or class"

count=$(wmctrl -l | wc -l)
rows=$(((count + max_cols - 1) / max_cols))
cols=$count
((cols > max_cols)) && cols=$max_cols
((cols < 1)) && cols=1
((rows > max_rows)) && rows=$max_rows

col_width=$((icon_size + element_hpad * 2))
win_width=$((col_width * cols + listview_spacing * (cols - 1) + mainbox_padding * 2))

# Rofi CMD
rofi_cmd() {
    rofi -modi window -show window \
        -show-icon \
        -p "$prompt" \
        -mesg "$mesg" \
        -theme ${theme} \
        -window-format "{t}" \
        -theme-str 'mainbox {padding: '${mainbox_padding}'px;}' \
        -theme-str 'element {padding: 20px '${element_hpad}'px;}' \
        -theme-str 'element-icon {size: '${icon_size}'px;}' \
        -theme-str 'window {width: '${win_width}'px;}' \
        -theme-str 'listview {columns: '${cols}'; lines: '${rows}'; flow: horizontal; spacing: '${listview_spacing}';}' \
        -hover-select -me-select-entry '' -me-accept-entry '' -me-accept-custom MousePrimary
}

rofi_cmd
