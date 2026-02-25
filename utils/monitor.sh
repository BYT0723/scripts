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
	index=$(xrandr --listactivemonitors | grep $name | cut -d ':' -f1)

	info=$(xrandr --listactivemonitors | grep $name | awk '{print $3}')
	width=$(echo $info | awk -F '/' '{print $1}')
	height=$(echo $info | awk -F 'x' '{print $2}' | awk -F '/' '{print $1}')
	read x y < <(echo $info | awk -F 'x' '{print $2}' | awk -F '+' '{print $2 " " $3}')
	echo $index $width $height $x $y
}

get_monitor_info_by_index() {
	local idx="$1"
	name=$(xrandr --listactivemonitors | grep "${idx}:" | awk '{print $NF}')
	get_monitor_info $name
}

get_current_monitor() {
	# 先尝试获取当前focus窗口ID
	local win=$(xdotool getwindowfocus)
	local use_mouse=$((win == 0 || win == 1 ? 1 : 0))

	if [ "$use_mouse" = 0 ]; then
		read px py < <(xdotool getwindowgeometry "$win" | awk 'NR==2 {print $2}' | awk -F ',' '{print $1 " " $2}')
	else
		read px py < <(xdotool getmouselocation | awk -F'[: ]' '{print $2, $4}')
	fi

	xrandr --listactivemonitors | {
		read
		while read -r monitor; do
			name=$(echo $monitor | awk '{print $NF}')
			read index width height x y < <(get_monitor_info "$name")

			if [ $(expr $px - $x) -ge 0 ] && [ $(expr $px - $x - $width) -le 0 ] && [ $(expr $py - $y) -ge 0 ] && [ $(expr $py - $y - $height) -le 0 ]; then
				echo "$index $name $width $height $x $y"
				return
			fi
		done
	}
}
