#!/bin/bash

WORK_DIR=$(dirname "$0")

term() {
	# new different termina by $Type
	case "$1" in
	"float")
		shift
		# WINIT_X11_SCALE_FACTOR=1 alacritty --config-file $HOME/.config/alacritty/alacritty-float.toml &
		kitty --class float-term \
			-o font_size=8 \
			-o initial_window_width=160c \
			-o initial_window_height=48c \
			tmux new -s "float-term-$RANDOM" -n main \; set destroy-unattached on &
		;;
	*)
		# WINIT_X11_SCALE_FACTOR=1 alacritty $@ &
		kitty &
		;;
	esac
}

apps() {
	/bin/bash "$WORK_DIR"/rofi/scripts/launcher_t3
}

powermenu() {
	/bin/bash "$WORK_DIR"/rofi/scripts/powermenu_t4
}

mpd() {
	/bin/bash "$WORK_DIR"/rofi/scripts/mpd.sh
}

modules() {
	/bin/bash "$WORK_DIR"/rofi/scripts/module.sh
}

screenshot() {
	/bin/bash "$WORK_DIR"/rofi/scripts/screenshot.sh
}

screencast() {
	/bin/bash "$WORK_DIR"/rofi/scripts/screencast.sh
}

quicklinks() {
	/bin/bash "$WORK_DIR"/rofi/scripts/quicklinks.sh
}

emoji() {
	/bin/bash "$WORK_DIR"/rofi/scripts/emoji.sh
}

toggle_conky() {
	[ ! -z "$(pgrep conky)" ] && pkill conky && return
	conky -U -d
}

wallpaper() {
	/bin/bash "$WORK_DIR"/rofi/scripts/wallpaper.sh
}

case "$1" in
"term") term $2 ;;
"apps") apps ;;
"powermenu") powermenu ;;
"modules") modules ;;
"mpd") mpd ;;
"screenshot") screenshot ;;
"screencast") screencast ;;
"quicklinks") quicklinks ;;
"emoji") emoji ;;
"conky") toggle_conky ;;
"wallpaper") wallpaper ;;
esac
