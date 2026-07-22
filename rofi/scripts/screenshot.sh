#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_WIDTH=500
MODULE_NAME=" Screenshot"
MODULE_MESG="screen capture"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

DIR="$(xdg-user-dir)/Screenshots"
[[ ! -d "$DIR" ]] && mkdir -p "$DIR"

time=$(date +%Y-%m-%d-%H-%M-%S)
geometry=$(xrandr | grep 'current' | head -n1 | cut -d',' -f2 | tr -d '[:blank:],current')
FILENAME="Screenshot_${time}_${geometry}.png"
appName="Screenshot"

module_parse <<MODULES
flameshot||Flameshot||
desktop||Capture Desktop||
area||Capture Area||
window||Capture Window||
timer||Capture in 5s||
MODULES

notify_view() {
	notify-send -i gscreenshot -c history-ignore -u low --replace-id=699 $appName "Copied to clipboard."
	feh $DIR/"$FILENAME"
	if [[ -e "$DIR/$FILENAME" ]]; then
		notify-send -i gscreenshot -c history-ignore -u low --replace-id=699 $appName "Screenshot Saved."
	else
		notify-send -i gscreenshot -c history-ignore -u low --replace-id=699 $appName "Screenshot Deleted."
	fi
}

copy_shot() { tee "$FILENAME" | xclip -selection clipboard -t image/png; }

countdown() {
	for sec in $(seq $1 -1 1); do
		notify-send -i gscreenshot -c history-ignore -t 1010 --replace-id=699 $appName "Taking shot in : $sec"
		sleep 1
	done
}

shotnow() {
	cd $DIR && sleep 0.5 && maim -u -f png | copy_shot
	notify_view
}
shot5() {
	countdown '5'
	sleep 1 && cd $DIR && maim -u -f png | copy_shot
	notify_view
}
shotwin() {
	cd $DIR && maim -u -f png -i $(xdotool getactivewindow) | copy_shot
	notify_view
}
shotarea() {
	cd $DIR && maim -u -f png -s -b 2 -c 0.35,0.55,0.85,0.25 -l | copy_shot
	notify_view
}

handle_flameshot() { flameshot gui; }
handle_desktop() { shotnow; }
handle_area() { shotarea; }
handle_window() { shotwin; }
handle_timer() { shot5; }

module_loop
