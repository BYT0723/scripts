#!/bin/bash

declare -A char2icons

char2icons["0"]="󰬹"
char2icons["1"]="󰬺"
char2icons["2"]="󰬻"
char2icons["3"]="󰬼"
char2icons["4"]="󰬽"
char2icons["5"]="󰬾"
char2icons["6"]="󰬿"
char2icons["7"]="󰭀"
char2icons["8"]="󰭁"
char2icons["9"]="󰭂"
char2icons["-"]=""

# 将文本中的数字转换为图标
# $1: string
number2icon() {
	s=$1
	for ((i = 0; i < ${#s}; i++)); do
		c="${s:i:1}"
		if [[ -v char2icons[$c] ]]; then
			out+="${char2icons[$c]}"
		else
			out+="$c"
		fi
	done
	printf "%s" "$out"
}
