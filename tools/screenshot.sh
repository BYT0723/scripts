#!/bin/bash

WORK_DIR="$(dirname "$(dirname "$0")")"
source "$WORK_DIR"/utils/monitor.sh

VIEWER="${SCREENSHOT_VIEWER:-nsxiv}"

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

shot_area() { shot_and_preview flameshot gui; }
shot_desktop() {
	read -r _ _ w h _ _ < <(get_current_monitor)
	shot_and_preview flameshot gui --region "${w}x${h}+0+0"
}
shot_window() { shot_and_preview bash -c 'maim -u -i "$(xdotool getactivewindow)" | xclip -selection clipboard -t image/png'; }
shot_timer() { sleep 5 && shot_desktop; }

case "${1:-}" in
area) shot_area ;;
desktop) shot_desktop ;;
window) shot_window ;;
timer) shot_timer ;;
*)
	echo "Usage: $0 {area|desktop|window|timer}" >&2
	exit 1
	;;
esac
