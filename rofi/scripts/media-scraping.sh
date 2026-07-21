#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"
MEDIA_DIR="$HOME/Applications/media-scraping"
COMPOSE_FILE="$MEDIA_DIR/docker-compose.yml"

theme="$ROFI_DIR/applets/type-1/style-2.rasi"
width=500

source "$(dirname "$0")"/util.sh

if [[ ("$theme" == *'type-1'*) || ("$theme" == *'type-3'*) || ("$theme" == *'type-5'*) ]]; then
	list_col='1'
	list_row='4'
elif [[ ("$theme" == *'type-2'*) || ("$theme" == *'type-4'*) ]]; then
	list_col='4'
	list_row='1'
fi

HUB=("jellyfin" "metatube")
SCRAPER=("sonarr" "radarr" "prowlarr" "bazarr" "qbittorrent")

_toggle() {
	local target="$1"
	shift
	local services=("$@")

	local any_running=false
	for svc in "${services[@]}"; do
		local state
		state=$(docker compose -f "$COMPOSE_FILE" ps --format json "$svc" 2>/dev/null | jq -r '.State // "stopped"')
		[[ "$state" == "running" ]] && any_running=true && break
	done

	if $any_running; then
		bash "$MEDIA_DIR/launch.sh" down "$target"
		if [[ "$target" == "hub" ]]; then
			pkill -f "jellyfin-mpv-shim" >/dev/null 2>&1 || true
		fi
	else
		bash "$MEDIA_DIR/launch.sh" up "$target"
		if [[ "$target" == "hub" ]]; then
			sleep 8
			/usr/bin/env jellyfin-mpv-shim >/dev/null 2>&1 &
		fi
	fi
}

_is_running() {
	for svc in "$@"; do
		local state
		state=$(docker compose -f "$COMPOSE_FILE" ps --format json "$svc" 2>/dev/null | jq -r '.State // "stopped"')
		[[ "$state" != "running" ]] && return 1
	done
	return 0
}

_toggle_icon() {
	if _is_running "$@"; then
		echo " "
	else
		echo " "
	fi
}

# Options
firstOpt=(
	"Open Hub"
	"Open Scraper"
	"Toggle Hub                 $(_toggle_icon "${HUB[@]}")"
	"Toggle Scraper             $(_toggle_icon "${SCRAPER[@]}")"
)

declare -A optId
optId[${firstOpt[0]}]="--open-hub"
optId[${firstOpt[1]}]="--open-scraper"
optId[${firstOpt[2]}]="--toggle-hub"
optId[${firstOpt[3]}]="--toggle-scraper"

rofi_cmd() {
	rofi -theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: "󰎁 ";} ' \
		-theme-str 'window {width: '$width'px;}' \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-theme ${theme} \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

run_rofi() {
	prompt="Media Scraping"
	mesg="Media Hub And Scraper"
	opts=("${firstOpt[@]}")

	for ((i = 0; i < ${#opts[@]}; i++)); do
		if [[ $i > 0 ]]; then
			msg=$msg"\n"
		fi
		msg=$msg${opts[$i]}
	done
	echo -e "$msg" | rofi_cmd
}

run_cmd() {
	case "$1" in
	--toggle-hub)
		_toggle hub "${HUB[@]}"
		;;
	--open-hub)
		_is_running "${HUB[@]}" && bash "$MEDIA_DIR/open.sh" "${HUB[@]}"
		;;
	--toggle-scraper)
		_toggle scraper "${SCRAPER[@]}"
		;;
	--open-scraper)
		_is_running "${SCRAPER[@]}" && bash "$MEDIA_DIR/open.sh" "${SCRAPER[@]}"
		;;
	*)
		return
		;;
	esac
}

chosen="$(run_rofi)"
if [[ "$chosen" == "" ]]; then
	exit
fi
run_cmd ${optId[$chosen]}
