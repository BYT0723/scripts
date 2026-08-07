#!/bin/bash

WORK_DIR=$(dirname "$0")

term() {
	# new different termina by $Type
	case "$1" in
	"float")
		shift
		local w=160c h=48c
		source "$WORK_DIR"/utils/monitor.sh
		is_portrait && {
			w=100c
			h=56c
		}
		kitty --class float-term \
			-o font_size=8 \
			-o initial_window_width=$w \
			-o initial_window_height=$h \
			tmux new -s "float-term-$RANDOM" -n main \; set destroy-unattached on &
		;;
	*)
		# WINIT_X11_SCALE_FACTOR=1 alacritty $@ &
		kitty &
		;;
	esac
}

apps() { /bin/bash "$WORK_DIR"/rofi/scripts/launcher_t3 "$@"; }
mpd() { /bin/bash "$WORK_DIR"/rofi/scripts/mpd.sh "$@"; }
modules() { /bin/bash "$WORK_DIR"/rofi/scripts/module.sh "$@"; }
screenshot() { [ -z "$1" ] && /bin/bash "$WORK_DIR"/rofi/scripts/screenshot.sh || /bin/bash "$WORK_DIR/tools/screenshot.sh" "$@"; }
screencast() { /bin/bash "$WORK_DIR"/rofi/scripts/screencast.sh "$@"; }
quicklinks() { /bin/bash "$WORK_DIR"/rofi/scripts/quicklinks.sh "$@"; }
emoji() { /bin/bash "$WORK_DIR"/rofi/scripts/emoji.sh "$@"; }
wallpaper() { /bin/bash "$WORK_DIR"/rofi/scripts/wallpaper.sh "$@"; }

powermenu() {
	local type=4
	source "$WORK_DIR"/utils/monitor.sh
	is_portrait && type=2
	/bin/bash "$WORK_DIR"/rofi/scripts/powermenu_t${type}
}

conky_launcher() {
	echo $1
	local action=${1:-toggle}
	local pid=$(pgrep -x conky)

	_launch() {
		conky -U -d &
		sleep 0.5
		xdotool search --class conky windowraise %@
	}

	case "$action" in
	start) [ -z "$pid" ] && _launch ;;
	stop) [ -n "$pid" ] && pkill conky ;;
	toggle) [ -n "$pid" ] && pkill conky || _launch ;;
	*) return ;;
	esac
}

subcmd=$1
shift

case "$subcmd" in
"term") term $@ ;;
"apps") apps $@ ;;
"powermenu") powermenu $@ ;;
"modules") modules $@ ;;
"mpd") mpd $@ ;;
"screenshot") screenshot $@ ;;
"screencast") screencast $@ ;;
"quicklinks") quicklinks $@ ;;
"emoji") emoji $@ ;;
"conky") conky_launcher $@ ;;
"wallpaper") wallpaper $@ ;;
"fm") xdg-open $HOME $@ ;;
esac
