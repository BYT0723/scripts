#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-2/style-2.rasi"
MODULE_NAME="Screenshot"
MODULE_MESG="screen capture"
MODULE_SEARCH_BAR=false

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

TOOL="$WORK_DIR/tools/screenshot.sh"

module_parse <<MODULES
area||Area||
desktop||Desktop||
window||Window||
timer||5s||
MODULES

handle_area() { "$TOOL" area; }
handle_desktop() { "$TOOL" desktop; }
handle_window() { "$TOOL" window; }
handle_timer() { "$TOOL" timer; }

module_loop
