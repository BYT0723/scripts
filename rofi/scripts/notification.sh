#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_MESSAGE_DISABLE="true"
MODULE_WIDTH=800
MODULE_FONT="Noto Sans CJK SC 10"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

read_all_entry="Mark all as read"

unread_count() {
	echo $(dunstctl count history)
}

build_menu() {
	mapfile -t DATA < <(
		dunstctl history | jq -r '
		.data[0][] |
		"\( .id.data )|\( .appname.data )|\( .summary.data | gsub("\n";"") )|\( .body.data | gsub("\n";" ") )|\( .timestamp.data )"
		'
	)
	uptime_sec=$(awk '{print int($1)}' /proc/uptime)
	echo $read_all_entry
	for i in "${DATA[@]}"; do
		IFS="|" read -r id app summary body ts_micro <<<"$i"

		ts_sec=$((ts_micro / 1000000))

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

		local body_display="$body"
		if ((${#body_display} > 80)); then
			body_display="${body_display:0:80}…"
		fi
		if [[ -n "$body_display" ]]; then
			echo "$id $app · $summary: $body_display  ($rel_time)"
		else
			echo "$id $app · $summary  ($rel_time)"
		fi
	done
}

run() {
	[[ $(dunstctl count displayed) > 0 ]] && dunstctl close-all
	[[ $(dunstctl count history) = 0 ]] && return
	local chosen="$(build_menu | module_sub_rofi " Notifications")"
	[ -z "$chosen" ] && return

	case "$chosen" in
	"$read_all_entry") dunstctl history-clear ;;
	*) pop "${chosen%% *}" ;;
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
