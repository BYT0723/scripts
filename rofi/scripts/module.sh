#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_MAX_LINES=8
MODULE_NAME=" Modules"
MODULE_MESG="Manage Module Of System"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

CONFIG_HOME="$HOME/.config/dwm"

declare -A confPath applicationCmd
confPath["picom"]="$CONFIG_HOME/picom.conf"
applicationCmd["picom"]="picom --config ${confPath["picom"]} -b"

toggleApplication() {
    if pgrep -q "$1"; then
        killall "$1"
    else
        ${applicationCmd[$1]}
    fi
}

# 注意: heredoc 故意不加引号 — touchpad 行的 $WORK_DIR 需在 parse 时展开,
# 因为 toggle-raw 经 icon() 直接执行 (不像 cmd: 那样 eval, 见 util.sh raw 分支)。
module_parse <<MODULES
picom|󰋩|Picom|toggle
conky|󰏘|Conky|toggle
network|󰈀|Network|active:NetworkManager
bluetooth|󰂯|Bluetooth|active-svc
audio-output|󰓃|Audio Output|
notification||Notification|cmd:dunstctl count history
calendar-lunar||Lunar Calendar|
calendar||Calendar|
media-scraping|󰎁|Media Scraping|
scrcpy|󰄟|Scrcpy (Android Mirror)|
sddm|󰍂|SDDM|
sing-box||sing-box (proxy)|active
theme|󰔟|Theme|
wallpaper|󰸉|Wallpaper|
xcolor|󰌁|Color Picker|
yt-dlp-wrapper|󰎆|YT-DLP Wrapper (downloader)|
steam-workshop|󰉋|Steam Workshop|
touchpad||Touch Pad|toggle-raw:$WORK_DIR/tools/touchpad.sh status
screencast|󰑊|Screencast (Recorder)|
MODULES

# ====== Handlers ======
handle_picom() { toggleApplication picom; }
handle_conky() { /bin/bash $WORK_DIR/dwm-launcher.sh conky toggle; }

handle_network() {
    local eth wifi mesg=""
    eth=$(nmcli -t -f DEVICE,TYPE,STATE dev status | awk -F: '$2=="ethernet" && $3=="connected" {print $1}')
    wifi=$(nmcli -t -f IN-USE,SSID,SIGNAL dev wifi list | awk -F: '/^\*/ {printf "%s(%s%%)", $2, $3}')
    [[ -n "$eth" ]] && mesg="  $eth"
    [[ -n "$wifi" ]] && mesg="${mesg:+$mesg\n}  $wifi"
    local opts=$(nmcli -t -f BARS,BAND,BSSID,SSID dev wifi list --rescan auto | awk -F: '{ ssid=$NF; if (ssid=="") { bssid=""; for (i=3;i<NF;i++) bssid=bssid (i>3?":":"") $i; ssid=bssid; gsub(/\\:/, ":", ssid) } printf "%4s [%7s] %s\n", $1, $2, ssid }' | awk '!a[$0]++')
    local chosen=$(echo "$opts" | module_sub_rofi "Network" "$mesg")
    [[ -z "$chosen" ]] && return
    chosen="${chosen#*] }"
    [[ "$chosen" == "$(nmcli -t -f IN-USE,SSID dev wifi list | awk -F: '$1=="*"{print $2}')" ]] && return
    if [[ "$chosen" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        local ssid
        ssid=$(module_input "Hidden Network" "Enter the SSID of the hidden network")
        [[ -z "$ssid" ]] && return
        nmcli device wifi connect "$ssid" hidden yes bssid "$chosen"
    else
        nmcli device wifi connect "$chosen"
    fi
}

handle_bluetooth() {
    local devices connected connected_device mesg opts chosen mac
    devices=$(bluetoothctl devices)
    connected=$(bluetoothctl devices Connected)
    connected_device=$(cut -d' ' -f3- <<<"$connected")
    mesg="No device connected"
    [[ -n "$connected_device" ]] && mesg="Connected: $connected_device"
    opts=$(cut -d' ' -f3- <<<"$devices")
    chosen=$(echo "$opts" | module_sub_rofi "Bluetooth" "$mesg")
    [[ -z "$chosen" ]] && return
    mac=$(grep -F -- "$chosen" <<<"$connected" | awk '{print $2; exit}')
    [[ -n "$mac" ]] && bluetoothctl disconnect "$mac"
}

handle_notification() { /bin/bash $ROFI_DIR/scripts/notification.sh; }
handle_sing_box() { /bin/bash $ROFI_DIR/scripts/sing-box.sh; }
handle_calendar() { /bin/bash $WORK_DIR/tools/calendar.sh; }
handle_calendar_lunar() { /bin/bash $WORK_DIR/tools/calendar.sh lunar; }
handle_media_scraping() { /bin/bash $ROFI_DIR/scripts/media-scraping.sh; }
handle_sddm() { /bin/bash $ROFI_DIR/scripts/sddm.sh; }
handle_scrcpy() { /bin/bash $ROFI_DIR/scripts/scrcpy.sh; }
handle_yt_dlp_wrapper() { /bin/bash $ROFI_DIR/scripts/yt-dlp-wrapper.sh; }
handle_steam_workshop() { /bin/bash $ROFI_DIR/scripts/steam-workshop.sh; }
handle_theme() { /bin/bash $ROFI_DIR/scripts/theme.sh; }
handle_xcolor() { /bin/bash $WORK_DIR/tools/color-picker.sh; }
handle_wallpaper() { /bin/bash $ROFI_DIR/scripts/wallpaper.sh; }
handle_touchpad() { /bin/bash $WORK_DIR/tools/touchpad.sh toggle; }
handle_screencast() { /bin/bash $WORK_DIR/dwm-launcher.sh screencast; }

handle_audio_output() {
    local default_sink default_desc line name desc vol
    default_sink=$(pactl info 2>/dev/null | awk -F': ' '/^Default Sink:/ {print $2}')

    local -a sink_names sink_lines

    _sink_flush() {
        [[ -z "$name" || -z "$desc" ]] && return
        [[ "$desc" == *"Controller "* ]] && desc="${desc##*Controller }"
        [[ ${#desc} -gt 35 ]] && desc="…${desc: -32}"
        local icon=" "
        if [[ "$name" == "$default_sink" ]]; then
            icon=""
            default_desc="$desc"
        fi
        sink_names+=("$name")
        sink_lines+=("$icon $desc (${vol:-?})")
    }

    while IFS= read -r line; do
        if [[ "$line" == "Sink "* ]]; then
            _sink_flush
            name=""
            desc=""
            vol=""
        elif [[ "$line" =~ ^[[:space:]]*Volume:[[:space:]] ]]; then
            [[ "$line" =~ ([0-9]+%) ]] && vol="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*Name:[[:space:]]+(.+) ]]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*Description:[[:space:]]+(.+) ]]; then
            desc="${BASH_REMATCH[1]}"
        fi
    done < <(pactl list sinks 2>/dev/null)
    _sink_flush

    ((${#sink_lines[@]} == 0)) && return

    local chosen
    chosen=$(printf '%s\n' "${sink_lines[@]}" | module_sub_rofi "󰓃 Audio Output" "current: ${default_desc:-$default_sink}")
    [[ -z "$chosen" ]] && return

    local idx target_sink
    for idx in "${!sink_lines[@]}"; do
        if [[ "${sink_lines[$idx]}" == "$chosen" ]]; then
            target_sink="${sink_names[$idx]}"
            break
        fi
    done

    [[ -z "$target_sink" ]] && return
    pactl set-default-sink "$target_sink"
}

module_loop
