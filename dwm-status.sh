#!/usr/bin/env /bin/bash

source "$(dirname "$0")/dwm-status-tools.sh"
source "$(dirname "$0")/status-ids.sh" # ST_* block ids, derived from status-ids.def

# Every block carries its status id (${ST_*_BYTE}); dwm's config owns the
# draw order, pill grouping and rounded caps (bar_left/bar_right in its
# config.h), so the order here is only for reading. The pane background is
# NOT sent: dwm's SchemeStatus colours come from the same xrdb keys via
# loadxrdb(), so a ^b here would just repeat them.
panes() {
    local panes
    local weather_str=$(print_weather)
    local rss_str=$(print_rss)
    local mail_str=$(print_mail)
    local notification_str=$(print_notification)
    local mpd_str=$(print_mpd)

    [ -n "$weather_str" ] && panes+="${ST_WEATHER_BYTE}^c$blue^$weather_str"

    # net traffic monitor pane
    panes+="${ST_NET_BYTE}^c$white^$(print_speed)"
    # system monitor pane
    panes+="${ST_CPU_BYTE}$(print_cpu)${ST_MEM_BYTE}$(print_mem)${ST_DISK_BYTE}$(print_disk /)"

    # notification pane
    if [[ -n $rss_str || -n $mail_str || -n $notification_str ]]; then
        panes+="${ST_RSS_BYTE}$rss_str${ST_MAIL_BYTE}$mail_str${ST_NOTIFY_BYTE}$notification_str"
    fi

    panes+="${ST_SCREENCAST_BYTE}$(print_screencast)${ST_DOCKER_BYTE}$(print_docker)${ST_SINGBOX_BYTE}$(print_singbox)${ST_MPD_BYTE}$mpd_str${ST_VOLUME_BYTE}$(print_volume)${ST_BATTERY_BYTE}$(print_battery)"
    # datetime pane
    panes+="${ST_DATE_BYTE}^c$cyan^$(print_date)"

    printf "%b\n" "$panes"
}

launch_daemon() {
    pids=()
    mkdir -p /tmp/dwm-status

    update_cpu_daemon &
    pids+=($!)
    update_traffic_daemon &
    pids+=($!)
    interval_update_daemon -i 1800 update_weather &
    pids+=($!)
    interval_update_daemon -i 3600 update_weather_forecast &
    pids+=($!)
    interval_update_daemon -i 300 update_mail &
    pids+=($!)
    interval_update_daemon -i 300 update_rss &
    pids+=($!)
    update_mpd_daemon &
    pids+=($!)
    update_docker_daemon &
    pids+=($!)

    # 保存当前进程 PID
    echo $BASHPID >/tmp/dwm-status/status-daemon-pid

    # 退出时杀掉所有子进程(含孙进程)
    trap '
		for p in "${pids[@]}"; do
			pkill -P $p 2>/dev/null
			kill $p 2>/dev/null
		done
		rm -f /tmp/dwm-status/status-daemon-pid
	' EXIT

    # Keep daemon running
    wait
}

launch_refresh() {
    mkdir -p /tmp/dwm-status

    # 保存当前进程 PID
    echo $BASHPID >/tmp/dwm-status/status-refresh-pid

    trap 'rm -f /tmp/dwm-status/status-refresh-pid' EXIT

    local interval=${1:-1}
    # loop dwm-status-refresh.sh to refresh statusBar
    while true; do
        xsetroot -name "$(panes)"
        # refresh interval
        sleep $interval
    done
}

reboot_daemon() {
    local pid_file="/tmp/dwm-status/status-daemon-pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        kill $pid 2>/dev/null
        waitpid $pid
    fi

    launch_daemon &
}

reboot_refresh() {
    local pid_file="/tmp/dwm-status/status-refresh-pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        kill $pid 2>/dev/null
        waitpid $pid
    fi

    launch_refresh &
}

case "$1" in
"reboot")
    reboot_daemon
    reboot_refresh
    ;;
"reboot-daemon")
    reboot_daemon
    ;;
"reboot-refresh")
    reboot_refresh
    ;;
*)
    launch_daemon &
    launch_refresh &
    ;;
esac
