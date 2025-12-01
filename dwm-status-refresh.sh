#!/bin/bash

# statusBar Environment
source $(dirname $0)/dwm-status-tools.sh
source $(dirname $0)/tools/monitor.sh

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

print_core() {
	printf "^b$black^"
	printf "\x08^(^$(print_cpu)$(print_temperature)"
	printf "\x07$(print_mem)"
	printf "\x06$(print_disk)"
	printf "^)^"
}

print_system_tools() {
	printf "^b$grey^"
	printf "\x0a^b$grey^^(^$(print_mpd)"
	printf "\x0d^c$yellow^$(print_rss)"
	printf "\x0c^c$yellow^$(print_mail)"
	printf "\x03^c$white^$(print_volume)"
	printf "\x02$(print_battery)"
	printf "^)^"
	printf "\x01^b$green^^c$grey^^(^$(print_date)^)^"
}

print_other_tools() {
	printf "\x0b^b$grey^^c$white^^(^$(print_speed)^)^"
	printf "\x09^c$blue^^b$grey^^(^$(print_weather)^)^"
}

xsetroot -name "$(print_other_tools)$(print_core)$(print_system_tools)"

# Update old values to perform new calculation
old_received_bytes=$received_bytes
old_transmitted_bytes=$transmitted_bytes
old_time=$now

exit 0
