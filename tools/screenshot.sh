#!/bin/bash

WORK_DIR="$(dirname "$(dirname "$0")")"
DIR="${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
mkdir -p "$DIR"

VIEWER="${SCREENSHOT_VIEWER:-nsxiv}"

source "$WORK_DIR"/utils/monitor.sh

flameshot_setting() {
	flameshot config -f '%F_%T' -n true

	local config="$HOME/.config/flameshot/flameshot.ini"
	if grep -q '^savePath=' "$config"; then
		sed -i "s|^savePath=.*|savePath=${DIR}|" "$config"
	else
		sed -i "/^\[General\]/a savePath=${DIR}" "$config"
	fi
}

shot_and_preview() {
	local tmpfile="/tmp/screenshot_preview.png"
	local before_md5=$(xclip -selection clipboard -t image/png -o 2>/dev/null | md5sum | cut -d' ' -f1)

	flameshot gui $@

	if xclip -selection clipboard -t image/png -o >"$tmpfile" 2>/dev/null; then
		local after_md5=$(md5sum "$tmpfile" | cut -d' ' -f1)
		[ "$before_md5" != "$after_md5" ] && $VIEWER "$tmpfile"
		rm -f "$tmpfile"
	fi
}

shot_area() { shot_and_preview; }

shot_desktop() {
	read -r _ _ w h _ _ < <(get_current_monitor)
	shot_and_preview --region "${w}x${h}+0+0"
}

shot_window() {
	read -r _ _ w h x y < <(get_current_monitor)
	local region=$(xdotool getwindowgeometry "$(xdotool getactivewindow)" | awk -v mx="$x" -v my="$y" '
/Position:/ { split($2, p, ",") }
/Geometry:/ { split($2, g, "x") }
END {
    printf "%sx%s+%s+%s", g[1], g[2], p[1] - mx, p[2] - my
}')
	shot_and_preview --region "$region"
}

shot_timer() { sleep 5 && shot_desktop; }

flameshot_setting

case "${1:-}" in
area) shot_area ;;
desktop) shot_desktop ;;
window) shot_window ;;
timer) shot_timer ;;
pure) flameshot gui ;;
*)
	echo "Usage: $0 {area|desktop|window|timer}" >&2
	exit 1
	;;
esac
