#!/bin/bash

WORK_DIR=$(dirname $0)

get_current_theme() {
	xrdb -query | awk -F': *\t*' '$1=="dwm.col_theme" {print $2}'
}

select_theme() {
	echo -e "dark\nlight" | bash $WORK_DIR/rofi/scripts/common_list.sh \
		-w 800 \
		-F "JetBrains Mono Nerd Font 16" \
		"Colorscheme" "Select a mode | Current: $(get_current_theme)"
}

set_dwm_theme() {
	local file="$HOME/.Xresources"
	local key="dwm.col_theme"
	local mode=$1
	[ -z "$mode" ] && return

	if grep -q "^$key:" "$file"; then
		# 替换已有
		sed -i "s/^$key:.*/$key: $1/" "$file"
	else
		# 不存在就追加
		echo "$key: $1" >>"$file"
	fi
}

set_kitty_theme() {
	[ -z $(command -v kitten) ] && return
	local mode=$1
	[ -z "$mode" ] && return

	case "$mode" in
	dark)
		kitten themes "Tokyo Night"
		;;
	light)
		kitten themes "Tokyo Night Day"
		;;
	esac
}

set_gtk_theme() {
	local mode=$1
	local theme

	local gtk2_cfg="$HOME/.gtkrc-2.0"
	local gtk3_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
	local gtk4_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini"

	[ -z "$mode" ] && return

	case "$mode" in
	dark) theme="WhiteSur-Dark-solid" ;;
	light) theme="WhiteSur-Light-solid" ;;
	*) return ;;
	esac

	# ---------- GTK2 ----------
	if [ -f "$gtk2_cfg" ]; then
		if grep -q '^gtk-theme-name=' "$gtk2_cfg"; then
			sed -i 's/^gtk-theme-name=.*/gtk-theme-name="'"$theme"'"/' "$gtk2_cfg"
		else
			echo 'gtk-theme-name="'"$theme"'"' >>"$gtk2_cfg"
		fi
	else
		echo 'gtk-theme-name="'"$theme"'"' >"$gtk2_cfg"
	fi

	# ---------- GTK3 / GTK4 ----------
	for cfg in "$gtk3_cfg" "$gtk4_cfg"; do
		mkdir -p "$(dirname "$cfg")"

		if [ -f "$cfg" ]; then
			if grep -q '^gtk-theme-name=' "$cfg"; then
				sed -i 's/^gtk-theme-name=.*/gtk-theme-name='"$theme"'/' "$cfg"
			else
				# 确保有 [Settings] 段
				grep -q '^\[Settings\]' "$cfg" || sed -i '1i [Settings]' "$cfg"
				echo "gtk-theme-name=$theme" >>"$cfg"
			fi
		else
			cat >"$cfg" <<EOF
[Settings]
gtk-theme-name=$theme
EOF
		fi
	done
}

case "$1" in
before)
	mode=$(select_theme)
	cur=$(get_current_theme)

	[ -z "$cur" ] && exit
	[[ "$mode" == "$cur" ]] && exit

	set_dwm_theme "$mode"
	set_kitty_theme "$mode"
	set_gtk_theme "$mode"

	# reload xrdb
	[ -f $HOME/.Xresources ] && xrdb -merge $HOME/.Xresources
	;;
after)
	/bin/bash $WORK_DIR/dwm-status.sh reboot
	;;
esac
