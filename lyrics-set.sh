#!/bin/bash

MusicsDir=/home/walter/Music
LyricsDir=/home/walter/Music/.lyrics

if [ -z "$(command -v kid3-cli)" ]; then
	echo "请安装kid3"
	exit 1
fi

# 替换或插入函数
replace_or_insert() {
	local lyric_file=$1 # 歌词文件
	local tag="$2"      # ti/ar/al
	local value="$3"    # 对应内容

	if grep -q "^\[${tag}:" "$lyric_file"; then
		# 匹配到就替换
		sed -i "s/^\[${tag}:.*\]/[${tag}:${value}]/" "$lyric_file"
	else
		# 没匹配到就插入到文件头
		sed -i "1i[${tag}:${value}]" "$lyric_file"
	fi
}

find "$MusicsDir" -type f -iname "*.mp3" | while IFS= read -r file; do
	mapfile -t metadata < <(kid3-cli -c "get title" -c "get artist" -c "get album" "$file")

	title="${metadata[0]}"
	artist="${metadata[1]}"
	album="${metadata[2]}"

	lyric_file="$LyricsDir/$(basename "$file" .mp3).lrc"

	[ ! -f "$lyric_file" ] && continue

	replace_or_insert "$lyric_file" "al" "$album"
	replace_or_insert "$lyric_file" "ar" "$artist"
	replace_or_insert "$lyric_file" "ti" "$title"
done
