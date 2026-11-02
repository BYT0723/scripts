#!/bin/bash

source "$(dirname "$0")/../utils/notify.sh"

[ -z "$(command -v i3lock)" ] && system-notify critical "Tool Not Found" "please install i3lock-color and archlinux-wallpaper for aur" && exit 1

pgrep -x i3lock >/dev/null && exit 0

LANG=en_US.UTF-8

backAlpha='dd'
alpha='cc'
ringAlpha='88'
back='#000000'
base03='#002b36'
base02='#073642'
base01='#586e75'
base00='#657b83'
base0='#839496'
base1='#93a1a1'
base2='#eee8d5'
base3='#fdf6e3'
yellow='#b58900'
orange='#cb4b16'
red='#dc322f'
magenta='#d33682'
violet='#6c71c4'
blue='#268bd2'
cyan='#2aa198'
green='#859900'

wallpaperDir=/usr/share/backgrounds/archlinux/
wallpaper=$(find "$wallpaperDir" -maxdepth 1 -type f -regextype posix-extended -regex ".*\.(jpg|png|jpeg)" | shuf -n 1)

# PERF: use --image，keypress and keyrelease handle will be slow
# or use https://github.com/BYT0723/i3lock-color (i3lock-color fork)

lock_dpms_timeout=30 # 锁屏期间最后一次输入后多少秒灭屏

_lock() {
    # DPMS 只在锁屏期间武装: 解锁态由 screen.sh 置 0 0 0, 灭屏不与空闲计时互相覆盖。
    # 每次输入会重置 X 的 DPMS 计时, 故唤醒后 lock_dpms_timeout 秒再次熄灭 (无需轮询)。
    xset dpms $lock_dpms_timeout $lock_dpms_timeout $lock_dpms_timeout
    # -n (nofork) 必须保留: i3lock 默认 fork, 父进程立刻退出会让下面的 wait 立即返回,
    # 于是 _lock_after 在锁屏期间就执行 (静音/DPMS 被立刻还原 → 锁屏后照样出声)。
    i3lock \
        -n \
        -i "$wallpaper" \
        --slideshow-interval 60 \
        --slideshow-random-selection \
        -F \
        --color=$back$backAlpha \
        --insidever-color=$base02$alpha \
        --insidewrong-color=$base02$alpha \
        --inside-color=$base02$alpha \
        --ringver-color=$green$ringAlpha \
        --ringwrong-color=$red$ringAlpha \
        --ringver-color=$green$ringAlpha \
        --ringwrong-color=$red$ringAlpha \
        --ring-color=$blue$ringAlpha \
        --line-uses-ring \
        --keyhl-color=$magenta$alpha \
        --bshl-color=$orange$alpha \
        --separator-color=$base01$alpha \
        --verif-color=$green \
        --wrong-color=$red \
        --layout-color=$blue \
        --date-color=$blue \
        --time-color=$blue \
        --clock \
        --indicator \
        --ignore-empty-password \
        --time-str="%H:%M:%S" \
        --date-str="%A, %Y-%m-%d" \
        --verif-text="Verifying..." \
        --wrong-text="Auth Failed" \
        --noinput="Press Password!" \
        --lock-text="Locking..." \
        --lockfailed="Lock Failed" \
        --time-size=50 \
        --date-font="Noto Sans CJK SC" \
        --date-size=20 \
        --radius=160 \
        --ring-width=10 \
        --pass-media-keys \
        --pass-screen-keys \
        --pass-volume-keys $@ &
    sleep 1
    xset dpms force standby
}

_lock_before() {
    # 快照必须在这里取: powermenu 是先 source 本脚本、再等用户点菜单,
    # 顶层取值会拿到几分钟前的状态, 期间开始的播放就暂停/静音不了。
    mpd_status=$(mpc status | awk 'NR==2 {print $1}')
    [ "$mpd_status" == "[playing]" ] && mpc -q toggle

    # 静音必须走 pulse 层: `amixer set Master off` 只作用于 ALSA 默认控制卡
    # (本机是卡 3 内屏), 而实际出声的 sink 可能是 Fosi USB DAC (卡 1, 只有 PCM)、
    # HDMI (卡 2) 或 easyeffects_sink (虚拟) → 打不中, 锁屏后照样出声。
    # 逐个 sink 静音, 只记录我们改过的, 解锁时原样还原。
    muted_sinks=()
    local _idx sink _rest
    while read -r _idx sink _rest; do
        [ -n "$sink" ] || continue
        [ "$(pactl get-sink-mute "$sink" 2>/dev/null | awk '{print $2}')" = "no" ] || continue
        muted_sinks+=("$sink")
        pactl set-sink-mute "$sink" 1 2>/dev/null
    done < <(pactl list short sinks 2>/dev/null)

    pkill -STOP -f "mpv.*--player-operation-mode=cplayer" 2>/dev/null
    pkill -STOP -x xwallpaperd 2>/dev/null
    pkill -STOP -x xwallpaper 2>/dev/null
}

_lock_after() {
    [ "$mpd_status" == "[playing]" ] && mpc -q toggle
    local sink
    for sink in "${muted_sinks[@]}"; do
        pactl set-sink-mute "$sink" 0 2>/dev/null
    done
    pkill -CONT -f "mpv.*--player-operation-mode=cplayer" 2>/dev/null
    pkill -CONT -x xwallpaperd 2>/dev/null
    pkill -CONT -x xwallpaper 2>/dev/null
    # 解锁后收回 DPMS: 灭屏只属于锁屏期, 否则会在解除抑制/解锁后立刻熄屏
    xset dpms 0 0 0
}

lock() {
    _lock_before
    _lock
    wait
    _lock_after
}

suspend() {
    _lock_before
    _lock
    systemctl suspend
    wait
    _lock_after
}

case "$1" in
lock)
    shift
    lock $@
    ;;
suspend)
    shift
    suspend
    ;;
esac
