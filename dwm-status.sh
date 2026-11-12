#!/usr/bin/env /bin/bash

source "$(dirname "$0")/dwm-status-tools.sh"
source "$(dirname "$0")/status-ids.sh" # ST_* block ids, derived from status-ids.def

# Register one status block per line, each tagged with its status id
# (${ST_*_BYTE}). dwm looks a block up by that id and draws it wherever its own
# config says, so the order here carries no meaning for the bar -- the lines
# are grouped by what they report, for reading. The pane background is NOT
# sent: dwm's SchemeStatus colours come from the same xrdb keys via loadxrdb(),
# so a ^b here would just repeat them.
#
# An empty block keeps its bare id byte, which dwm drops (no visible text);
# weather is the exception, as its colour code alone counts as visible text,
# hence the [ -n ] guard. A block that dwm's config does not list (volume at
# the moment) is registered but not drawn.
panes() {
    local panes

    # system load: cpu / memory / root disk usage
    panes+="${ST_CPU_BYTE}$(print_cpu)"
    panes+="${ST_MEM_BYTE}$(print_mem)"
    panes+="${ST_DISK_BYTE}$(print_disk /)"

    # unread counters: rss / mail / desktop notifications
    panes+="${ST_RSS_BYTE}$(print_rss)"
    panes+="${ST_MAIL_BYTE}$(print_mail)"
    panes+="${ST_NOTIFY_BYTE}$(print_notification)"

    # network throughput (tx / rx)
    panes+="${ST_NET_BYTE}^c$white^$(print_speed)"

    # current conditions, only when a reading is cached
    local weather_str=$(print_weather)
    [ -n "$weather_str" ] && panes+="${ST_WEATHER_BYTE}^c$blue^$weather_str"

    # docker containers: running / total
    panes+="${ST_DOCKER_BYTE}$(print_docker)"

    # screen recording in progress
    panes+="${ST_SCREENCAST_BYTE}$(print_screencast)"

    # proxy daemons
    panes+="${ST_DAE_BYTE}$(print_dae)"
    panes+="${ST_SINGBOX_BYTE}$(print_singbox)"

    # audio: mpd play state, output volume
    panes+="${ST_MPD_BYTE}$(print_mpd)"
    panes+="${ST_VOLUME_BYTE}$(print_volume)"

    # power and clock
    panes+="${ST_BATTERY_BYTE}$(print_battery)"
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
