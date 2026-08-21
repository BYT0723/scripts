#!/bin/bash

screen_saver_time=600
dpms_sleep_time=900
dpms_suspend_time=1200
dpms_off_time=1800
duration=600
SCREEN_AUDIO_MODE="video"
SCREEN_DEBUG_NOTIFY=0
LOCKER="$(dirname "$0")/lock.sh lock"
current_hash=$(md5sum "$0" | awk '{print $1}')

state=0

command -v pw-dump &>/dev/null && _audio_backend="pipewire" || _audio_backend="pulseaudio"

_screensaver() {
	if [ "$1" = on ]; then
		if [ $state -eq 1 ]; then
			return
		fi
		pkill xautolock 2>/dev/null
		xautolock -time $((screen_saver_time / 60)) -locker "$LOCKER" -detectsleep &
		xset s $screen_saver_time $screen_saver_time +dpms
		xset dpms $dpms_sleep_time $dpms_suspend_time $dpms_off_time
		state=1
		[[ $SCREEN_DEBUG_NOTIFY -eq 1 ]] && notify-send -t 2000 "[Screensaver and DPMS] enabled" || true
	else
		if [ $state -eq 0 ]; then
			return
		fi
		pkill xautolock 2>/dev/null
		xset s off -dpms
		state=0
		[[ $SCREEN_DEBUG_NOTIFY -eq 1 ]] && notify-send -t 2000 "[Screensaver and DPMS] disabled" || true
	fi
}

_has_active_audio() {
	if [ "$_audio_backend" = "pipewire" ]; then
		local _filter
		if [ "$SCREEN_AUDIO_MODE" = "any" ]; then
			_filter='
				.type == "PipeWire:Interface:Node"
				and .info.props["application.name"] != "wallpaper"
				and .info.state == "running"
				and (
					(.info.props["application.name"] != "Firefox" and .info.props["application.name"] != "Chromium")
					or (.info.props["pulse.attr.tlength"] != null and .info.props["pulse.attr.tlength"] > 20000)
				)
			'
		else
			_filter='
				.type == "PipeWire:Interface:Node"
				and .info.props["application.name"] != "wallpaper"
				and .info.state == "running"
				and (
					.info.props["media.role"] == "video"
					or (
						(.info.props["application.name"] == "Firefox" or .info.props["application.name"] == "Chromium")
						and .info.props["pulse.attr.tlength"] != null
						and .info.props["pulse.attr.tlength"] > 20000
					)
				)
			'
		fi
		pw-dump 2>/dev/null | jq -e "[.[] | select($_filter)] | length > 0" >/dev/null 2>&1
	else
		if [ "$SCREEN_AUDIO_MODE" = "any" ]; then
			pactl -f json list sink-inputs | jq -e '
				map(select(.properties["application.name"] != "wallpaper" and .corked == false)) | length > 0
			' >/dev/null 2>&1
		else
			pactl -f json list sink-inputs | jq -e '.[] | select(
				.properties["application.name"] != "wallpaper" and
				.corked == false and (
					.properties["media.role"] == "video" or
					.properties["application.name"] == "Firefox" or
					.properties["application.name"] == "Chromium"
				)
			)' >/dev/null 2>&1
		fi
	fi
}

daemon() {
	_screensaver on
	while true; do
		_has_active_audio && _screensaver off || _screensaver on

		if [[ "$(md5sum "$0" | awk '{print $1}')" != "$current_hash" ]]; then
			/bin/bash "$0" &
			exit 0
		fi

		sleep $duration
	done
}

daemon
