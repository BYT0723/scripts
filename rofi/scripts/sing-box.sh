#!/usr/bin/env bash

# Use Sing-Box’s clash api to control proxies

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_WIDTH=600

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/utils/notify.sh"

API=${1:-"http://127.0.0.1:9090"}
SECRET=$2

[ -z "$(pgrep sing-box)" ] && system-notify critical "Module" "Sing-Box is not running!" && exit

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

# Group select
chosen=$(get_selectors | module_sub_rofi " Proxies" "Selector Proxies")
[[ -z "$chosen" ]] && exit 0
read -r group __ <<<"$chosen"

# Node select
current=$(get_now "$group")
sleep 0.1
chosen=$(get_options "$group" "$current" | module_sub_rofi " $group" "current: $current")
[[ -z "$chosen" ]] && exit 0
node=$(echo "$chosen" | sed 's/^✓ //;s/^  //' | awk '{print $1}')
[[ -n "$node" ]] && switch_node "$group" "$node"
