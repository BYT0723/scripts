#!/bin/bash

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
icons["disk"]=" "
icons["memory"]=" "
icons["cpu"]=" "
icons["temp"]=" "
icons["mpd"]=" "

# seconds
weather_interval=600
weather_path="/tmp/.weather"

# Datetime
print_date() {
	timeIcons=('' '' '' '' '' '' '' '' '' '' '' '')
	# colorscheme
	printf "\x01^b$green^^c$grey^"
	# date '+ %m/%d(%a) '${timeIcons[$(echo $(date '+%l') | bc)]}' %R'
	date '+%m/%d(%a) '${timeIcons[$(echo $(date '+%l') | bc)]}' %R'
}

print_battery() {
	battery_icons=(' ' ' ' ' ' ' ' ' ')
	# battery_icons=('' '' '' '' '' '' '' '' '' '' '')
	charging_icons=('')
	percent=$(acpi -b | head -n 1 | grep -Eo '[0-9]+%' | sed -r 's/%//g')

	icon=${battery_icons[$(echo $percent"/20.01" | bc)]}

	# duration=$(acpi -b | awk '{print $5}')

	if $(acpi -b | head -n 1 | grep --quiet Discharging); then
		printf "\x02^c$white^^b$grey^"
	else
		printf "\x02^c$yellow^^b$grey^"
	fi

	# printf "$icon $percent"
	printf "$icon"
}

print_volume() {
	printf "\x03^c$white^^b$grey^"

	volume="$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)%\].*/\1/')"
	status="$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)\].*/\1/')"

	if [ "$volume" -eq 0 ]; then
		icon=""
	elif [ "$status" == "off" ]; then
		icon="婢"
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
	local disk_root=$(df -h | grep /dev/nvme0n1p6 | awk '{print $4}')
	# colorscheme
	printf "\x06^c$white^^b$black^"
	# output
	printf "${icons[disk]}$disk_root"
}

# Memory usage
print_mem() {
	# memory value
	local mem_val=$(free -h | awk 'NR==2 {print $3}' | sed s/i//g)
	# colorscheme
	printf "\x07^c$blue^^b$black^"
	# output
	printf "${icons[memory]}$mem_val"
}

print_cpu() {
	# cpu load value
	local cpu_val=$(grep -o "^[^ ]*" /proc/loadavg)
	# local cpu_percent=$(printf "%2.0f" $(iostat -c 1 2 | awk 'NR==9 {print $1}'))

	# colorscheme
	if [ $(echo "$cpu_val > $(nproc)" | bc) -eq 1 ]; then
		printf "\x08^c$black^^b$red^"
	else
		printf "\x08^c$white^^b$black^"
	fi
	# output
	# printf "${icons[cpu]}$cpu_percent%%"
	printf "${icons[cpu]}$cpu_val"

	if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
		temp=$(head -c 2 /sys/class/thermal/thermal_zone0/temp)
		if [ $temp -ge 70 ]; then
			printf "\x08^c$black^^b$red^"
		else
			printf "\x08^c$white^^b$black^"
		fi
		printf "${icons["temp"]}${temp}°C"
	fi
}

# Update weather to $weather_path
function update_weather() {
	# code=$(curl -I -s -o /dev/null -w "%{http_code}" "wttr.in?format=%c%t\n")
	# if [ "$code" != "200" ]; then
	# 	return
	# fi
	# more look at: https://github.com/chubin/wttr.in
	# 获取主机使用语言
	local language=$(echo $LANG | awk -F '_' '{print $1}')
	# weather=$(curl -H "Accept-Language:"$language -s -m 1 "wttr.in?format=%c%t\n")
	weather=$(curl -H "Accept-Language:"$language -s -m 1.5 "wttr.in?format=%C+%t\n")
	# weather=$(curl -H "Accept-Language:"$language -s -m 1 "wttr.in?format=%c%C+%t\n")
	if [ ! -z "$weather" ]; then
		echo $weather'?'$(date +'%Y-%m-%d %H:%M:%S') >$weather_path
	fi
}

print_weather() {
	printf "\x09^c$blue^^b$grey^"
	printf "$(cat $weather_path | awk -F '?' '{print $1}' | head -c 20)"

	# 计算两次请求时间间隔
	# 如果时间间隔超过$weather_interval秒,则更新天气状态
	local duration=$(($(date +%s) - $(date -d "$(cat $weather_path | awk -F '?' '{print $2}')" +%s)))
	if [ ! -f $weather_path ] || [ -z "$(cat $weather_path | awk -F '?' '{print $2}')" ] || [ $duration -gt $weather_interval ]; then
		update_weather
	fi
}

# Music Player Daemon
print_mpd() {
	if [[ -z "$(mpc status)" ]]; then
		return
	fi

	songName=$(mpc -f "%title% - %artist%" current)

	maxLen=16

	if [ ${#songName} -gt $maxLen ]; then
		songName=${songName:0:$(($maxLen - 2))}'..'
	fi

	# mpd play status
	if [[ $(mpc status) == *"[playing]"* ]]; then
		printf "\x0a^c$black^^b$darkblue^"
	else
		printf "\x0a^c$blue^^b$grey^"
	fi
	# output
	printf "${icons[mpd]} $songName"
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
