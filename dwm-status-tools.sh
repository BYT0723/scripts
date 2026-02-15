#!/bin/bash

source "$(dirname $0)/utils/weather.sh"
source "$(dirname $0)/utils/notify.sh"

# colorscheme
black=#1e222a
yellow=#ffff00
green=#7eca9c
white=#abb2bf
grey=#282c34
blue=#7aa2f7
red=#d47d85
darkblue=#668ee3

# Icons initial
declare -A icons
icons["disk"]=""
icons["memory"]=""
icons["cpu"]=""
icons["temp"]=""
icons["mpd"]=""
icons["mail"]=""
icons["rss"]=""

cache_dir="/tmp/dwm-status"
mkdir -p $cache_dir

cpu_usage_path="$cache_dir/cpu_usage"
weather_path="$cache_dir/weather"
traffic_rx_path="$cache_dir/network-traffic-rx"
traffic_tx_path="$cache_dir/network-traffic-tx"
mail_unread_path="$cache_dir/mail-unread"
rss_unread_path="$cache_dir/rss-unread"

# MPD
mpd_show_name=0

# Datetime
print_date() {
	timeIcons=('' '' '' '' '' '' '' '' '' '' '' '')
	date '+ %m/%d(%a) '${timeIcons[$(echo $(date '+%l')'%12' | bc)]}' %R'
	# date '+ %Y-%m-%d(%a) '${timeIcons[$(echo $(date '+%l')'%12' | bc)]}' %R'
}

print_battery() {
	battery_icons=('' '' '' '' '')
	# battery_icons=('' '' '' '' '' '' '' '' '' '' '')
	charging_icons=('')
	percent=$(acpi -b | head -n 1 | grep -Eo '[0-9]+%' | sed -r 's/%//g')

	icon=${battery_icons[$(echo $percent"/20.01" | bc)]}

	# duration=$(acpi -b | awk '{print $5}')

	if $(acpi -b | head -n 1 | grep --quiet Discharging); then
		printf "^c$white^"
	else
		printf "^c$yellow^"
	fi

	# printf "$icon $percent"
	printf "$icon"
}

print_volume() {
	volume="$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)%\].*/\1/')"
	status="$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)\].*/\1/')"

	if [ "$status" == "off" ]; then
		icon=""
	elif [ "$volume" -eq 0 ]; then
		icon=""
	else
		icon=""
	fi
	# printf "%s %2d" $icon $volume
	printf "%s" $icon
}

print_brightness() {
	icon="󰃟 "
	printf "\x04^c$white^^b$black^"
	printf "%s%2d" $icon $(xbacklight -get)
}

print_wifi() {
	wifi=$(nmcli connection show -active | grep -E 'wifi' | awk '{print $1}')

	printf "\x05^b$black^^c$darkblue^"
	if [ "$wifi" == "" ]; then
		printf "󰖪"
	else
		printf "󰖩 $wifi"
	fi
}

# Disk free space size
# disk path in variable $disk_root
print_disk() {
	# root disk space value
	local disk_root=$(df -h | grep '/$' | awk '{print $4}')
	# root disk usage
	local disk_root_usage=$(df -h | grep '/$' | awk '{print $5}' | cut -d "%" -f1)

	if [ "$disk_root_usage" -gt 90 ]; then
		printf "^c$yellow^"
	else
		printf "^c$white^"
	fi
	# output
	printf "${icons[disk]} $disk_root"
}

# Memory usage
print_mem() {
	# memory value
	local mem_val=$(LANG= free -h | awk '/Mem:/ {print $3}' | sed s/i//g)
	# memory percent
	local mem_usage=$(LANG= free | awk '/Mem:/ {printf("%.0f\n", 100*(1-$7/$2))}')

	if [ "$mem_usage" -gt 80 ]; then
		printf "^c$yellow^"
	else
		printf "^c$white^"
	fi
	# output
	printf "${icons[memory]} $mem_val"
}

print_cpu() {
	local cpu_usage=$(cat "$cpu_usage_path")

	if ((cpu_usage >= 80)); then
		printf "^c$yellow^"
	else
		printf "^c$white^"
	fi

	# output
	printf "${icons[cpu]}%3d%%" "$cpu_usage"
}

print_temperature() {
	vendor=$(cat /proc/cpuinfo | grep "vendor_id" | head -n 1 | awk -F ':' '{print $2}' | xargs)
	case $vendor in
	"GenuineIntel")
		cpuIndex=$(cat -n /sys/class/thermal/thermal_zone*/type | grep "x86_pkg_temp$" | awk '{print $1 - 1}')
		if [ ! -z "$cpuIndex" ] && [ -f "/sys/class/thermal/thermal_zone$cpuIndex/temp" ]; then
			temp=$(head -c 2 /sys/class/thermal/thermal_zone$cpuIndex/temp)
		fi
		;;
	"AuthenticAMD")
		cpuIndex=$(cat -n /sys/class/hwmon/hwmon*/name | grep "k10temp$" | awk '{print $1 - 1}')
		if [ ! -z "$cpuIndex" ] && [ -f "/sys/class/hwmon/hwmon$cpuIndex/temp1_input" ]; then
			temp=$(head -c 2 "/sys/class/hwmon/hwmon$cpuIndex/temp1_input")
		fi
		;;
	*)
		notify-send "unsupported arch to get cpu temperature: "$vendor
		;;
	esac

	if [ ! -z "$temp" ] && [ $temp -ge 70 ]; then
		printf "^c$yellow^"
	else
		printf "^c$white^"
	fi
	printf "${icons["temp"]} ${temp}°C"
}

print_weather() {
	weather=$(cat $weather_path)
	[ ! -z "$weather" ] && printf "$weather"
}

# Music Player Daemon
print_mpd() {
	if [[ -z "$(mpc status 2>/dev/null)" ]]; then
		return
	fi

	# mpd play status
	if [[ $(mpc status) == *"[playing]"* ]]; then
		printf "^c$darkblue^"
	else
		printf "^c$white^"
	fi

	if [ $mpd_show_name -gt 0 ]; then
		songName=$(mpc -f "%title% - %artist%" current)

		maxLen=16

		if [ ${#songName} -gt $maxLen ]; then
			songName=${songName:0:$(($maxLen - 2))}'..'
		fi

		printf "${icons[mpd]} $songName"
	else
		printf "${icons[mpd]}"
	fi

}

human_speed() {
	local bytes=$1

	if ((bytes < 1024)); then
		printf "%5d B/s" "$bytes"
	elif ((bytes < 1024000)); then
		printf "%5.1f K/s" "$(bc -l <<<"$bytes/1024")"
	else
		printf "%5.1f M/s" "$(bc -l <<<"$bytes/1024000")"
	fi
}

# Network traffic
print_speed() {
	# output
	printf " $(human_speed $(cat $traffic_rx_path))  $(human_speed $(cat $traffic_tx_path))"
}

# Only fcitx and fcitx5 are supported
print_im() {
	if [ -x fcitx-remote ]; then
		cmd="fcitx-remote"
	fi
	if [ -x fcitx5-remote ]; then
		cmd="fcitx5-remote"
	fi

	case "$(fcitx5-remote -n)" in
	'keyboard-us')
		im="en"
		;;
	'pinyin')
		im="cn"
		;;
	'mozc')
		im="jp"
		;;
	'hangul')
		im="kr"
		;;
	esac
	printf "   $im"
}

print_mail() {
	unread=$(cat "$mail_unread_path")
	if [[ $unread > 0 ]]; then
		printf "${icons[mail]} $unread"
	fi
}

print_rss() {
	unread=$(cat "$rss_unread_path")
	if [[ $unread > 0 ]]; then
		printf "${icons[rss]} $unread"
	fi
}

update_cpu() {
	local interval=${1:-2}

	# 保存上一次采样
	local prev_total=0
	local prev_idle=0

	while true; do
		# 读取第一行 cpu 汇总
		read -r _ user nice system idle iowait irq softirq steal _ </proc/stat

		# idle 时间
		local idle_time=$((idle + iowait))

		# 总时间
		local total_time=$((user + nice + system + idle + iowait + irq + softirq + steal))

		# 第一次调用只初始化
		if ((prev_total == 0)); then
			prev_total=$total_time
			prev_idle=$idle_time
			echo 0 >"$cpu_usage_path"

			sleep $interval
			continue
		fi

		# 差值
		local delta_total=$((total_time - prev_total))
		local delta_idle=$((idle_time - prev_idle))

		# 保存
		prev_total=$total_time
		prev_idle=$idle_time

		((delta_total == 0)) && sleep $interval && continue

		# 计算使用率
		local usage=$(((100 * (delta_total - delta_idle)) / delta_total))

		echo $usage >"$cpu_usage_path"

		sleep $interval
	done
}

update_traffic() {
	local interval=${1:-1}
	local iface prev_rx prev_tx now_rx now_tx

	while true; do
		iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5}' | head -n1)

		if [[ -z $iface ]]; then
			sleep 1
			continue
		fi

		[ -z $prev_rx ] && read prev_rx </sys/class/net/$iface/statistics/rx_bytes
		[ -z $prev_tx ] && read prev_tx </sys/class/net/$iface/statistics/tx_bytes

		sleep $interval

		read now_rx </sys/class/net/$iface/statistics/rx_bytes
		read now_tx </sys/class/net/$iface/statistics/tx_bytes

		echo $((now_rx - prev_rx)) >"$traffic_rx_path"
		echo $((now_tx - prev_tx)) >"$traffic_tx_path"

		prev_rx=$now_rx
		prev_tx=$now_tx
	done
}

update_weather() {
	local interval=${1:-300}
	while true; do
		weather=$(wttr.in)
		[ -z "$weather" ] && weather=$(ipinfo-openMeteo)
		echo "$weather" >"$weather_path"
		sleep $interval
	done

}

update_mail() {
	local interval=${1:-300}

	[ -z "$(command -v offlineimap)" ] && system-notify critical "Tool Not Found" "please install offlineimap" && return
	[ -z "$(command -v notmuch)" ] && system-notify critical "Tool Not Found" "please install notmuch" && return

	while true; do
		output=$(offlineimap -o >>/dev/null)
		if [ ! -z "$output" ]; then
			notify-send -u critical -i mail-unread-symbolic "Mailbox synchronization failed:"$output
			sleep $interval
			continue
		fi

		notmuch new
		unread=$(notmuch count tag:unread)

		echo $unread >"$mail_unread_path"

		if [ $unread -gt 0 ]; then
			notify-send -i mail-unread-symbolic "$(notmuch search --output=files tag:unread | cut -d/ -f5 | sort | uniq -c | awk '{print "[" $2 "] \t" $1 "封新邮件"}')"
		fi

		sleep $interval
	done
}

update_rss() {
	local interval=${1:-300}

	[ -z "$(command -v newsboat)" ] && system-notify critical "Tool Not Found" "please install newsboat" && return

	while true; do
		echo "$(newsboat -x print-unread | awk '{print $1}')" >"$rss_unread_path"
		sleep $interval
	done
}
