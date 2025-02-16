#!/bin/bash

state=1                # screen saver and dpms state
screen_saver_time=600  # 屏保时间 10分钟
dpms_sleep_time=900    # dpms待机时间 15分钟
dpms_suspend_time=1200 # dpms挂起时间 20分钟
dpms_off_time=1800     # dpms关机时间 30分钟
# 获取文件的当前哈希值
current_hash=$(md5sum $0 | awk '{print $1}')
# 检查间隔
duration=30 # 检查间隔 1分钟

# init
init() {
	if [ $state -eq 1 ]; then
		if [ ! -z "$(pgrep xautolock)" ]; then
			pkill xautolock
		fi
		xautolock -time $(echo "$screen_saver_time/60" | bc) -locker slock -detectsleep &
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
		xautolock -time $(echo "$screen_saver_time/60" | bc) -locker slock -detectsleep &
		xset s $screen_saver_time $screen_saver_time +dpms           # 屏保 10 分钟
		xset dpms $dpms_sleep_time $dpms_suspend_time $dpms_off_time # DPMS: 待机 15 分钟, 挂起 20 分钟, 关闭 30 分钟
		state=1
		notify-send -t 2000 "[Screensaver and DPMS] enabled"
	fi
}

disable_screen_saver_and_dpms() {
	if [ $state -eq 1 ]; then
		pkill xautolock
		xset s off -dpms
		state=0
		notify-send -t 2000 "[Screensaver and DPMS] disabled"
	fi
}

# # Set Xorg Screen Saver And DPMS
daemon() {
	enable_screen_saver_and_dpms
	while true; do
		# 判断系统当前是否有音频输出
		if [ ! -z "$(pactl list short sinks | grep 'RUNNING')" ]; then
			# 获取当前音频输入应用
			# corked == false 表示没有暂停
			# media.role == "video" 表示是视频
			apps=$(pactl -f json list sink-inputs |
				jq -r '.[] | select(.corked == false and (
                .properties["media.role"] == "video" or
                .properties["application.name"] == "Firefox" or
                .properties["application.name"] == "Chromium"
            )) | .properties["application.name"]')

			# 如果存在视频音频流
			if [ ! -z "$apps" ]; then
				disable_screen_saver_and_dpms
			else # 不存在视频音频流
				enable_screen_saver_and_dpms
			fi
		else # 没有正在播放的音频流
			enable_screen_saver_and_dpms
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
