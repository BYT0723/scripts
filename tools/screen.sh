#!/bin/bash

# 空闲/锁屏/灭屏的唯一权威链路:
#   xset s (锁屏时刻-预告) <预告> → 空闲到点先压暗提示, cycle 到点 X 屏保再次触发
#   (SCREEN_SAVER_CYCLE) → xss-lock 拉起 LOCKER; 预告时段由 xss-lock -n 的通知器负责。
#   xss-lock 同时接管 logind 的 lock-session 与挂起/休眠前锁屏。
# 媒体抑制不拆计时器: 有音频时周期性 `xset s reset` 把空闲计数压回 0,
# 解除后自然从 0 重新计时 —— X 服务端处理 ScreenSaverReset 时会把
# lastDeviceEventTime 置为当前时间。旧实现用 `xset s off` + 重新 `xset s 600`,
# 已空闲超过超时时会在重新武装的瞬间触发屏保 (电影一结束就黑屏), 故废弃。
#
# 子命令 (仅供 xss-lock -n 使用, 不在 daemon 里跑):
#   screen.sh notifier  → 压暗屏幕作为锁屏预告; SIGHUP(用户活动)/SIGTERM(上锁前) 还原

# BASH_SOURCE[0] 而非 $0: 被 source (测试) 时 $0 是调用者, 路径会算错
source "$(dirname "${BASH_SOURCE[0]}")/../utils/notify.sh"

screen_saver_time=600 # 空闲多少秒锁屏
warn_seconds=30       # 锁屏前多少秒压暗提示 (= xset cycle; 0 或 >= 锁屏时刻则关闭)
dim_gamma=0.4         # 预告时的 gamma 亮度乘数 (1.0 = 不压暗)
duration=${SCREEN_TICK:-20} # 音频抑制轮询间隔 (秒); SCREEN_TICK 仅供测试缩短
SCREEN_DEBUG_NOTIFY=0
SELF="${BASH_SOURCE[0]}"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
LOCKER="${SELF%/*}/lock.sh"
arm_file="${SCREEN_ARM_FILE:-/tmp/dwm-status/screen-arm.fp}"
current_hash=$(md5sum "$SELF" | awk '{print $1}')

inhibited=0
warned_xss=0

# 已启用的输出 (以 xrandr 报告的几何为准; connected 但未启用的 eDP 之类会被跳过)。
# 几何字段位置不固定: primary 输出是 $4, 普通输出是 $3, 故扫一遍字段。
_active_outputs() {
    xrandr --query 2>/dev/null |
        awk '/ connected / { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+x[0-9]+\+/) { print $1; break } }'
}

# 对所有已启用输出设置 gamma 亮度乘数 (不动硬件亮度)
_set_screen_gamma() {
    local level=$1 output
    while read -r output; do
        [ -n "$output" ] && xrandr --output "$output" --brightness "$level" 2>/dev/null
    done < <(_active_outputs)
}

_dim_done=0
_dim_sleep_pid=""

# gamma 还原 (幂等): 正常退出 / 用户活动 (SIGHUP) / 上锁前 (SIGTERM) 都会走
_dim_stop() {
    [ "$_dim_done" -eq 1 ] && return 0
    _dim_done=1
    [ -n "$_dim_sleep_pid" ] && kill "$_dim_sleep_pid" 2>/dev/null
    _set_screen_gamma 1.0
}

# xss-lock -n 通知器 (screen.sh notifier): 锁屏前压暗作为提示。
# 生命周期归 xss-lock: 空闲到 (锁屏时刻-预告) 启动, 上锁前被 SIGTERM; 一动键鼠被 SIGHUP。
# 两种信号都必须还原 gamma, 否则会停在暗屏 (锁屏/解锁画面也会暗)。
_notifier() {
    command -v xrandr >/dev/null 2>&1 || return 0
    [ -n "$(_active_outputs)" ] || return 0

    trap '_dim_stop' HUP INT TERM EXIT
    _set_screen_gamma "$dim_gamma"
    # 前台 sleep 会把 trap 推迟到睡醒, 必须后台 + wait 才能及时响应 HUP/TERM
    sleep 2147483647 &
    _dim_sleep_pid=$!
    wait
}

# 实际生效的预告秒数 (0 = 无预告); 越界/非正数一律按关闭处理
_effective_warn() {
    if ((warn_seconds > 0 && warn_seconds < screen_saver_time)); then
        printf '%s' "$warn_seconds"
    else
        printf '0'
    fi
}

# 处于"不能重启 xss-lock"的状态: 锁屏中重启会让它的 exit_service SIGTERM 掉 i3lock
# (等于直接解锁); 压暗中重启会杀掉 notifier (亮度会还原, 但本轮提示丢失)。
# 推迟到这两个状态结束后, 由 daemon 每轮的 _ensure_xss_lock 补齐。
_rearm_deferred() {
    pgrep -x i3lock >/dev/null && return 0
    pgrep -f 'screen\.sh notifier' >/dev/null && return 0
    return 1
}

# 保证 xss-lock 在跑且参数与当前配置一致 (daemon 启动与每轮都会调)。
# 指纹任何一项变了都要重启 (xss-lock 启动后不再重读这些值)。
_ensure_xss_lock() {
    local warn want fps=""
    warn=$(_effective_warn)
    printf -v want '%s|%s|%s|%s|%s' "$warn" "$screen_saver_time" "$dim_gamma" "$SELF" "$LOCKER"
    [ -f "$arm_file" ] && IFS= read -r fps <"$arm_file"

    if pgrep -x xss-lock >/dev/null; then
        [ "$fps" = "$want" ] && return 0
        _rearm_deferred && return 0
        # 必须等旧实例真正退出: 新实例会因 screensaver 已被占用 (SetAttributes) 直接报错退出
        pkill -x xss-lock 2>/dev/null
        for _ in {1..20}; do
            pgrep -x xss-lock >/dev/null || break
            sleep 0.1
        done
    fi

    [ -d "${arm_file%/*}" ] || mkdir -p "${arm_file%/*}" 2>/dev/null
    printf '%s\n' "$want" >"$arm_file" 2>/dev/null
    # xss-lock 直接 execv (不经 shell), notifier 必须是可执行 argv;
    # 本文件没有 +x, 故显式用 /bin/bash 解释。
    xss-lock -n "/bin/bash $SELF notifier" -- "$LOCKER" lock &
}

_screensaver_start() {
    # 旧链路 (xautolock) 的私有计时器必须消失, 否则与本链路双重锁屏
    pkill -x xautolock 2>/dev/null
    # 缺包时保持 daemon 存活并每轮重试: 装上后 duration 秒内自动接管, 不静默丢锁屏。
    # 已有存活实例 (热重启前拉起的) 则继续走武装对账, 不做缺包早退。
    if ! command -v xss-lock >/dev/null 2>&1 && ! pgrep -x xss-lock >/dev/null; then
        if [ "$warned_xss" -eq 0 ]; then
            warned_xss=1
            system-notify critical "Tool Not Found" "please install xss-lock (extra)"
        fi
        return 1
    fi
    # 预告时段: timeout = 锁屏时刻 - 预告, cycle = 预告 (Xorg 第二次 ON 转 CYCLE → 上锁)。
    # xset s 只是重设 timer, 空闲判定仍基于 LastEventTime (xserver ProcSetScreenSaver),
    # 故重复武装不会延长/缩短空闲计时。注意 xset s 一次只接受 [timeout [cycle]] 或关键字。
    local warn
    warn=$(_effective_warn)
    if [ "$warn" -gt 0 ]; then
        xset s $((screen_saver_time - warn)) "$warn"
    else
        xset s "$screen_saver_time" 0
    fi
    xset s noblank
    # 解锁态不做 DPMS: 灭屏只发生在锁屏期间 (lock.sh 武装), 两条时间线不打架
    xset dpms 0 0 0
    # 武装时 X 的空闲计数可能早已超时 (xss-lock 在看视频时崩掉/开机晚启), 不归零就会
    # 立刻锁屏。锁屏中绝不能 reset: xss-lock 会把 reset 当成强制解除并杀掉 locker。
    pgrep -x i3lock >/dev/null || xset s reset

    _ensure_xss_lock

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

# /proc/<pid>/stat 的 comm 可含空格, 先切掉 "pid (comm) " 再取 starttime
# (去掉前两字段后 state 是第 1 个, starttime 是第 20 个)
_proc_start_time() {
    sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'
}

# argv 恰为 [/bin/bash, <本文件>] 的进程才是 daemon; `... screen.sh notifier` 是子命令, 不能误杀
_is_self_daemon() {
    local -a argv
    # 2>/dev/null 必须写在输入重定向之前: pgrep 到读取之间进程可能已退出
    mapfile -d '' -t argv 2>/dev/null <"/proc/$1/cmdline" || return 1
    [ "${#argv[@]}" -eq 2 ] && [ "${argv[1]}" = "$SELF" ]
}

# 单实例接管: 热重启时 launch 用的是它记录的 pid, 而自重启 (旧实现 fork 新 pid) 会让该记录失真,
# 于是新旧实例并存。这里由"后启动者"清理更早的实例, 保证全局只有一个 daemon。
# 只杀比自己早启动的 (starttime 相同则比 pid), 避免两个新实例互杀导致一个都不剩。
_takeover() {
    local p mine theirs
    mine=$(_proc_start_time "$$")
    [ -n "$mine" ] || return 0
    for p in $(pgrep -f "$SELF" 2>/dev/null); do
        [ "$p" = "$$" ] && continue
        _is_self_daemon "$p" || continue
        theirs=$(_proc_start_time "$p")
        [ -n "$theirs" ] || continue
        if [ "$theirs" -lt "$mine" ] || { [ "$theirs" -eq "$mine" ] && [ "$p" -lt "$$" ]; }; then
            kill "$p" 2>/dev/null
        fi
    done
}

daemon() {
    _takeover
    _screensaver_start
    while true; do
        # xss-lock 若异常退出, 空闲事件就再也没人接 (静默失去锁屏保护), 每轮补一次;
        # 锁屏/压暗中被推迟的重新武装也在状态结束后由这里补齐。
        if pgrep -x xss-lock >/dev/null; then
            _ensure_xss_lock
        else
            _screensaver_start
        fi
        _inhibit_poke

        if [[ "$(md5sum "$SELF" | awk '{print $1}')" != "$current_hash" ]]; then
            # exec 保持 pid: 旧实现 fork 新进程会换 pid, launch 记录的 autostart-launch-screen.pid
            # 随即失真 → 下次热重启 kill 不中, 新旧实例并存。
            exec /bin/bash "$SELF" daemon
        fi

        sleep $duration
    done
}

# 直接执行才分发; 被 source (测试) 时只加载函数, 避免误起 daemon/通知器。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-daemon}" in
    notifier) _notifier ;;
    daemon) [ "${SCREEN_NO_DAEMON:-0}" = 1 ] || daemon ;;
    esac
fi
