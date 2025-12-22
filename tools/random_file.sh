#!/bin/bash

set -euo pipefail

dir=${1:-}
len=${2:-10}

[ -z "$dir" ] && echo "Usage: $(basename $0) <dir> [len]" && exit 1
[ ! -d "$dir" ] && echo "$dir is not a directory" && exit 1

[[ "$dir" != /* ]] && dir=$(realpath "$dir")

(
	cd "$dir"
	mpv \
		--really-quiet \
		--playlist=<(
			find "$dir" -type f \
				\( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mov" \) \
				-print0 |
				shuf -z -n "$len" |
				tr '\0' '\n'
		)
)
