#!/bin/bash

# required
# bc
# xdotool
# xrandr
# arandr

# 不推荐使用，dwm有内置focusmon 和 tagmon方法

read mouse_x mouse_y < <(xdotool getmouselocation | sed -n 's/.*x:\([0-9]*\).*y:\([0-9]*\).*/\1 \2/p')

# TODO: monitor layout列表，选择不同的布局
# list_layout() {
# 	local dir="$HOME/.screenlayout"
# 	if [ ! -d "$dir" ]; then
# 		return
# 	fi
#
# 	rofi
#
# 	for file in; do
# 		echo $(basename $file)
# 	done
# }

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

cycle_monitor() {
	action=$1
	if [ -z "$action" ]; then
		echo "no action to do"
		return
	fi

	monitors=($(xrandr | grep " connected " | awk '{print $1}'))

	for i in "${!monitors[@]}"; do
		read _ width height x y < <(get_monitor_info ${monitors[$i]})

		if [ $(echo "$mouse_x - $x" | bc) -ge 0 ] && [ $(echo "$mouse_x - $x - $width" | bc) -le 0 ] && [ $(echo "$mouse_y - $y" | bc) -ge 0 ] && [ $(echo "$mouse_y - $y - $height" | bc) -le 0 ]; then
			case "$action" in
			"prev")
				target_index=$(((i - 1 + ${#monitors[@]}) % ${#monitors[@]})) # 计算上一个监视器的索引
				;;
			"next")
				target_index=$(((i + 1) % ${#monitors[@]})) # 计算下一个监视器的索引
				;;
			esac
			echo ${monitors[$target_index]}

			read _ target_width target_height target_x target_y < <(get_monitor_info ${monitors[$target_index]})
			# 然后切换到目标monitor
			new_x=$(echo $target_x + $target_width/2 | bc)
			new_y=$(echo $target_y + $target_height/2 | bc)
			xdotool mousemove $new_x $new_y
			break
		fi
	done
}

case "$1" in
"next")
	cycle_monitor $1
	;;
"prev")
	cycle_monitor $1
	;;
esac
