#!/usr/bin/env bash
# utils/form.sh — 通用表单工具
#
# 依赖: jq (JSON 输出), 后端 yad (优先) / zenity (fallback)
#
# 用法:
#   source utils/form.sh
#   form_show <<'EOF'
#   name|entry|Name|
#   icon|combo|Icon||󰖟!󰂤
#   url|entry|URL|
#   EOF
#   # 成功输出单行 JSON {"name":"...","icon":"...","url":"..."}
#   # 取消/ESC 返回非 0 且无输出
#
# 字段定义协议 (每行):
#   key|type|label|default|candidates
#   type: entry / password / multiline / combo / combo-entry / calendar
#   combo 的 candidates 用 `!` 分隔 (yad 原生格式, zenity 自动转 `|`)
#
# 环境变量 (均可选):
#   FORM_BACKEND=yad|zenity  强制后端
#   FORM_CSS=<css>           覆盖默认 GTK CSS (表单 grid/entry margin)
#   FORM_WIDTH=<px>          yad 窗口宽度 (默认留空 = 自动)
#   FORM_FONT=<font>         设置表单字体 (yad 专用, 如 "JetBrains Mono Nerd Font 14"; zenity 不支持)

declare -gA _F_TYPE _F_LABEL _F_DEFAULT _F_CANDIDATE
declare -ga _F_KEYS

_form_parse() {
	_F_KEYS=()
	while IFS='|' read -r key type label default candidates; do
		[[ -z "$key" ]] && continue
		_F_KEYS+=("$key")
		_F_TYPE[$key]=$type
		_F_LABEL[$key]=$label
		_F_DEFAULT[$key]=$default
		_F_CANDIDATE[$key]=$candidates
	done
}

form_show() {
	_form_parse
	((${#_F_KEYS[@]} == 0)) && return 1

	local -A values=()
	local backend="${FORM_BACKEND:-}"
	if [[ -z "$backend" ]]; then
		command -v yad &>/dev/null && backend=yad || backend=zenity
	fi
	if [[ "$backend" == yad ]]; then
		_form_yad values || return $?
	else
		_form_zenity values || return $?
	fi

	local obj='{}' k
	for k in "${_F_KEYS[@]}"; do
		obj=$(jq -cn --argjson o "$obj" --arg k "$k" --arg v "${values[$k]:-}" '$o + {($k): $v}')
	done
	echo "$obj"
}

# yad 分支: --form, 每字段 --field=Label[:type] 后跟默认值/候选值
# CSS 默认给表单 grid 与输入框留边距, 可用 FORM_CSS 覆盖
_FORM_CSS_DEFAULT='grid { margin: 8px; }'
_form_yad() {
	local -n out=$1
	local -a args=(--form)
	local css="${FORM_CSS:-$_FORM_CSS_DEFAULT}"
	if [[ -n "${FORM_FONT:-}" ]]; then
		local font_desc="${FORM_FONT#\"}"
		font_desc="${font_desc%\"}"
		local family size=""
		if [[ "$font_desc" =~ ^(.+)[[:space:]]+([0-9]+)$ ]]; then
			family="${BASH_REMATCH[1]}"
			size="${BASH_REMATCH[2]}"
			css="* { font-family: \"$family\"; font-size: ${size}px; } $css"
		else
			css="* { font-family: \"$font_desc\"; } $css"
		fi
	fi
	[[ -n "$css" ]] && args+=("--css=$css")
	local width="${FORM_WIDTH:-400}"
	[[ -n "$width" ]] && args+=("--width=$width")
	local k suffix
	for k in "${_F_KEYS[@]}"; do
		suffix=""
		case "${_F_TYPE[$k]}" in
		password) suffix=':H' ;;
		multiline) suffix=':TXT' ;;
		combo) suffix=':CB' ;;
		combo-entry) suffix=':CBE' ;;
		calendar) suffix=':DT' ;;
		esac
		args+=("--field=${_F_LABEL[$k]}${suffix}")
		case "${_F_TYPE[$k]}" in
		combo | combo-entry)
			local cand="${_F_CANDIDATE[$k]}"
			# yad: 候选串中 ^ 前缀项作为默认值 (默认值不在候选时仍可显示)
			[[ -n "${_F_DEFAULT[$k]}" ]] && cand="^${_F_DEFAULT[$k]}!${cand}"
			args+=("$cand")
			;;
		*) args+=("${_F_DEFAULT[$k]}") ;;
		esac
	done

	local out_str
	out_str=$(yad "${args[@]}")
	local rc=$?
	((rc != 0)) && return $rc

	local -a vals
	IFS='|' read -r -a vals <<<"$out_str"
	local i
	for i in "${!_F_KEYS[@]}"; do
		out[${_F_KEYS[$i]}]="${vals[$i]:-}"
	done
}

# zenity 分支: --forms, 每字段 --add-*; combo 候选转 `|` 分隔
_form_zenity() {
	local -n out=$1
	local -a args=(--forms)
	local k
	for k in "${_F_KEYS[@]}"; do
		case "${_F_TYPE[$k]}" in
		entry | combo-entry) args+=("--add-entry=${_F_LABEL[$k]}") ;;
		password) args+=("--add-password=${_F_LABEL[$k]}") ;;
		multiline) args+=("--add-multiline-entry=${_F_LABEL[$k]}") ;;
		combo) args+=("--add-combo=${_F_LABEL[$k]}") ;;
		calendar) args+=("--add-calendar=${_F_LABEL[$k]}") ;;
		esac
	done
	local cv
	for k in "${_F_KEYS[@]}"; do
		if [[ "${_F_TYPE[$k]}" == "combo" ]]; then
			args+=("--combo-values=${_F_CANDIDATE[$k]//!/|}")
		fi
	done

	local out_str
	out_str=$(zenity "${args[@]}")
	local rc=$?
	((rc != 0)) && return $rc

	local -a vals
	IFS='|' read -r -a vals <<<"$out_str"
	local i
	for i in "${!_F_KEYS[@]}"; do
		out[${_F_KEYS[$i]}]="${vals[$i]:-}"
	done
}
