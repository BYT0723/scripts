#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

MODULE_THEME="$ROFI_DIR/applets/type-2/style-3.rasi"
MODULE_WIDTH=900
MODULE_SEARCH_BAR=false

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

status=$(mpc status "%state%")
repeat_state=$(mpc status "%repeat%")
random_state=$(mpc status "%random%")

get_current_song() {
    local title artist file

    title="$(mpc -f '%title%' current)"
    artist="$(mpc -f '%artist%' current)"

    if [[ -n "$title" && -n "$artist" ]]; then
        printf '%s - %s' "$title" "$artist"
        return
    fi

    if [[ -n "$title" ]]; then
        printf '%s' "$title"
        return
    fi

    if [[ -n "$artist" ]]; then
        printf '%s' "$artist"
        return
    fi

    file="$(mpc -f '%file%' current)"
    file="${file##*/}"
    printf '%s' "${file%.*}"
}

if [[ -z "$status" ]]; then
    MODULE_NAME=" Offline"
    MODULE_MESG="MPD is Offline"

    module_parse <<MODULES
start|⏻|Start Local MPD|
MODULES

    handle_start() { mpd; }
else
    song=$(get_current_song)
    MODULE_NAME=" ${song:0:30}"
    MODULE_MESG="$(mpc status "%currenttime%/%totaltime%  墳 %volume%")"

    play_icon=$([[ "$status" == "playing" ]] && echo "󰏤" || echo "󰐊")
    play_label=$([[ "$status" == "playing" ]] && echo "Pause" || echo "Play")

    # Repeat/Random 高亮索引 (基于注册表行序)
    active_idx="" urgent_idx=""
    [[ "$repeat_state" == "on" ]] && active_idx="6"
    [[ "$repeat_state" == "off" ]] && urgent_idx="6"
    [[ "$random_state" == "on" ]] && active_idx="${active_idx}${active_idx:+,}7"
    [[ "$random_state" == "off" ]] && urgent_idx="${urgent_idx}${urgent_idx:+,}7"
    MODULE_ACTIVE="$active_idx"
    MODULE_URGENT="$urgent_idx"

    module_parse <<MODULES
play-pause|${play_icon}|${play_label}|
stop|󰓛|Stop|
prev|󰒮|Previous|
next|󰒭|Next|
vol-down|󰝞|Down|
vol-up|󰝝|Up|
repeat|󰑖|Repeat|
random||Random|
MODULES

    _handle_play_icon() {
        [[ "$status" == "playing" ]] && echo "media-playback-pause-symbolic" || echo "media-playback-start-symbolic"
    }

    handle_play_pause() {
        mpc -q toggle
        notify-send -c mpd -i "$(_handle_play_icon)" \
            -h string:x-dunst-stack-tag:music_info \
            "$(get_current_song)"
    }
    handle_stop() { mpc -q stop; }
    handle_prev() {
        mpc -q prev
        notify-send -c mpd -i "$(_handle_play_icon)" \
            -h string:x-dunst-stack-tag:music_info \
            "$(get_current_song)"
    }
    handle_next() {
        mpc -q next
        notify-send -c mpd -i "$(_handle_play_icon)" \
            -h string:x-dunst-stack-tag:music_info \
            "$(get_current_song)"
    }
    handle_vol_down() {
        mpc volume -20
        local current=$(mpc volume | cut -d':' -f2 | cut -d' ' -f2 | cut -d'%' -f1)
        notify-send -c mpd -h string:x-dunst-stack-tag:music_volumn_info \
            -h int:value:"${current}" "MPD Volume: $current"
    }
    handle_vol_up() {
        mpc volume +20
        local current=$(mpc volume | cut -d':' -f2 | cut -d' ' -f2 | cut -d'%' -f1)
        notify-send -c mpd -h string:x-dunst-stack-tag:music_volumn_info \
            -h int:value:"${current}" "MPD Volume: $current"
    }
    handle_repeat() { mpc -q repeat; }
    handle_random() { mpc -q random; }
fi

module_loop
