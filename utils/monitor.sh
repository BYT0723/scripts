#!/usr/bin/env /bin/bash

# required
# 	bc
# 	xdotool
# 	xrandr

# 不推荐使用，dwm有内置focusmon 和 tagmon方法

get_monitor_info() {
	name=$1
	if [ -z "$name" ]; then
		echo "invalid monitor name"
		exit 1
	fi
	index=$(xrandr --listactivemonitors | grep "$name" | cut -d ':' -f1)

	info=$(xrandr --listactivemonitors | grep "$name" | awk '{print $3}')
	width=$(echo "$info" | awk -F '/' '{print $1}')
	height=$(echo "$info" | awk -F 'x' '{print $2}' | awk -F '/' '{print $1}')
	read x y < <(echo "$info" | awk -F 'x' '{print $2}' | awk -F '+' '{print $2 " " $3}')
	echo "$index $width $height $x $y"
}

get_monitor_info_by_index() {
	local idx="$1"
	name=$(xrandr --listactivemonitors | grep "${idx}:" | awk '{print $NF}')
	get_monitor_info "$name"
}

is_portrait() {
	local idx="${1:-}"
	local mon_info
	if [ -n "$idx" ]; then
		mon_info=$(get_monitor_info_by_index "$idx")
	else
		mon_info=$(get_current_monitor)
	fi
	if [ -z "$mon_info" ]; then
		return 1
	fi
	local width height
	read _ _ width height _ _ <<<"$mon_info"
	[ "$width" -lt "$height" ]
}

get_current_monitor() {
	read px py < <(xdotool getmouselocation | awk -F'[: ]' '{print $2, $4}')

		xrandr --listactivemonitors | {
		read
		while read -r monitor; do
			name=$(echo "$monitor" | awk '{print $NF}')
			read index width height x y < <(get_monitor_info "$name")

			if [ $((px - x)) -ge 0 ] && [ $((px - x - width)) -le 0 ] && [ $((py - y)) -ge 0 ] && [ $((py - y - height)) -le 0 ]; then
				echo "$index $name $width $height $x $y"
				return
			fi
		done
	}
}
