#!/usr/bin/env /bin/bash

source "$(dirname $0)/dwm-status-tools.sh"

DWM_STATUS_LEFT_RADIUS="^(^"
DWM_STATUS_RIGHT_RADIUS="^)^"

# $1: background color
# ${@:2} tools...
new_pane() {
	fg=$1
	shift

	case "$1" in
	\\x??*)
		first_status_code="${1:0:4}"
		first_text="${1:4}"
		;;
	*)
		first_text="$1"
		;;
	esac
	shift

	printf "%s" "^b$fg^$first_status_code$DWM_STATUS_LEFT_RADIUS$first_text$@$DWM_STATUS_RIGHT_RADIUS"
}

panes() {
	local panes
	local weather_str=$(print_weather)
	local rss_str=$(print_rss)
	local mail_str=$(print_mail)
	local notification_str=$(print_notification)
	local mpd_str=$(print_mpd)

	[ -n "$weather_str" ] && panes+="$(new_pane $black "\x09^c$blue^$weather_str")"
	[ $mpd_single_pane -gt 0 ] && [ -n "$mpd_str" ] && panes+="$(new_pane $black "\x0a$mpd_str")"

	# net traffic monitor pane
	panes+="$(new_pane $black "\x0b^c$white^$(print_speed)")"
	# system monitor pane
	panes+="$(new_pane $black "\x08$(print_cpu)$(print_temperature)" "\x07$(print_mem)" "\x06$(print_disk)")"

	# notification pane
	if [[ -n $rss_str || -n $mail_str || -n $notification_str ]]; then
		panes+="$(new_pane $black "\x0d$rss_str" "\x0c$mail_str" "\x0f$notification_str")"
	fi

	# one icon tools pane
	[ "$mpd_single_pane" -eq 0 ] && mpd_part="\x0a$mpd_str"

	panes+="$(new_pane $black "\x0e$(print_singbox)" "$mpd_part" "\x03$(print_volume)" "\x02$(print_battery)")"
	# datetime pane
	panes+="$(new_pane $black "\x01^c$cyan^$(print_date)")"

	printf "%b\n" "$panes"
}

launch_daemon() {
	local pids=()
	mkdir -p /tmp/dwm-status

	update_cpu_daemon &
	pids+=($!)
	update_traffic_daemon &
	pids+=($!)
	interval_update_daemon -i 1800 update_weather &
	pids+=($!)
	interval_update_daemon -i 3600 update_weather_forecast &
	pids+=($!)
	interval_update_daemon -i 300 update_mail &
	pids+=($!)
	interval_update_daemon -i 300 update_rss &
	pids+=($!)
	update_mpd_daemon &
	pids+=($!)

	# 保存当前进程 PID
	echo $BASHPID >/tmp/dwm-status/status-daemon-pid

	# 退出时杀掉所有子进程
	trap 'kill "${pids[@]}" 2>/dev/null; rm -f /tmp/dwm-status/status-daemon-pid' EXIT

	# Keep daemon running
	wait
}

launch_refresh() {
	mkdir -p /tmp/dwm-status

	# 保存当前进程 PID
	echo $BASHPID >/tmp/dwm-status/status-refresh-pid

	trap 'rm -f /tmp/dwm-status/status-refresh-pid' EXIT

	local interval=${1:-1}
	# loop dwm-status-refresh.sh to refresh statusBar
	while true; do
		xsetroot -name "$(panes)"
		# refresh interval
		sleep $interval
	done
}

reboot_daemon() {
	local pid_file="/tmp/dwm-status/status-daemon-pid"
	if [ -f "$pid_file" ]; then
		local pid=$(cat "$pid_file")
		kill $pid 2>/dev/null
		waitpid $pid 2>/dev/null
	fi

	launch_daemon &
}

reboot_refresh() {
	local pid_file="/tmp/dwm-status/status-refresh-pid"
	if [ -f "$pid_file" ]; then
		local pid=$(cat "$pid_file")
		kill $pid 2>/dev/null
		waitpid $pid 2>/dev/null
	fi

	launch_refresh &
}

case "$1" in
"reboot")
	reboot_daemon
	reboot_refresh
	;;
"reboot-daemon")
	reboot_daemon
	;;
"reboot-refresh")
	reboot_refresh
	;;
*)
	launch_daemon &
	launch_refresh &

	wait
	;;
esac
