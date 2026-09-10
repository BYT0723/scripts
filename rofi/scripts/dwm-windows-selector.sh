#!/usr/bin/env bash
# rofi-windows.sh — dwm windows grouped by tag, bar order within each group.
#
# 读取 EWMH 属性（dwm 发布）：
#   _NET_CLIENT_LIST  已按 (主 tag 升序，组内 bar 顺序) 排列（含 hidden）
#   _NET_WM_DESKTOP   每窗主 tag（多 tag 只取最低位；sticky 归第 1 组）
#   _NET_DESKTOP_NAMES  icon+name（tag 列标签来源，与 dwm 同源）
# 输出 flat 列表（无标题行，filter 可直接匹配 tag/monitor/class/title），每行：
#   tag(icon+name)\tmonitor\tclass\ttitle（前三列垫齐到最长）+\0icon\x1f<class小写>
# 已按 (主 tag 升序，组内 bar 顺序) 排列（含 hidden，标题带 ` (hidden)` 后缀）。
# monitor 显示 xrandr 输出短名（DisplayPort-0→DP-0，HDMI-A-0→HDMI-0，重名回退全名）；
# 当前 monitor（指针所在 ≈ selmon）的行在 monitor 列前标 `*`；几何未知显示 `?`。
# 选中后 `xdotool windowactivate` 走 _NET_ACTIVE_WINDOW，dwm 侧
# jump_on_activate=1 会自动跳到对应 tag/monitor 并显示 hidden 窗口。
#
# tag 标签读 _NET_DESKTOP_NAMES（与 dwm 同源，无需同步）。
#
# 接线：dwm-launcher.sh windows() 调用本脚本（已替换旧 windows-selector.sh）；
# dwm 侧 Mod+w 经 LAUNCHCMD("windows") 进入。
#
# 依赖：bash, xprop, xrandr, xdotool, rofi。
set -u

ROFI_DIR="$(dirname "$(dirname "$0")")"
type="$ROFI_DIR/launchers/type-3"
style='style-5.rasi'
theme="$type/$style"

# tag 标签取自 dwm 发布的 _NET_DESKTOP_NAMES，与 dwm 同源，无需同步；
# 取不到时直接退出（分组无从谈起）。
TAG_LABELS=()
while IFS= read -r line; do
    line=${line%\"}
    line=${line#\"}
    TAG_LABELS+=("$line")
done < <(xprop -root _NET_DESKTOP_NAMES 2>/dev/null | grep -o '"[^"]*"')
NTAGS=${#TAG_LABELS[@]}
[ "$NTAGS" -eq 0 ] && exit 0 # 无 desktop 定义：分组无从谈起（dwm 未发布 EWMH 时）

# --- monitors: xrandr 名称 + 几何，按 xrandr 顺序编号（M<idx> 兜底） ---
MON_NAME=()
MON_GEO=()
if command -v xrandr >/dev/null 2>&1; then
    while IFS= read -r line; do
        # e.g. " 0: +*DP-1 1920/600x1080/340+0+0  DP-1"
        if [[ "$line" =~ ^\ *([0-9]+):.*\ ([0-9]+)/[0-9]+x([0-9]+)/[0-9]+\+([0-9]+)\+([0-9]+)\ +([^ ]+)\ *$ ]]; then
            MON_NAME[${BASH_REMATCH[1]}]="${BASH_REMATCH[6]}"
            MON_GEO[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]} ${BASH_REMATCH[5]}"
        fi
    done < <(xrandr --listmonitors 2>/dev/null | tail -n +2)
fi
[ ${#MON_GEO[@]} -eq 0 ] && {
    MON_NAME=("M0")
    MON_GEO=("0 0 0 0")
}

mon_of() { # cx cy -> idx
    local cx=$1 cy=$2 i w h x y
    for i in "${!MON_GEO[@]}"; do
        read -r w h x y <<<"${MON_GEO[$i]}"
        if [ "$w" -eq 0 ] && [ "$h" -eq 0 ]; then
            echo 0
            return
        fi
        if [ "$cx" -ge "$x" ] && [ "$cx" -lt $((x + w)) ] &&
            [ "$cy" -ge "$y" ] && [ "$cy" -lt $((y + h)) ]; then
            echo "$i"
            return
        fi
    done
    echo 0
}

# DRM 长名 → 短名：DisplayPort-0→DP-0，HDMI-A-0→HDMI-0，DVI-D-0→DVI-0；
# 其余（eDP、DP-1、HDMI-1…）保持原样。
short_name() {
    local s=$1
    s=${s/#DisplayPort-/DP-}
    if [[ "$s" =~ ^HDMI-[A-Za-z]-.+ ]]; then s="HDMI-${s#HDMI-?-}"; fi
    if [[ "$s" =~ ^DVI-[DI]-.+ ]]; then s="DVI-${s#DVI-?-}"; fi
    echo "$s"
}

# 当前 monitor ≈ 指针所在 monitor（dwm selmon 跟随焦点/指针）；
# 取不到指针位置时为 -1，此时无 `*` 标注（避免误报）。
CURMON=-1
if mloc=$(xdotool getmouselocation --shell 2>/dev/null); then
    mx=$(echo "$mloc" | sed -n 's/^X=//p')
    my=$(echo "$mloc" | sed -n 's/^Y=//p')
    if [[ "$mx" =~ ^-?[0-9]+$ && "$my" =~ ^-?[0-9]+$ ]]; then
        CURMON=$(mon_of "$mx" "$my")
    fi
fi

# 短名表（映射冲突时相关 monitor 回退全名，避免重名混淆）
MON_SHORT=()
for i in "${!MON_NAME[@]}"; do MON_SHORT[$i]=$(short_name "${MON_NAME[$i]}"); done
for i in "${!MON_SHORT[@]}"; do
    for j in "${!MON_SHORT[@]}"; do
        if [ "$i" -ne "$j" ] && [ "${MON_SHORT[$i]}" = "${MON_SHORT[$j]}" ]; then
            MON_SHORT[$i]="${MON_NAME[$i]}"
            break
        fi
    done
done

monlabel() { # $1 = mon idx 或 "?" -> "*name" / " name" / " ?"（前导标记位占齐）
    if [ "$1" = "?" ]; then
        echo " ?"
    elif [ "$CURMON" -ne -1 ] && [ "$1" -eq "$CURMON" ]; then
        echo "*${MON_SHORT[$1]:-M$1}"
    else
        echo " ${MON_SHORT[$1]:-M$1}"
    fi
}

# --- client list (already tag-grouped, bar-ordered by dwm) ---
IDS=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-fA-F]\+' | tr '\n' ' ')
[ -z "${IDS// /}" ] && exit 0

# rows: desk \t mon \t class \t title \t winid（列宽同步计算，输出时不再扫描）
ROWS=$(mktemp)
trap 'rm -f "$ROWS"' EXIT
TAGW=0
MONW=0
CLASSW=0

for id in $IDS; do # intentional word-splitting：IDS 为 xprop 解析出的空格分隔 id 表
    # 一次 xprop 取全字段（此前每窗 4 次）
    props=$(xprop -id "$id" _NET_WM_DESKTOP _NET_WM_NAME WM_CLASS WM_STATE 2>/dev/null) || continue
    desk=$(printf '%s\n' "$props" | sed -n 's/^_NET_WM_DESKTOP(CARDINAL) = \([0-9][0-9]*\)$/\1/p')
    case "${desk:-}" in '' | *[!0-9]*) continue ;; esac
    [ "$desk" = "4294967295" ] && desk=0 # sticky -> 第一组（与 dwm 一致）
    [ "$desk" -ge "$NTAGS" ] && desk=0
    title=$(printf '%s\n' "$props" | sed -n 's/^_NET_WM_NAME([^)]*) = "\(.*\)"$/\1/p')
    [ -z "$title" ] && title=$(xprop -id "$id" WM_NAME 2>/dev/null | sed -n 's/.* = "\(.*\)"$/\1/p')
    [ -z "$title" ] && title="(untitled)"
    title=$(printf '%s' "$title" | sed -e 's/\\\\/\\/g' -e 's/\\"/"/g') # xprop 转义还原
    class=$(printf '%s\n' "$props" | sed -n 's/^WM_CLASS(STRING) = ".*", "\(.*\)"$/\1/p')
    [ -z "$class" ] && class="?"
    hidden=""
    printf '%s\n' "$props" | grep -q '^WM_STATE.*Iconic' && hidden=" (hidden)"
    mon="?"
    if geo=$(xdotool getwindowgeometry --shell "$id" 2>/dev/null); then
        read -r gx gy gw gh <<<"$(printf '%s\n' "$geo" | awk -F= '{v[$1]=$2} END{print v["X"]+0, v["Y"]+0, v["WIDTH"]+0, v["HEIGHT"]+0}')"
        mon=$(mon_of $((gx + gw / 2)) $((gy + gh / 2)))
    fi
    t="${TAG_LABELS[$desk]}"
    m=$(monlabel "$mon")
    [ ${#t} -gt $TAGW ] && TAGW=${#t}
    [ ${#m} -gt $MONW ] && MONW=${#m}
    [ ${#class} -gt $CLASSW ] && CLASSW=${#class}
    printf '%d\t%s\t%s\t%s%s\t%s\n' "$desk" "$mon" "$class" "$title" "$hidden" "$id" >>"$ROWS"
done
[ -s "$ROWS" ] || exit 0

# 输出：按主 tag 稳定排序（输入已是 bar 顺序，stable sort 保持组内顺序）
MENU=$(mktemp)
MAP=$(mktemp)
trap 'rm -f "$ROWS" "$MENU" "$MAP"' EXIT
sort -s -n -k1,1 "$ROWS" | while IFS=$'\t' read -r desk mon class tit win; do
    printf -v tag "%-${TAGW}s" "${TAG_LABELS[$desk]}"
    printf -v mon "%-${MONW}s" "$(monlabel "$mon")"
    printf -v cls "%-${CLASSW}s" "$class"
    # 行图标：class 小写查 icon theme（如 kitty→kitty；找不到则该行无图标，不报错）
    # NUL 字节 bash 变量装不下：行尾先写 \x01 占位，喂 rofi 前统一 tr 成 NUL
    printf '%s\t%s\t%s\t%s'$'\001icon\x1f%s\x1f''\n' "$tag" "$mon" "$cls" "$tit" "${class,,}" >>"$MENU"
    printf '%s\n' "$win" >>"$MAP"
done

MENU_NUL=$(mktemp)
trap 'rm -f "$ROWS" "$MENU" "$MAP" "$MENU_NUL"' EXIT
tr '\001' '\000' <"$MENU" >"$MENU_NUL"

SEL=$(
    rofi -dmenu -i -p windows -format i -no-custom -show-icons \
        -theme "${theme}" \
        -theme-str '* {font: "JetBrains Mono Nerd Font 10";}' \
        <"$MENU_NUL" 2>/dev/null
) || exit 0
case "$SEL" in '' | *[!0-9]*) exit 0 ;; esac
WIN=$(sed -n "$((SEL + 1))p" "$MAP")
[ -z "$WIN" ] && exit 0
xdotool windowactivate "$WIN" 2>/dev/null
