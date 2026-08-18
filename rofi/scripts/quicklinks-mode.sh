#!/usr/bin/env bash
# rofi script mode: quicklinks (rofi -show quicklinks)
# 参考 rofi/scripts/quicklinks.sh 实现, 该文件保持不动

ROFI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(dirname "$ROFI_DIR")"

CONFIG="$HOME/.config/dwm/quicklinks.json"
SEARCH_ENGINE="https://www.google.com/search?q="
NEW_LINK=" New (Add)"
# script mode 下 rofi 存活期间 grab 键盘: 交互前须等待其退出释放 grab (实测 EOF→退出 < 0.4s)
GRAB_RELEASE_WAIT=0.4

source "$WORK_DIR/utils/form.sh"
source "$WORK_DIR/utils/notify.sh"
source "$WORK_DIR/utils/url.sh"
source "$WORK_DIR/utils/string.sh"
source "$ROFI_DIR/scripts/lib-module.sh"

# ---- parse links ----
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
		_write_json --arg id "$(_gen_id "$name" "$url")" --argjson i "$i" '.links[$i].id = $id'
	done
}

_load() {
	_id_map=()
	_menu=""
	while IFS=$'\t' read -r key id url; do
		_id_map["$key"]="$id"
		_menu+="${_menu:+$'\n'}$key"
	done < <(jq -r '.links[] | "\((if (.icon // "") == "" then " " else .icon end)) \(.name)\t\(.id)\t\(.url)"' "$CONFIG")
}

# 行文本 -> id: _id_map 以行文本为 key, ROFI_INFO 以 id 传递选中项
_list() {
	_ensure_ids
	_load
	local line
	while IFS= read -r line; do
		printf '%s\0info\x1f%s\n' "$line" "${_id_map[$line]}"
	done <<<"$_menu"
	printf '%s\0info\x1fnew\n' "$NEW_LINK"
	printf '\0use-hot-keys\x1ftrue\n'
}

# 按 id 打开 URL; 外部程序须后台执行 (rofi 会等待脚本 stdout 关闭)
_open_url() {
	(xdg-open "$1" >/dev/null 2>&1 &)
}

_open_by_id() {
	local url
	url=$(jq -r --arg id "$1" '.links[] | select(.id == $id) | .url' "$CONFIG")
	[[ -n "$url" ]] || return 0
	_open_url "$url"
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

# 后台交互包装: script mode 下 rofi 存活期间 grab 键盘, yad/嵌套 rofi 拿不到输入
# → 子 shell sleep 等 rofi 退出释放 grab 后再执行命令, 父脚本立即结束 (stdout EOF 令 rofi 退出)
_interact_async() {
	(
		sleep "$GRAB_RELEASE_WAIT"
		"$@"
	) >/dev/null 2>&1 &
}

# 原子写回 CONFIG: jq [args...] <expr> 输出到唯一 tmp 再 mv (避免并发写 .tmp 冲突)
_write_json() {
	local tmp
	tmp=$(mktemp "$CONFIG.tmp.XXXXXX") || return 1
	jq "$@" "$CONFIG" >"$tmp" && mv "$tmp" "$CONFIG"
}

# 常用分类图标池: 图标+名称, 候选项间用 ! 分隔 (yad CBE 原生格式)

# Alt+1 编辑: 按 id 定位原条目, 预填当前值, 保存按 id 替换 (保留 id)
_edit_link() {
	local id="$1"
	[[ -n "$id" ]] || return 0

	local cur
	cur=$(jq -c --arg id "$id" '.links[] | select(.id == $id)' "$CONFIG" 2>/dev/null)
	[[ -n "$cur" ]] || return 0

	local name icon url
	name=$(jq -r '.name' <<<"$cur")
	icon=$(jq -r '.icon' <<<"$cur")
	url=$(jq -r '.url' <<<"$cur")
	_interact_async _edit_form "$id" "$name" "$icon" "$url"
}

_edit_form() { # 表单录入 + 按 id 替换写库 (rofi 退出后执行)
	local id="$1" name="$2" icon="$3" url="$4"
	_edit_loop "$name" "$icon" "$url" &&
		_write_json --arg id "$id" --arg name "$_LINK_NAME" --arg icon "$_LINK_ICON" --arg url "$_LINK_URL" \
			'(.links[] | select(.id == $id)) |= {id: .id, name: $name, icon: $icon, url: $url}'
}

# Alt+2/Shift+Delete 删除: 按 id 定位, 确认后删除
_delete_link() {
	local id="$1"
	[[ -n "$id" ]] || return 0
	local name
	name=$(jq -r --arg id "$id" '.links[] | select(.id == $id) | .name' "$CONFIG")
	[[ -n "$name" ]] || return 0
	_interact_async _delete_form "$id" "$name"
}

_delete_form() { # 确认 + 删除写库 (rofi 退出后执行)
	local id="$1" name="$2"
	module_confirm "删除「$name」？" &&
		_write_json --arg id "$id" 'del(.links[] | select(.id == $id))' &&
		tool-notify normal "Quicklinks" "已删除: $name"
}

# New: 剪贴板有效 URL 预填, 表单校验后追加
_new_link() {
	_interact_async _new_form
}

_new_form() { # 剪贴板预填 + 表单 + 追加写库 (rofi 退出后执行)
	local url
	# clipboard_url 也在此执行: xclip/xsel/wl-paste 读取剪贴板可能阻塞, 不能留在 rofi grab 存活期间
	url=$(clipboard_url)
	_edit_loop "" "" "$url" &&
		_write_json --arg id "$(_gen_id "$_LINK_NAME" "$_LINK_URL")" --arg name "$_LINK_NAME" --arg icon "$_LINK_ICON" --arg url "$_LINK_URL" \
			'.links += [{name: $name, icon: $icon, url: $url, id: $id}]'
}

_dispatch() {
	case "${ROFI_INFO:-}" in
	new) _new_link ;;
	*) _open_by_id "${ROFI_INFO:-}" ;;
	esac
}

# 自定义输入: URL → 补协议打开; 否则搜索引擎
_handle_input() {
	local text="$*"
	[[ -n "$text" ]] || return 0
	if is_url "$text"; then
		[[ "$text" =~ ^https?:// ]] || text="https://$text"
	else
		text="${SEARCH_ENGINE}${text}"
	fi
	_open_url "$text"
}

# ---- 表单 (参考 quicklinks.sh, yad form_show) ----

ICON_POOL="󰖟 web! search!󰖬 doc!󰊌 forum!󰭹 chat! mail! video! music! game! linux! neovim! code!🔞 adult"

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

_main() {
	case "${ROFI_RETV:-0}" in
	0) _list ;;
	1) _dispatch ;;
	2) _handle_input "$*" ;;
	3 | 11) _delete_link "${ROFI_INFO:-}" ;;
	10) _edit_link "${ROFI_INFO:-}" ;;
	*) exit 0 ;;
	esac
}

# ---- main (source 时跳过) ----
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	_main
fi
