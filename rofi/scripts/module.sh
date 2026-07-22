#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_WIDTH=500
MODULE_MAX_LINES=8
MODULE_NAME=" Modules"
MODULE_MESG="Manage Module Of System"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

CONFIG_HOME="$HOME/.config/dwm"

declare -A confPath applicationCmd
confPath["picom"]="$CONFIG_HOME/picom.conf"
applicationCmd["picom"]="picom --config ${confPath["picom"]} -b"
applicationCmd["conky"]="conky -U -d &"

toggleApplication() {
	if [[ -n $(pgrep $1) ]]; then
		killall $1
	else
		${applicationCmd[$1]}
	fi
}

module_parse <<MODULES
picom|󰋩|Picom|Windows Composer|toggle
conky|󰏘|Conky|System Monitor|toggle
network|󰈀|Network||active:NetworkManager
bluetooth|󰂯|Bluetooth||active-svc
notification||Notification||str:$($ROFI_DIR/scripts/notification.sh unread)
sddm|󰍂|SDDM Setting||
media-scraping|󰎁|Media Scraping||
sing-box||SingBox||active
calendar||Calendar||
calendar-lunar||Calendar (Lunar)||
MODULES

# ====== Handlers ======
handle_picom() { toggleApplication picom; }
handle_conky() { toggleApplication conky; }

handle_network() {
	local eth wifi mesg=""
	eth=$(nmcli -t -f DEVICE,TYPE,STATE dev status | awk -F: '$2=="ethernet" && $3=="connected" {print $1}')
	wifi=$(nmcli -t -f IN-USE,SSID,SIGNAL dev wifi list | grep '^*' | awk -F : '{printf "%s(%s%%)", $2, $3}')
	[ "$eth" != "" ] && mesg="  $eth"
	[[ "$wifi" != "" ]] && { [ "$mesg" != "" ] && mesg="$mesg\n  $wifi" || mesg="  $wifi"; }
	local opts=$(nmcli device wifi list --rescan auto | awk 'NR!=1 {print substr($0,9)}' | awk '{print $8," ",$2}' | awk '!a[$0]++')
	local chosen=$(echo "$opts" | module_sub_rofi "Network" "$mesg")
	[[ "$chosen" == "" || "$chosen" == "$(nmcli connection show -active | grep -E 'wifi' | awk '{print $1}')" ]] && return
	nmcli device wifi connect $(echo $chosen | awk '{print $2}')
}

handle_bluetooth() {
	local connected_device=$(bluetoothctl devices Connected | awk '{print substr($0,25)}')
	local mesg="No device connected"
	[ "$connected_device" != "" ] && mesg="Connected:$connected_device"
	local opts=$(bluetoothctl devices | awk '{print substr($0,26)}')
	local chosen=$(echo "$opts" | module_sub_rofi "Bluetooth" "$mesg")
	[[ "$chosen" == "" ]] && return
	bluetoothctl disconnect $(bluetoothctl devices Connected | grep "$chosen" | awk '{print $2}')
}

handle_notification() { $ROFI_DIR/scripts/notification.sh; }
handle_sing_box() { /bin/bash $ROFI_DIR/scripts/sing-box.sh; }
handle_calendar() { /bin/bash $WORK_DIR/tools/calendar.sh; }
handle_calendar_lunar() { /bin/bash $WORK_DIR/tools/calendar.sh lunar; }
handle_media_scraping() { /bin/bash $ROFI_DIR/scripts/media-scraping.sh; }
handle_sddm() { /bin/bash $ROFI_DIR/scripts/sddm.sh; }

module_loop
