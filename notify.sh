#!/bin/bash

# 计算输出文本占用终端大小
calculate_dimensions() {
	local row=0
	local col=0
	while IFS= read -r line; do
		row=$(($row + 1))
		len=$((${#line} + $(echo "$line" | grep -oP "[^\x00-\x7F]" | wc -l)))
		if [ $len -gt $col ]; then
			col=$len
		fi
	done <<<"$1" # 使用Here String传递输出

	echo "$(($col))"x"$(($row + 1))"
}

position() {
	case "$1" in
	'left-top')
		echo "+10+50"
		;;
	'right-top')
		echo "-10+50"
		;;
	'left-bottom')
		echo "+10-10"
		;;
	'right-bottom')
		echo "-10-10"
		;;
	esac

}

pos=right-top
cmd=$@
size=$(calculate_dimensions "$($cmd)")

# 在此之后继续处理row和col的值
st -i -g "$size$(position $pos)" -f "CaskaydiaCove Nerd Font:style=Bold:pixelsize=18:antialias=true:autohint=true" -e bash $(dirname $0)/notify-run.sh $cmd
