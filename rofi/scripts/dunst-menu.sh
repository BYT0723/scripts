#!/usr/bin/env bash
# dunst action dmenu — 把 dunst 的 action / URL 列表交给 rofi 选择
# dunst 配置 (dunstrc): dmenu = "~/.dwm/rofi/scripts/dunst-menu.sh"
#
# stdin 每行一条 (dunst src/menu.c):
#   action: #<action 文本> (<通知 summary>) [<id>,<action key>]
#   URL:    <裸 URL>
# dunst 用行尾 [id,key] 派发 action, 所以选中后必须原样回传整行;
# 显示为 "<label> <key>" (label 可能是图标字形; 空 label 只显示 key),
# 丢弃通知 summary, 用 -format i 的 0 基序号回映射原始行。

ROFI_DIR="$(dirname "$(dirname "$0")")"
THEME="$ROFI_DIR/applets/type-2/style-2.rasi"

# 兼容 dmenu 的 -p <prompt>; dunst 默认不追加参数, 此时用 Actions
prompt="Actions"
while getopts ":p:" opt; do
    case "$opt" in
    p) prompt="$OPTARG" ;;
    esac
done

# 读完 stdin 再起 rofi: dunst 写完后关闭管道, 不会互相阻塞
mapfile -t lines
rows=()
show=()
id_sfx=()
for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue
    rows+=("$line")
    if [[ "$line" != '#'* ]]; then
        show+=("$line")
        id_sfx+=("")
        continue
    fi

    body="${line#'#'}"
    # 行尾 [<id>,<key>] (与 dunst invoke_action 的 strrchr 一致)
    meta="${body##*\[}"
    id="${meta%%,*}"
    key="${meta#*,}"
    key="${key%]}"
    id_sfx+=("#${id}")

    # dunst 的主体是 "<label> (<notification summary>)": 保留 label
    # (常是图标字形/动作名), 丢掉 summary. 按第一个 " (" 切: summary 自带
    # 括号很常见 ("New message (3)"), label 自带 " (" 极少见 (dunst 不转义).
    raw_text="${body% \[*\]}"
    label="${raw_text%% (*}"
    label="${label%"${label##*[![:space:]]}"}" # 去 label 尾部空格
    if [[ -z "$label" ]]; then
        # 空 label (播放器等应用会这样发 action): 只显示 key
        show+=("${key:-#${id}}")
    elif [[ -z "$key" ]]; then
        show+=("$label")
    else
        show+=("$label $key") # key 不包裹, 直接跟在 label 后
    fi
done
[[ ${#rows[@]} -eq 0 ]] && exit 0

# 不同通知出现完全相同的 "label key" 时补通知 id, 保证每行可选; 常规菜单无后缀.
declare -A count=()
for s in "${show[@]}"; do
    count["$s"]=$((${count["$s"]:-0} + 1))
done
for i in "${!show[@]}"; do
    [[ -n "${id_sfx[$i]}" ]] || continue
    s="${show[$i]}"
    ((${count["$s"]:-0} > 1)) || continue
    show[$i]+=" ${id_sfx[$i]}"
done

# type-1 文本列表 (与 notification.sh 一致); type-2 图标网格会压扁 action 文本
sel=$(printf '%s\n' "${show[@]}" | rofi -dmenu -i -no-custom -format i -p "$prompt" \
    -theme "$THEME" \
    -theme-str 'window {width: 800px;}' \
    -theme-str "element {padding: 20px 5px;}" \
    -theme-str "element-text {font: \"JetBrains Mono Nerd Font 12\";}" \
    -theme-str 'inputbar {children: [ "textbox-prompt-colon"];}' \
    -theme-str 'entry {padding: 8px; background-color: inherit; text-color: inherit;}' \
    -theme-str 'textbox-prompt-colon {str: "'"$prompt"'";}' \
    -hover-select -me-select-entry '' -me-accept-entry MousePrimary 2>/dev/null)
rc=$?

# ESC/取消/无序号: 静默退出, dunst 视为中止 (不派发 action)
[[ $rc -eq 0 && "$sel" =~ ^[0-9]+$ ]] || exit 0
((sel < ${#rows[@]})) || exit 0

printf '%s\n' "${rows[$sel]}"
