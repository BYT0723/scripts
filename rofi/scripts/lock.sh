#!/bin/bash

source "$(dirname $0)/../../utils/notify.sh"

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
wallpaper=$(find $wallpaperDir -maxdepth 1 -type f -regextype posix-extended -regex ".*\.(jpg|png|jpeg)" | shuf -n 1)

# PERF: use --image，keypress and keyrelease handle will be slow
# or use https://github.com/BYT0723/i3lock-color (i3lock-color fork)

# 当前的一些状态
mpd_status=$(mpc status | awk 'NR==2 {print $1}')
volume_status=$(amixer get Master | tail -n1 | sed -r 's/.*\[(.*)\].*/\1/')

_lock() {
	i3lock \
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
	[ "$mpd_status" == "[playing]" ] && mpc -q toggle
	[ "$volume_status" == "on" ] && amixer set Master off >>/dev/null
}

_lock_after() {
	[ "$mpd_status" == "[playing]" ] && mpc -q toggle
	[ "$volume_status" == "on" ] && amixer set Master on >>/dev/null
}

_screen_lock_loop() {
	if ! command -v xprintidle >/dev/null 2>&1; then
		system-notify critical "Tool Not Found" "please install xprintidle"
		return
	fi

	while pgrep -x i3lock >/dev/null; do
		while pgrep -x i3lock >/dev/null && ! xset q 2>/dev/null | grep -q "Monitor is On"; do sleep 1; done
		pgrep -x i3lock >/dev/null || break
		while pgrep -x i3lock >/dev/null && [ "$(xprintidle 2>/dev/null)" -lt 10000 ]; do sleep 1; done
		pgrep -x i3lock >/dev/null || break
		xdotool key Escape 2>/dev/null
		sleep 1
		xset dpms force standby
	done
}
