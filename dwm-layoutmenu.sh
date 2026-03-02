#!/bin/sh

# dwm layout menu using rofi
# Display names only, output number for dwm

WORK_DIR=$(dirname "$0")

# 定义 layout 显示名字数组
layouts=(
	"[]= Tiled"
	"[F] Floating"
	"[M] Monocle"
	"[@] Spiral"
	"[\] Dwindle"
	"H[] Deck"
	"TTT BStack"
	"=== BStackHoriz"
	"HHH Grid"
	"### NRowGrid"
	"--- HorizGrid"
	"::: GapLessGrid"
	"|M| CenteredMaster"
	">M> CenteredFloatingMaster"
)

# 生成 rofi 列表（只显示名字）
choice=$(printf "%s\n" "${layouts[@]}" |
	bash "$WORK_DIR/rofi/scripts/common_list.sh" \
	-t 1-3 \
	-f "JetBrains Mono Nerd Font 18" \
	-F "JetBrains Mono Nerd Font 16" \
	-w 450 \
	"DWM Layout Setting" \
	"Select a layout")

# 用户取消
[ -z "$choice" ] && exit

# 查找选择在数组中的索引 → 输出给 dwm
for i in "${!layouts[@]}"; do
	if [ "${layouts[$i]}" = "$choice" ]; then
		echo "$i"
		exit
	fi
done
