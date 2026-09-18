#!/usr/bin/env /bin/bash

source "$(dirname "$0")/dwm-status-tools.sh"
source "$(dirname "$0")/status-ids.sh" # ST_* block ids, derived from status-ids.def

# $1: background color
# ${@:2} blocks... each argument starts with its block id (${ST_*_BYTE} control byte).
# Grouping and rounded caps live in dwm's config; the pane colour stays here
# so it keeps following the xrdb theme, and dwm paints the cap with it.
new_pane() {
    bg=$1
    shift

    # the block id is one leading control byte (< 0x20); anything else is text
    first=$1
    if [ -n "$first" ]; then
        ord=$(printf '%d' "'${first:0:1}")
    else
        ord=0
    fi
    if [ "$ord" -ge 1 ] && [ "$ord" -le 16 ]; then
        first_status_code=${first:0:1}
        first_text=${first:1}
    else
        first_status_code=""
        first_text="$first"
    fi
    shift

    printf "%s" "$first_status_code^b$bg^$first_text" "$@"
}

panes() {
    local panes
    local weather_str=$(print_weather)
    local rss_str=$(print_rss)
    local mail_str=$(print_mail)
    local notification_str=$(print_notification)
    local mpd_str=$(print_mpd)

    [ -n "$weather_str" ] && panes+="$(new_pane $black "${ST_WEATHER_BYTE}^c$blue^$weather_str")"
    [ $mpd_single_pane -gt 0 ] && [ -n "$mpd_str" ] && panes+="$(new_pane $black "${ST_MPD_BYTE}$mpd_str")"

    # net traffic monitor pane
    panes+="$(new_pane $black "${ST_NET_BYTE}^c$white^$(print_speed)")"
    # system monitor pane
    panes+="$(new_pane $black "${ST_CPU_BYTE}$(print_cpu)$(print_temperature)" "${ST_MEM_BYTE}$(print_mem)" "${ST_DISK_BYTE}$(print_disk /)")"

    # notification pane
    if [[ -n $rss_str || -n $mail_str || -n $notification_str ]]; then
        panes+="$(new_pane $black "${ST_RSS_BYTE}$rss_str" "${ST_MAIL_BYTE}$mail_str" "${ST_NOTIFY_BYTE}$notification_str")"
    fi

    # one icon tools pane
    [ "$mpd_single_pane" -eq 0 ] && mpd_part="${ST_MPD_BYTE}$mpd_str"

    panes+="$(new_pane $black "${ST_SCREENCAST_BYTE}$(print_screencast)" "${ST_SINGBOX_BYTE}$(print_singbox)" "$mpd_part" "${ST_VOLUME_BYTE}$(print_volume)" "${ST_BATTERY_BYTE}$(print_battery)")"
    # datetime pane
    panes+="$(new_pane $black "${ST_DATE_BYTE}^c$cyan^$(print_date)")"

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
    interval_update_daemon -i 60 update_mail &
    pids+=($!)
    interval_update_daemon -i 300 update_rss &
    pids+=($!)
    update_mpd_daemon &
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
