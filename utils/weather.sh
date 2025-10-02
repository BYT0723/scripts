#!/bin/bash

ipinfo-openMeteo() {
	RESP=$(curl -s https://ipinfo.io)
	if [ $? -ne 0 ]; then
		return 1
	fi
	CITY=$(echo $RESP | jq -r '.city')
	LATLON=$(echo $RESP | jq -r '.loc')
	LAT=$(echo $LATLON | cut -d',' -f1)
	LON=$(echo $LATLON | cut -d',' -f2)

	RESP=$(curl -s "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current_weather=true")
	if [ $? -ne 0 ]; then
		return 1
	fi

	TEMP="$(echo $RESP | jq '.current_weather.temperature')$(echo $RESP | jq -r '.current_weather_units.temperature')"
	CODE=$(echo $RESP | jq '.current_weather.weathercode')

	case $CODE in
	0)
		WEATHER_TEXT="晴天"
		WEATHER_ICON="🌞"
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
