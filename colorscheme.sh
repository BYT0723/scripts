#!/bin/bash

WORK_DIR=$(dirname $0)

COLORSCHEME_CONF="$HOME/.config/dwm/colorscheme.json"

get_theme_config() {
	local mode="$1" key="$2"
	jq -r ".[\"$mode\"][\"$key\"] // empty" "$COLORSCHEME_CONF"
}

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
	[ -z "$mode" ] && return

	if grep -q "^$key:" "$file"; then
		# 替换已有
		sed -i "s/^$key:.*/$key: $mode/" "$file"
	else
		# 不存在就追加
		echo "$key: $mode" >>"$file"
	fi
}

set_rofi_theme() {
	[ -z "$mode" ] && return
	local theme
	theme=$(get_theme_config "$mode" "rofi") || return
	[ -z "$theme" ] && return

	files=(
		"$WORK_DIR"/rofi/launchers/*/shared/colors.rasi
		"$WORK_DIR"/rofi/powermenu/*/shared/colors.rasi
		"$WORK_DIR"/rofi/applets/shared/colors.rasi
	)

	sed -E -i \
		"s|/[^/\"]+\.rasi|/$theme.rasi|g" \
		"${files[@]}"
}

set_fcitx5_theme() {
	[ -z "$mode" ] && return
	local theme
	theme=$(get_theme_config "$mode" "fcitx5") || return
	[ -z "$theme" ] && return

	if [ ! -d "/usr/share/fcitx5/themes/$theme" ]; then
		system-notify normal "Fcitx5 Theme Not Found" "fcitx5 theme \"$theme\" is not found, please make sure the theme exists"
		return
	fi

	local file="$HOME/.config/fcitx5/conf/classicui.conf"

	[ -f "$file" ] || return

	if grep -q '^Theme=' "$file"; then
		sed -i "s/^Theme=.*/Theme=$theme/" "$file"
	else
		echo "Theme=$theme" >>"$file"
	fi

	fcitx5 -r &
	# refresh pid file for autostart.sh launch check
	sleep 0.3
	local new_pid
	new_pid=$(pgrep -n fcitx5 2>/dev/null)
	[ -n "$new_pid" ] && echo "$new_pid" >"/tmp/dwm-status/autostart-launch-fcitx5.pid"
}

set_kitty_theme() {
	[ -z "$(command -v kitten)" ] && return
	[ -z "$mode" ] && return
	local theme
	theme=$(get_theme_config "$mode" "kitty") || return
	[ -z "$theme" ] && return

	kitten themes "$theme"
}

set_qt_theme() {
	[ -z "$mode" ] && return
	[ -z "$(command -v qt6ct)" ] && return

	if [ "$QT_QPA_PLATFORMTHEME" != "qt6ct" ]; then
		system-notify normal "Environment Variable Not Set" "please set QT_QPA_PLATFORMTHEME=qt6ct"
		return
	fi

	local color_scheme_path icon_theme
	color_scheme_path=$(get_theme_config "$mode" "qt") || return
	icon_theme=$(get_theme_config "$mode" "icon") || true

	local cfg_file="$HOME/.config/qt6ct/qt6ct.conf"

	mkdir -p "$(dirname "$cfg_file")"

	if [ -f "$cfg_file" ]; then
		if grep -q '^\[Appearance\]' "$cfg_file"; then
			if [ -n "$color_scheme_path" ]; then
				if grep -q '^color_scheme_path=' "$cfg_file"; then
					sed -i 's|^color_scheme_path=.*|color_scheme_path='"$color_scheme_path"'|' "$cfg_file"
				else
					sed -i '/^\[Appearance\]/a color_scheme_path='"$color_scheme_path" "$cfg_file"
				fi
			fi
			if [ -n "$icon_theme" ]; then
				if grep -q '^icon_theme=' "$cfg_file"; then
					sed -i 's|^icon_theme=.*|icon_theme='"$icon_theme"'|' "$cfg_file"
				else
					sed -i '/^\[Appearance\]/a icon_theme='"$icon_theme" "$cfg_file"
				fi
			fi
		else
			echo "" >>"$cfg_file"
			echo "[Appearance]" >>"$cfg_file"
			[ -n "$color_scheme_path" ] && echo "color_scheme_path=$color_scheme_path" >>"$cfg_file"
			[ -n "$icon_theme" ] && echo "icon_theme=$icon_theme" >>"$cfg_file"
		fi
	else
		{
			echo "[Appearance]"
			[ -n "$color_scheme_path" ] && echo "color_scheme_path=$color_scheme_path"
			[ -n "$icon_theme" ] && echo "icon_theme=$icon_theme"
		} >"$cfg_file"
	fi
}

set_dunst_theme() {
	local cfg="$HOME/.config/dunst/dunstrc"

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
	[ -z "$mode" ] && return
	local theme icon_theme
	theme=$(get_theme_config "$mode" "gtk") || return
	icon_theme=$(get_theme_config "$mode" "icon") || return
	[ -z "$theme" ] && return

	local gtk2_cfg="$HOME/.gtkrc-2.0"
	local gtk3_cfg="$HOME/.config/gtk-3.0/settings.ini"
	local gtk4_cfg="$HOME/.config/gtk-4.0/settings.ini"

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
	for conf in "$gtk3_cfg" "$gtk4_cfg"; do
		mkdir -p "$(dirname "$conf")"

		if [ -f "$conf" ] && grep -q '^\[Settings\]' "$conf" 2>/dev/null; then
			if grep -q '^gtk-theme-name=' "$conf"; then
				sed -i 's/^gtk-theme-name=.*/gtk-theme-name='"$theme"'/' "$conf"
			else
				sed -i '/^\[Settings\]/a gtk-theme-name='"$theme" "$conf"
			fi

			if grep -q '^gtk-icon-theme-name=' "$conf"; then
				sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name='"$icon_theme"'/' "$conf"
			else
				sed -i '/^\[Settings\]/a gtk-icon-theme-name='"$icon_theme" "$conf"
			fi
		else
			mkdir -p "$(dirname "$conf")"
			{
				echo "[Settings]"
				echo "gtk-theme-name=$theme"
				echo "gtk-icon-theme-name=$icon_theme"
			} >>"$conf"
		fi
	done
}

case "$1" in
before)
	mode=$(select_theme)
	cur=$(get_current_theme)

	[ -z "$cur" ] && exit
	[[ "$mode" == "$cur" ]] && exit

	set_dwm_theme
	set_rofi_theme
	set_kitty_theme &
	set_qt_theme
	set_gtk_theme
	set_fcitx5_theme

	# reload xrdb
	[ -f $HOME/.Xresources ] && xrdb -merge $HOME/.Xresources

	# after reload (xrdb has been updated)
	set_dunst_theme
	;;
after)
	/bin/bash $WORK_DIR/dwm-status.sh reboot-refresh
	;;
esac
