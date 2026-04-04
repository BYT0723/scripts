#!/bin/bash
set -euo pipefail

target_path=${1:-"./ruleset"}

tmp_zip_path=$(mktemp)
tmp_ruleset_path=$(mktemp -d)

trap 'rm -rf "$tmp_zip_path" "$tmp_ruleset_path"' EXIT

mkdir -p "$target_path"

echo "[1/3] downloading ruleset..."
wget -q --show-progress \
	https://github.com/DustinWin/ruleset_geodata/archive/refs/heads/sing-box-ruleset.zip \
	-O "$tmp_zip_path"

echo "[2/3] Extract Zip..."
unzip -q "$tmp_zip_path" -d "$tmp_ruleset_path"

echo "[3/3] Sync Rule File to $target_path"
rsync -a --delete \
	"$tmp_ruleset_path/ruleset_geodata-sing-box-ruleset/" \
	"$target_path" >/dev/null

echo "Done."
