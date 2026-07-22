#!/usr/bin/env bash

TERM=${TERMINAL:-kitty}

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-3.rasi"
MODULE_WIDTH=500
MODULE_MAX_LINES=6
MODULE_NAME="󰍂 SDDM"
MODULE_MESG="sddm theme setting"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

SDDM_SCRIPT="$WORK_DIR/tools/sddm.sh"

module_parse <<MODULES
set-theme||Set Theme||
preview||Preview||
set-config||Set Config||
edit-config||Edit Config||
install-themes||Install Themes||
MODULES

handle_set_theme() {
	local mesg="Current: $(eval "$SDDM_SCRIPT" cur_theme)"
	local opts=$(bash "$SDDM_SCRIPT" list_theme)
	local chosen=$(echo "$opts" | module_sub_rofi "SDDM Themes" "$mesg")
	[[ -z "$chosen" ]] && return
	pkexec "$SDDM_SCRIPT" set_theme "$chosen"
}

handle_preview() {
	eval "$SDDM_SCRIPT" preview
}

handle_set_config() {
	local opts=$(bash "$SDDM_SCRIPT" list_cfg)
	local chosen=$(echo "$opts" | module_sub_rofi "SDDM Configs" "Select config")
	[[ -z "$chosen" ]] && return
	pkexec "$SDDM_SCRIPT" set_cfg "$chosen"
}

handle_edit_config() {
	$TERM -e sudo -E nvim "$(eval "$SDDM_SCRIPT" cur_cfg_path)"
}

handle_install_themes() {
	$TERM -e /bin/bash -c "$SDDM_SCRIPT install; echo; read -p 'Press enter to close...'"
}

module_loop
