#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_WIDTH=550
MODULE_NAME="󰄟 Scrcpy"
MODULE_SEARCH_BAR="true"
MODULE_FONT="JetBrains Mono Nerd Font 14"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

SCRCPY_FLAGS=" \
--video-codec=h265 \
--video-bit-rate=8M \
--max-size=1600 \
--max-fps=60 \
--keyboard=uhid \
--turn-screen-off \
--power-off-on-close \
"

_sanitize_key() {
	echo "$1" | tr -c '[:alnum:]' '_'
}

_device_pid_file() {
	echo "/tmp/scrcpy_pid_$(_sanitize_key "$1")"
}

_check_deps() {
	if ! command -v adb &>/dev/null; then
		notify-send -c tools -i dialog-error "Scrcpy" "adb not found. Please install android-tools."
		exit 1
	fi
	if ! command -v scrcpy &>/dev/null; then
		notify-send -c tools -i dialog-error "Scrcpy" "scrcpy not found."
		exit 1
	fi
}

_get_devices() {
	adb devices -l 2>/dev/null | grep -w device | grep -v '_adb-tls-connect' | while read -r serial _ rest; do
		local model=$(echo "$rest" | grep -oP 'model:\K\S+')
		[ -n "$model" ] && echo "${serial} (${model//_/ })" || echo "$serial"
	done
}

_is_device_connected() {
	local pid_file=$(_device_pid_file "$1")
	if [ -f "$pid_file" ]; then
		kill -0 "$(cat "$pid_file")" 2>/dev/null && return 0
		rm -f "$pid_file"
	fi
	return 1
}

_connect() {
	local serial="$1"
	nohup scrcpy ${SCRCPY_FLAGS} -s "$serial" >/dev/null 2>&1 &
	echo $! >"$(_device_pid_file "$serial")"
}

_disconnect() {
	local pid_file=$(_device_pid_file "$1")
	if [ -f "$pid_file" ]; then
		kill "$(cat "$pid_file")" 2>/dev/null
		rm -f "$pid_file"
	fi
}

_check_deps

devices=$(_get_devices)

declare -A _device_map
menu_lines=""

if [ -n "$devices" ]; then
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		serial=$(echo "$line" | awk '{print $1}')
		key="device_$(_sanitize_key "$serial")"
		_device_map[$key]="$serial"

		if _is_device_connected "$serial"; then
			icon=""
		else
			icon=""
		fi

		printf -v _line "%s|%s|%s||\n" "$key" "$icon" "$line"
		menu_lines+="$_line"
	done <<<"$devices"
fi

printf -v _line "%s|%s|%s||\n" "wireless-connect" "󰈀" "Wireless Connect"
menu_lines+="$_line"
printf -v _line "%s|%s|%s||\n" "wireless-pair" "󰐺" "Pair New Device"
menu_lines+="$_line"

module_parse <<<"$menu_lines"

connected=0
for key in "${!_device_map[@]}"; do
	serial="${_device_map[$key]}"
	if _is_device_connected "$serial"; then
		eval "handle_${key}() { _disconnect '${serial}'; }"
		((connected++))
	else
		eval "handle_${key}() { _connect '${serial}'; }"
	fi
done

handle_wireless_connect() {
	local connect_addr=$(bash "$ROFI_DIR/scripts/common_input.sh" \
		-w 500 \
		"Address:" \
		"IP:Port from Wireless Debugging screen")
	[[ -z "$connect_addr" ]] && return

	if ! adb connect "$connect_addr" 2>/dev/null; then
		notify-send -c tools -i dialog-error "Scrcpy" "Connect failed."
		return
	fi
	notify-send -c tools -i smartphone "Scrcpy" "Connected: $connect_addr"

	_connect "$connect_addr"
}

handle_wireless_pair() {
	local pair_addr=$(bash "$ROFI_DIR/scripts/common_input.sh" \
		-w 500 \
		"Address:" \
		"IP:port from pairing section")
	[[ -z "$pair_addr" ]] && return

	local pair_code=$(bash "$ROFI_DIR/scripts/common_input.sh" \
		-w 500 \
		"Code:" \
		"6-digit code shown on your device")
	[[ -z "$pair_code" ]] && return

	if ! adb pair "$pair_addr" "$pair_code" 2>/dev/null; then
		notify-send -c tools -i dialog-error "Scrcpy" "Pairing failed."
		return
	fi
	notify-send -c tools -i smartphone "Scrcpy" "Paired: $pair_addr"

	handle_wireless_connect
}

if [ "$connected" -gt 0 ]; then
	MODULE_MESG="$connected device(s) connected"
else
	MODULE_MESG="Select device or connect wirelessly"
fi

module_loop
