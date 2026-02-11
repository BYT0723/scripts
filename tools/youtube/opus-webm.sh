#!/usr/bin/env bash

extract_opus() {
	local target="${1:-.}"

	# 依赖检查
	for cmd in ffmpeg ffprobe; do
		command -v "$cmd" >/dev/null 2>&1 || {
			echo "Missing dependency: $cmd" >&2
			return 1
		}
	done

	shopt -s nullglob

	local files=()

	if [[ -d "$target" ]]; then
		files=("$target"/*.webm)
	elif [[ -f "$target" ]]; then
		files=("$target")
	else
		echo "Invalid path: $target"
		return 1
	fi

	for file in "${files[@]}"; do
		local base="${file%.webm}"
		local output="${base}.opus"

		if [[ -f "$output" ]]; then
			echo "Skip (exists): $output"
			continue
		fi

		echo "Processing: $file"

		# metadata
		local title artist
		title=$(ffprobe -v quiet \
			-show_entries format_tags=title \
			-of default=noprint_wrappers=1:nokey=1 "$file")

		artist=$(ffprobe -v quiet \
			-show_entries format_tags=artist \
			-of default=noprint_wrappers=1:nokey=1 "$file")

		title=${title:-$(basename "$base")}
		artist=${artist:-Unknown}

		# debug info
		ffprobe -v error -select_streams a:0 \
			-show_entries stream=codec_name,bit_rate \
			-of default=noprint_wrappers=1 "$file"

		# extract
		if ffmpeg -loglevel error \
			-i "$file" \
			-vn \
			-map_metadata 0 \
			-metadata title="$title" \
			-metadata artist="$artist" \
			-c:a copy \
			"$output"; then

			echo "✔ Done -> $output"
		else
			echo "✘ Failed: $file"
		fi
	done
}
