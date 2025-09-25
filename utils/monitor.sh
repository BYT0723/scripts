#!/bin/bash

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

get_current_monitor() {
	read mouse_x mouse_y < <(xdotool getmouselocation | sed -n 's/.*x:\([0-9]*\).*y:\([0-9]*\).*/\1 \2/p')

	xrandr --listactivemonitors | {
		read
		while read -r monitor; do
			name=$(echo $monitor | awk '{print $NF}')
			read index width height x y < <(get_monitor_info "$name")

			if [ $(expr $mouse_x - $x) -ge 0 ] && [ $(expr $mouse_x - $x - $width) -le 0 ] && [ $(expr $mouse_y - $y) -ge 0 ] && [ $(expr $mouse_y - $y - $height) -le 0 ]; then
				echo "$index $name $width $height $x $y"
				return
			fi
		done
	}
}
