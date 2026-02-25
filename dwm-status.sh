#!/usr/bin/env /bin/bash

source "$(dirname $0)/dwm-status-tools.sh"

DWM_STATUS_LEFT_RADIUS="^(^"
DWM_STATUS_RIGHT_RADIUS="^)^"
SING_BOX_CONFIG="/etc/sing-box/config.json"

# $1: background color
# ${@:2} tools...
new_pane() {
	fg=$1
	shift

	if [[ $1 =~ ^(\\x[0-9a-fA-F]{2})(.*) ]]; then
		first_status_code="${BASH_REMATCH[1]}" # 控制字符
		first_text="${BASH_REMATCH[2]}"        # 剩余内容
	else
		first_text=$1
	fi
	shift

	printf "%s" "^b$fg^$first_status_code$DWM_STATUS_LEFT_RADIUS$first_text$@$DWM_STATUS_RIGHT_RADIUS"
}

panes() {
	local panes
	panes+="$(new_pane $grey "\x0b^c$white^$(print_speed)")"
	weather=$(print_weather)
	[[ ! -z "$weather" ]] && panes+="$(new_pane $grey "\x09^c$blue^$weather")"

	if [ -f "$SING_BOX_CONFIG" ]; then
		host=$(get_sing_box_outbound_host $SING_BOX_CONFIG "trojan-out")
		tls_conns=$(print_tls_count "$host" "")
		[[ ! -z "$tls_conns" ]] && panes+="$(new_pane $grey "\x0e^c$yellow^$tls_conns")"
	fi

	panes+="$(new_pane $grey "\x08$(print_cpu)$(print_temperature)" "\x07$(print_mem)" "\x06$(print_disk)")"
	panes+="$(new_pane $grey "\x0a$(print_mpd)" "\x0d^c$yellow^$(print_rss)" "\x0c^c$yellow^$(print_mail)" "\x03^c$white^$(print_volume)" "\x02$(print_battery)")"
	panes+="$(new_pane $green "\x01^c$black^$(print_date)")"
	echo -e "$panes"
}

refresh_status() {
	local interval=${1:-1}
	# loop dwm-status-refresh.sh to refresh statusBar
	while true; do
		xsetroot -name "$(panes)"
		# refresh interval
		sleep $interval
	done
}

launch() {
	update_cpu &
	update_traffic &
	# update_mail &
	update_weather &
	update_rss &
	refresh_status
}

reboot() {
	for pid in $(pgrep -f "[d]wm-status.sh"); do
		[[ $pid == $$ ]] && continue
		kill $pid
		# waitpid is a utility from util-linux package, it waits for the process to terminate.
		waitpid $pid
	done

	launch &
}

case "$1" in
"reboot")
	reboot
	;;
*)
	launch
	;;
esac
