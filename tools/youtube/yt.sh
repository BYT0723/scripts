#!/usr/bin/env bash

source "$(dirname "$0")/opus-webm.sh"

: "${YT_DL_DIR:=$HOME/Downloads/yt}"

yt_download() {
	local url="$1" mode="$2" fmt="$3"

	command -v yt-dlp >/dev/null || {
		echo "yt-dlp missing" >&2
		return 1
	}

	command -v ffmpeg >/dev/null || {
		echo "ffmpeg missing" >&2
		return 1
	}

	mkdir -p "$YT_DL_DIR"

	local ytdlp_opts=(
		--cookies-from-browser "${BROWSER:-firefox}"
		-o "$YT_DL_DIR/%(title)s.%(ext)s"
	)

	case "$mode" in
	audio)
		ytdlp_opts+=(-f bestaudio)
		;;
	video)
		local height="${fmt:-1080}"
		ytdlp_opts+=(
			-f "bestvideo[height<=${height}]+bestaudio/best[height<=${height}]/best"
		)
		;;
	raw)
		ytdlp_opts+=(-f "$fmt")
		;;
	*)
		echo "Unknown mode: $mode" >&2
		return 1
		;;
	esac

	yt-dlp "${ytdlp_opts[@]}" "$url" || return 1

	if [[ "$mode" == "audio" ]]; then
		extract_opus "$YT_DL_DIR" || return 1
	fi
}

case "$1" in
audio)
	shift
	yt_download "$1" audio
	;;
video)
	shift
	yt_download "$1" video "$2"
	;;
raw)
	shift
	yt_download "$1" raw "$2"
	;;
extra)
	shift
	extract_opus "$@"
	;;
esac
