#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"

type="$ROFI_DIR/launchers/type-1"
style='style-5.rasi'
theme="$type/$style"
font="JetBrains Mono Nerd Font 14"

NEW_LINK=" New (Add)"
CONFIG="$HOME/.config/dwm/quicklinks.json"
SEARCH_ENGINE="https://www.google.com/search?q="

WORK_DIR="$(dirname "$ROFI_DIR")"
source "$WORK_DIR/utils/form.sh"
source "$WORK_DIR/utils/notify.sh"
source "$WORK_DIR/utils/url.sh"
source "$WORK_DIR/utils/string.sh"
source "$ROFI_DIR/scripts/lib-module.sh"

# ---- parse links ----
declare -A _url_map
declare -A _id_map
_menu=""

# 生成链接 id: 优先 uuidgen, 无则 base64(name|url) fallback 并提示安装
_gen_id() {
	if command -v uuidgen >/dev/null 2>&1; then
		uuidgen
		return
	fi
	if [[ "${_ID_FALLBACK_NOTIFIED:-}" != 1 ]]; then
		_ID_FALLBACK_NOTIFIED=1
		tool-notify normal "Quicklinks" "未检测到 uuidgen, id 回退为 base64 (建议安装: sudo pacman -S util-linux)"
	fi
	printf '%s|%s' "$1" "$2" | base64 | tr -d '\n'
}

# 补全缺失 id: 正常情况所有链接已有 id, 零写入 (避免每次启动全量重写文件)
# 仅当存在缺 id 的链接 (迁移/异常) 时才全量重生成
_ensure_ids() {
	local total i
	total=$(jq '.links | length' "$CONFIG")
	((total == 0)) && return 0
	if ! jq -e 'any(.links[]?; (.id // "") == "")' "$CONFIG" >/dev/null 2>&1; then
		return 0
	fi
	for i in $(seq 0 $((total - 1))); do
		local name url
		name=$(jq -r --argjson i "$i" '.links[$i].name' "$CONFIG")
		url=$(jq -r --argjson i "$i" '.links[$i].url' "$CONFIG")
		jq --arg id "$(_gen_id "$name" "$url")" --argjson i "$i" \
			'.links[$i].id = $id' "$CONFIG" >"$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
	done
}

_load() {
	while IFS=$'\t' read -r key id url; do
		_url_map["$key"]="$url"
		_id_map["$key"]="$id"
		_menu+="${_menu:+$'\n'}$key"
	done < <(jq -r '.links[] | "\((if (.icon // "") == "" then " " else .icon end)) \(.name)\t\(.id)\t\(.url)"' "$CONFIG")
}

_ensure_ids
_load

# ---- rofi ----
rofi_cmd() {
	rofi -dmenu -i \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-theme-str "* {font: \"$font\";}" \
		-theme-str 'configuration {show-icons:false;}' \
		-theme-str 'window {width: 500px;}' \
		-p "Quicklinks" \
		-mesg "Enter: Open    Alt+1: Edit    Alt+2: Delete" \
		-markup-rows \
		-theme "${theme}" \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary \
		-kb-custom-1 "Alt+1" -kb-custom-2 "Alt+2"
}

# 读取剪贴板, trim 首尾空白后必须为严格完整有效 URL (http/https), 否则静默返回非 0
clipboard_url() {
	local clip
	if command -v xclip >/dev/null 2>&1; then
		clip=$(xclip -o -selection clipboard 2>/dev/null)
	elif command -v xsel >/dev/null 2>&1; then
		clip=$(xsel --clipboard --output 2>/dev/null)
	elif command -v wl-paste >/dev/null 2>&1; then
		clip=$(wl-paste 2>/dev/null)
	fi
	[[ -n "$clip" ]] || return 1
	clip=$(trim_str "$clip")
	# valid_url 只校验 host, path 不查; 须整体无空白 (拒绝多行/含空格文本)
	[[ "$clip" != *[[:space:]]* ]] || return 1
	valid_url "$clip" || return 1
	printf '%s' "$clip"
}

# ---- new link via form ----

# 常用分类图标池: 图标+名称, 候选项间用 ! 分隔 (yad CBE 原生格式)
# 图标均取自 Nerd Font cheat sheet (nf-md-forum/chat/email/movie, nf-linux-neovim, nf-md-code_brackets)
ICON_POOL="󰖟 web! search!󰖬 doc!󰊌 forum! chat! mail! video! music!󰊖 game! linux! neovim! code!🔞 adult"

# Alt+2 删除: 按 _id_map 定位, 确认后按 id 删除
_delete_link() {
	local key="$1" id name
	id="${_id_map[$key]}"
	[[ -n "$id" ]] || return 1
	name=$(jq -r --arg id "$id" '.links[] | select(.id == $id) | .name' "$CONFIG")
	[[ -n "$name" ]] || return 1
	module_confirm "删除「$name」？" || return 1
	jq --arg id "$id" 'del(.links[] | select(.id == $id))' \
		"$CONFIG" >"$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
	tool-notify normal "Quicklinks" "已删除: $name"
}

# 将 icon 输入的 \uXXXX / \UXXXXXXXX 字面转义转换为实际 Unicode 字符
icon_symbol() {
	local icon="$1"
	if [[ "$icon" =~ ^\\[uU]([0-9a-fA-F]{4}|[0-9a-fA-F]{8})$ ]]; then
		printf '%b' "$icon"
		return
	fi
	printf '%s' "$icon"
}

# 弹表单录入链接, 校验失败 notify 并重开; 成功设置 _LINK_NAME/_LINK_ICON/_LINK_URL, 取消返回 1
_edit_loop() {
	local name="$1" icon="$2" url="$3"
	while :; do
		local json=$(
			form_show <<EOF
name|entry|Name|${name:-}|
icon|combo-entry|Icon|${icon:-󰖟 web}|${ICON_POOL}
url|entry|URL|${url:-}|
EOF
		)
		[[ -z "$json" ]] && return 1

		name=$(jq -r '.name' <<<"$json")
		icon=$(jq -r '.icon' <<<"$json")
		url=$(jq -r '.url' <<<"$json")
		name=$(trim_str "$name")
		url=$(trim_str "$url")
		if [[ -z "$name" ]]; then
			tool-notify critical "Quicklinks" "链接名称不能为空"
			continue
		fi
		if [[ -z "$url" ]]; then
			tool-notify critical "Quicklinks" "链接 URL 不能为空"
			continue
		fi
		icon=$(icon_symbol "$icon")
		icon=${icon:0:1}
		[[ -z "$icon" || "$icon" == " " ]] && icon="󰖟"

		if ! valid_url "$url" && ! valid_url "https://$url"; then
			tool-notify critical "Quicklinks" "链接 URL 无效: $url"
			continue
		fi
		[[ "$url" =~ ^https?:// ]] || url="https://$url"
		break
	done
	_LINK_NAME="$name"
	_LINK_ICON="$icon"
	_LINK_URL="$url"
}

_new_link() {
	local url
	# 首次打开时预填剪贴板有效 URL; 循环内不再回读 (重开保留用户输入)
	url=$(clipboard_url)
	_edit_loop "" "" "$url" || return 1

	jq --arg id "$(_gen_id "$_LINK_NAME" "$_LINK_URL")" --arg name "$_LINK_NAME" --arg icon "$_LINK_ICON" --arg url "$_LINK_URL" \
		'.links += [{name: $name, icon: $icon, url: $url, id: $id}]' \
		"$CONFIG" >"$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
}

# Alt+1 编辑: 按 _id_map 定位原条目, 预填当前值, 保存按 id 替换 (保留 id)
_edit_link() {
	local key="$1" id
	id="${_id_map[$key]}"
	[[ -n "$id" ]] || return 1

	local cur
	cur=$(jq -c --arg id "$id" '.links[] | select(.id == $id)' "$CONFIG" 2>/dev/null)
	[[ -n "$cur" ]] || return 1

	local name icon url
	name=$(jq -r '.name' <<<"$cur")
	icon=$(jq -r '.icon' <<<"$cur")
	url=$(jq -r '.url' <<<"$cur")
	_edit_loop "$name" "$icon" "$url" || return 1

	jq --arg id "$id" --arg name "$_LINK_NAME" --arg icon "$_LINK_ICON" --arg url "$_LINK_URL" \
		'(.links[] | select(.id == $id)) |= {id: .id, name: $name, icon: $icon, url: $url}' \
		"$CONFIG" >"$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
}

run_cmd() {
	local chosen="$1"

	[[ "$chosen" == "$NEW_LINK" ]] && {
		_new_link
		return
	}

	local url="${_url_map[$chosen]}"
	if [[ -n "$url" ]]; then
		xdg-open "$url"
		return
	fi

	if is_url "$chosen"; then
		[[ "$chosen" =~ ^https?:// ]] || chosen="https://$chosen"
		xdg-open "$chosen"
		return
	fi

	xdg-open "${SEARCH_ENGINE}${chosen}"
}

chosen=$(printf '%s\n%s' "$_menu" "$NEW_LINK" | rofi_cmd)
rc=$?
if [[ "$rc" == 10 ]]; then
	# Alt+1: 编辑选中链接
	[[ -n "$chosen" ]] && _edit_link "$chosen"
elif [[ "$rc" == 11 ]]; then
	# Alt+2: 删除选中链接
	[[ -n "$chosen" ]] && _delete_link "$chosen"
elif [[ -n "$chosen" ]]; then
	run_cmd "$chosen"
fi
