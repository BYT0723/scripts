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
# key = [cmdIndex,clickType]
# value = function name (for multi-line) or inline command string (for one-liners)

left=1 middle=2 right=3 scroll_up=4 scroll_down=5

declare -A actions=(
    [1,$left]='D="$HOME/.local/state/dwm/status"; [[ -f "$D/date-collapse" ]] && rm -f "$D/date-collapse" || { mkdir -p "$D" && touch "$D/date-collapse"; }'
    [1,$right]='"$WORK_DIR/tools/calendar.sh" lunar'
    [2,$left]='notify-send -c status -i battery -h string:x-dunst-stack-tag:batteryInformation "Battery" "$(acpi -i)"'
    [2,$right]=_battery_dpms
    [2,$scroll_up]='"$TOOLS_DIR/brightness.sh" up'
    [2,$scroll_down]='"$TOOLS_DIR/brightness.sh" down'
    [3,$left]='"$TOOLS_DIR/volume.sh" toggle'
    [3,$right]=_volume_ncpamixer
    [3,$scroll_up]='"$TOOLS_DIR/volume.sh" up'
    [3,$scroll_down]='"$TOOLS_DIR/volume.sh" down'
    [6,$left]='notify-send -c status -h string:x-dunst-stack-tag:diskInformation "💾 Storage" "$(LANG=en_US.UTF-8 df -h -x tmpfs -x devtmpfs)"'
    [8,$right]=_cpu_monitor
    [9,$left]='W="$HOME/.local/state/dwm/cache"; notify-send -c status -i weather -h string:x-dunst-stack-tag:weatherForecast "Weather Forecast" "当前天气:$(cat "$W/weather")\n\n$(cat "$W/weather-forecast")"'
    [9,$middle]='xdg-open https://wttr.in/?T'
    [10,$left]='"$ROFI_SCRIPT_DIR/mpd.sh"'
    [10,$middle]='mpd --kill'
    [10,$right]=_mpd_rmpc
    [11,$left]='D="$HOME/.local/state/dwm/status"; [[ -f "$D/net-traffic-collapse" ]] && rm -f "$D/net-traffic-collapse" || { mkdir -p "$D" && touch "$D/net-traffic-collapse"; }'
    [11,$right]=_net_speedtest
    [12,$left]='thunderbird -mail &'
    [12,$right]=_mail_aerc
    [13,$left]=_rss_notify
    [13,$right]=_rss_launch
    [14,$left]='"$ROFI_SCRIPT_DIR/sing-box.sh"'
    [14,$right]='xdg-open "http://127.0.0.1:9090/ui"'
    [15,$left]='"$ROFI_SCRIPT_DIR/notification.sh" pop-latest'
    [15,$right]='"$ROFI_SCRIPT_DIR/notification.sh"'
    [16,$left]='"$ROFI_SCRIPT_DIR/screencast.sh"'
    [16,$right]='"$TOOLS_DIR/screencast.sh" stop'
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
