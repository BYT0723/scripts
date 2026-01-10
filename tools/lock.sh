#!/usr/bin/env bash

source "$(dirname $0)/../utils/notify.sh"

[ -z "$(command -v i3lock)" ] && system-notify critical "Tool Not Found" "please install i3lock-color and archlinux-wallpaper for aur" && exit

alpha='cc'
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

i3lock \
	-i /usr/share/backgrounds/archlinux/archwave.png \
	--insidever-color=$base02$alpha \
	--insidewrong-color=$base02$alpha \
	--inside-color=$base02$alpha \
	--ringver-color=$green$alpha \
	--ringwrong-color=$red$alpha \
	--ringver-color=$green$alpha \
	--ringwrong-color=$red$alpha \
	--ring-color=$blue$alpha \
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
	--time-str="%H:%M:%S" \
	--date-str="%A, %Y-%m-%d" \
	--verif-text="Verifying..." \
	--wrong-text="Auth Failed" \
	--noinput="Press Password!" \
	--lock-text="Locking..." \
	--lockfailed="Lock Failed" \
	--time-font="ComicShannsMono Nerd Font Mono" \
	--time-size=50 \
	--date-font="Xiaolai Mono SC" \
	--date-size=20 \
	--layout-font="ComicShannsMono Nerd Font Mono" \
	--verif-font="ComicShannsMono Nerd Font Mono" \
	--wrong-font="ComicShannsMono Nerd Font Mono" \
	--radius=160 \
	--ring-width=10 \
	--pass-media-keys \
	--pass-screen-keys \
	--pass-volume-keys
