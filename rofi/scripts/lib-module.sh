# lib-module.sh — rofi 模块菜单框架
#
# 依赖: util.sh (需调用方先 source)
# 调用方需设定: MODULE_THEME MODULE_WIDTH ROFI_DIR
# 使用方法见末尾注释

_module_menu_build() {
	local layout=$(grep 'USE_ICON' ${MODULE_THEME} | cut -d'=' -f2)
	declare -ga MAIN_OPTS=()
	declare -ga OPT_KEYS=()

	for key in "${MODULE_KEYS[@]}"; do
		local icon="${MODULE_ICON[$key]}"
		local label="${MODULE_LABEL[$key]}"
		local status=$(_module_status "$key" "${MODULE_STATUS[$key]}")

		if [[ "$layout" == 'NO' ]]; then
			MAIN_OPTS+=("$(printf "%-30s %s" "${icon} ${label}" "$status")")
		else
			MAIN_OPTS+=("$icon $status")
		fi
		OPT_KEYS+=("$key")
	done

	local count=${#MODULE_KEYS[@]}
	[ "$_module_col" = "1" ] && _module_row=${MODULE_MAX_LINES:-$count} || _module_col=$count
}

_module_status() {
	local key=$1 expr=$2
	case "$expr" in
	toggle:*) icon toggle app "${expr#*:}" ;;
	toggle) icon toggle app "$key" ;;
	active:*) icon active app "${expr#*:}" ;;
	active) icon active app "$key" ;;
	active-svc:*) icon active service "${expr#*:}" ;;
	active-svc) icon active service "$key" ;;
	cmd:*) eval "${expr#cmd:}" ;;
	str:*) echo "${expr#str:}" ;;
	esac
}

_module_rofi() {
	local extra=()
	if [[ "${MODULE_SEARCH_BAR:-true}" == 'true' ]]; then
		extra=(
			-theme-str 'inputbar {children: [ "textbox-prompt-colon", "entry"];}'
			-theme-str 'entry {padding:8px;background-color:inherit;text-color:inherit;}'
		)
	else
		extra=(-theme-str 'inputbar {children: [ "textbox-prompt-colon"];}')
	fi
	local mesg_safe="${MODULE_MESG:-}"
	mesg_safe="${mesg_safe//&/&amp;}"
	local font_str=()
	[[ -n "${MODULE_FONT:-}" ]] && font_str=(-theme-str "* {font: \"${MODULE_FONT}\";}")
	rofi -theme-str "listview {columns: $_module_col; lines: $_module_row;}" \
		-theme-str 'textbox-prompt-colon {str: "'"${MODULE_NAME}"'";}' \
		-theme-str 'window {width: '$MODULE_WIDTH'px;}' \
		"${extra[@]}" \
		"${font_str[@]}" \
		${MODULE_ACTIVE:+-a "$MODULE_ACTIVE"} ${MODULE_URGENT:+-u "$MODULE_URGENT"} \
		-dmenu -i \
		-mesg "${mesg_safe}" \
		-theme ${MODULE_THEME} \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

module_sub_rofi() {
	local prompt="${1:-}" mesg="${2:-}"
	mesg="${mesg//&/&amp;}"
	local font_str=()
	[[ -n "${MODULE_FONT:-}" ]] && font_str=(-theme-str "* {font: \"${MODULE_FONT}\";}")
	rofi -theme-str "listview {columns: 1;}" \
		-theme-str 'window {width: '$MODULE_WIDTH'px;}' \
		"${font_str[@]}" \
		-dmenu -i \
		-p "$prompt" -mesg "$mesg" \
		-theme ${MODULE_THEME} \
		-hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

# 从 stdin 读取注册表 (pipe 分隔)
# 格式: key|icon|label|mesg|status_expr
module_parse() {
	MODULE_KEYS=()
	declare -gA MODULE_ICON MODULE_LABEL MODULE_MESG MODULE_STATUS
	while IFS='|' read -r key icon label mesg status_expr; do
		[[ -z "$key" ]] && continue
		MODULE_KEYS+=("$key")
		MODULE_ICON[$key]="$icon"
		MODULE_LABEL[$key]="$label"
		MODULE_MESG[$key]="$mesg"
		MODULE_STATUS[$key]="$status_expr"
	done
}

# 主循环: build menu → show → dispatch → repeat
module_loop() {
	case "$MODULE_THEME" in
	*type-1* | *type-3* | *type-5*) _module_col=1 ;;
	*) _module_row=1 ;;
	esac

	_module_menu_build
	local chosen=$(printf '%s\n' "${MAIN_OPTS[@]}" | _module_rofi)
	[[ -z "$chosen" ]] && return

	local key=""
	for i in "${!MAIN_OPTS[@]}"; do
		[[ "${MAIN_OPTS[$i]}" == "$chosen" ]] && {
			key="${OPT_KEYS[$i]}"
			break
		}
	done
	[[ -z "$key" ]] && return

	local handler="handle_${key//-/_}"
	declare -F "$handler" &>/dev/null && "$handler"
}

# ============ 使用示例 ============
#
# #!/usr/bin/env bash
# ROFI_DIR="$(dirname "$(dirname "$0")")"
# MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
# MODULE_WIDTH=500
# MODULE_MAX_LINES=8          # 可选，限制菜单可视行数
# source "$(dirname "$0")"/util.sh
# source "$(dirname "$0")"/lib-module.sh
#
# toggleApplication() { ... }
#
# module_parse <<'MODULES'
# picom|󰋩|Picom|Windows Composer|toggle
# conky|󰏘|Conky|System Monitor|toggle
# MODULES
#
# handle_picom() { toggleApplication picom; }
# handle_conky() { toggleApplication conky; }
#
# module_loop
