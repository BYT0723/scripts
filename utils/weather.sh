#!/bin/bash

# jq: WMO天气代码映射（单一来源）
JQ_WMO='def wmo_label:
	if . == 0 then "晴"
	elif . == 1 then "少云"
	elif . == 2 then "多云"
	elif . == 3 then "阴"
	elif . == 45 or . == 48 then "雾"
	elif . >= 50 and . <= 59 then "小雨"
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
def wmo_notice($code; $start; $end):
	(($code | wmo_emoji) + " " + $start + "至" + $end +
	 if $code >= 50 and $code <= 59 then
		"有小雨，出行记得带伞"
	 elif $code >= 61 and $code <= 69 then
		"有降雨，出行记得带伞"
	 elif $code >= 70 and $code <= 79 then
		"有降雪，出行注意御寒"
	 elif $code >= 80 and $code <= 88 then
		"有阵雨，不建议出门哦"
	 elif $code >= 95 and $code <= 99 then
		"有雷暴天气，在家躲好哦"
	 else
		"有未知天气变化，请注意出行安全"
	 end);
def wmo_icon: "\(wmo_emoji) \(wmo_label)";'

# 获取未来12小时天气预报，写入缓存文件，极端天气/降雨时发送通知
weather-forecast() {
	local forecast_hours=${1:-12}
	local cache_file=${2:-"/tmp/dwm-status/weather-forecast"}

	mkdir -p $(dirname "$cache_file")

	IFS=, read LAT LON < <(curl -m 2 -fsS https://ipinfo.io/loc) || return 1

	local forecast_json=$(curl -m 5 -fsS "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&timezone=auto&hourly=temperature_2m,weather_code&forecast_hours=${forecast_hours}") || return 1
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
		# 恶劣天气：按“连续时段”分组（同类型但不连续会拆分）
		([range($h.time | length)] | map(
			select($h.weather_code[.] >= 50) |
			{
				i: .,
				t: ($h.time[.] | split("T")[1]),
				c: $h.weather_code[.],
				label: ($h.weather_code[.] | wmo_label)
			}
		) | reduce .[] as $e (
			[];
			if length == 0 then
				[[ $e ]]
			else
				(.[-1][-1]) as $prev |
				if ($e.label == $prev.label and $e.i == ($prev.i + 1)) then
					.[0:-1] + [ (.[-1] + [ $e ]) ]
				else
					. + [[ $e ]]
				end
			end
		) | map(
			(.[0].c) as $code |
			(.[0].t) as $start |
			(.[-1].t | split(":") | "\(.[0] | tonumber + 1 | tostring | if length == 1 then "0" + . else . end):\(.[1])") as $end |
			wmo_notice($code; $start; $end)
		)) as $weather_alerts |
		# 极端温度
		([if $tmin <= 0 then "🥶最低温 \($tmin)°C，注意保暖" else empty end] +
		 [if $tmax >= 35 then "🔥 最高温 \($tmax)°C，注意防暑" else empty end] +
		 [if ($tmax - $tmin) >= 10 then "温差过大\($tmax - $tmin | round)°C，注意增减衣物" else empty end]) as $temp_alerts |
		($weather_alerts + $temp_alerts) |
		if length == 0 then empty
		else join("\n")
		end
	')
	echo "$alert"
}

ipinfo-openMeteo() {
	IFS=, read LAT LON < <(curl -m 2 -fsS https://ipinfo.io/loc) || return 1

	curl -m 2 -fsS "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current_weather=true" |
		jq -r "$JQ_WMO"'
			.current_weather.weathercode as $code |
			.current_weather.temperature as $temp |
			.current_weather_units.temperature as $unit |
			"\($code | wmo_emoji) \($temp)\($unit) (\($code | wmo_label))"
		'
}

wttr.in() {
	# 见: https://github.com/chubin/wttr.in#one-line-output
	local url="https://wttr.in?format=%c%t+(%C)\n"
	# 获取主机使用语言
	local language=$(echo $LANG | awk -F '_' '{print $1}')
	local response=$(curl -k -f -H "Accept-Language:"$language -s -m 2 "$url")

	if [ $? -eq 0 ]; then
		echo "$response"
	else
		return 1
	fi
}
