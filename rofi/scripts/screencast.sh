#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_WIDTH=500
MODULE_NAME=" Screencast"
MODULE_MESG="screen record"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR"/utils/monitor.sh

appName="Screencast"
appIcon="screenrecorder"
PID_FILE="/tmp/screencaster_pid"
PATH_FILE="/tmp/screencaster_path"
DIR="$(xdg-user-dir)/Screencasts"
FRAME_RATE=60

countdown() {
	while IFS= read -r sec; do
		notify-send -i $appIcon -c history-ignore -t 1010 --replace-id=699 "$appName" "Start in : ${sec}sec"
		sleep 1
	done < <(seq "$1" -1 1)
}

setup_virtual_devices() {
	echo "$(pactl load-module module-null-sink sink_name=screencast_sink sink_properties=device.description=ScreencastVirtualSink)" >>"/tmp/screencast_sink"
	echo "$(pactl load-module module-loopback source="$(pactl get-default-sink)".monitor sink=screencast_sink sink_input_properties=device.description=ScreencastDesktop)" >>"/tmp/screencast_default_sink"
	echo "$(pactl load-module module-loopback source="$(pactl get-default-source)" sink=screencast_sink sink_input_properties=device.description=ScreencastMic)" >>"/tmp/screencast_default_source"
}

toggle_desktop_volume() {
	index=$(pactl -f json list sink-inputs | jq -r '.[] | select(.properties."device.description" == "ScreencastDesktop") | .index')
	pactl set-sink-input-mute "$index" toggle
}

get_desktop_volume_state() {
	if [ "$(pactl -f json list sink-inputs | jq -r '.[] | select(.properties."device.description" == "ScreencastDesktop") | .mute')" == "false" ]; then
		echo " "
	else
		echo " "
	fi
}

toggle_mic_volume() {
	index=$(pactl -f json list sink-inputs | jq -r '.[] | select(.properties."device.description" == "ScreencastMic") | .index')
	pactl set-sink-input-mute "$index" toggle
}

get_mic_state() {
	if [ "$(pactl -f json list sink-inputs | jq -r '.[] | select(.properties."device.description" == "ScreencastMic") | .mute')" == "false" ]; then
		echo " "
	else
		echo " "
	fi
}

cleanup_virtual_devices() {
	pactl unload-module "$(cat /tmp/screencast_default_source)"
	pactl unload-module "$(cat /tmp/screencast_default_sink)"
	pactl unload-module "$(cat /tmp/screencast_sink)"
	rm -f /tmp/screencast_default_source /tmp/screencast_default_sink /tmp/screencast_sink
}

cast_area() {
	geometry=$(slop -f "%x %y %w %h")
	if [ "$geometry" = "" ]; then
		notify-send -c history-ignore -i $appIcon "$appName" "No region selected. Exiting."
		exit 1
	fi
	read -r X Y W H <<<"$geometry"
	if [ "$W" -eq 0 ] || [ "$H" -eq 0 ]; then
		notify-send -c history-ignore -i $appIcon "$appName" "Invalid region size. Exiting."
		exit 1
	fi
	filepath="$DIR/$(date '+%Y-%m-%d_%H-%M-%S').mp4"
	countdown '3'
	ffmpeg -video_size "${W}x${H}" -framerate "$FRAME_RATE" -f x11grab -i ":0.0+${X},${Y}" \
		-f pulse -i "screencast_sink.monitor" \
		-fps_mode cfr -c:v libx264 -threads 8 -preset veryfast -crf 23 "$filepath" >/dev/null 2>&1 &
	echo $! >"$PID_FILE"
	echo "$filepath" >"$PATH_FILE"
}

cast_fullscreen() {
	filepath=$DIR/$(date '+%Y-%m-%d_%H-%M-%S').mp4
	countdown '3'
	read index name width height x y < <(get_current_monitor)
	ffmpeg -video_size "${width}x${height}" -framerate "$FRAME_RATE" -f x11grab -i :0.0+"${x},${y}" \
		-f pulse -i "screencast_sink.monitor" \
		-fps_mode cfr -c:v libx264 -threads 8 -preset veryfast -crf 23 "$filepath" >/dev/null 2>&1 &
	echo $! >"$PID_FILE"
	echo "$filepath" >"$PATH_FILE"
}

stop_cast() {
	if [ -f "$PID_FILE" ]; then
		PID=$(cat "$PID_FILE")
		kill "$PID"
		rm -f "$PID_FILE"
		notify-send -c history-ignore -i $appIcon "$appName" "Recording stopped, Saved to $(cat "$PATH_FILE")"
		rm -f "$PATH_FILE"
	fi
}

if [ -f "$PID_FILE" ]; then
	last_modified_timestamp=$(stat -c "%Y" "$PID_FILE")
	current_timestamp=$(date +%s)
	difference=$((current_timestamp - last_modified_timestamp))
	hours=$((difference / 3600))
	difference=$((difference % 3600))
	minutes=$((difference / 60))
	seconds=$((difference % 60))
	MODULE_NAME=" Screencast 󰑊 ${hours}h ${minutes}m ${seconds}s"

	module_parse <<MODULES
stop||Stop Screencast||
toggle-desktop||Mute Desktop||cmd:get_desktop_volume_state
toggle-mic||Mute Mic||cmd:get_mic_state
MODULES

	handle_stop() {
		cleanup_virtual_devices
		stop_cast
	}
	handle_toggle_desktop() { toggle_desktop_volume; }
	handle_toggle_mic() { toggle_mic_volume; }
else
	module_parse <<MODULES
fullscreen||Record Desktop||
area||Record Area||
window||Record Window||
MODULES

	handle_fullscreen() {
		setup_virtual_devices
		cast_fullscreen
	}
	handle_area() {
		setup_virtual_devices
		cast_area
	}
	handle_window() {
		setup_virtual_devices
		cast_area
	}
fi

module_loop
