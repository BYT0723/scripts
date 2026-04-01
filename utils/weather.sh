#!/bin/bash

# jq: WMO天气代码映射（单一来源）
JQ_WMO='def wmo_label:
	if . == 0 then "晴"
	elif . == 1 then "少云"
	elif . == 2 then "多云"
	elif . == 3 then "阴"
	elif . == 45 or . == 48 then "雾"
	elif . >= 50 and . <= 59 then "细雨"
	elif . >= 61 and . <= 69 then "雨"
	elif . >= 70 and . <= 79 then "雪"
	elif . >= 80 and . <= 88 then "阵雨"
	elif . >= 95 and . <= 99 then "雷暴"
	else "未知" end;
def wmo_emoji:
	if . == 0 then "☀"
	elif . == 1 then "🌤"
	elif . == 2 then "⛅"
	elif . == 3 then "☁"
	elif . == 45 or . == 48 then "🌫"
	elif . >= 50 and . <= 59 then "🌦"
	elif . >= 61 and . <= 69 then "🌧"
	elif . >= 70 and . <= 79 then "🌨"
	elif . >= 80 and . <= 88 then "⛈"
	elif . >= 95 and . <= 99 then "🌩"
	else "❓" end;
def wmo_icon: "\(wmo_emoji) \(wmo_label)";'

# 获取未来12小时天气预报，写入缓存文件，极端天气/降雨时发送通知
weather-forecast() {
	local forecast_hours=${1:-12}
	local cache_file=${2:-"/tmp/dwm-status/weather-forecast"}

	mkdir -p $(dirname "$cache_file")

	local LAT LON
	IFS=, read LAT LON < <(curl -fsS https://ipinfo.io/loc) || return 1

	local forecast_json=$(curl -fsS "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&timezone=auto&hourly=temperature_2m,weather_code&forecast_hours=${forecast_hours}&models=cma_grapes_global") || return 1
	[ -z "$forecast_json" ] && return 1

	echo "$forecast_json" | jq -r \
		--arg hours "$forecast_hours" \
		"$JQ_WMO"'
	  .hourly as $h |
	  ($h.temperature_2m | min) as $tmin |
	  ($h.temperature_2m | max) as $tmax |
	  "未来\($hours)小时天气变化\n温度: \($tmin)°C ~ \($tmax)°C\n\n" +
	  ([range($h.time | length)] |
		map(
		  ($h.time[.] | split("T")[1]) as $t |
		  ($h.temperature_2m[.]) as $temp |
		  ($h.weather_code[.] | wmo_icon) as $w |
		  (
			if $temp == $tmax then "(H)"
			elif $temp == $tmin then "(L)"
			else "   "
			end
		  ) as $mark |
		  "\($t)\t\($w)\t\($temp)°C \($mark)"
		) | join("\n"))
	' >"$cache_file"

	# 极端天气/降雨告警
	local alert
	alert=$(echo "$forecast_json" | jq -r "$JQ_WMO"'
		.hourly as $h |
		($h.temperature_2m | min) as $tmin |
		($h.temperature_2m | max) as $tmax |
		# 恶劣天气：合并同类型，标注起始时间
		([range($h.time | length)] | map(
			select($h.weather_code[.] >= 45) |
			{ t: ($h.time[.] | split("T")[1]), c: $h.weather_code[.] }
		) | group_by(.c | wmo_label) | map(
			(.[0].c | wmo_label) as $label |
			"  ⚠ \(.[0].t)起 \($label)，持续\(length)小时"
		)) as $weather_alerts |
		# 极端温度
		([if $tmin <= 0 then "  🥶 最低温 \($tmin)°C，注意保暖" else empty end] +
		 [if $tmax >= 35 then "  🔥 最高温 \($tmax)°C，注意防暑" else empty end] +
		 [if ($tmax - $tmin) > 8 then "  🌡 温差\($tmax - $tmin | round)°C，注意增减衣物" else empty end]) as $temp_alerts |
		($weather_alerts + $temp_alerts) |
		if length == 0 then empty
		else join("\n")
		end
	')
	echo $alert
}

ipinfo-openMeteo() {
	IFS=, read LAT LON < <(curl -fsS https://ipinfo.io/loc) || return 1

	read TEMP CODE < <(
		curl -fsS "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current_weather=true&models=cma_grapes_global" |
			jq -r '"\(.current_weather.temperature)\(.current_weather_units.temperature) \(.current_weather.weathercode)"'
	) || return 1

	case $CODE in
	0)
		WEATHER_TEXT="晴天"
		WEATHER_ICON=""
		;;
	1)
		WEATHER_TEXT="少量多云"
		WEATHER_ICON="🌤"
		;;
	2)
		WEATHER_TEXT="部分多云"
		WEATHER_ICON="⛅️"
		;;
	3)
		WEATHER_TEXT="阴天"
		WEATHER_ICON="☁️"
		;;
	45 | 48)
		WEATHER_TEXT="有雾"
		WEATHER_ICON="🌫"
		;;
	50 | 51 | 52 | 53 | 54 | 55 | 56 | 57 | 58 | 59)
		WEATHER_TEXT="毛毛雨/细雨"
		WEATHER_ICON="🌦"
		;;
	61 | 63 | 65 | 66 | 67 | 68 | 69)
		WEATHER_TEXT="下雨"
		WEATHER_ICON="🌧"
		;;
	70 | 71 | 72 | 73 | 74 | 75 | 76 | 77 | 78 | 79)
		WEATHER_TEXT="降雪"
		WEATHER_ICON="🌨"
		;;
	80 | 81 | 82 | 83 | 84 | 85 | 86 | 87 | 88)
		WEATHER_TEXT="阵雨/阵雪"
		WEATHER_ICON="⛈"
		;;
	95 | 96 | 97 | 98 | 99)
		WEATHER_TEXT="雷暴"
		WEATHER_ICON="🌩"
		;;
	*)
		WEATHER_TEXT="未知天气"
		WEATHER_ICON="❓"
		;;
	esac

	echo "$WEATHER_ICON $TEMP ($WEATHER_TEXT)"
}

wttr.in() {
	# 见: https://github.com/chubin/wttr.in#one-line-output
	local url="https://wttr.in?format=%c%t+(%C)\n"
	# 获取主机使用语言
	local language=$(echo $LANG | awk -F '_' '{print $1}')
	local response=$(curl -k -f -H "Accept-Language:"$language -s -m 5 "$url")

	if [ $? -eq 0 ]; then
		echo "$response"
	else
		return 1
	fi
}
