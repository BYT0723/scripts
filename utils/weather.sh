#!/bin/bash

# jq: WMO 4677 天气代码映射（单一来源）
# 参考: https://www.nodc.noaa.gov/archive/arc0021/0002199/1.1/data/0-data/HTML/WMO-CODE/WMO4677.HTM
# - wmo_label / wmo_emoji: 用于预报展示, 按 code 细分(强度/形态)
# - wmo_alert_group:        用于告警分组, 粗粒度类别, 避免相邻 code 把告警拆得过碎
# - wmo_group_emoji / wmo_group_notice: 告警时按分组使用统一的图标和提示语
JQ_WMO='def wmo_label:
	if . == 0 then "晴"
	elif . == 1 then "少云"
	elif . == 2 then "多云"
	elif . == 3 then "阴"
	elif . >= 4 and . <= 9 then "霾/沙尘"
	elif . >= 10 and . <= 12 then "轻雾"
	elif . >= 13 and . <= 16 then "周边降水"
	elif . == 17 then "雷暴"
	elif . == 18 then "大风"
	elif . == 19 then "龙卷"
	elif . >= 20 and . <= 29 then "近时降水"
	elif . >= 30 and . <= 35 then "沙尘暴"
	elif . >= 36 and . <= 39 then "吹雪"
	elif . >= 40 and . <= 49 then "雾"
	elif . >= 50 and . <= 55 then "毛毛雨"
	elif . == 56 or . == 57 or . == 66 or . == 67 then "冻雨"
	elif . == 58 or . == 59 then "毛毛雨夹雨"
	elif . >= 60 and . <= 63 then "雨"
	elif . == 64 or . == 65 then "大雨"
	elif . == 68 or . == 69 or . == 83 or . == 84 then "雨夹雪"
	elif . >= 70 and . <= 73 then "雪"
	elif . == 74 or . == 75 then "大雪"
	elif . >= 76 and . <= 79 then "冰粒"
	elif . == 80 then "小阵雨"
	elif . == 81 then "强阵雨"
	elif . == 82 then "暴雨"
	elif . == 85 or . == 86 then "阵雪"
	elif . >= 87 and . <= 90 then "冰雹"
	elif . >= 91 and . <= 94 then "雷暴后降水"
	elif . == 96 or . == 99 then "雷暴伴冰雹"
	elif . == 98 then "雷暴伴沙尘"
	elif . >= 95 and . <= 99 then "雷暴"
	else "未知" end;
def wmo_emoji:
	if   . == 0 then "☀️"
	elif . == 1 then "🌤️"
	elif . == 2 then "⛅"
	elif . == 3 then "☁️"
	elif . >= 4 and . <= 9 then "🌫️"
	elif . >= 10 and . <= 12 then "🌫️"
	elif . == 13 then "⚡"
	elif . >= 14 and . <= 16 then "🌧️"
	elif . == 17 then "⛈️"
	elif . == 18 then "🌬️"
	elif . == 19 then "🌪️"
	elif . == 20 then "🌦️"
	elif . == 21 then "🌧️"
	elif . == 22 then "🌨️"
	elif . == 23 then "🌨️"
	elif . == 24 then "🧊"
	elif . == 25 then "🌧️"
	elif . == 26 then "🌨️"
	elif . == 27 then "🧊"
	elif . == 28 then "🌫️"
	elif . == 29 then "⛈️"
	elif . >= 30 and . <= 35 then "🌪️"
	elif . >= 36 and . <= 39 then "🌨️"
	elif . >= 40 and . <= 49 then "🌫️"
	elif . == 56 or . == 57 or . == 66 or . == 67 then "🧊"
	elif . >= 50 and . <= 59 then "🌦️"
	elif . >= 60 and . <= 65 then "🌧️"
	elif . == 68 or . == 69 or . == 83 or . == 84 then "🌨️"
	elif . >= 70 and . <= 75 then "🌨️"
	elif . == 76 or . == 79 then "🧊"
	elif . == 77 or . == 78 then "🌨️"
	elif . == 80 or . == 81 then "🌦️"
	elif . == 82 then "⛈️"
	elif . == 85 or . == 86 then "🌨️"
	elif . >= 87 and . <= 90 then "🧊"
	elif . >= 91 and . <= 92 then "🌧️"
	elif . == 93 or . == 94 then "🌨️"
	elif . == 95 or . == 97 then "⛈️"
	elif . == 96 or . == 99 then "🌩️"
	elif . == 98 then "🌪️"
	else "❓" end;
# 告警分组: 同组相邻时段会合并, 减少碎片
def wmo_alert_group:
	if   . == 19 then "龙卷"
	elif . == 82 then "暴雨"
	elif . == 56 or . == 57 or . == 66 or . == 67 then "冻雨"
	elif (. >= 87 and . <= 90) or . == 96 or . == 99 then "冰雹"
	elif . == 17 or (. >= 95 and . <= 99) then "雷暴"
	elif . >= 30 and . <= 35 then "沙尘暴"
	elif . >= 36 and . <= 39 then "吹雪"
	elif (. >= 70 and . <= 79) or . == 85 or . == 86 then "雪"
	elif . == 68 or . == 69 or . == 83 or . == 84 then "雨夹雪"
	elif . == 80 or . == 81 then "阵雨"
	elif . >= 91 and . <= 94 then "雷暴后降水"
	elif . >= 50 and . <= 65 then "雨"
	else "" end;
def wmo_group_emoji($g):
	if   $g == "龙卷"     then "🌪️"
	elif $g == "暴雨"     then "⛈️"
	elif $g == "冻雨"     then "🧊"
	elif $g == "冰雹"     then "🧊"
	elif $g == "雷暴"     then "⛈️"
	elif $g == "沙尘暴"   then "🌪️"
	elif $g == "吹雪"     then "🌨️"
	elif $g == "雪"       then "🌨️"
	elif $g == "雨夹雪"   then "🌨️"
	elif $g == "阵雨"     then "🌦️"
	elif $g == "雷暴后降水" then "⛈️"
	elif $g == "雨"       then "🌧️"
	else "⚠️" end;
def wmo_group_text($g):
	if   $g == "龙卷"     then "有龙卷风，立即避险"
	elif $g == "暴雨"     then "有暴雨，注意防范积水内涝"
	elif $g == "冻雨"     then "有冻雨，路面湿滑注意防摔"
	elif $g == "冰雹"     then "有冰雹，注意防护"
	elif $g == "雷暴"     then "有雷暴，注意防雷避险"
	elif $g == "沙尘暴"   then "有沙尘暴，减少外出注意防护"
	elif $g == "吹雪"     then "有吹雪，注意出行安全"
	elif $g == "雪"       then "有降雪，注意防滑御寒"
	elif $g == "雨夹雪"   then "有雨夹雪，注意保暖防滑"
	elif $g == "阵雨"     then "有阵雨，出行记得带伞"
	elif $g == "雷暴后降水" then "雷暴后仍有降水，注意安全"
	elif $g == "雨"       then "有降雨，出行记得带伞"
	else "有恶劣天气，注意出行安全" end;
def wmo_notice($group; $start; $end):
	(wmo_group_emoji($group) + " " + $start + "至" + $end + wmo_group_text($group));
def wmo_icon: "\(wmo_emoji) \(wmo_label)";
# 按视觉宽度计算字符串宽度: ASCII=1, 变体选择符 U+FE0F=0, 其余>127 视为 2(中文/emoji)
def vwidth: [explode[] | if . == 65039 then 0 elif . > 127 then 2 else 1 end] | add // 0;
def vpad($w): . + (if vwidth >= $w then "" else " " * ($w - vwidth) end);'

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
  ($h.weather_code[.] | wmo_icon | vpad(12)) as $w |
		  (
			if $temp == $tmax then "(H)"
			elif $temp == $tmin then "(L)"
			else "   "
			end
		  ) as $mark |
		  "\($t)  \($w)  \($temp)°C \($mark)"
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
			select(($h.weather_code[.] | wmo_alert_group) != "") |
			{
				i: .,
				t: ($h.time[.] | split("T")[1]),
				c: $h.weather_code[.],
				label: ($h.weather_code[.] | wmo_alert_group)
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
			(.[0].label) as $group |
			(.[0].t) as $start |
			(.[-1].t | split(":") | "\(.[0] | tonumber + 1 | tostring | if length == 1 then "0" + . else . end):\(.[1])") as $end |
			wmo_notice($group; $start; $end)
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

	curl -m 2 -fsS "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&models=cma_grapes_global&current_weather=true" |
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
