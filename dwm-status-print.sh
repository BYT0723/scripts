print_date() {
	timeIcons=('' '' '' '' '' '' '' '' '' '' '' '')
	local hour=$(date '+%l')
	if [ -f /tmp/dwm-status/date-collapse ]; then
		date '+'${timeIcons[$((hour % 12))]}' %R'
	else
		date '+ %m/%d(%a) '${timeIcons[$((hour % 12))]}' %R'
		# date '+ %Y-%m-%d(%a) '${timeIcons[$((hour % 12))]}' %R'
	fi
}

print_battery() {
	[ -z "$(command -v acpi)" ] && system-notify critical "Tool Not Found" "please install acpi" && return
	[ -z "$(acpi)" ] && return

	# icon style: 5 (coarse) or 11 (fine granularity)
	if [ "${BATTERY_ICON_STYLE:-11}" = "11" ]; then
		battery_icons=('' '' '' '' '' '' '' '' '󰂁' '󰂂' '󰁹')
		charging_icons=('󰢜' '󰢜' '󰂆' '󰂇' '󰂈' '󰢝' '󰂉' '󰢞' '󰂊' '󰂋' '󰂅')
	else
		battery_icons=('' '' '' '' '')
		charging_icons=('󰢜' '󰂇' '󰂉' '󰂊' '󰂅')
	fi

	IFS='|' read -r status percent < <(acpi -b | awk -F': |, |%' 'NR==1 {print $2"|"$3}')

	max_idx=$((${#battery_icons[@]} - 1))
	idx=$(((percent * max_idx + 50) / 100))

	if [[ "$status" == "Discharging" ]]; then
		icon=${battery_icons[$idx]}
		fg="$white"
	else
		icon=${charging_icons[$idx]}
		fg="$yellow"
	fi
	printf "^c$fg^$icon"
}

print_volume() {
	[ -z "$(command -v amixer)" ] && system-notify critical "Tool Not Found" "please install alsa-utils" && return

	read volume status < <(amixer get Master | awk -F'[][]' 'END{gsub(/%/,"",$2); print $2, $4}')

	if [ "$status" == "off" ]; then
		fg="$red"
		icon=""
	elif [ "$volume" -eq 0 ]; then
		fg="$yellow"
		icon=""
	else
		fg="$white"
		icon=""
	fi
	printf "^c$fg^$icon"
	# printf "%s %2d" $icon $volume
}

print_brightness() {
	# 获取第一个 backlight 设备
	local dev
	dev=$(ls /sys/class/backlight | head -n1) || return

	# 读取当前亮度和最大亮度
	local cur max percent
	cur=$(cat /sys/class/backlight/"$dev"/brightness)
	max=$(cat /sys/class/backlight/"$dev"/max_brightness)

	# 计算百分比
	percent=$((100 * cur / max))

	# 输出图标 + 百分比
	local icon="󰃟"
	printf "%s %2d%%" "$icon" "$percent"
}

print_wifi() {
	local wifi=$(iwgetid -r)
	local icon="󰖩"

	[ -z "$wifi" ] && icon="󰖪"

	printf "%s %s" $icon $wifi
}

# Disk free space size
# disk path in variable $disk_root
print_disk() {
	read avail usage < <(df -h / | awk 'NR==2 {gsub(/%/,"",$5);print $4" "$5}')
	local fg="$white"

	[ "$usage" -gt 90 ] && fg="$yellow"
	# output
	printf "^c$fg^${icons[disk]} $avail"
}

# Memory usage
print_mem() {
	read mem_usage mem_used < <(
		awk '
		/MemTotal:/     {total=$2}
		/MemAvailable:/ {avail=$2}
		END {
			used = total - avail
			usage = 100 * used / total
			printf "%d %.1fG", usage, used/1024/1024
		}' /proc/meminfo
	)
	fg="$white"

	[ "$mem_usage" -gt 90 ] && fg="$yellow"
	printf "^c$fg^${icons[memory]} $mem_used"
}

print_cpu() {
	read cpu_usage <"$cpu_usage_path"
	fg=$white

	((cpu_usage >= 80)) && fg="$yellow"

	# output
	printf "^c$fg^${icons[cpu]}%3d%%" "$cpu_usage"
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
			system-notify critical "[DWM STATUS BAR] Unsupported Arch" "unsupported arch $vendor to get cpu temperature" && return
			;;
		esac
	fi

	read temp <"$cpu_temperature_filepath"
	temp=$((temp / 1000))

	fg=$white

	[ $temp -ge 70 ] && fg="$yellow"

	printf "^c$fg^${icons["temp"]} ${temp}°C"
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
	[ ! -f "$mpd_status_path" ] && return

	IFS='|' read songname state <"$mpd_status_path"

	local fg="$white"

	# mpd play status
	[[ $state == "playing" ]] && fg="$blue"

	if [ $mpd_single_pane -gt 0 ]; then
		max_len_output "${icons[mpd]} $songname"
	else
		printf "^c$fg^${icons[mpd]}"
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
	pgrep sing-box >/dev/null && printf "^c$white^"
}

print_notification() {
	unread=$(dunstctl count history)
	((unread > 0)) && printf "^c$yellow^${icons["notification"]} $unread"
}
