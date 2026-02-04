#!/bin/bash

WORKDIR=$(dirname "$0")

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
	/bin/bash "$WORKDIR"/rofi/scripts/launcher_t3
}

powermenu() {
	/bin/bash "$WORKDIR"/rofi/scripts/powermenu_t2
}

mpd() {
	/bin/bash "$WORKDIR"/rofi/scripts/mpd.sh
}

modules() {
	/bin/bash "$WORKDIR"/rofi/scripts/module.sh
}

screenshot() {
	/bin/bash "$WORKDIR"/rofi/scripts/screenshot.sh
}

screencast() {
	/bin/bash "$WORKDIR"/rofi/scripts/screencast.sh
}

quicklinks() {
	/bin/bash "$WORKDIR"/rofi/scripts/quicklinks.sh
}

emoji() {
	/bin/bash "$WORKDIR"/rofi/scripts/emoji.sh
}

case "$1" in
"term")
	term $2
	;;
"apps")
	apps
	;;
"powermenu")
	powermenu
	;;
"modules")
	modules
	;;
"mpd")
	mpd
	;;
"screenshot")
	screenshot
	;;
"screencast")
	screencast
	;;
"quicklinks")
	quicklinks
	;;
"emoji")
	emoji
	;;
esac
