#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_NAME="Screenshot"
MODULE_MESG="screen capture"
VIEWER="nsxiv"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$(dirname "$ROFI_DIR")/utils/monitor.sh"

module_parse <<MODULES
desktop||Capture Desktop||
area||Capture Area||
window||Capture Window||
timer||Capture in 5s||
MODULES

shot_and_preview() {
	tmpfile="/tmp/screenshot_preview.png"
	before_md5=$(xclip -selection clipboard -t image/png -o 2>/dev/null | md5sum | cut -d' ' -f1)

	"$@"

	if ! xclip -selection clipboard -t image/png -o >"$tmpfile" 2>/dev/null; then
		return 0
	fi
	after_md5=$(md5sum "$tmpfile" | cut -d' ' -f1)
	if [ "$before_md5" != "$after_md5" ]; then
		$VIEWER "$tmpfile"
	fi
	rm -f "$tmpfile"
}

handle_desktop() {
	read -r _ _ w h _ _ < <(get_current_monitor)
	shot_and_preview flameshot gui --region "${w}x${h}+0+0"
}
handle_area() { shot_and_preview flameshot gui; }
handle_window() {
	tmpfile="/tmp/screenshot_preview.png"
	before_md5=$(xclip -selection clipboard -t image/png -o 2>/dev/null | md5sum | cut -d' ' -f1)

	maim -u -i "$(xdotool getactivewindow)" | xclip -selection clipboard -t image/png

	if ! xclip -selection clipboard -t image/png -o >"$tmpfile" 2>/dev/null; then
		return 0
	fi
	after_md5=$(md5sum "$tmpfile" | cut -d' ' -f1)
	if [ "$before_md5" != "$after_md5" ]; then
		$VIEWER "$tmpfile"
	fi
	rm -f "$tmpfile"
}
handle_timer() { sleep 5 && handle_desktop; }

module_loop
