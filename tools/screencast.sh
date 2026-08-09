#!/bin/bash

WORK_DIR="$(dirname "$(dirname "$0")")"
source "$WORK_DIR"/utils/monitor.sh

APP_NAME="Screencast"
APP_ICON="screenrecorder"
PID_FILE="/tmp/screencaster_pid"
PATH_FILE="/tmp/screencaster_path"
DIR="$(xdg-user-dir)/Videos/Screencasts"
FRAME_RATE=60

countdown() {
	while IFS= read -r sec; do
		notify-send -i $APP_ICON -c history-ignore -t 1010 --replace-id=699 "$APP_NAME" "Start in : ${sec}sec"
		sleep 1
	done < <(seq "$1" -1 1)
}

setup_virtual_devices() {
	echo "$(pactl load-module module-null-sink sink_name=screencast_sink sink_properties=device.description=ScreencastVirtualSink)" >>"/tmp/screencast_sink"
	echo "$(pactl load-module module-loopback source="$(pactl get-default-sink)".monitor sink=screencast_sink sink_input_properties=device.description=ScreencastDesktop)" >>"/tmp/screencast_default_sink"
	echo "$(pactl load-module module-loopback source="$(pactl get-default-source)" sink=screencast_sink sink_input_properties=device.description=ScreencastMic)" >>"/tmp/screencast_default_source"
}

cleanup_virtual_devices() {
	for f in /tmp/screencast_default_source /tmp/screencast_default_sink /tmp/screencast_sink; do
		[ -f "$f" ] && pactl unload-module "$(cat "$f")" 2>/dev/null
	done
	rm -f /tmp/screencast_default_source /tmp/screencast_default_sink /tmp/screencast_sink
}

toggle_desktop_volume() {
	index=$(pactl -f json list sink-inputs | jq -r '.[] | select(.properties."device.description" == "ScreencastDesktop") | .index')
	pactl set-sink-input-mute "$index" toggle
}

toggle_mic_volume() {
	index=$(pactl -f json list sink-inputs | jq -r '.[] | select(.properties."device.description" == "ScreencastMic") | .index')
	pactl set-sink-input-mute "$index" toggle
}

get_system_audio_state() {
	if [ "$(pactl -f json list sink-inputs | jq -r '.[] | select(.properties."device.description" == "ScreencastDesktop") | .mute')" == "false" ]; then
		echo ""
	else
		echo ""
	fi
}

get_mic_state() {
	if [ "$(pactl -f json list sink-inputs | jq -r '.[] | select(.properties."device.description" == "ScreencastMic") | .mute')" == "false" ]; then
		echo ""
	else
		echo ""
	fi
}

start_recording() {
	local filepath="$1" width="$2" height="$3" x="$4" y="$5"
	ffmpeg -video_size "${width}x${height}" -framerate "$FRAME_RATE" -f x11grab -i ":0.0+${x},${y}" \
		-f pulse -i "screencast_sink.monitor" \
		-fps_mode cfr -c:v libx264 -threads 8 -preset veryfast -crf 23 "$filepath" >/dev/null 2>&1 &
	echo $! >"$PID_FILE"
	echo "$filepath" >"$PATH_FILE"
}

cast_area() {
	geometry=$(slop -f "%x %y %w %h")
	if [ -z "$geometry" ]; then
		notify-send -c history-ignore -i $APP_ICON "$APP_NAME" "No region selected. Exiting."
		exit 1
	fi
	read -r X Y W H <<<"$geometry"
	if [ "$W" -eq 0 ] || [ "$H" -eq 0 ]; then
		notify-send -c history-ignore -i $APP_ICON "$APP_NAME" "Invalid region size. Exiting."
		exit 1
	fi
	filepath="$DIR/$(date '+%Y-%m-%d_%H-%M-%S').mp4"
	countdown '3'
	start_recording "$filepath" "$W" "$H" "$X" "$Y"
}

cast_fullscreen() {
	filepath="$DIR/$(date '+%Y-%m-%d_%H-%M-%S').mp4"
	countdown '3'
	read index name width height x y < <(get_current_monitor)
	start_recording "$filepath" "$width" "$height" "$x" "$y"
}

cast_window() {
	sleep 0.5
	eval "$(xdotool getactivewindow getwindowgeometry --shell)"
	filepath="$DIR/$(date '+%Y-%m-%d_%H-%M-%S').mp4"
	countdown '3'
	start_recording "$filepath" "$WIDTH" "$HEIGHT" "$X" "$Y"
}

stop_cast() {
	if [ -f "$PID_FILE" ]; then
		PID=$(cat "$PID_FILE")
		kill "$PID"
		rm -f "$PID_FILE"
		notify-send -c history-ignore -i $APP_ICON "$APP_NAME" "Recording stopped, Saved to $(cat "$PATH_FILE")"
		rm -f "$PATH_FILE"
	fi
}

is_recording() {
	local pid
	read -r pid <"$PID_FILE" 2>/dev/null || return 1
	kill -0 "$pid" 2>/dev/null
}

recording_time() {
	local diff=$(($(date +%s) - $(stat -c "%Y" "$PID_FILE")))
	printf "%dh %dm %ds" $((diff / 3600)) $((diff % 3600 / 60)) $((diff % 60))
}

case "${1:-}" in
start)
	setup_virtual_devices
	mkdir -p "$DIR"
	case "${2:-}" in
	fullscreen) cast_fullscreen ;;
	area) cast_area ;;
	window) cast_window ;;
	*) echo "Usage: $0 start {fullscreen|area|window}" >&2 && exit 1 ;;
	esac
	;;
stop)
	cleanup_virtual_devices
	stop_cast
	;;
toggle-desktop) toggle_desktop_volume ;;
toggle-mic) toggle_mic_volume ;;
audio-state) get_system_audio_state ;;
mic-state) get_mic_state ;;
is-recording) is_recording ;;
recording-time) recording_time ;;
cleanup) cleanup_virtual_devices ;;
*)
	echo "Usage: $0 {start|stop|toggle-desktop|toggle-mic|audio-state|mic-state|is-recording|recording-time|cleanup}" >&2
	exit 1
	;;
esac
