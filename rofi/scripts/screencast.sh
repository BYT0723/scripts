#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-2/style-2.rasi"
MODULE_NAME="Screencast"
MODULE_MESG="screen record"
MODULE_SEARCH_BAR=false

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

TOOL="$WORK_DIR/tools/screencast.sh"

if "$TOOL" is-recording; then
	MODULE_NAME=" 󰑊 $($TOOL recording-time) "

	module_parse <<MODULES
stop||Stop Screencast||
toggle-desktop|$($TOOL audio-state)|Mute System Audio||
toggle-mic|$($TOOL mic-state)|Mute Mic||
MODULES

	handle_stop() { "$TOOL" stop; }
	handle_toggle_desktop() { "$TOOL" toggle-desktop; }
	handle_toggle_mic() { "$TOOL" toggle-mic; }
else
	module_parse <<MODULES
fullscreen||Desktop||
area||Area||
window||Window||
MODULES

	handle_fullscreen() { "$TOOL" start fullscreen; }
	handle_area() { "$TOOL" start area; }
	handle_window() { "$TOOL" start window; }
fi

module_loop
