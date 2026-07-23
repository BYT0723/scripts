#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"
MEDIA_DIR="$HOME/Applications/media-scraping"
COMPOSE_FILE="$MEDIA_DIR/docker-compose.yml"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_WIDTH=500
MODULE_NAME="󰎁 Media Scraping"
MODULE_MESG="Media Hub And Scraper"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh

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

module_parse <<MODULES
open-hub|󰎁|Hub (jellyfin)||
open-index|󰎁|Index (prowlarr)||
open-movie|󰎁|Movie (radarr)||
open-tv|󰎁|TV (sonarr)||
open-downloader|󰎁|Downloader (qbittorrent)||
open-subtitle|󰎁|Subtitle (bazarr)||
toggle-hub|󰙉|Toggle Hub||cmd:_is_running jellyfin metatube && echo " " || echo " "
toggle-scraper|󰙉|Toggle Scraper||cmd:_is_running sonarr radarr prowlarr bazarr qbittorrent && echo " " || echo " "
MODULES

handle_toggle_hub() { _toggle hub "${HUB[@]}"; }
handle_toggle_scraper() { _toggle scraper "${SCRAPER[@]}"; }
handle_open_hub() { _is_running "${HUB[@]}" && bash "$MEDIA_DIR/open.sh" "${HUB[@]}"; }
handle_open_index()     { _is_running prowlarr    && bash "$MEDIA_DIR/open.sh" prowlarr; }
handle_open_movie()     { _is_running radarr     && bash "$MEDIA_DIR/open.sh" radarr; }
handle_open_tv()        { _is_running sonarr     && bash "$MEDIA_DIR/open.sh" sonarr; }
handle_open_downloader(){ _is_running qbittorrent && bash "$MEDIA_DIR/open.sh" qbittorrent; }
handle_open_subtitle()  { _is_running bazarr     && bash "$MEDIA_DIR/open.sh" bazarr; }

module_loop
