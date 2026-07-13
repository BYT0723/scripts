#!/usr/bin/env bash

# Use Sing-Box’s clash api to control proxies

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

# Import Current Theme

API=${1:-"http://127.0.0.1:9090"}
SECRET=$2 # 如果有 secret 填这里
width=720
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
	local proxies
	proxies=$(curl -s $(auth_header) "$API/proxies")
	printf '%s\n' "$proxies" | jq -r '.proxies | to_entries[] | select(.value.type=="Selector") | "\(.key)\t\(.value.now)"' |
		while IFS=$'\t' read -r key now; do
			local delay delay_str
			delay=$(printf '%s\n' "$proxies" | jq -r --arg n "$now" '.proxies[$n].history[0].delay // empty')
			if [[ ! "$delay" =~ ^[0-9]+$ ]]; then
				local child
				child=$(printf '%s\n' "$proxies" | jq -r --arg n "$now" '.proxies[$n].now // empty')
				[[ -n "$child" && "$child" != "$now" ]] && delay=$(printf '%s\n' "$proxies" | jq -r --arg n "$child" '.proxies[$n].history[0].delay // "✗"')
			fi
			if [[ "$delay" =~ ^[0-9]+$ ]]; then
				delay_str="${delay}ms"
			else
				delay_str="${delay:-✗}"
			fi
			printf "%-16s  %-20s%6s\n" "$key" "$now" "$delay_str"
		done
}

get_options() {
	local group="$1"
	local current="$2"
	local proxies
	proxies=$(curl -s $(auth_header) "$API/proxies")
	echo "$proxies" | jq -r --arg group "$group" --arg current "$current" '
		.proxies[$group].all[] as $name |
		(.proxies[$name] // {type: "?", history: []}) |
		[ $name, .type, (.history[0].delay // "✗"), (.now // "") ] |
		@tsv
	' | awk -F'\t' -v current="$current" '
		{
			name = $1
			type = $2
			delay = $3
			now = $4
			if (type == "Shadowsocks") type = "SS"
			else if (type == "ShadowsocksR") type = "SSR"
			else if (type == "Hysteria2") type = "Hy2"
			else if (type == "WireGuard") type = "WG"
			if (delay ~ /^[0-9]+$/)
				delay_str = sprintf("%dms", delay)
			else
				delay_str = delay
			marker = (name == current && current != "") ? "✓ " : "  "
			show = name
			if (type == "URLTest" && now != "" && now != name)
				show = name " → " now
			printf "%2s%-26s%-8s%8s\n", marker, show, type, delay_str
		}
	'
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
		prompt="Sing-Box Proxies"
		mesg="Selector Proxies"
		get_selectors | rofi_cmd
		;;
	--node)
		group="$2"
		prompt="$group"
		current=$(get_now "$group")
		mesg="current: $current"
		sleep 0.1
		get_options "$group" "$current" | rofi_cmd
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
		[[ -z "$chosen" ]] && return
		node=$(echo "$chosen" | sed 's/^✓ //;s/^  //' | awk '{print $1}')
		[[ -z "$node" ]] && return
		switch_node "$group" "$node"
		;;
	esac
}

run_cmd --group
