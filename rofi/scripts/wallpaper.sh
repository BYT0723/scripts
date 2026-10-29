#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"
MODULE_NAME=" Wallpaper"
MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_MAX_LINES=8

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/utils/notify.sh"
source "$WORK_DIR/tools/wallpaper-lib.sh"
source "$WORK_DIR/tools/wallpaper-render.sh"

# ---- Monitor Selection ----
monitor_selection() {
    local list_text=$(get_monitor_list_text)
    local groups=" Groups"

    if [ "$(echo "$list_text" | wc -l)" = 1 ]; then
        echo "$list_text"
        return
    fi

    local chosen=$(printf '%s\n%s\n' "$list_text" "$groups" | module_sub_rofi "  Monitor" "Select a monitor for wallpaper")
    [ -z "$chosen" ] && return

    [[ "$chosen" == "$groups" ]] && echo "__GROUPS__" && return
    echo "$chosen" | awk '{print $2}'
}

handle_group() {
    local new_group=" New (Add)"
    local opts=("$new_group")
    while IFS= read -r grp; do
        [ -z "$grp" ] && continue
        local en_icon="󰔢"
        [ "$(get_group_enabled "$grp")" = "true" ] && en_icon="󰔡"
        opts+=("$en_icon $grp")
    done < <(group_names)

    local chosen=$(printf '%s\n' "${opts[@]}" | module_sub_rofi "󰮄  Wallpaper Groups" "Select or create a group")
    [ -z "$chosen" ] && return

    if [[ "$chosen" == "$new_group" ]]; then
        local monitors=$(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}')
        [ -z "$monitors" ] && {
            error "No monitors detected"
            return
        }
        local selected=$(printf '%s\n' $monitors | module_multi_rofi "󰮄 Select Monitors" "Choose monitors for the group")
        [ -z "$selected" ] && return

        while IFS= read -r mon; do
            [ -z "$mon" ] && continue
            local owner=$(group_for_monitor "$mon" all)
            [ -n "$owner" ] && error "Monitor '$mon' already belongs to group '$owner'" && return
        done <<<"$selected"

        local name=$(module_input "󰮄 Group Name" "Name for the new group")
        [ -z "$name" ] && return

        if has_group "$name"; then
            error "Group '$name' already exists" && return
        fi

        local members_json=$(printf '%s\n' $selected | jq -Rnc '[inputs]')
        jq --arg n "$name" --argjson m "$members_json" \
            '.groups[$n] = {enabled: true, members: $m}' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
        handle_error "info" "Group '$name' created"
    else
        local group_name="${chosen#* }"
        local sub_opts=()
        local en
        en=$(get_group_enabled "$group_name")
        [ "$en" = "true" ] && sub_opts+=("󰔡 Disable") || sub_opts+=("󰔢 Enable")
        sub_opts+=("󰑉 Rename")
        sub_opts+=("󰔨 Edit Members")
        sub_opts+=("󰆴 Delete")

        local action=$(printf '%s\n' "${sub_opts[@]}" | module_sub_rofi "󰮄 $group_name" "Manage group")
        [ -z "$action" ] && return

        case "$action" in
        *Disable)
            jq --arg n "$group_name" '.groups[$n].enabled = false' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            clean_group "$group_name"
            handle_error "info" "Group '$group_name' disabled"
            ;;
        *Enable)
            jq --arg n "$group_name" '.groups[$n].enabled = true' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            handle_error "info" "Group '$group_name' enabled"
            ;;
        *Rename)
            local new_name=$(module_input "󰑉 Rename Group" "Current: $group_name" "$group_name")
            [ -z "$new_name" ] || [ "$new_name" = "$group_name" ] && return
            if has_group "$new_name"; then
                error "Group '$new_name' already exists" && return
            fi
            jq --arg old "$group_name" --arg new "$new_name" \
                '.groups[$new] = .groups[$old] | del(.groups[$old]) | if .monitors[$old] then .monitors[$new] = .monitors[$old] | del(.monitors[$old]) else . end' \
                "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            clean_group "$group_name"
            handle_error "info" "Group renamed to '$new_name'"
            ;;
        *"Edit Members")
            local all_mons=$(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}')
            local cur=$(get_group_members "$group_name" | xargs)
            local selected=$(printf '%s\n' $all_mons | module_multi_rofi "󰮄 Edit Members" "Current: ${cur:-none}")
            [ -z "$selected" ] && return

            while IFS= read -r mon; do
                [ -z "$mon" ] && continue
                local owner=$(group_for_monitor "$mon" all)
                [ -n "$owner" ] && [ "$owner" != "$group_name" ] && error "Monitor '$mon' already belongs to group '$owner'" && return
            done <<<"$selected"

            local members_json=$(printf '%s\n' $selected | jq -Rnc '[inputs]')
            jq --arg n "$group_name" --argjson m "$members_json" \
                '.groups[$n].members = $m' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            clean_group "$group_name"
            handle_error "info" "Group '$group_name' members updated"
            ;;
        *Delete)
            local confirm=$(printf 'Yes\nNo' | module_sub_rofi "󰮄 Delete '$group_name'?" "This cannot be undone")
            [ "$confirm" != "Yes" ] && return
            clean_group "$group_name"
            jq --arg n "$group_name" 'del(.groups[$n])' "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
            handle_error "info" "Group '$group_name' deleted"
            ;;
        esac
    fi
}

# ---- Main ----
MONITOR=$(monitor_selection)
[ -z "$MONITOR" ] && exit 0

if [[ "$MONITOR" == "__GROUPS__" ]]; then
    handle_group
    exit 0
fi

ensure_monitor_config "$MONITOR"
MODULE_MESG="Monitor: $MONITOR"

module_parse <<'MODULES'
next|󰑐|Next|
select||Select|
random_switch||Random|cmd:icon toggle conf wallpaper random number "$MONITOR"
random_type|󱧶|Type|cmd:t=$(getConfig -m "$MONITOR" random_type); case "$t" in video) echo "";; web) echo "";; scene) echo "";; *) echo "";; esac
random_duration|󰔟|Duration|cmd:getConfig -m "$MONITOR" duration
fps||FPS|cmd:get_video_render_config "$MONITOR" fps
property|󰔉|Property|cmd:n=$(prop_tunables "$MONITOR" 2>/dev/null | grep -c .); [ "${n:-0}" -gt 0 ] 2>/dev/null && echo "$n"
property_reset|󰜉|Reset Property|
random_images_path||Images Path|
random_videos_path||Videos Path|
random_web_path||Web Path|
random_scene_path||Scene Path|
random_images_path_dark||Images Path (Dark)|
random_videos_path_dark||Videos Path (Dark)|
random_web_path_dark||Web Path (Dark)|
MODULES
handle_next() { ("$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" next &) }
# yazi 选目录 (web/scene): 起始于主题目录, 文件输入归一到上层,
# 经 project_entry 校验入口 (web 认 project.json:file，回退 index.html;
# scene 互认 scene.pkg|json) 后直接应用。
# 成功 (已应用) 返回 0, 取消/非法返回 1 (调用方继续循环重显)。
# Usage: select_yazi_directory <config-base> (kind 按 base 名推导: *scene* 即 scene)
select_yazi_directory() {
    local base="$1" kind="web" start tmp picked
    [[ "$base" == *scene* ]] && kind="scene"
    start=$(expand_path "$(get_theme_dir "$MONITOR" "$base")")
    [ -d "$start" ] || start="$HOME"
    tmp=$(mktemp) || return 1
    YAZI_CONFIG_HOME=$HOME/.config/yazi_wallpaper $TERM yazi "$start" --chooser-file="$tmp" 2>/dev/null
    picked=$(cat "$tmp" 2>/dev/null)
    rm -f "$tmp"
    [ -n "$picked" ] || return 1
    [ -e "$picked" ] || return 1
    [ -f "$picked" ] && picked=$(dirname "$picked")
    if ! project_entry "$picked" "$kind" >/dev/null 2>&1; then
        if [ "$kind" = "web" ]; then
            system-notify critical "Wallpaper" "Not a web wallpaper (missing entry from project.json)"$'\n'"$picked"
        else
            system-notify critical "Wallpaper" "Not a scene wallpaper (missing scene.pkg/json)"$'\n'"$picked"
        fi
        return 1
    fi
    "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" file "$picked"
}
# web/scene 用 rofi 图文选择器 (标题+预览缩略图): yazi 顶层只见数字 id,
# 名字在 project.json:title 里, 预览经 project_preview (preview 字段优先，回退
# preview.*)。池为含 project.json 且 type 匹配的目录 (find_project_dirs)。image/video 保留 yazi 大图预览。
# 末条为 yazi 目录入口 (map 值为 __YAZI__), 同 image/video 选择逻辑按目录挑选。
# Usage: select_marker_wallpaper <label> <config-base> <type: web|scene>
select_marker_wallpaper() {
    local label="$1" base="$2" wtype="$3"
    local dir depth files
    dir=$(get_theme_dir "$MONITOR" "$base")
    depth=$(getConfig random_depth)
    if ! files=$(find_project_dirs "$dir" "$depth" "$wtype"); then
        return 1
    fi

    local menu map menu_nul
    menu=$(mktemp)
    map=$(mktemp)
    menu_nul=$(mktemp)
    trap 'rm -f "$menu" "$map" "$menu_nul"' RETURN

    local d id title icon
    local -A seen=()
    while IFS= read -r d; do
        [ -z "$d" ] && continue
        # 去重到目录, 保证 menu 与 map 行号一一对应
        [ -n "${seen[$d]}" ] && continue
        seen[$d]=1
        id=$(basename "$d")
        title="$id"
        if [ -f "$d/project.json" ]; then
            title=$(jq -r '.title // empty' "$d/project.json" 2>/dev/null)
            [ -z "$title" ] && title="$id"
        fi
        title=$(printf '%s' "$title" | tr '\t\n\r' '   ')
        icon=$(project_preview "$d" 2>/dev/null) || icon=""
        # NUL 字节 bash 变量装不下: 行尾先写 \001 占位, 喂 rofi 前统一 tr 成 NUL (同 windows-selector)
        printf '%s (%s)\001icon\x1f%s\x1f\n' "$title" "$id" "$icon" >>"$menu"
        printf '%s\n' "$d" >>"$map"
    done <<<"$files"
    # 末条 yazi 目录入口 (同 image/video 按目录挑选): menu/map 行号保持一一对应
    printf '%s\001icon\x1f%s\x1f\n' "󰉋 Browse directory (yazi)" "" >>"$menu"
    printf '%s\n' "__YAZI__" >>"$map"
    tr '\001' '\000' <"$menu" >"$menu_nul"

    local sel rc picked
    # 网格主题 (双列卡片 + 128px 大缩略图): inputbar 只有 entry, prompt 经 -p 设置。
    # Alt+1 打开目录 / Alt+2 复制绝对路径 / Alt+3 确认删除: config.rasi 已绑
    # kb-custom-1/2/3, dmenu 下退出码 10/11/12, -format i 输出高亮序号。
    # Alt+1/2 执行后循环重显继续挑；Alt+3 删完回模块菜单 (menu/map 是快照, 删后已过期)；
    # Enter 应用后退出；ESC 直接返回。
    while true; do
        sel=$(rofi -dmenu -i -p "$label (Alt+1 open · Alt+2 copy · Alt+3 del)" -format i -no-custom -show-icons \
            -theme "$ROFI_DIR/launchers/type-3/style-6.rasi" \
            -theme-str 'listview {columns: 4; lines: 4; flow: horizontal; }' \
            -theme-str 'window {width: 800px;}' \
            -hover-select -me-select-entry '' -me-accept-entry '' -me-accept-custom MousePrimary <"$menu_nul" 2>/dev/null)
        rc=$?
        case "$rc" in
        0) ;;            # 正常选中, 走下面原流程
        10 | 11 | 12) ;; # Alt+1/2/3, 需序号定位条目
        *) return 0 ;;   # ESC/其他直接返回
        esac
        case "$sel" in
        '' | *[!0-9]*) picked="" ;;
        *) picked=$(sed -n "$((sel + 1))p" "$map") ;;
        esac
        # 空选/越界: Enter 回模块菜单；快捷键无序号则重显
        # (custom key 未输出序号时可重试，ESC 可出)
        if [ -z "$picked" ]; then
            [ "$rc" = 0 ] && return 0
            continue
        fi
        if [ "$picked" = "__YAZI__" ]; then
            # yazi 目录入口: Alt+1/2/3 忽略重显; Enter 选目录,
            # 成功应用后退出, 取消/非法回 selector 继续挑
            [ "$rc" = 0 ] || continue
            if select_yazi_directory "$base"; then
                return 0
            fi
            continue
        fi
        case "$rc" in
        10) (xdg-open "$picked" &>/dev/null &) ;;
        11)
            printf '%s' "$picked" | xclip -selection clipboard 2>/dev/null
            system-notify low "Wallpaper" "Copied"$'\n'"$picked"
            ;;
        12)
            if module_confirm "Delete wallpaper?"$'\n'"$picked"; then
                if rm -rf "$picked" 2>/dev/null; then
                    system-notify normal "Wallpaper" "Deleted"$'\n'"$picked"
                else
                    system-notify critical "Wallpaper" "Delete failed"$'\n'"$picked"
                fi
                return 0
            fi
            ;;
        0)
            "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" file "$picked"
            return 0
            ;;
        esac
    done
}
handle_select() {
    case "$(getConfig -m "$MONITOR" random_type)" in
    web) select_marker_wallpaper "Web" random_web_dir web ;;
    scene) select_marker_wallpaper "Scene" random_scene_dir scene ;;
    *) "$WORK_DIR"/tools/wallpaper.sh -m "$MONITOR" select ;;
    esac
}
handle_random_switch() { toggleConf wallpaper random number "$MONITOR"; }
handle_random_type() {
    local cur chosen
    cur=$(getConfig -m "$MONITOR" random_type)
    chosen=$(printf 'image\nvideo\nweb\nscene' | module_sub_rofi "Random type" "current: $cur")
    case "$chosen" in image | video | web | scene) ;; *) return ;; esac
    [ "$chosen" = "$cur" ] && return
    jq --arg m "$MONITOR" --arg v "$chosen" '.monitors[$m].random_type = $v' \
        "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
}
handle_random_duration() { set_numeric_config "$MONITOR" duration "Duration" "Wallpaper change interval in minutes (≥ 1)" 1; }
handle_fps() {
    # setter 仅在写入新值时返回 0 (取消/非法/未改变直接返回)；有改变才重建 video 壁纸
    set_video_render_config "$MONITOR" fps "FPS" "Video frame rate limit (0 = unlimited, ≥ 0)" 0 &&
        reapply_video_wallpaper "$MONITOR"
}
# ---- Wallpaper user property (web/scene slider/color/file/bool/combo) ----
# --list-properties 仅 web/scene 有输出 (image/video 直接失败);
# group/Screen 属 -g 几何窗口, -m 无法寻址同样失败 → 通知后返回 (限定单 monitor)。
# slider 走 yad --scale --print-partial 逐值实时 set;
# color 的 yad 对话框无 partial (--changed-action 仅 CHK/CB/SW 有效),
# 只能 OK 单次应用 / 取消恢复原值;
# file 走 prop_pick_file (与 image/video select 同样的 yazi 选择器),
# 选中即单次 set / 取消恢复原值;
# bool 一键翻转直接 set, 无需对话框;
# combo 经 project.json options 用 rofi 选 label → set value (无 options 则自由输入)。
prop_tunables() { xwallpaper --list-properties -m "$1" 2>/dev/null | awk -F'\t' '$2 ~ /^(slider|color|file|bool|combo)$/'; }
prop_combo_options() { # <dir> <name> → "value\tlabel" 行; 无 options/空数组返回 1
    # options 三种变体: [{label,value}] (value 可为数字) / 纯字符串数组 (value=序号索引) / 缺失
    local dir="$1" name="$2" opts
    opts=$(jq -r --arg n "$name" '
        .general.properties[$n].options
        | if type != "array" or length == 0 then empty
          elif .[0] | type == "object" then
            .[] | "\(.value | tostring)\t\(.label // (.value | tostring))"
          else
            to_entries[] | "\(.key)\t\(.value | tostring)"
          end' "$dir/project.json" 2>/dev/null)
    [ -n "$opts" ] || return 1
    printf '%s\n' "$opts"
}
prop_commit_once() { # <name> <original> <yad-status> <yad-output>: OK 非空即应用 / 取消则恢复原值
    if (($3 == 0)); then
        [ -n "$4" ] && xwallpaper --set-property "$1=$4" -m "$MONITOR" 2>/dev/null
    else
        xwallpaper --set-property "$1=$2" -m "$MONITOR" 2>/dev/null
    fi
}
prop_reset() { # 确认后 xwallpaper --clear-properties, 清用户覆盖回 project.json 默认
    [ -n "$(prop_tunables "$MONITOR")" ] || {
        system-notify low "Wallpaper" "No adjustable properties on $MONITOR"
        return 1
    }
    module_confirm "Reset all properties to defaults?"$'\n'"$MONITOR" || return 1
    if xwallpaper --clear-properties -m "$MONITOR" 2>/dev/null; then
        system-notify normal "Wallpaper" "Properties reset"$'\n'"$MONITOR"
    else
        system-notify critical "Wallpaper" "Reset failed"$'\n'"$MONITOR"
        return 1
    fi
}
prop_label() { # <dir> <name> → 显示标签 (project.json text 原样显示, 缺失回退 name)
    local dir="$1" name="$2" text=""
    if [ -n "$dir" ] && [ -f "$dir/project.json" ]; then
        text=$(jq -r --arg n "$name" '.general.properties[$n].text // empty' "$dir/project.json" 2>/dev/null)
    fi
    [ -n "$text" ] || text="$name"
    printf '%s' "$text"
}
prop_wall_dir() { # → 当前 MONITOR 的壁纸目录 (state path 是目录则原样, 文件取 dirname)
    local path
    path=$(xwallpaper --state 2>/dev/null | awk -F'\t' -v n="$MONITOR" '$1==n {print $3; exit}')
    [ -d "$path" ] && printf '%s' "$path" || dirname "$path"
}
prop_pick_file() { # <start-dir> → 输出选中路径; 取消/空返回非 0 (与 image/video select 同样的 yazi 选择器)
    local start="$1" tmp picked
    [ -d "$start" ] || start="$HOME"
    tmp=$(mktemp) || return 1
    YAZI_CONFIG_HOME=$HOME/.config/yazi_wallpaper $TERM yazi "$start" --chooser-file="$tmp" 2>/dev/null
    picked=$(cat "$tmp" 2>/dev/null)
    rm -f "$tmp"
    [ -n "$picked" ] || return 1
    printf '%s' "$picked"
}
prop_color_hex() { # "r g b" (0..1 floats) → #rrggbb; 非法输入输出空
    [[ "$1" =~ ^[0-9.]+[[:space:]]+[0-9.]+[[:space:]]+[0-9.]+$ ]] || return 1
    awk '{r=$1*255+0.5; g=$2*255+0.5; b=$3*255+0.5;
        if (r<0||r>255.5||g<0||g>255.5||b<0||b>255.5) exit 1;
        printf "#%02X%02X%02X", int(r), int(g), int(b)}' <<<"$1" 2>/dev/null
}
prop_hex_to_rgb() { # #rrggbb/#rgb → "r g b" (%.6f floats); 非法输入失败
    # scene 把 color 原样透传给 JS (按空格 split), 不认 hex; web 两者都认。
    # set 一律转回 triple, 两后端通用。
    local h="${1#\#}" r g b
    if [[ "$h" =~ ^[0-9a-fA-F]{6}$ ]]; then
        r=$((16#${h:0:2}))
        g=$((16#${h:2:2}))
        b=$((16#${h:4:2}))
    elif [[ "$h" =~ ^[0-9a-fA-F]{3}$ ]]; then
        r=$((16#${h:0:1}${h:0:1}))
        g=$((16#${h:1:1}${h:1:1}))
        b=$((16#${h:2:1}${h:2:1}))
    else
        return 1
    fi
    awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN {printf "%.6f %.6f %.6f", r/255, g/255, b/255}'
}
prop_range() { # <dir> <name> → "min max" (project.json 缺失/非法时 fallback 0 100)
    local dir="$1" name="$2" out min max
    out=$(jq -r --arg n "$name" '.general.properties[$n] | "\(.min // 0) \(.max // 100)"' "$dir/project.json" 2>/dev/null)
    read min max <<<"$out"
    [[ "$min" =~ ^-?[0-9]+$ ]] || min=0
    [[ "$max" =~ ^-?[0-9]+$ ]] || max=100
    [ "$max" -gt "$min" ] 2>/dev/null || {
        min=0
        max=100
    }
    printf '%s %s' "$min" "$max"
}
handle_property() {
    local tunables name
    tunables=$(prop_tunables "$MONITOR")
    [ -n "$tunables" ] || {
        system-notify low "Wallpaper" "No adjustable properties on $MONITOR"
        return
    }
    # 单属性直接调完回主菜单; 多属性循环停留在选择层, ESC 返回主菜单
    # (复用 theme.sh handle_monitor_brightness 的内层循环模式)
    if [ "$(printf '%s\n' "$tunables" | wc -l)" = 1 ]; then
        _apply_property "$(printf '%s' "$tunables" | cut -f1)"
        return
    fi
    local dir
    dir=$(prop_wall_dir)
    # text 全串较长, property 流程窗口加宽 (local 仅作用域内, 主菜单/其它模块保持 500)
    local MODULE_WIDTH=600
    local RESET_LINE="󰜉 Reset to defaults"
    while true; do
        # 显示 project.json text 全串 (prop_label, 无 text 回退 name), 寻址仍用英文 name:
        # display line → name 关联映射 (label 含空格, 不能再按列切), 另保留
        # raw-name 精确命中作兼容回退; color 值显示为 hex (纯表现层, 转换失败回退原值)。
        local -A _line_to_name=()
        local menu="" chosen line label pn pt pv
        while IFS=$'\t' read -r pn pt pv; do
            [ -n "$pn" ] || continue
            [ "$pt" = color ] && pv=$(prop_color_hex "$pv" 2>/dev/null || printf '%s' "$pv")
            label=$(prop_label "$dir" "$pn")
            line=$(printf '%-36s %10s' "$label" "$pv")
            _line_to_name["$line"]="$pn"
            menu+="$line"$'\n'
        done <<<"$tunables"
        menu+="$RESET_LINE"$'\n'
        chosen=$(printf '%s' "$menu" | module_sub_rofi "Property ($MONITOR)" "Select a slider/color/file/bool/combo property")
        [ -z "$chosen" ] && return
        if [ "$chosen" = "$RESET_LINE" ]; then
            prop_reset
            # 重置后重取: 选择列表显示新默认值 (壁纸被换掉则静默回主菜单)
            tunables=$(prop_tunables "$MONITOR")
            [ -n "$tunables" ] || return
            continue
        fi
        name="${_line_to_name[$chosen]}"
        [ -n "$name" ] || name=$(printf '%s\n' "$tunables" | awk -F'\t' -v c="$chosen" '$1==c {print $1; exit}')
        [ -z "$name" ] && continue
        _apply_property "$name"
        # 上轮改完重取: 选择列表显示新值 (壁纸被换掉则静默回主菜单)
        tunables=$(prop_tunables "$MONITOR")
        [ -n "$tunables" ] || return
    done
}
_apply_property() { # <name>: 按 type 调起对应编辑器 ($tunables 取自调用者, bash 动态作用域)
    local name="$1" type cur dir label opts chosen new original init start min max value last v l yad_fd yad_pid tmpdir fifo status
    local -a _vals=() _menu=()
    type=$(printf '%s\n' "$tunables" | awk -F'\t' -v n="$name" '$1==n {print $2; exit}')
    cur=$(printf '%s\n' "$tunables" | awk -F'\t' -v n="$name" '$1==n {print $3; exit}')
    original="$cur"
    dir=$(prop_wall_dir)
    # 展示用 text 全串 (prop_label), --set-property 仍用英文 $name
    label=$(prop_label "$dir" "$name")
    if [ "$type" = "bool" ]; then
        # 开关一键翻转, 无需对话框
        case "${cur,,}" in true | 1 | on) new="false" ;; *) new="true" ;; esac
        xwallpaper --set-property "$name=$new" -m "$MONITOR" 2>/dev/null
        return
    fi
    if [ "$type" = "combo" ]; then
        if ! opts=$(prop_combo_options "$dir" "$name"); then
            # 无 options 定义: 自由输入, 当前值作默认值
            new=$(module_input "Wallpaper Property" "$MONITOR : $label" "$cur")
            [ -n "$new" ] && xwallpaper --set-property "$name=$new" -m "$MONITOR" 2>/dev/null
            return
        fi
        # 菜单只显示 options label 全串 (label 碰撞才加 " (value)" 区分, 不掺改写);
        # 显示加 ✓ 与回查共用 _menu, set 一律英文 value
        local -a _labels=()
        while IFS=$'\t' read -r v l; do
            [ -n "$v" ] || continue
            [ -n "$l" ] || l="$v"
            _vals+=("$v")
            _labels+=("$l")
        done <<<"$opts"
        [ "${#_vals[@]}" -gt 0 ] || return
        local -A _dup=()
        for l in "${_labels[@]}"; do _dup["$l"]=$((${_dup["$l"]:-0} + 1)); done
        for i in "${!_vals[@]}"; do
            v="${_labels[$i]}"
            [ "${_dup[$v]:-0}" -gt 1 ] && v="$v (${_vals[$i]})"
            _menu+=("$v")
        done
        chosen=$(
            for i in "${!_vals[@]}"; do
                v="${_menu[$i]}"
                [ "${_vals[$i]}" = "$cur" ] && v="$v ✓"
                printf '%s\n' "$v"
            done | module_sub_rofi "Property ($MONITOR)" "$label: select option"
        )
        [ -z "$chosen" ] && return
        chosen="${chosen% ✓}"
        for i in "${!_vals[@]}"; do
            if [ "${_menu[$i]}" = "$chosen" ]; then
                xwallpaper --set-property "$name=${_vals[$i]}" -m "$MONITOR" 2>/dev/null
                return
            fi
        done
        return
    fi
    if [ "$type" = "color" ]; then
        init=$(prop_color_hex "$cur")
        new=$(yad --color --title="Wallpaper Property" --text="$MONITOR : $label" \
            ${init:+--init-color="$init"} 2>/dev/null)
        # yad 输出 hex; set 前转回 triple (scene 只认 triple, web 两者都认)。
        # 取消/ESC 恢复原值 (OK 但输出为空视为无改动, 不恢复)
        prop_commit_once "$name" "$original" "$?" "$(prop_hex_to_rgb "$(printf '%s' "$new" | tr -d '\n')")"
        return
    fi
    if [ "$type" = "file" ]; then
        # 与 image/video select 同样的 yazi 选择器 (起始于当前值所在目录, 无值时用壁纸目录);
        # 选中即单次 set, 取消则恢复原值 (无 partial, 恢复即 no-op)
        start="$dir"
        [ -f "$cur" ] && start=$(dirname "$cur")
        if new=$(prop_pick_file "$start"); then
            xwallpaper --set-property "$name=$new" -m "$MONITOR" 2>/dev/null
        else
            xwallpaper --set-property "$name=$original" -m "$MONITOR" 2>/dev/null
        fi
        return
    fi
    [[ "$cur" =~ ^-?[0-9]+$ ]] || cur=0
    read min max <<<"$(prop_range "$dir" "$name")"
    [ "$cur" -ge "$min" ] 2>/dev/null || cur="$min"
    [ "$cur" -le "$max" ] 2>/dev/null || cur="$max"

    # 复用 theme.sh handle_monitor_brightness 的 FIFO + 后台 pid 模式
    # (set-property ~1ms, 无需 DDC 那套 drain, 逐值即时应用)
    tmpdir=$(mktemp -d) || return
    fifo="$tmpdir/out"
    mkfifo "$fifo" || {
        rm -rf "$tmpdir"
        return
    }
    yad \
        --scale \
        --title="Wallpaper Property" \
        --text="$MONITOR : $label" \
        --min-value="$min" \
        --max-value="$max" \
        --value="$cur" \
        --step=1 \
        --print-partial >"$fifo" 2>/dev/null &
    yad_pid=$!
    exec {yad_fd}<"$fifo"

    while IFS= read -r value <&"$yad_fd"; do
        last="$value"
        xwallpaper --set-property "$name=$value" -m "$MONITOR" 2>/dev/null
    done
    exec {yad_fd}<&-
    rm -rf "$tmpdir"

    wait "$yad_pid"
    status=$?

    if ((status != 0)); then
        # 取消/ESC: 恢复原值
        xwallpaper --set-property "$name=$original" -m "$MONITOR" 2>/dev/null
    fi
}
handle_property_reset() { prop_reset; }
handle_random_images_path() { pick_config_dir "$MONITOR" random_image_dir; }
handle_random_videos_path() { pick_config_dir "$MONITOR" random_video_dir; }
handle_random_web_path() { pick_config_dir "$MONITOR" random_web_dir; }
handle_random_scene_path() { pick_config_dir "$MONITOR" random_scene_dir; }
handle_random_images_path_dark() { pick_config_dir "$MONITOR" random_image_dir_dark; }
handle_random_videos_path_dark() { pick_config_dir "$MONITOR" random_video_dir_dark; }
handle_random_web_path_dark() { pick_config_dir "$MONITOR" random_web_dir_dark; }

while module_loop; do :; done
