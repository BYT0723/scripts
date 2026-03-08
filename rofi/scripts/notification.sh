#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

source "$(dirname "$0")"/util.sh

# Import Current Theme
type="$ROFI_DIR/launchers/type-1"
style='style-5.rasi'
theme="$type/$style"
font="JetBrains Mono Nerd Font 16"
# font="Noto Sans CJK SC 12"
width=1200px

read_all_entry="Mark all as read"

unread_count() {
	echo $(dunstctl count history)
}

build_menu() {
	# 读取通知
	mapfile -t DATA < <(
		dunstctl history | jq -r '
		.data[0][] |
		"\( .id.data )|\( .appname.data )|\( .summary.data | gsub("\n";"") )|\( .body.data | gsub("\n";" ") )|\( .timestamp.data )"
		'
	)
	# 获取系统 uptime（秒）
	uptime_sec=$(awk '{print int($1)}' /proc/uptime)
	for i in "${DATA[@]}"; do
		IFS="|" read -r id app summary body ts_micro <<<"$i"

		# dunst timestamp 是 microseconds
		ts_sec=$((ts_micro / 1000000))

		# 计算相对时间
		diff=$((uptime_sec - ts_sec))
		if ((diff < 60)); then
			rel_time="just now"
		elif ((diff < 3600)); then
			rel_time="$((diff / 60)) min ago"
		elif ((diff < 86400)); then
			rel_time="$((diff / 3600)) hr ago"
		else
			rel_time="$(date -d "@$(($(date +%s) - diff))" "+%m-%d %H:%M")"
		fi

		echo "$id [$rel_time] [$app]: $summary $body"
	done
	echo $read_all_entry
}

# Rofi CMD
rofi_cmd() {
	rofi \
		-dmenu \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str "mainbox {children: ["inputbar","listview"];}" \
		-theme-str "* {font: \"$font\";}" \
		-theme-str 'configuration {show-icons:false;}' \
		-theme-str 'window {width: '$width';}' \
		-p "$prompt" \
		-markup-rows \
		-theme ${theme} \
		-i \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

run() {
	[[ $(dunstctl count displayed) > 0 ]] && dunstctl close-all
	[[ $(dunstctl count history) = 0 ]] && return
	local chosen="$(build_menu | rofi_cmd)"
	[ -z "$chosen" ] && return

	case "$chosen" in
	"$read_all_entry") dunstctl history-clear ;;
	*)
		pop "$(echo $chosen | cut -d' ' -f1)"
		;;
	esac
}

pop() {
	local id=$1
	local timeout=${2:-5}
	dunstctl history-pop $id && sleep $timeout && dunstctl close $id && dunstctl history-rm $id &
}

case "$1" in
"unread") unread_count ;;
"pop-latest") pop "$(dunstctl history | jq -r '.data[0][0].id.data')" ;;
*) run ;;
esac
