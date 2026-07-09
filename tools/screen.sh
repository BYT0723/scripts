#!/bin/bash

state=1                # screen saver and dpms state
screen_saver_time=600  # 屏保时间 10分钟
dpms_sleep_time=900    # dpms待机时间 15分钟
dpms_suspend_time=1200 # dpms挂起时间 20分钟
dpms_off_time=1800     # dpms关机时间 30分钟
# 获取文件的当前哈希值
current_hash=$(md5sum $0 | awk '{print $1}')
# 检查间隔
duration=300 # 检查间隔 5分钟

# SCREEN_AUDIO_MODE: "any" 任何音频禁止熄屏 / "video" 仅视频音频禁止熄屏
SCREEN_AUDIO_MODE="any"

# DEBUG LOG
SCREEN_DEBUG_NOTIFY=0

LOCKER="$(dirname "$0")/lock.sh lock"

# init
init() {
	if [ $state -eq 1 ]; then
		if [ ! -z "$(pgrep xautolock)" ]; then
			pkill xautolock
		fi
		xautolock -time $(echo "$screen_saver_time/60" | bc) -locker "$LOCKER" -detectsleep &
		xset s $screen_saver_time $screen_saver_time +dpms
		xset dpms $dpms_sleep_time $dpms_suspend_time $dpms_off_time
	else
		pkill xautolock
		xset s off -dpms
	fi
}

enable_screen_saver_and_dpms() {
	if [ $state -eq 0 ]; then
		if [ ! -z "$(pgrep xautolock)" ]; then
			pkill xautolock
		fi
		xautolock -time $(echo "$screen_saver_time/60" | bc) -locker "$LOCKER" -detectsleep &
		xset s $screen_saver_time $screen_saver_time +dpms           # 屏保 10 分钟
		xset dpms $dpms_sleep_time $dpms_suspend_time $dpms_off_time # DPMS: 待机 15 分钟, 挂起 20 分钟, 关闭 30 分钟
		state=1
		[[ $SCREEN_DEBUG_NOTIFY -eq 1 ]] && notify-send -t 2000 "[Screensaver and DPMS] enabled" || true
	fi
}

disable_screen_saver_and_dpms() {
	if [ $state -eq 1 ]; then
		pkill xautolock
		xset s off -dpms
		state=0
		[[ $SCREEN_DEBUG_NOTIFY -eq 1 ]] && notify-send -t 2000 "[Screensaver and DPMS] disabled" || true
	fi
}

# # Set Xorg Screen Saver And DPMS
daemon() {
	enable_screen_saver_and_dpms
	while true; do
		if [ "$SCREEN_AUDIO_MODE" = "any" ]; then
			# 存在非 wallpaper 的未暂停音频流则禁止熄屏
			if pactl -f json list sink-inputs | jq -e '
				map(select(.properties["application.name"] != "wallpaper" and .corked == false)) | length > 0
			' >/dev/null 2>&1; then
				disable_screen_saver_and_dpms
			else
				enable_screen_saver_and_dpms
			fi
		else
			if pactl -f json list sink-inputs | jq -e '.[] | select(
				.properties["application.name"] != "wallpaper" and
				.corked == false and (
					.properties["media.role"] == "video" or
					.properties["application.name"] == "Firefox" or
					.properties["application.name"] == "Chromium"
				)
			)' >/dev/null 2>&1; then
				disable_screen_saver_and_dpms
			else
				enable_screen_saver_and_dpms
			fi
		fi

		# 如果文件内容发生变化, 则重新加载
		if [[ "$(md5sum $0 | awk '{print $1}')" != "$current_hash" ]]; then
			/bin/bash $0 &
			exit 0
		fi

		sleep $duration
	done
}

init
daemon
