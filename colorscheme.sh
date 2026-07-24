#!/bin/bash

WORK_DIR=$(dirname "$0")
COLORSCHEME_CONF="$HOME/.config/dwm/colorscheme.json"

source "$(dirname "$0")/utils/notify.sh"

# ---------- helpers ----------

get_theme_config() {
	local mode="$1" key="$2"
	jq -r ".[\"$mode\"][\"$key\"] // empty" "$COLORSCHEME_CONF"
}

_ensure_config_line() {
	local file="$1" search="$2" replacement="$3"
	if grep -q "$search" "$file" 2>/dev/null; then
		sed -i "s|$search|$replacement|" "$file"
	else
		echo "$replacement" >>"$file"
	fi
}

# ---------- queries ----------

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


# ---------- setters ----------

set_dwm_theme() {
	local mode="$1"
	[ -z "$mode" ] && return

	local file="$HOME/.Xresources"
	local key="dwm.col_theme"
	_ensure_config_line "$file" "^$key:.*" "$key: $mode"
}

set_rofi_theme() {
	local mode="$1"
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
	local mode="$1"
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

	_ensure_config_line "$file" "^Theme=.*" "Theme=$theme"

	fcitx5 -r &
	local new_pid
	for i in {1..10}; do
		sleep 0.1
		new_pid=$(pgrep -n fcitx5 2>/dev/null) && break
	done
	if [ -n "$new_pid" ]; then
		mkdir -p "/tmp/dwm-status" &&
			echo "$new_pid" >"/tmp/dwm-status/autostart-launch-fcitx5.pid"
	fi
}

set_kitty_theme() {
	local mode="$1"
	[ -z "$(command -v kitten)" ] && return
	[ -z "$mode" ] && return

	local theme
	theme=$(get_theme_config "$mode" "kitty") || return
	[ -z "$theme" ] && return

	kitten themes "$theme"
}

set_qt_theme() {
	local mode="$1"
	[ -z "$mode" ] && return
	[ -z "$(command -v kvantummanager)" ] && return

	if [ "$QT_QPA_PLATFORMTHEME" != "qt6ct" ]; then
		system-notify normal "Environment Variable Not Set" "please set QT_QPA_PLATFORMTHEME=qt6ct"
		return
	fi

	local kvantum_theme icon_theme
	kvantum_theme=$(get_theme_config "$mode" "qt") || return
	icon_theme=$(get_theme_config "$mode" "icon") || true

	local cfg_file="$HOME/.config/qt6ct/qt6ct.conf"
	mkdir -p "$(dirname "$cfg_file")"

	if [ -f "$cfg_file" ]; then
		if grep -q '^\[Appearance\]' "$cfg_file"; then
			if grep -q '^style=' "$cfg_file"; then
				sed -i 's|^style=.*|style=kvantum|' "$cfg_file"
			else
				sed -i '/^\[Appearance\]/a style=kvantum' "$cfg_file"
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
			echo "style=kvantum" >>"$cfg_file"
			[ -n "$icon_theme" ] && echo "icon_theme=$icon_theme" >>"$cfg_file"
		fi
	else
		{
			echo "[Appearance]"
			echo "style=kvantum"
			[ -n "$icon_theme" ] && echo "icon_theme=$icon_theme"
		} >"$cfg_file"
	fi

	kvantummanager --set "$kvantum_theme"
}

set_dunst_theme() {
	local mode="$1"
	[ -z "$mode" ] && return

	local cfg="$HOME/.config/dunst/dunstrc"

	read bg fg < <(get_bg_fg_colors)
	[ -z "$bg" ] && return

	if grep -q 'background' "$cfg"; then
		sed -i "s/^\([[:space:]]*\)background[[:space:]]*=.*/\1background = \"$bg\"/" "$cfg"
	else
		echo "background = \"$bg\"" >>"$cfg"
	fi

	if grep -q 'foreground' "$cfg"; then
		sed -i "s/^\([[:space:]]*\)foreground[[:space:]]*=.*/\1foreground = \"$fg\"/" "$cfg"
	else
		echo "foreground = \"$fg\"" >>"$cfg"
	fi

	if grep -q 'frame_color' "$cfg"; then
		sed -i "s/^\([[:space:]]*\)frame_color[[:space:]]*=.*/\1frame_color = \"$fg\"/" "$cfg"
	else
		echo "frame_color = \"$fg\"" >>"$cfg"
	fi

	dunstctl reload 2>/dev/null || killall -SIGUSR1 dunst
}

set_gtk_theme() {
	local mode="$1"
	[ -z "$mode" ] && return

	local theme icon_theme
	theme=$(get_theme_config "$mode" "gtk") || return
	icon_theme=$(get_theme_config "$mode" "icon") || return
	[ -z "$theme" ] && return

	local gtk2_cfg="$HOME/.gtkrc-2.0"
	local gtk3_cfg="$HOME/.config/gtk-3.0/settings.ini"
	local gtk4_cfg="$HOME/.config/gtk-4.0/settings.ini"

	if [ -f "$gtk2_cfg" ]; then
		_ensure_config_line "$gtk2_cfg" '^gtk-theme-name=.*' 'gtk-theme-name="'"$theme"'"'
		_ensure_config_line "$gtk2_cfg" '^gtk-icon-theme-name=.*' 'gtk-icon-theme-name="'"$icon_theme"'"'
	else
		echo 'gtk-theme-name="'"$theme"'"' >"$gtk2_cfg"
		echo 'gtk-icon-theme-name="'"$icon_theme"'"' >>"$gtk2_cfg"
	fi

	for conf in "$gtk3_cfg" "$gtk4_cfg"; do
		if [ -f "$conf" ] && grep -q '^\[Settings\]' "$conf" 2>/dev/null; then
			_ensure_config_line "$conf" '^gtk-theme-name=.*' "gtk-theme-name=$theme"
			_ensure_config_line "$conf" '^gtk-icon-theme-name=.*' "gtk-icon-theme-name=$icon_theme"
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
check)
	pkgs=(
		"tela-icon-theme-git"
		"orchis-theme"
		"fcitx5-themes-candlelight"
		"kvantum"
		"kvantum-qt5"
		"kvantum-theme-orchis-git"
	)
	missing=()
	for pkg in "${pkgs[@]}"; do
		if ! pacman -Qi "$pkg" &>/dev/null; then
			missing+=("$pkg")
		fi
	done
	if [ ${#missing[@]} -gt 0 ]; then
		system-notify normal "Installing Themes" "Installing: ${missing[*]}"
		paru -S --noconfirm --needed "${missing[@]}"
	else
		system-notify normal "Themes Check" "All theme packages are already installed"
	fi
	;;
before)
	cur=$(get_current_theme)
	[ -z "$cur" ] && exit

	case "$cur" in
		dark) mode="light" ;;
		light) mode="dark" ;;
		*) exit ;;
	esac

	set_dwm_theme "$mode"
	set_rofi_theme "$mode"
	set_kitty_theme "$mode" &
	set_qt_theme "$mode"
	set_gtk_theme "$mode"
	set_fcitx5_theme "$mode"

	[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

	set_dunst_theme "$mode"
	;;
after)
	/bin/bash $WORK_DIR/dwm-status.sh reboot-refresh
	;;
esac
