#!/usr/bin/env bash

source "$(dirname $0)/opus-webm.sh"

yt_download() {
	local url="$1"

	command -v yt-dlp >/dev/null || {
		echo "yt-dlp missing" >&2
		return 1
	}

	yt-dlp \
		--cookies-from-browser $BROWSER \
		-f bestaudio \
		--exec 'bash -c "source '$(dirname $0)/opus-webm.sh' && extract_opus {}"' \
		"$url"
}

case "$1" in
"download")
	shift
	yt_download "$@"
	;;
"extra")
	shift
	extract_opus "$@"
	;;
esac
