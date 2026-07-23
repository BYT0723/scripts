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

source "$(dirname "$0")/dwm-status-print.sh"
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
