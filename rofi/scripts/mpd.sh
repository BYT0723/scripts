#!/usr/bin/env /bin/bash

ROFI_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"

MODULE_THEME="$ROFI_DIR/applets/type-2/style-3.rasi"
MODULE_WIDTH=900
MODULE_SEARCH_BAR=false

source "$(dirname "${BASH_SOURCE[0]}")"/util.sh
source "$(dirname "${BASH_SOURCE[0]}")"/lib-module.sh

# 单次 readpicture 请求 → 响应写入 outfile (nc 优先, bash /dev/tcp fallback)
_mpd_readpicture() { # uri offset outfile
    local uri="$1" offset="$2" outfile="$3"
    local host="${MPD_HOST:-127.0.0.1}" port="${MPD_PORT:-6600}"
    if command -v nc >/dev/null 2>&1; then
        { printf 'readpicture "%s" %s\nclose\n' "$uri" "$offset"; } |
            timeout 5 nc -q1 "$host" "$port" >"$outfile" 2>/dev/null
    else
        exec 3<>"/dev/tcp/$host/$port" || return 1
        printf 'readpicture "%s" %s\nclose\n' "$uri" "$offset" >&3
        cat <&3 >"$outfile"
        exec 3<&-
    fi
}

# 分块拉取当前歌曲内嵌封面 → out (offset 递增拼接), 成功返回 0
fetch_cover() { # uri outfile
    local uri="$1" out="$2"
    local tmpd size="" offset=0 bin off
    tmpd="$(mktemp -d)" || return 1
    : >"$out"
    while true; do
        _mpd_readpicture "$uri" "$offset" "$tmpd/c" || break
        [[ -z "$size" ]] && size=$(grep -ao 'size: [0-9]*' "$tmpd/c" | head -1 | cut -d' ' -f2)
        bin=$(grep -ao 'binary: [0-9]*' "$tmpd/c" | tail -1 | cut -d' ' -f2)
        [[ "$bin" =~ ^[0-9]+$ ]] && [[ "$bin" -gt 0 ]] || break
        off=$(grep -abo 'binary:' "$tmpd/c" | tail -1 | cut -d: -f1)
        dd if="$tmpd/c" bs=1 skip=$((off + 8 + ${#bin} + 1)) count="$bin" >>"$out" 2>/dev/null
        offset=$((offset + bin))
        [[ "$offset" -ge "$size" ]] && break
        [[ "$offset" -gt 5000000 ]] && break
    done
    rm -rf "$tmpd"
    [[ "$size" =~ ^[0-9]+$ ]] && [[ "$size" -gt 0 ]] && [[ "$(wc -c <"$out" 2>/dev/null)" -ge "$size" ]] && return 0
    return 1
}

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

    # 封面: 从 MPD 拉取当前歌曲内嵌图 → imagebox 覆盖
    # cache 命中直接用封面; 未命中先用默认图并后台异步拉取 (下次打开生效)
    MODULE_THEME_STR=()
    song_file=$(mpc -f '%file%' current | head -1)
    if [[ -n "$song_file" ]]; then
        cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dwm/mpd-cover"
        mkdir -p "$cache_dir" 2>/dev/null
        uri_hash=$(printf '%s' "$song_file" | cksum | cut -d' ' -f1)
        cover="$cache_dir/mpd-cover-$uri_hash.jpg"
        img="$cover"
        if [[ ! -f "$cover" ]]; then
            img="$ROFI_DIR/images/j.jpg"
            (
                fetch_cover "$song_file" "$cover" &
                disown
            ) 2>/dev/null
        fi
        MODULE_THEME_STR=(
            "imagebox { enabled: true; width: 200px; expand: false; margin: 0; border-radius: 10px; background-color: transparent; background-image: url(\"$img\", both); }"
            "mainbox { enabled: true; padding: 20px; background-color: transparent; orientation: horizontal; children: [\"imagebox\", \"rightbox\"]; }"
            "rightbox { enabled: true; orientation: vertical; spacing: 10px; margin: 0px; background-color: transparent; children: [\"inputbar\", \"message\", \"listview\"]; }"
            "element { padding: 20px 0px 20px 5px;}"
            "element-text { font: \"JetBrains Mono Nerd Font 18\";}"
        )
    fi

    play_icon=$([[ "$status" == "playing" ]] && echo "" || echo "")
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
stop||Stop|
prev|󰒮|Previous|
next|󰒭|Next|
vol-down|󰝞|Down|
vol-up|󰝝|Up|
repeat||Repeat|
random||Random|
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
