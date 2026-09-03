#!/bin/bash

screen_saver_time=600
dpms_sleep_time=900
dpms_suspend_time=1200
dpms_off_time=1800
duration=600
SCREEN_DEBUG_NOTIFY=0
LOCKER="$(dirname "$0")/lock.sh lock"
current_hash=$(md5sum "$0" | awk '{print $1}')

state=0

_screensaver() {
    if [ "$1" = on ]; then
        if [ $state -eq 1 ]; then
            return
        fi
        pkill xautolock 2>/dev/null
        xautolock -time $((screen_saver_time / 60)) -locker "$LOCKER" -detectsleep &
        xset s $screen_saver_time $screen_saver_time +dpms
        xset dpms $dpms_sleep_time $dpms_suspend_time $dpms_off_time
        state=1
        [[ $SCREEN_DEBUG_NOTIFY -eq 1 ]] && notify-send -t 2000 "[Screensaver and DPMS] enabled" || true
    else
        if [ $state -eq 0 ]; then
            return
        fi
        pkill xautolock 2>/dev/null
        xset s off -dpms
        state=0
        [[ $SCREEN_DEBUG_NOTIFY -eq 1 ]] && notify-send -t 2000 "[Screensaver and DPMS] disabled" || true
    fi
}

_has_active_audio() {
    local rate=48000 channels=2 duration_ms=150 threshold=-78 bytes sink result

    # parec 与 pactl 同包 (pulse 客户端); 缺失则视为无音频检测, 屏保按默认行为启用
    command -v parec >/dev/null 2>&1 || return 1
    sink="$(pactl get-default-sink)" || return 1
    bytes=$((rate * duration_ms / 1000 * channels * 2)) # 150ms 的 s16 双声道字节数

    # 必须走 pulse 层的 parec 而非 raw pw-record: 本机 pw-record 解析不到 *.monitor
    # 节点, 会静默回落到默认麦克风 (录的是输入而非输出)。monitor 采的是 sink 音量
    # 衰减后的信号 (本机 Fosi 30% 音量衰减约 25dB), 故阈值取 -78: 低于典型响度、
    # 高于真静音底 (~-91 dB)。
    result=$(
        parec --device="${sink}.monitor" --format=s16le \
            --rate "$rate" --channels "$channels" --raw 2>/dev/null |
            head -c "$bytes" |
            ffmpeg -hide_banner -nostats -loglevel info \
                -f s16le -ar "$rate" -ac "$channels" \
                -i pipe:0 -af volumedetect -f null - 2>&1 |
            awk '/max_volume:/ { v = $(NF - 1); if (v ~ /^-?[0-9.]+$/) print v; exit }' # 值在行尾 "-<值> dB"; -inf 视为无音量
    )
    [[ -n "$result" ]] || return 1 # 纯静音 max_volume 为 -inf, 无数值视为无活动音频

    awk -v volume="$result" -v threshold="$threshold" \
        'BEGIN { exit !(volume > threshold) }'
}

daemon() {
    _screensaver on
    while true; do
        _has_active_audio && _screensaver off || _screensaver on

        if [[ "$(md5sum "$0" | awk '{print $1}')" != "$current_hash" ]]; then
            /bin/bash "$0" &
            exit 0
        fi

        sleep $duration
    done
}

daemon
