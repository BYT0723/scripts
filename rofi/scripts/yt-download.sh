#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_NAME="󰎆 YouTube Downloader"
MODULE_MESG="Download audio/video from YouTube"

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/utils/notify.sh"

DL_DIR="${YT_DL_DIR:-$HOME/Downloads/yt}"
YT_SH="$WORK_DIR/tools/youtube/yt.sh"
mkdir -p "$DL_DIR"

CLIP_URL=""
if command -v xclip &>/dev/null; then
	CLIP_URL=$(xclip -selection clipboard -o 2>/dev/null | grep -oE 'https?://[^[:space:]]+' | head -1)
fi

# ------- helpers -------

_download() {
	local url="$1" mode="$2" fmt="${3:-}"
	local label
	case "$mode" in
	audio) label="Audio (Opus)" ;;
	video) label="Video${fmt:+ ${fmt}p}" ;;
	raw) label="Custom ($fmt)" ;;
	esac

	system-notify low "YouTube" "$label\n$url"

	(
		local rc=0 title
		title=$(yt-dlp --get-title --no-playlist --cookies-from-browser "${BROWSER:-firefox}" "$url" 2>/dev/null)
		title="${title:-$label}"
		[[ ${#title} -gt 65 ]] && title="${title:0:62}..."

		case "$mode" in
		audio) "$YT_SH" audio "$url" >/dev/null 2>&1 || rc=$? ;;
		video) "$YT_SH" video "$url" "$fmt" >/dev/null 2>&1 || rc=$? ;;
		raw) "$YT_SH" raw "$url" "$fmt" >/dev/null 2>&1 || rc=$? ;;
		esac
		if [[ $rc -eq 0 ]]; then
			system-notify normal "YouTube" "Done\n$title"
		else
			system-notify critical "YouTube" "Failed (rc=$rc)\n$title\n$url"
		fi
	) &
}

_format_download() {
	local url="$1"

	system-notify low "YouTube" "Fetching format list..."
	local formats
	formats=$(yt-dlp -F "$url" --no-warnings 2>/dev/null | awk '
		/^ID / { p=1; next }
		p && /^[0-9]+/ && !/storyboard|mhtml/ {
			id=$1; ext=$2
			sub(/^[0-9]+[ \t]+[^ \t]+[ \t]+/,"")
			printf "%s|%s\n", id, $0
		}')
	if [[ -z "$formats" ]]; then
		system-notify critical "YouTube" "Could not fetch format list"
		return
	fi

	local chosen
	chosen=$(printf '%s\n' "$formats" | module_sub_rofi "󰋽 Formats" "Select format, Enter to download")
	[[ -z "$chosen" ]] && return

	_download "$url" raw "${chosen%%|*}"
}

# ------- handlers -------

_pick_resolution() {
	local url="$1" show_custom="${2:-}"
	local choice heights
	heights=$'2160p\n1440p\n1080p\n720p\n360p'
	if [[ -n "$show_custom" ]]; then
		choice=$(printf '%s\n-F custom\n' "$heights" | module_sub_rofi "󰎇 Video Quality" "4K / 2K / 1080p / 720p / 360p")
	else
		choice=$(printf '%s\n' "$heights" | module_sub_rofi "󰎇 Video Quality" "4K / 2K / 1080p / 720p / 360p")
	fi
	[[ -z "$choice" ]] && return 1
	case "$choice" in
	-F*) _format_download "$url" ;;
	*) _download "$url" video "${choice%p}" ;;
	esac
}

handle_audio() {
	local url
	url=$(module_input "Audio URL" "Enter YouTube link" "${CLIP_URL:-}")
	[[ -z "$url" ]] && return
	_download "$url" audio
}

handle_video() {
	local url
	url=$(module_input "Video URL" "Enter YouTube link" "${CLIP_URL:-}")
	[[ -z "$url" ]] && return
	_pick_resolution "$url" 1
}

handle_clipboard() {
	[[ -z "$CLIP_URL" ]] && return

	local choice
	choice=$(printf 'Audio (Opus)\nVideo' | module_sub_rofi "󰅐 Clipboard" "$CLIP_URL")
	[[ -z "$choice" ]] && return

	case "$choice" in
	Audio*)
		_download "$CLIP_URL" audio
		;;
	Video*)
		_pick_resolution "$CLIP_URL"
		;;
	esac
}

handle_format() {
	local url
	url=$(module_input "Format URL" "Enter YouTube link for -F" "${CLIP_URL:-}")
	[[ -z "$url" ]] && return
	_format_download "$url"
}

handle_open() { xdg-open "$DL_DIR"; }

# ------- main -------

_menu="audio|󰎆|Audio (Opus)|bestaudio → opus|"$'\n'
_menu+="video|󰎇|Video|bestvideo+bestaudio|"$'\n'
[[ -n "$CLIP_URL" ]] && _menu+="clipboard|󰅐|Clipboard||"$'\n'
_menu+="format|󰋽|Custom Format|yt-dlp -F list|"$'\n'
_menu+="open|󰝰|Open Directory|$DL_DIR|"$'\n'

module_parse <<<"$_menu"

module_loop
