#!/bin/bash

# statusBar Environment
source $(dirname $0)/dwm-status-tools.sh

function get_bytes {
	# Find active network interface
	interface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5}')
	line=$(grep $interface /proc/net/dev | cut -d ':' -f 2 | awk '{print "received_bytes="$1, "transmitted_bytes="$9}')
	eval $line
	now=$(date +%s%N)
}

# Function which calculates the speed using actual and old byte number.
# Speed is shown in KByte per second when greater or equal than 1 KByte per second.
# This function should be called each second.

function get_velocity {
	value=$1
	old_value=$2
	now=$3

	timediff=$(($now - $old_time))
	velKB=$(echo "1000000000*($value-$old_value)/1024/$timediff" | bc)
	if [ $velKB -gt 1000 ]; then
		# echo $(echo "scale=2; $velKB/1024" | bc)M/s
		printf "%4.1fM/s" $(echo "scale=1; $velKB/1024" | bc)
	else
		# echo ${velKB}K/s
		printf "%4dK/s" ${velKB}
	fi
}

# Get initial values
get_bytes
old_received_bytes=$received_bytes
old_transmitted_bytes=$transmitted_bytes
old_time=$now

get_bytes

# Calculates velocity
vel_recv="$(get_velocity $received_bytes $old_received_bytes $now)"
vel_trans="$(get_velocity $transmitted_bytes $old_transmitted_bytes $now)"

# Network velocity
print_speed() {
	# define the calculated upper and lower symbols
	local recvIcon=""
	local transIcon=""
	# output
	printf "${recvIcon} $vel_recv ${transIcon} $vel_trans"
}

DWM_STATUS_LEFT_RADIUS="^(^"
DWM_STATUS_RIGHT_RADIUS="^)^"

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
	if [[ ! -z "$weather" ]]; then
		panes+="$(new_pane $grey "\x09^c$blue^$weather")"
	fi
	panes+="$(new_pane $grey "\x08$(print_cpu)$(print_temperature)" "\x07$(print_mem)" "\x06$(print_disk)")"
	panes+="$(new_pane $grey "\x0a$(print_mpd)" "\x0d^c$yellow^$(print_rss)" "\x0c^c$yellow^$(print_mail)" "\x03^c$white^$(print_volume)" "\x02$(print_battery)")"
	panes+="$(new_pane $green "\x01^c$black^$(print_date)")"
	echo -e "$panes"
}

xsetroot -name "$(panes)"

# Update old values to perform new calculation
old_received_bytes=$received_bytes
old_transmitted_bytes=$transmitted_bytes
old_time=$now

exit 0
