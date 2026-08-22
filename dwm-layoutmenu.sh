#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ROFI_DIR="$SCRIPT_DIR/rofi"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"

source "$ROFI_DIR/scripts/util.sh"
source "$ROFI_DIR/scripts/lib-module.sh"

layouts=(
    "[]= Tiled"
    "[F] Floating"
    "[M] Monocle"
    "[@] Spiral"
    "[\] Dwindle"
    "H[] Deck"
    "TTT BStack"
    "=== BStackHoriz"
    "HHH Grid"
    "### NRowGrid"
    "--- HorizGrid"
    "::: GapLessGrid"
    "|M| CenteredMaster"
    ">M> CenteredFloatingMaster"
)

choice=$(printf "%s\n" "${layouts[@]}" |
    module_sub_rofi " DWM Layouts" "Select a dwm window layout")

[ -z "$choice" ] && exit

for i in "${!layouts[@]}"; do
    if [ "${layouts[$i]}" = "$choice" ]; then
        echo "$i"
        exit
    fi
done
