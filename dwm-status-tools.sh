#!/bin/bash

WORK_DIR=$(dirname $0)
source "$WORK_DIR/utils/weather.sh"
source "$WORK_DIR/utils/notify.sh"

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
icons["notification"]=""
icons["rss"]=""

cache_dir="/tmp/dwm-status"
mkdir -p "$cache_dir"

cpu_usage_path="$cache_dir/cpu_usage"
weather_path="$cache_dir/weather"
traffic_rx_path="$cache_dir/network-traffic-rx"
traffic_tx_path="$cache_dir/network-traffic-tx"
mail_unread_path="$cache_dir/mail-unread"
rss_unread_path="$cache_dir/rss-unread"

sing_box_config="/etc/sing-box/config.json"

# MPD
mpd_single_pane=0

# Datetime
print_date() {
	timeIcons=('' '' '' '' '' '' '' '' '' '' '' '')
	local hour=$(date '+%l')
	date '+ %m/%d(%a) '${timeIcons[$((hour % 12))]}' %R'
	# date '+ %Y-%m-%d(%a) '${timeIcons[$((hour % 12))]}' %R'
}

print_battery() {
	[ -z "$(command -v acpi)" ] && system-notify critical "Tool Not Found" "please install acpi" && return
	[ -z "$(acpi)" ] && return

	battery_icons=('' '' '' '' '')
	# battery_icons=('' '' '' '' '' '' '' '' '' '' '')
	charging_icons=('')
	read status percent remain < <(acpi -b | awk 'NR==1 {gsub(/%,/,"",$4);gsub(/,/,"",$3); print $3" "$4}')

	icon=${battery_icons[$(((percent - 1) / 20))]}

	[[ "$status" == "Discharging" ]] && printf "^c$white^" || printf "^c$yellow^"

	# printf "$icon $percent"
	printf "$icon"
}

print_volume() {
	[ -z "$(command -v amixer)" ] && system-notify critical "Tool Not Found" "please install alsa-utils" && return

	read volume status < <(amixer get Master | awk -F'[][]' 'END{gsub(/%/,"",$2); print $2, $4}')

	if [ "$status" == "off" ]; then
		printf "^c$red^"
	elif [ "$volume" -eq 0 ]; then
		printf "^c$yellow^"
	else
		printf "^c$white^"
	fi
	# printf "%s %2d" $icon $volume
}

print_brightness() {
	icon="󰃟 "
	printf "%s%2d" $icon $(xbacklight -get)
}

print_wifi() {
	wifi=$(nmcli -f NAME,TYPE connection show --active | awk '$2=="wifi"{print $1}')

	if [ "$wifi" == "" ]; then
		printf "󰖪"
	else
		printf "󰖩 $wifi"
	fi
}

# Disk free space size
# disk path in variable $disk_root
print_disk() {
	read avail usage < <(df -h / | awk 'NR==2 {gsub(/%/,"",$5);print $4" "$5}')

	[ "$usage" -gt 90 ] && printf "^c$yellow^" || printf "^c$white^"
	# output
	printf "${icons[disk]} $avail"
}

# Memory usage
print_mem() {
	# memory value
	local mem_used=$(free -h | awk 'NR==2 {print $3}')
	# memory percent
	local mem_usage=$(free | awk 'NR==2 {printf("%.0f\n", 100*(1-$3/$2))}')

	[ "$mem_usage" -gt 90 ] && printf "^c$yellow^" || printf "^c$white^"
	# output
	printf "${icons[memory]} $mem_used"
}

print_cpu() {
	read cpu_usage <"$cpu_usage_path"

	((cpu_usage >= 80)) && printf "^c$yellow^" || printf "^c$white^"

	# output
	printf "${icons[cpu]}%3d%%" "$cpu_usage"
}

cpu_temperature_filepath=""

print_temperature() {
	if [ -z "$cpu_temperature_filepath" ]; then
		vendor=$(awk '$1=="vendor_id" {print $3;exit}' /proc/cpuinfo)
		case $vendor in
		"GenuineIntel")
			cpu_temperature_filepath=$(awk '$1=="x86_pkg_temp" {sub("/[^/]+$","",FILENAME); print FILENAME}' /sys/class/thermal/thermal_zone*/type)"/temp"
			;;
		"AuthenticAMD")
			cpu_temperature_filepath=$(awk '$1=="k10temp" {sub("/[^/]+$","",FILENAME); print FILENAME}' /sys/class/hwmon/hwmon*/name)"/temp1_input"
			;;
		*)
			system-notify critical "[DWM STATUS BAR] Unsupport Arch" "unsupport arch $vendor to get cpu temperature" && return
			;;
		esac
	fi

	read temp <"$cpu_temperature_filepath"
	temp=$((temp / 1000))

	[ $temp -ge 70 ] && printf "^c$yellow^" || printf "^c$white^"

	printf "${icons["temp"]} ${temp}°C"
}

max_len_output() {
	local input=$1
	local len=${2:-16}
	[ ${#input} -le $len ] && printf "%s" "$input" || printf "%s..." "${input:0:len-3}"
}

print_weather() {
	read -r weather <"$weather_path"
	[ -n "$weather" ] && max_len_output "$weather"
}

# Music Player Daemon
print_mpd() {
	local mpc_out=$(mpc status 2>/dev/null)

	[[ -z "$mpc_out" ]] && return

	# mpd play status
	[[ $mpc_out == *"[playing]"* ]] && printf "^c$darkblue^" || printf "^c$white^"

	if [ $mpd_single_pane -gt 0 ]; then
		songName=$(mpc -f "%title% - %artist%" current)
		max_len_output "${icons[mpd]} $songName"
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
	read rx <"$traffic_rx_path"
	read tx <"$traffic_tx_path"
	# output
	printf " "
	human_speed $rx
	printf "  "
	human_speed $tx
}

print_mail() {
	read unread <"$mail_unread_path"
	(($unread > 0)) && printf "^c$yellow^${icons[mail]} $unread"
}

print_rss() {
	read unread <"$rss_unread_path"
	(($unread > 0)) && printf "^c$yellow^${icons[rss]} $unread"
}

print_singbox() {
	[ -f "$sing_box_config" ] && pgrep sing-box >/dev/null && printf "^c$white^"
}

print_notification() {
	unread=$(/bin/bash $WORK_DIR/rofi/scripts/notification.sh unread)
	((unread > 0)) && printf "^c$yellow^${icons["notification"]} $unread"
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
	local iface last_iface prev_rx prev_tx now_rx now_tx

	while true; do
		read iface < <(awk '$2=="00000000"{print $1; exit}' /proc/net/route)

		if [[ -z $iface || ! -e /sys/class/net/$iface/statistics/rx_bytes ]]; then
			sleep "$interval"
			continue
		fi

		# 接口变化重置
		if [[ "$iface" != "$last_iface" ]]; then
			read prev_rx </sys/class/net/$iface/statistics/rx_bytes
			read prev_tx </sys/class/net/$iface/statistics/tx_bytes
			last_iface=$iface
			sleep "$interval"
			continue
		fi

		[ -z "$prev_rx" ] && read prev_rx </sys/class/net/$iface/statistics/rx_bytes
		[ -z "$prev_tx" ] && read prev_tx </sys/class/net/$iface/statistics/tx_bytes

		sleep "$interval"

		read now_rx </sys/class/net/$iface/statistics/rx_bytes
		read now_tx </sys/class/net/$iface/statistics/tx_bytes

		echo $((now_rx >= prev_rx ? (now_rx - prev_rx) / interval : 0)) >"$traffic_rx_path"
		echo $((now_tx >= prev_tx ? (now_tx - prev_tx) / interval : 0)) >"$traffic_tx_path"

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

		# FIX: 放弃通知，由于没有做唯一判断，会反复发送重复通知
		# if [ $unread -gt 0 ]; then
		# 	notify-send -i mail-unread-symbolic "$(notmuch search --output=files tag:unread | cut -d/ -f5 | sort | uniq -c | awk '{print "[" $2 "] \t" $1 "封新邮件"}')"
		# fi

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
