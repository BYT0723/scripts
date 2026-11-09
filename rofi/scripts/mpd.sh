#!/usr/bin/env /bin/bash

ROFI_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"

MODULE_THEME="$ROFI_DIR/applets/type-2/style-3.rasi"
MODULE_WIDTH=800
MODULE_SEARCH_BAR=false

source "$(dirname "${BASH_SOURCE[0]}")"/util.sh
source "$(dirname "${BASH_SOURCE[0]}")"/lib-module.sh

# cover 文件校验: 非空且 MIME 为 image/* (空/损坏文件视为无效)
_cover_valid() { # file
    [[ -s "$1" ]] && [[ "$(file -b --mime-type "$1" 2>/dev/null)" == image/* ]]
}

# 单次 readpicture 请求 → 响应写入 outfile (nc 优先, bash /dev/tcp fallback)
# -q0 而非 -q1: nc 在 stdin EOF 后须等 N 秒才退出, MPD 收到 close 不主动断连,
# -q1 让每块白白多等 1s (fetch_cover 分块拉取时 N 块 ≈ N 秒; 实测 30KB 封面 4 块 4.1s → 88ms)
_mpd_readpicture() { # uri offset outfile
    local uri="$1" offset="$2" outfile="$3"
    local host="${MPD_HOST:-127.0.0.1}" port="${MPD_PORT:-6600}"
    if command -v nc >/dev/null 2>&1; then
        { printf 'readpicture "%s" %s\nclose\n' "$uri" "$offset"; } |
            timeout 5 nc -q0 "$host" "$port" >"$outfile" 2>/dev/null
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
        # bs=1 逐字节 skip+拷贝 O(n) 字节级 syscall, 大封面累积 O(n²) 极慢; iflag=skip_bytes,count_bytes 精确 seek+块拷贝
        dd if="$tmpd/c" iflag=skip_bytes,count_bytes bs=4096 \
            skip=$((off + 8 + ${#bin} + 1)) count="$bin" >>"$out" 2>/dev/null
        offset=$((offset + bin))
        [[ "$offset" -ge "$size" ]] && break
        [[ "$offset" -gt 5000000 ]] && break
    done
    rm -rf "$tmpd"
    if [[ "$size" =~ ^[0-9]+$ ]] && [[ "$size" -gt 0 ]] &&
        [[ "$(wc -c <"$out" 2>/dev/null)" -ge "$size" ]] &&
        _cover_valid "$out"; then
        return 0
    fi
    rm -f "$out"
    return 1
}

if ! command -v mpc &>/dev/null; then
    notify-send -c tools -i dialog-error "MPD" "mpc not found. Please install mpc"
    exit 1
fi

# 有桥时切歌通知由 MPRIS 客户端负责, 无需手动 notify;
# 未安装 mpdris2-rs 时无桥接管, 回退到手动 notify (否则切歌静默)
_have_mpris() { command -v mpdris2-rs >/dev/null 2>&1; }

# mpdris2-rs 通知模板 — repo 即配置源, 由 _mpris_override_action 生成 systemd drop-in
# (service 本身不含参数, ~/.config/systemd 也不在备份范围; 生成物由本脚本重建)。
# 占位符: %state% %title% %artist% %album% %album_artist% %elapsed% %duration% %empty% 等;
# 正文用 \n 换行。改完下次打开本菜单即生效 (内容变了才 restart)。
MPDRIS2_NOTIFY_ARGS=(
    --notification-summary "%state%"
    --notification-summary-paused "%state%"
    --notification-body "<b>%title%</b>\n%artist%\n%album%\n%empty%"
    --notification-body-paused "<b>%title%</b>\n%artist%\n%album%\n%empty%"
)

# 生成/更新用户级 drop-in, 输出 systemctl 动作 (start|restart)。
# 模板没变 → start (幂等, 不打断正在运行的桥); 变了 → daemon-reload 后 restart。
# unit 里 % 是 specifier, 写入时必须转义成 %%; 数组里仍写单 % 便于阅读。
_mpris_override_action() {
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/mpdris2-rs.service.d"
    local file="$dir/override.conf"
    local cmdline="ExecStart=/usr/bin/mpdris2-rs"
    local want flag val i
    for ((i = 0; i < ${#MPDRIS2_NOTIFY_ARGS[@]}; i += 2)); do
        flag="${MPDRIS2_NOTIFY_ARGS[i]}"
        val="${MPDRIS2_NOTIFY_ARGS[i + 1]}"
        val="${val//$'\n'/\\n}" # 真实换行会破坏 unit 单行语法
        val="${val//\"/\\\"}"   # unit 双引号内需转义
        val="${val//%/%%}"      # systemd specifier 转义
        cmdline+=" $flag \"$val\""
    done
    want=$'[Service]\nExecStart=\n'"$cmdline"
    if [[ -f "$file" && "$(<"$file")" == "$want" ]]; then
        printf 'start'
        return
    fi
    # 写失败按未变处理: 继续用现有/默认配置, 不因生成配置挡住菜单
    mkdir -p "$dir" 2>/dev/null &&
        printf '%s\n' "$want" >"$file" 2>/dev/null || {
        printf 'start'
        return
    }
    systemctl --user daemon-reload >/dev/null 2>&1
    printf 'restart'
}

# MPRIS 桥: MPD 就绪后确保 mpdris2-rs 在运行 (systemd user service);
# 未安装只通知不中断 (菜单照常打开)
_ensure_mpris_bridge() {
    if ! _have_mpris; then
        notify-send -c tools -i dialog-error "MPRIS" "mpdris2-rs not found. Please install mpdris2-rs"
        return 0
    fi
    systemctl --user "$(_mpris_override_action)" mpdris2-rs.service >/dev/null 2>&1
}

if ! mpc status &>/dev/null; then
    systemctl --user start mpd.service >/dev/null 2>&1

    if ! mpc status &>/dev/null; then
        notify-send -c tools -i dialog-error "MPD" "Failed to start MPD"
        exit 1
    fi
fi

_ensure_mpris_bridge

status=$(mpc status "%state%")

repeat_state=$(mpc status "%repeat%")
random_state=$(mpc status "%random%")
single_state=$(mpc status "%single%")

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

song=$(get_current_song)
MODULE_NAME=" ${song:0:30}"
MODULE_MESG="$(mpc status "%currenttime%/%totaltime%  墳 %volume%")"

# 封面: 从 MPD 拉取当前歌曲内嵌图 → icon-cover 注入 (icon widget size 强制 1:1)
# cache 命中直接用封面; 未命中同步拉取 (fetch_cover 已优化 ~50ms), 失败回退默认图
MODULE_THEME_STR=()
song_file=$(mpc -f '%file%' current | head -1)
if [[ -n "$song_file" ]]; then
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dwm/mpd-cover"
    mkdir -p "$cache_dir" 2>/dev/null
    uri_hash=$(printf '%s' "$song_file" | cksum | cut -d' ' -f1)
    cover="$cache_dir/mpd-cover-$uri_hash.jpg"
    img="$ROFI_DIR/images/flowers-2.png"
    if _cover_valid "$cover"; then
        img="$cover"
    else
        rm -f "$cover"
        fetch_cover "$song_file" "$cover" && img="$cover"
    fi
    MODULE_THEME_STR=(
        "icon-cover { enabled: true; filename: \"$img\"; size: 200; expand: false; margin: 0; border-radius: 20px; background-color: transparent; }"
        "mainbox { enabled: true; padding: 20px; background-color: transparent; orientation: horizontal; children: [\"icon-cover\", \"rightbox\"]; }"
        "rightbox { enabled: true; orientation: vertical; spacing: 20px; margin: 10px; background-color: transparent; children: [\"inputbar\", \"message\", \"listview\"]; }"
        "element { padding: 10px 0px 10px 8px;}"
        "element-text { font: \"JetBrains Mono Nerd Font 18\";}"
        "* { font: \"JetBrains Mono Nerd Font 12\";}"
        "listview {columns: 8; lines: 1; flow: horizontal;}"
    )
fi

play_icon=$([[ "$status" == "playing" ]] && echo "" || echo "")
play_label=$([[ "$status" == "playing" ]] && echo "Pause" || echo "Play")

# Repeat/Random 高亮索引 (基于注册表行序)
active_idx="" urgent_idx=""
[[ "$repeat_state" == "on" ]] && active_idx="4"
[[ "$repeat_state" == "off" ]] && urgent_idx="4"
[[ "$random_state" == "on" ]] && active_idx="${active_idx}${active_idx:+,}5"
[[ "$random_state" == "off" ]] && urgent_idx="${urgent_idx}${urgent_idx:+,}5"
[[ "$single_state" == "on" ]] && active_idx="${active_idx}${active_idx:+,}6"
[[ "$single_state" == "off" ]] && urgent_idx="${urgent_idx}${urgent_idx:+,}6"
MODULE_ACTIVE="$active_idx"
MODULE_URGENT="$urgent_idx"

module_parse <<MODULES
play-pause|${play_icon}|${play_label}|
stop||Stop|
prev|󰒮|Previous|
next|󰒭|Next|
repeat||Repeat|
random||Random|
single|󰬺|Single|
MODULES

_handle_play_icon() {
    [[ "$status" == "playing" ]] && echo "media-playback-pause-symbolic" || echo "media-playback-start-symbolic"
}

# 有桥时直接返回 (MPRIS 接管通知, 避免重复); 无桥时手动 notify 兜底
_notify_song() { # icon
    _have_mpris && return 0
    notify-send -c mpd -i "$1" \
        -h string:x-dunst-stack-tag:music_info \
        "$(get_current_song)"
}

handle_play_pause() { mpc -q toggle; _notify_song "$(_handle_play_icon)"; }
handle_stop() { mpc -q stop; }
handle_prev() { mpc -q prev; _notify_song "$(_handle_play_icon)"; }
handle_next() { mpc -q next; _notify_song "$(_handle_play_icon)"; }
handle_repeat() { mpc -q repeat; }
handle_random() { mpc -q random; }
handle_single() { mpc -q single; }

module_loop
