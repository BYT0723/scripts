#!/usr/bin/env bash

dir=$(dirname "$0")

# Import Current Theme
type="$dir/rofi/applets/type-1"
style='style-2.rasi'
theme="$type/$style"
appName="Screencast"
appIcon="screenrecorder"

PID_FILE="/tmp/screencaster_pid"
PATH_FILE="/tmp/screencaster_path"
DIR="$(xdg-user-dir)/Screencasts"

# Frame rate
FRAME_RATE=60

# Theme Elements
prompt='Screencast'
mesg="  $DIR"

source "$(dirname "$0")"/monitor.sh

# countdown
countdown() {
	while IFS= read -r sec; do
		notify-send -i $appIcon -t 1010 --replace-id=699 "$appName" "Start in : ${sec}sec"
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
	rm -f /tmp/screencast_default_source
	rm -f /tmp/screencast_default_sink
	rm -f /tmp/screencast_sink
}

# Dependencies
handle_dependencies() {
	# Check if slop and ffmpeg are installed
	if ! command -v slop &>/dev/null || ! command -v ffmpeg &>/dev/null; then
		notify-send -i $appIcon "$appName" "slop and ffmpeg are required but not installed."
		exit 1
	fi
	if [ ! -d "$DIR" ]; then
		mkdir -p "$DIR"
	fi
}

cast_area() {
	# Use slop to select region and get the geometry
	geometry=$(slop -f "%x %y %w %h")
	if [ "$geometry" = "" ]; then
		notify-send -i $appIcon "$appName" "No region selected. Exiting."
		exit 1
	fi

	# Parse the selected region's coordinates and dimensions
	read -r X Y W H <<<"$geometry"

	# Check if the width and height are valid
	if [ "$W" -eq 0 ] || [ "$H" -eq 0 ]; then
		notify-send -i $appIcon "$appName" "Invalid region size. Exiting."
		exit 1
	fi

	filepath="$DIR/$(date '+%Y-%m-%d_%H-%M-%S').mp4"

	countdown '3'

	ffmpeg -video_size \""${W}x${H}"\" -framerate "$FRAME_RATE" -f x11grab -i ":0.0+${X},${Y}" \
		-f pulse -i "screencast_sink.monitor" \
		-vsync 2 -c:v libx264 -threads 8 -preset veryfast -crf 23 "$filepath" >/dev/null 2>&1 &

	# Save the ffmpeg process PID
	echo $! >"$PID_FILE"
	echo "$filepath" >"$PATH_FILE"
}

cast_fullscreen() {
	filepath=$DIR/$(date '+%Y-%m-%d_%H-%M-%S').mp4

	countdown '3'

	read index name width height x y < <(get_current_monitor)

	ffmpeg -video_size "${width}x${height}" -framerate "$FRAME_RATE" -f x11grab -i :0.0+"${x},${y}" \
		-f pulse -i "screencast_sink.monitor" \
		-vsync 2 -c:v libx264 -threads 8 -preset veryfast -crf 23 "$filepath" >/dev/null 2>&1 &

	# Save the ffmpeg process PID
	echo $! >"$PID_FILE"
	echo "$filepath" >"$PATH_FILE"
}

# Function to stop recording
stop_cast() {
	if [ -f "$PID_FILE" ]; then
		PID=$(cat "$PID_FILE")
		kill "$PID"
		rm -f "$PID_FILE"
		notify-send -i $appIcon "$appName" "Recording stopped, Saved to $(cat "$PATH_FILE")"
		rm -f "$PATH_FILE"
	fi
}

if [ -f "$PID_FILE" ]; then
	last_modified_timestamp=$(stat -c "%Y" "$PID_FILE")
	current_timestamp=$(date +%s)

	# Calculate the difference in seconds
	difference=$((current_timestamp - last_modified_timestamp))

	hours=$((difference / 3600))
	difference=$((difference % 3600))
	minutes=$((difference / 60))
	seconds=$((difference % 60))
	prompt=""$prompt" 󰑊 "${hours}"h "${minutes}"m "${seconds}s
fi

if [[ ""$theme == *'type-1'* ]]; then
	list_col='1'
	list_row='3'
	win_width='500px'
elif [[ ""$theme == *'type-3'* ]]; then
	list_col='1'
	list_row='3'
	win_width='120px'
elif [[ ""$theme == *'type-5'* ]]; then
	list_col='1'
	list_row='3'
	win_width='520px'
elif [[ (""$theme == *'type-2'*) || (""$theme == *'type-4'*) ]]; then
	list_col='3'
	list_row='1'
	win_width='670px'
fi

system_volume_status=$(get_desktop_volume_state)
mic_status=$(get_mic_state)

# Options
layout=$(cat "$theme" | grep 'USE_ICON' | cut -d'=' -f2)
if [[ ""$layout == 'NO' ]]; then
	option_1=" Record Desktop"
	option_2=" Record Area"
	option_3=" Record Window"
	option_1_1=" Stop Screencast"
	option_1_2=""$system_volume_status" Mute Desktop"
	option_1_3=""$mic_status" Mute Mic"
else
	option_1=""
	option_2=""
	option_3=""
	option_1_1=""
	option_1_2=""$system_volume_status
	option_1_3=""$mic_status
fi

# Rofi CMD
rofi_cmd() {
	rofi -theme-str "window {width: $win_width;}" \
		-theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-monitor -4 \
		-theme "$theme"
}

# Pass variables to rofi dmenu
run_rofi() {
	if [ -f "$PID_FILE" ]; then
		echo -e "$option_1_1\n$option_1_2\n$option_1_3" | rofi_cmd
	else
		echo -e "$option_1\n$option_2\n$option_3" | rofi_cmd
	fi
}

run_audio_menu() {
	echo -e "$audio_option_1\n$audio_option_2"\n"$audio_option_3\n$audio_option_4" | rofi_cmd
}

# Execute Command
run_cmd() {
	case ""$1 in
	"--opt1")
		setup_virtual_devices
		cast_fullscreen
		;;
	"--opt2")
		setup_virtual_devices
		cast_area
		;;
	"--opt3")
		setup_virtual_devices
		cast_area
		;;
	"--opt1_1")
		cleanup_virtual_devices
		stop_cast
		;;
	"--opt1_2")
		toggle_desktop_volume
		;;
	"--opt1_3")
		toggle_mic_volume
		;;
	esac
}

# Actions
chosen=""$(run_rofi)
case ${chosen} in
$option_1)
	run_cmd --opt1
	;;
$option_2)
	run_cmd --opt2
	;;
$option_3)
	run_cmd --opt3
	;;
$option_1_1)
	run_cmd --opt1_1
	;;
$option_1_2)
	run_cmd --opt1_2
	;;
$option_1_3)
	run_cmd --opt1_3
	;;
esac
