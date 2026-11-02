#!/bin/bash

# 空闲/锁屏/灭屏的唯一权威链路:
#   xset s 600 → X 屏保激活 (MIT-SCREEN-SAVER) → xss-lock 拉起 LOCKER
#   xss-lock 同时接管 logind 的 lock-session 与挂起/休眠前锁屏。
# 媒体抑制不拆计时器: 有音频时周期性 `xset s reset` 把空闲计数压回 0,
# 解除后自然从 0 重新计时 —— X 服务端处理 ScreenSaverReset 时会把
# lastDeviceEventTime 置为当前时间。旧实现用 `xset s off` + 重新 `xset s 600`,
# 已空闲超过超时时会在重新武装的瞬间触发屏保 (电影一结束就黑屏), 故废弃。

source "$(dirname "$0")/../utils/notify.sh"

screen_saver_time=600 # 空闲多少秒锁屏
duration=20           # 音频抑制轮询间隔 (秒)
SCREEN_DEBUG_NOTIFY=0
LOCKER="$(dirname "$0")/lock.sh"
current_hash=$(md5sum "$0" | awk '{print $1}')

inhibited=0
warned_xss=0

_screensaver_start() {
    # 旧链路 (xautolock) 的私有计时器必须消失, 否则与本链路双重锁屏
    pkill -x xautolock 2>/dev/null
    # xss-lock 常驻; 自重启时直接复用, 不重建 (避免事件丢失窗口)
    if ! pgrep -x xss-lock >/dev/null; then
        # 缺包时保持 daemon 存活并每轮重试: 装上后 duration 秒内自动接管, 不静默丢锁屏
        if ! command -v xss-lock >/dev/null 2>&1; then
            if [ "$warned_xss" -eq 0 ]; then
                warned_xss=1
                system-notify critical "Tool Not Found" "please install xss-lock (extra)"
            fi
            return 1
        fi
        # cycle=0 → 激活即拉起 locker; 关掉 blanking → 不先黑屏 (i3lock 自己铺满)
        # 注意: xset s 一次只接受 [timeout [cycle]] 或单个关键字, 两条必须分开
        xset s "$screen_saver_time" 0
        xset s noblank
        # 解锁态不做 DPMS: 灭屏只发生在锁屏期间 (lock.sh 武装), 两条时间线不打架
        xset dpms 0 0 0
        # 武装时 X 的空闲计数可能早已超时 (xss-lock 在看视频时崩掉/开机晚启), 不归零就会
        # 立刻锁屏。锁屏中绝不能 reset: xss-lock 会把 reset 当成强制解除并杀掉 locker。
        pgrep -x i3lock >/dev/null || xset s reset
        xss-lock -- "$LOCKER" lock & # xss-lock 直接 execv, 参数必须分开传 (不能塞进同一字符串)
    fi
    [[ $SCREEN_DEBUG_NOTIFY -eq 1 ]] && system-notify low "Screensaver" "on (xss-lock)" || true
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

# 有音频且未锁屏 → 把空闲计数压回 0 (抑制); 解除抑制后 X 从 0 重新计时。
# 已锁屏时不参与: lock.sh 已暂停播放, 且 reset 会 unblank 打扰锁屏画面。
_inhibit_poke() {
    if pgrep -x i3lock >/dev/null || ! _has_active_audio; then
        inhibited=0
        return 1
    fi

    xset s reset
    if [ "$inhibited" -eq 0 ]; then
        inhibited=1
        [[ $SCREEN_DEBUG_NOTIFY -eq 1 ]] && system-notify low "Screensaver" "inhibited (audio)" || true
    fi
    return 0
}

daemon() {
    _screensaver_start
    while true; do
        # xss-lock 若异常退出, 空闲事件就再也没人接 (静默失去锁屏保护), 每轮补一次
        pgrep -x xss-lock >/dev/null || _screensaver_start
        _inhibit_poke

        if [[ "$(md5sum "$0" | awk '{print $1}')" != "$current_hash" ]]; then
            /bin/bash "$0" &
            exit 0
        fi

        sleep $duration
    done
}

[ "${SCREEN_NO_DAEMON:-0}" = 1 ] || daemon
