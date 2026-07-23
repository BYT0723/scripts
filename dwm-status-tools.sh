#!/bin/bash

WORK_DIR=$(dirname "$0")
source "$WORK_DIR/utils/weather.sh"
source "$WORK_DIR/utils/notify.sh"

# colorscheme
black=#1e222a
yellow=#ffff00
green=#7eca9c
white=#abb2bf
blue=#7aa2f7
cyan=#7dcfff
red=#d47d85

# load color from xrdb (.Xresources)
eval "$(
	xrdb -query | awk -F: '
	{
	  gsub(/^[ \t]+/, "", $2)
	  map[$1]=$2
	}

	END {
	  theme = map["dwm.col_theme"]

	  for (k in map) {
		if (k !~ /^dwm\.col_/) continue

		name = k
		sub(/^dwm\.col_/, "", name)

		# theme logic
		if (theme == "light") {
		  # light: prefer light_ if exists, fallback normal
		  if (name ~ /^light_/) {
			base = name
			sub(/^light_/, "", base)

			# ensure fallback exists
			if (map[k] != "") {
			  printf("%s=%s\n", base, map[k])
			}
		  }
		} else {
		  # dark: normal colors only
		  if (name !~ /^light_/) {
			printf("%s=%s\n", name, map[k])
		  }
		}
	  }
	}'
)"

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
weather_forecast_path="$cache_dir/weather-forecast"
traffic_rx_path="$cache_dir/network-traffic-rx"
traffic_tx_path="$cache_dir/network-traffic-tx"
mail_unread_path="$cache_dir/mail-unread"
rss_unread_path="$cache_dir/rss-unread"
mpd_status_path="$cache_dir/mpd-status"

mail_account_config=$HOME/.config/dwm/mail.json

# MPD
mpd_single_pane=0

# Datetime
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

update_cpu_daemon() {
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

update_traffic_daemon() {
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

update_mpd_daemon() {
	local retry_interval=${1:-1}
	while true; do
		# 尝试获取 MPD 状态，如果失败就说明 MPD 不可用
		if mpc status >/dev/null 2>&1; then
			[ ! -f "$mpd_status_path" ] && touch $mpd_status_path
			# 事件驱动循环
			mpc idleloop player | while read -r event; do
				state=$(mpc status '%state%')
				name=$(mpc current -f "%title% - %artist%")
				printf "%s|%s" "$name" "$state" >"$mpd_status_path"
			done

			rm -f $mpd_status_path
		else
			# 远程 MPD 没连接上，等待再试
			sleep $retry_interval
		fi
	done
}

# 用于长间隔更新
interval_update_daemon() {
	local interval=600
	local check_interval=60
	local max_time=30

	while getopts "i:c:m:" opt; do
		case $opt in
		i) interval=$OPTARG ;;
		c) check_interval=$OPTARG ;;
		m) max_time=$OPTARG ;;
		esac
	done

	shift $((OPTIND - 1))

	local last_slot=-1

	((check_interval > interval)) && check_interval=$interval

	while true; do
		now=$(date +%s)
		slot=$((now / interval))

		if ((slot != last_slot)); then
			last_slot=$slot

			if declare -F "$1" >/dev/null; then
				# 是函数 → 当前 shell 执行
				if ! "$@"; then
					system-notify critical "[DWM Status Interval Update Daemon]" "task timeout or failed: $*"
				fi
			else
				# 是命令 → 用 timeout
				if ! timeout "$max_time" "$@"; then
					system-notify critical "[DWM Status Interval Update Daemon]" "task timeout or failed: $*"
				fi
			fi

		fi

		sleep "$check_interval"
	done
}

update_weather() {
	local weather=$(ipinfo-openMeteo)
	[ -n "$weather" ] && echo "$weather" >"$weather_path" || true
}

update_weather_forecast() {
	alert=$(weather-forecast 12 "$weather_forecast_path")
	[ -n "$alert" ] && notify-send -u critical -i weather -h string:x-dunst-stack-tag:weatherAlert "Weather" "$alert" || true
}

# 通过imap更新未读邮件数量
# 不支持163邮箱，因为伞兵网易做了不信任客户端校验
update_mail() {
	local count=0
	local tmpfile
	tmpfile=$(mktemp) || return

	jq -r '.[] | select(.disabled!=true) | "machine \(.server) login \(.user) password \(.pass)"' "$mail_account_config" >"$tmpfile"

	while read -r server; do
		ws=$(curl -s --netrc-file "$tmpfile" "imaps://$server/INBOX;MAILINDEX=1" -X 'SEARCH UNSEEN' | wc -w)
		((ws > 2)) && ((count += ws - 2))
	done < <(jq -r '.[] | select(.disabled!=true) | .server' "$mail_account_config")

	rm -f "$tmpfile"
	echo "$count" >"$mail_unread_path"
}

update_rss() {
	[ -z "$(command -v newsboat)" ] && system-notify critical "Tool Not Found" "please install newsboat" && return

	newsboat -x print-unread 2>/dev/null | awk '{print $1}' >"$rss_unread_path"
}
