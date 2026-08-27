# lib-module.sh — rofi 模块菜单框架
#
# 依赖: util.sh (需调用方先 source)
# 调用方需设定: MODULE_THEME ROFI_DIR
# 可选: MODULE_WIDTH (默认 500) MODULE_FONT
# 可选数组 (外部 theme-str, 追加在内置之后覆盖 rasi):
#   MODULE_THEME_STR   → 主菜单 (_module_rofi)
#   MODULE_SUB_THEME_STR   → 子菜单 (module_sub_rofi)
#   MODULE_INPUT_THEME_STR → 输入框 (module_input)
#   MODULE_MULTI_THEME_STR → 多选 (module_multi_rofi)
# 使用方法见末尾注释

MODULE_WIDTH="${MODULE_WIDTH:-500}"
ENTRY_NAME_WIDTH="${ITEM_SPACE_WIDTH:-38}"
ENTRY_STATE_WIDTH=$((40 - ENTRY_NAME_WIDTH))

_module_menu_build() {
    local layout=$(grep 'USE_ICON' ${MODULE_THEME} | cut -d'=' -f2)
    declare -ga MAIN_OPTS=()
    declare -ga OPT_KEYS=()

    for key in "${MODULE_KEYS[@]}"; do
        local icon="${MODULE_ICON[$key]}"
        local label="${MODULE_LABEL[$key]}"
        local status=$(_module_status "$key" "${MODULE_STATUS[$key]}")

        if [[ "$layout" == 'NO' ]]; then
            MAIN_OPTS+=("$(printf "%-${ENTRY_NAME_WIDTH}s %${ENTRY_STATE_WIDTH}s" "${icon} ${label}" "$status")")
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
    toggle-raw:*) icon toggle raw "${expr#*:}" ;;
    active:*) icon active app "${expr#*:}" ;;
    active) icon active app "$key" ;;
    active-svc:*) icon active service "${expr#*:}" ;;
    active-svc) icon active service "$key" ;;
    cmd:*) eval "${expr#cmd:}" ;;
    str:*) echo "${expr#str:}" ;;
    esac
}

# 外部 theme-str 数组 → -theme-str 参数对 (未设置时为空, 追加覆盖 rasi)
_module_theme_str_args() { # src_var 数组 → dest_var 数组 (nameref)
    local -n src="$1" dest="$2"
    local s
    [[ -v src ]] || return 0
    for s in "${src[@]}"; do
        dest+=(-theme-str "$s")
    done
}

_module_rofi() {
    local extra=()
    if [[ "${MODULE_SEARCH_BAR:-true}" == 'true' ]]; then
        extra+=(
            -theme-str 'inputbar {children: [ "textbox-prompt-colon", "entry"];}'
            -theme-str 'entry {padding:8px;background-color:inherit;text-color:inherit;}'
        )
    else
        extra+=(-theme-str 'inputbar {children: [ "textbox-prompt-colon"];}')
    fi
    if [[ "${MODULE_MESSAGE_DISABLE:-false}" == 'true' ]]; then
        extra+=(-theme-str 'mainbox { children: ["inputbar", "listview"];}')
    fi
    local mesg_safe="${MODULE_MESG:-}"
    mesg_safe="${mesg_safe//&/&amp;}"
    local font_str=()
    [[ -n "${MODULE_FONT:-}" ]] && font_str=(-theme-str "* {font: \"${MODULE_FONT}\";}")
    local theme_str=()
    _module_theme_str_args MODULE_THEME_STR theme_str
    rofi -theme-str "listview {columns: $_module_col; lines: $_module_row;}" \
        -theme-str 'textbox-prompt-colon {str: "'"${MODULE_NAME}"'";}' \
        -theme-str 'window {width: '$MODULE_WIDTH'px;}' \
        "${extra[@]}" \
        "${font_str[@]}" \
        "${theme_str[@]}" \
        ${MODULE_ACTIVE:+-a "$MODULE_ACTIVE"} ${MODULE_URGENT:+-u "$MODULE_URGENT"} \
        -dmenu -i \
        -mesg "${mesg_safe}" \
        -theme ${MODULE_THEME} \
        -hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

module_sub_rofi() {
    local extra=()
    if [[ "${MODULE_SEARCH_BAR:-true}" == 'true' ]]; then
        extra+=(
            -theme-str 'inputbar {children: [ "textbox-prompt-colon", "entry"];}'
            -theme-str 'entry {padding:8px;background-color:inherit;text-color:inherit;}'
        )
    else
        extra+=(-theme-str 'inputbar {children: [ "textbox-prompt-colon"];}')
    fi
    if [[ "${MODULE_MESSAGE_DISABLE:-false}" == 'true' ]]; then
        extra+=(-theme-str 'mainbox { children: ["inputbar", "listview"];}')
    fi
    local prompt="${1:-}" mesg="${2:-}"
    mesg="${mesg//&/&amp;}"
    local font_str=()
    [[ -n "${MODULE_FONT:-}" ]] && font_str=(-theme-str "* {font: \"${MODULE_FONT}\";}")
    local theme_str=()
    _module_theme_str_args MODULE_SUB_THEME_STR theme_str
    rofi -theme-str "listview {columns: 1;}" \
        -theme-str 'textbox-prompt-colon {str: "'"$prompt"'";}' \
        -theme-str 'window {width: '$MODULE_WIDTH'px;}' \
        "${extra[@]}" \
        "${font_str[@]}" \
        "${theme_str[@]}" \
        -dmenu -i \
        -mesg "$mesg" \
        -theme ${MODULE_THEME} \
        -hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

module_input() {
    local prompt="${1:-Input}"
    local mesg="${2:-}"
    local default="${3:-}"
    mesg="${mesg//&/&amp;}"
    local font_str=()
    [[ -n "${MODULE_FONT:-}" ]] && font_str=(-theme-str "* {font: \"${MODULE_FONT}\";}")
    local theme_str=()
    _module_theme_str_args MODULE_INPUT_THEME_STR theme_str
    rofi \
        -theme-str 'window {width: '$MODULE_WIDTH'px;}' \
        -theme-str 'mainbox { children: ["inputbar", "message"];}' \
        -theme-str 'inputbar {children: ["textbox-prompt-colon", "entry"];}' \
        -theme-str 'textbox-prompt-colon {str: "'"$prompt"'";}' \
        -theme-str 'entry {padding:10px;background-color:inherit;text-color:inherit;placeholder: "'"$default"'";}' \
        "${font_str[@]}" \
        "${theme_str[@]}" \
        -dmenu \
        -mesg "$mesg" \
        -theme ${MODULE_THEME} \
        -hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

# rofi 确认对话框: 默认选中 No(取消), 输出 Yes 返回 0, No/ESC 返回 1
# 用法: module_confirm "提示文本" && 执行危险操作
module_confirm() {
    local mesg="${1:-Confirm}"
    mesg="${mesg//&/&amp;}"
    local font_str=()
    [[ -n "${MODULE_CONFIRM_FONT:-}" ]] && font_str=(-theme-str "* {font: \"${MODULE_CONFIRM_FONT}\";}")
    local ans
    ans=$(printf 'Yes\nNo\n' | rofi -dmenu -select 'No' \
        -theme-str 'window {width: '${MODULE_CONFIRM_WIDTH:-400}'px;}' \
        "${font_str[@]}" \
        -dmenu \
        -mesg "$mesg" \
        -theme ${ROFI_DIR}/applets/shared/confirm.rasi \
        -hover-select -me-select-entry '' -me-accept-entry MousePrimary)
    [[ "$ans" == "Yes" ]]
}

module_multi_rofi() {
    local prompt="${1:-}" mesg="${2:-}"
    mesg="${mesg//&/&amp;}"
    local font_str=()
    [[ -n "${MODULE_FONT:-}" ]] && font_str=(-theme-str "* {font: \"${MODULE_FONT}\";}")
    local theme_str=()
    _module_theme_str_args MODULE_MULTI_THEME_STR theme_str
    rofi -theme-str "listview {columns: 1;}" \
        -theme-str 'textbox-prompt-colon {str: "'"$prompt"'";}' \
        -theme-str 'window {width: '$MODULE_WIDTH'px;}' \
        -theme-str 'inputbar {children: [ "textbox-prompt-colon", "entry"];}' \
        -theme-str 'entry {padding:8px;background-color:inherit;text-color:inherit;}' \
        "${font_str[@]}" \
        "${theme_str[@]}" \
        -dmenu -i -multi-select \
        -mesg "$mesg" \
        -theme ${MODULE_THEME} \
        -hover-select -me-select-entry '' -me-accept-entry MousePrimary
}

# 从 stdin 读取注册表 (pipe 分隔)
# 格式: key|icon|label|status
module_parse() {
    MODULE_KEYS=()
    declare -gA MODULE_ICON MODULE_LABEL MODULE_STATUS
    while IFS='|' read -r key icon label status_expr; do
        [[ -z "$key" ]] && continue
        MODULE_KEYS+=("$key")
        MODULE_ICON[$key]="$icon"
        MODULE_LABEL[$key]="$label"
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
    [[ -z "$chosen" ]] && return 1

    local key=""
    for i in "${!MAIN_OPTS[@]}"; do
        [[ "${MAIN_OPTS[$i]}" == "$chosen" ]] && {
            key="${OPT_KEYS[$i]}"
            break
        }
    done
    [[ -z "$key" ]] && return 1

    local handler="handle_${key//-/_}"
    declare -F "$handler" &>/dev/null && "$handler"
    return 0
}

# ============ 使用示例 ============
#
# #!/usr/bin/env bash
# ROFI_DIR="$(dirname "$(dirname "$0")")"
# MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
# # MODULE_WIDTH 可选，默认 500
# MODULE_MAX_LINES=8          # 可选，限制菜单可视行数
# MODULE_THEME_STR=('window {fullscreen: true;}')  # 可选，覆盖 rasi 定义
# source "$(dirname "$0")"/util.sh
# source "$(dirname "$0")"/lib-module.sh
#
# toggleApplication() { ... }
#
# module_parse <<'MODULES'
# picom|󰋩|Picom|toggle
# conky|󰏘|Conky|toggle
# MODULES
#
# handle_picom() { toggleApplication picom; }
# handle_conky() { toggleApplication conky; }
#
# module_loop
