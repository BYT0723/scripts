#!/bin/bash

WORK_DIR=$(dirname $0)

source "$(dirname $0)/utils/notify.sh"

get_current_theme() {
	xrdb -query | awk -F': *\t*' '$1=="dwm.col_theme" {print $2}'
}

get_bg_fg_colors() {
	xrdb -query | awk -F': *' '
    {
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      map[$1] = $2
    }
    END {
      if (map["dwm.col_theme"] == "dark") {
        print map["dwm.col_black"], map["dwm.col_white"]
      } else {
        print map["dwm.col_light_black"], map["dwm.col_light_white"]
      }
    }
  '
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

set_rofi_theme() {
	local mode=$1
	local theme

	[ -z "$mode" ] && return

	case "$mode" in
	dark) theme="onedark" ;;
	light) theme="paper" ;;
	*) return ;;
	esac

	find $WORK_DIR/rofi/launchers/*/shared/colors.rasi | while read -r path; do
		sed -E -i \
			's|/[^/"]+\.rasi|/'"$theme"'.rasi|g' \
			"$path"
	done
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

set_qt_theme() {
	local mode=$1

	[ -z "$mode" ] && return
	[ -z "$(command -v qt6ct)" ] && return

	if [ "$QT_QPA_PLATFORMTHEME" != "qt6ct" ]; then
		system-notify normal "Environment Variable Not Set" "please set QT_QPA_PLATFORMTHEME=qt6ct"
		return
	fi

	local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/qt6ct/qt6ct.conf"
	local color_scheme_path

	case "$mode" in
	dark) color_scheme_path="/usr/share/qt6ct/colors/darker.conf" ;;
	light) color_scheme_path="/usr/share/qt6ct/colors/simple.conf" ;;
	*) return ;;
	esac

	mkdir -p "$(dirname "$cfg")"

	if [ -f "$cfg" ]; then
		if grep -q '^\[Appearance\]' "$cfg"; then
			# If [Appearance] section exists, update or add color_scheme_path
			if grep -q '^color_scheme_path=' "$cfg"; then
				sed -i 's|^color_scheme_path=.*|color_scheme_path='"$color_scheme_path"'|' "$cfg"
			else
				sed -i '/^\[Appearance\]/a color_scheme_path='"$color_scheme_path" "$cfg"
			fi
		else
			# Add [Appearance] section if it doesn't exist
			echo "" >>"$cfg"
			echo "[Appearance]" >>"$cfg"
			echo "color_scheme_path=$color_scheme_path" >>"$cfg"
		fi
	else
		cat >"$cfg" <<EOF
[Appearance]
color_scheme_path=$color_scheme_path
EOF
	fi
}

set_dunst_theme() {
	local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/dunst/dunstrc"

	read bg fg < <(get_bg_fg_colors)

	grep -q 'background' "$cfg" &&
		sed -i "s/^\([[:space:]]*\)background[[:space:]]*=.*/\1background = \"$bg\"/" "$cfg" ||
		echo "background = \"$bg\"" >>"$cfg"

	grep -q 'foreground' "$cfg" &&
		sed -i "s/^\([[:space:]]*\)foreground[[:space:]]*=.*/\1foreground = \"$fg\"/" "$cfg" ||
		echo "foreground = \"$fg\"" >>"$cfg"

	grep -q 'frame_color' "$cfg" &&
		sed -i "s/^\([[:space:]]*\)frame_color[[:space:]]*=.*/\1frame_color = \"$fg\"/" "$cfg" ||
		echo "frame_color = \"$fg\"" >>"$cfg"

	dunstctl reload 2>/dev/null || killall -SIGUSR1 dunst
}

set_gtk_theme() {
	local mode=$1
	local theme icon_theme

	local gtk2_cfg="$HOME/.gtkrc-2.0"
	local gtk3_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
	local gtk4_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini"

	[ -z "$mode" ] && return

	case "$mode" in
	dark)
		theme="WhiteSur-Dark-solid"
		icon_theme="WhiteSur-dark"
		;;
	light)
		theme="WhiteSur-Light-solid"
		icon_theme="WhiteSur-light"
		;;
	*) return ;;
	esac

	# ---------- GTK2 ----------
	if [ -f "$gtk2_cfg" ]; then
		if grep -q '^gtk-theme-name=' "$gtk2_cfg"; then
			sed -i 's/^gtk-theme-name=.*/gtk-theme-name="'"$theme"'"/' "$gtk2_cfg"
		else
			echo 'gtk-theme-name="'"$theme"'"' >>"$gtk2_cfg"
		fi

		if grep -q '^gtk-icon-theme-name=' "$gtk2_cfg"; then
			sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name="'"$icon_theme"'"/' "$gtk2_cfg"
		else
			echo 'gtk-icon-theme-name="'"$icon_theme"'"' >>"$gtk2_cfg"
		fi
	else
		echo 'gtk-theme-name="'"$theme"'"' >"$gtk2_cfg"
		echo 'gtk-icon-theme-name="'"$icon_theme"'"' >>"$gtk2_cfg"
	fi

	# ---------- GTK3 / GTK4 ----------
	for cfg in "$gtk3_cfg" "$gtk4_cfg"; do
		mkdir -p "$(dirname "$cfg")"

		if [ -f "$cfg" ] && grep -q '^\[Settings\]' "$cfg" 2>/dev/null; then
			# 已有 [Settings]，在段内更新或插入
			if grep -q '^gtk-theme-name=' "$cfg"; then
				sed -i 's/^gtk-theme-name=.*/gtk-theme-name='"$theme"'/' "$cfg"
			else
				sed -i '/^\[Settings\]/a gtk-theme-name='"$theme" "$cfg"
			fi

			if grep -q '^gtk-icon-theme-name=' "$cfg"; then
				sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name='"$icon_theme"'/' "$cfg"
			else
				sed -i '/^\[Settings\]/a gtk-icon-theme-name='"$icon_theme" "$cfg"
			fi
		else
			# 无文件或无 [Settings]，整段写入
			mkdir -p "$(dirname "$cfg")"
			{
				echo "[Settings]"
				echo "gtk-theme-name=$theme"
				echo "gtk-icon-theme-name=$icon_theme"
			} >>"$cfg"
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
	set_rofi_theme "$mode"
	set_kitty_theme "$mode" &
	set_qt_theme "$mode"
	set_gtk_theme "$mode"

	# reload xrdb
	[ -f $HOME/.Xresources ] && xrdb -merge $HOME/.Xresources

	# after reload (xrdb has been updated)
	set_dunst_theme
	;;
after)
	/bin/bash $WORK_DIR/dwm-status.sh reboot-refresh
	;;
esac
