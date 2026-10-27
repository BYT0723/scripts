#!/bin/bash

# 进程快照缓存: 单次菜单构建内多次 icon ... app 共用一次 /proc 快照,
# 由 lib-module.sh _module_menu_build 在每次构建前清空 (_ICON_PS="")。
# 构建内毫秒级 skew 可接受; 跨构建重采保证 toggle 后图标正确。
_ICON_PS=""

icon() {
    local icons
    if [[ "$1" == "toggle" ]]; then
        icons=("" "")
    else
        icons=("" "")
    fi

    local idx=0
    case "$2" in
    app)
        # /proc 快照替代 ps: 同等内容, 省一半时间 (557 进程下 16ms vs 32ms)
        [[ -n "$_ICON_PS" ]] || _ICON_PS=$(cat /proc/[0-9]*/comm 2>/dev/null)
        [[ "$_ICON_PS" == *"$3"* ]] && idx=1
        ;;
    service) systemctl is-active --quiet "$3" 2>/dev/null && idx=1 ;;
    conf)
        if [ "$3" = "wallpaper" ]; then
            local w_conf="$HOME/.config/dwm/wallpaper.json"
            local val=""
            [ -n "$6" ] && val=$(jq -r ".monitors[\"$6\"].\"$4\" // empty" "$w_conf" 2>/dev/null)
            [ -z "$val" ] && val=$(jq -r ".defaults.\"$4\" // empty" "$w_conf" 2>/dev/null)
            [ "$val" != "$(typeToValue $5)" ] && [ -n "$val" ] && idx=1
        else
            [[ -n $(grep -E "^$4\s*=\s*$(typeToValue $5)" ${confPath[$3]}) ]] || idx=1
        fi
        ;;
    cmd)
        [[ -n $(ps ax | grep "$3" | grep -v grep) ]] && idx=1
        ;;
    raw) idx=$($3) ;;
    esac
    echo ${icons[$idx]}
}

typeToValue() {
    case "$1" in
    bool) echo false ;;
    number) echo 0 ;;
    esac
}

toggleConf() {
    if [ "$1" = "wallpaper" ]; then
        local key="$2" type="$3" monitor="${4:-}"
        local conf="$HOME/.config/dwm/wallpaper.json"
        local path=".monitors[\"$monitor\"]"

        local def=$(typeToValue "$type")
        local cur=$(jq -r "${path}.${key} // empty" "$conf" 2>/dev/null)
        if [ "$cur" = "$def" ] || [ -z "$cur" ]; then
            jq "${path}.${key} = 1" "$conf" >"$conf.tmp"
        else
            jq "${path}.${key} = 0" "$conf" >"$conf.tmp"
        fi
        mv "$conf.tmp" "$conf"
        return
    fi

    local def=$(typeToValue "$3") val
    if grep -qE "^$2\s*=\s*$def" "${confPath[$1]}"; then
        case "$3" in bool) val=true ;; number) val=1 ;; esac
    else
        case "$3" in bool) val=false ;; number) val=0 ;; esac
    fi
    sed -i "s|^$2\s*=\s*[^ ]*|$2\ =\ $val|g" "${confPath[$1]}"
}

getConfig() {
    grep -E "^$2\s*=" "${confPath[$1]}" | tail -1 | awk -F '=' '{print $2}' | grep -o "[^ ]\+\( \+[^ ]\+\)*"
}
