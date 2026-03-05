#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

# Import Current Theme

API=${1:-"http://127.0.0.1:9090"}
SECRET=$2 # 如果有 secret 填这里
width=550
font="JetBrains Mono Nerd Font 16"
theme="$ROFI_DIR/applets/type-1/style-2.rasi"

source "$(dirname "$0")"/util.sh
source "$WORK_DIR/utils/notify.sh"

[ -z "$(pgrep sing-box)" ] && system-notify critical "Module" "Sing-Box is not running!" && exit

if [[ ("$theme" == *'type-1'*) || ("$theme" == *'type-3'*) || ("$theme" == *'type-5'*) ]]; then
	list_col='1'
	list_row='6'
elif [[ ("$theme" == *'type-2'*) || ("$theme" == *'type-4'*) ]]; then
	list_col='6'
	list_row='1'
fi

# -----------------------------
# Clash API
# -----------------------------

auth_header() {
	if [[ -n "$SECRET" ]]; then
		echo "-H Authorization: Bearer $SECRET"
	fi
}

get_selectors() {
	curl -s $(auth_header) "$API/proxies" |
		jq -r '.proxies | to_entries[] | select(.value.type=="Selector") | "\(.key)\t\(.value.now)"' |
		while IFS=$'\t' read -r key now; do
			printf "%-10s\t %s\n" "$key" "$now"
		done
}

get_options() {
	local group="$1"
	curl -s $(auth_header) "$API/proxies/$group" |
		jq -r '.all[]'
}

get_now() {
	local group="$1"
	curl -s $(auth_header) "$API/proxies/$group" |
		jq -r '.now'
}

switch_node() {
	local group="$1"
	local node="$2"

	curl -s -X PUT $(auth_header) \
		-H "Content-Type: application/json" \
		-d "{\"name\":\"$node\"}" \
		"$API/proxies/$group" >/dev/null
}

# Rofi CMD
rofi_cmd() {
	rofi -theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str 'window {width: '$width';}' \
		-theme-str "* {font: \"$font\";}" \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-monitor -4 \
		-theme "$theme" \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

run_rofi() {
	case "$1" in
	--group)
		prompt="Clash Proxies"
		mesg="Selector Proxies"
		get_selectors | rofi_cmd
		;;
	--node)
		group="$2"
		prompt="$group"
		current=$(get_now "$group")
		mesg="Current: $current"
		get_options "$group" | rofi_cmd
		;;
	*)
		return
		;;
	esac
}

# Execute Command
run_cmd() {
	case "$1" in
	--group)
		chosen="$(run_rofi --group)"
		[[ -z "$chosen" ]] && return
		read -r group now <<<"$chosen"
		run_cmd --node "$group"
		;;
	--node)
		group="$2"
		chosen="$(run_rofi --node "$group")"
		[[ -n "$chosen" ]] && switch_node "$group" "$chosen"
		;;
	esac
}

# -----------------------------
# Entry
# -----------------------------

run_cmd --group
