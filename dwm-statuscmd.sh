#!/bin/bash

#
#  Handle the statusBar click event
#  see file config.h variable statuscmds
#
#

ROFI_SCRIPT_DIR="$(dirname $0)/rofi/scripts"
TOOLS_DIR="$(dirname $0)/tools"
WORK_DIR=$(dirname $0)
terminal="${TERMINAL:-kitty}"

_topen() {
    case "$terminal" in
    kitty) "$terminal" "$@" ;;
    *) "$terminal" -e "$@" ;;
    esac
}
_ftopen() {
    case "$terminal" in
    kitty) "$terminal" --class float-term -o font_size=10 -o initial_window_width=120c -o initial_window_height=36c "$@" ;;
    *) "$terminal" --class float-term -e "$@" ;;
    esac
}

source "$WORK_DIR/utils/notify.sh"
source "$WORK_DIR/status-ids.sh" # ST_* block ids, derived from status-ids.def

# --- Command functions (only for actions that need flow control / return) ---

_battery_dpms() {
    local timeout=$(xset q | grep "timeout" | awk '{print $2}')
    local dpms=$(xset q | grep "DPMS" | tail -n 1 | awk '{print $3}')
    notify-send -c status -i display "DPMS" -h string:x-dunst-stack-tag:dpms "\
ScreenSaver: $([ "$timeout" -gt 0 ] && echo "Enabled" || echo "Disabled")\n\
DPMS:        $dpms"
}

_cpu_monitor() {
    command -v htop >/dev/null 2>&1 && {
        _topen htop
        return
    }
    command -v btop >/dev/null 2>&1 && {
        _topen btop
        return
    }
    command -v top >/dev/null 2>&1 && {
        _topen top
        return
    }
    system-notify normal "Tool Not Found" "please install one of btop,htop,top"
}

_net_speedtest() {
    command -v speedtest >/dev/null 2>&1 && {
        _topen speedtest
        return
    }
    system-notify normal "Tool Not Found" "please install speedtest-cli"
}

_mpd_rmpc() {
    command -v rmpc >/dev/null 2>&1 && {
        _ftopen rmpc
        return
    }
    system-notify normal "Tool Not Found" "please install rmpc"
}

_mpd_volume() {
    case "$1" in
    up)
        mpc volume +2
        ;;
    down)
        mpc volume -2
        ;;
    *)
        return
        ;;
    esac
    volume=$(mpc volume | grep -oP '\d+(?=%)')
    notify-send -c tools -h string:x-dunst-stack-tag:mpd-volume -h int:value:"$volume" "  $volume"
}

_volume_ncpamixer() {
    command -v ncpamixer >/dev/null 2>&1 && {
        _ftopen ncpamixer
        return
    }
    system-notify normal "Tool Not Found" "please install ncpamixer"
}

_mail_aerc() {
    if command -v aerc >/dev/null 2>&1; then
        _topen aerc
        [ -z "$(pgrep -f "bash $TOOLS_DIR/mail.sh")" ] && bash "$TOOLS_DIR/mail.sh" &
        return
    fi
    system-notify normal "Tool Not Found" "please install aerc"
}

_rss_notify() {
    command -v newsboat >/dev/null 2>&1 && {
        notify-send -i rss "$(newsboat -x print-unread)"
        return
    }
    system-notify normal "Tool Not Found" "please install newsboat"
}

_rss_launch() {
    command -v newsboat >/dev/null 2>&1 && {
        _topen newsboat
        return
    }
    system-notify normal "Tool Not Found" "please install newsboat"
}

# --- Dispatch table ---
# key = [cmdIndex,clickType]; cmdIndex is $ST_* from status-ids.def, the same
# id dwm reports as $INDEX. Never hardcode the number here.
# value = function name (for multi-line) or inline command string (for one-liners)

left=1 middle=2 right=3 scroll_up=4 scroll_down=5

declare -A actions=(
    [$ST_DATE,$left]='D="$HOME/.local/state/dwm/status"; [[ -f "$D/date-collapse" ]] && rm -f "$D/date-collapse" || { mkdir -p "$D" && touch "$D/date-collapse"; }'
    [$ST_DATE,$right]='"$WORK_DIR/tools/calendar.sh" lunar'
    [$ST_BATTERY,$left]='notify-send -c status -i battery -h string:x-dunst-stack-tag:batteryInformation "Battery" "$(acpi -i)"'
    [$ST_BATTERY,$right]=_battery_dpms
    [$ST_BATTERY,$scroll_up]='"$TOOLS_DIR/brightness.sh" up'
    [$ST_BATTERY,$scroll_down]='"$TOOLS_DIR/brightness.sh" down'
    [$ST_VOLUME,$left]='"$TOOLS_DIR/volume.sh" toggle'
    [$ST_VOLUME,$right]=_volume_ncpamixer
    [$ST_VOLUME,$scroll_up]='"$TOOLS_DIR/volume.sh" up'
    [$ST_VOLUME,$scroll_down]='"$TOOLS_DIR/volume.sh" down'
    [$ST_DISK,$left]='notify-send -c status -h string:x-dunst-stack-tag:diskInformation "💾 Storage" "$(LANG=en_US.UTF-8 df -h -x tmpfs -x devtmpfs)"'
    [$ST_CPU,$right]=_cpu_monitor
    [$ST_WEATHER,$left]='W="$HOME/.local/state/dwm/cache"; notify-send -c status -i weather -h string:x-dunst-stack-tag:weatherForecast "Weather Forecast" "当前天气:$(cat "$W/weather")\n\n$(cat "$W/weather-forecast")"'
    [$ST_WEATHER,$middle]='xdg-open https://wttr.in/?T'
    [$ST_MPD,$left]='"$ROFI_SCRIPT_DIR/mpd.sh"'
    [$ST_MPD,$middle]='mpd --kill'
    [$ST_MPD,$scroll_up]='_mpd_volume up'
    [$ST_MPD,$scroll_down]='_mpd_volume down'
    [$ST_MPD,$right]=_mpd_rmpc
    [$ST_NET,$left]='D="$HOME/.local/state/dwm/status"; [[ -f "$D/net-traffic-collapse" ]] && rm -f "$D/net-traffic-collapse" || { mkdir -p "$D" && touch "$D/net-traffic-collapse"; }'
    [$ST_NET,$right]=_net_speedtest
    [$ST_MAIL,$left]='thunderbird -mail &'
    [$ST_MAIL,$right]=_mail_aerc
    [$ST_RSS,$left]=_rss_notify
    [$ST_RSS,$right]=_rss_launch
    [$ST_SINGBOX,$left]='"$ROFI_SCRIPT_DIR/sing-box.sh"'
    [$ST_SINGBOX,$right]='xdg-open "http://127.0.0.1:9090/ui"'
    [$ST_NOTIFY,$left]='"$ROFI_SCRIPT_DIR/notification.sh" pop-latest'
    [$ST_NOTIFY,$right]='"$ROFI_SCRIPT_DIR/notification.sh"'
    [$ST_SCREENCAST,$left]='"$ROFI_SCRIPT_DIR/screencast.sh"'
    [$ST_SCREENCAST,$right]='"$TOOLS_DIR/screencast.sh" stop'
)

# --- Main dispatch ---

cmdIndex=$1
shift
buttonType=${1:-0}

action=${actions[$cmdIndex,$buttonType]}
if [[ -n ${action:-} ]]; then
    if declare -f "$action" >/dev/null 2>&1; then
        "$action" >>~/.statuscmd.log
    else
        eval "$action"
    fi
fi
