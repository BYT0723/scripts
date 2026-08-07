#!/bin/bash

source "$(dirname "$0")/../utils/notify.sh"

[ -z "$(command -v xcolor)" ] && system-notify critical "Tool Not Found" "please install xcolor" && exit 1

color=$(xcolor -f hex 2>/dev/null) || exit 1
printf '%s' "$color" | xclip -selection clipboard -in

r=$((16#${color:1:2}))
g=$((16#${color:3:2}))
b=$((16#${color:5:2}))
lum=$(((299 * r + 587 * g + 114 * b) / 1000))
if [ $lum -gt 128 ]; then fg="black"; else fg="white"; fi

tool-notify low "Color Picker" "<span bgcolor='$color' fgcolor='$fg'>$color</span> copied to clipboard"
