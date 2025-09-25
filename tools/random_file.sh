#!/bin/bash

dir=$1
len=$2

if [[ -z $dir ]]; then
	echo "Usage: $0 <dir> [len]"
	exit 0
fi

# 检查dir是否是绝对路径
if [[ $dir != /* ]]; then
	dir=$(realpath $dir)
fi

if [[ ! -d $dir ]]; then
	echo "$dir is not a directory"
	exit 1
fi

if [[ -z $len ]]; then
	len=10
fi

cd "$dir"

mpv \
	--really-quiet \
	--playlist=<(find "$dir" -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mov" \) | shuf -n $len)
