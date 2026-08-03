#!/usr/bin/env bash

WORK_DIR=$(dirname "$(dirname "${BASH_SOURCE[0]}")")
THEME_CONF="$HOME/.config/dwm/theme.json"

source "$WORK_DIR/utils/notify.sh"

# ---------- helpers ----------

get_theme_config() {
	local mode="$1" key="$2"
	jq -r ".[\"$mode\"][\"$key\"] // empty" "$THEME_CONF"
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

get_current_theme() { cat "$HOME/.local/state/dwm/current-theme" 2>/dev/null; }

get_bg_fg_colors() {
	xrdb -query | awk -F': *' '
    {
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      map[$1] = $2
    }
    END {
      print map["dwm.col_black"], map["dwm.col_white"]
    }
  '
}

# ---------- setters ----------

set_dwm_theme() {
	local mode="$1"
	[ -z "$mode" ] && return

	local file="$HOME/.Xresources"
	local cs_dir="$HOME/.config/dwm/colorschemes"
	local scheme

	scheme=$(jq -r ".[\"$mode\"].colorscheme // empty" "$THEME_CONF")

	sed -i '/^dwm\.col_/d' "$file"
	[ -n "$scheme" ] && [ -f "$cs_dir/$scheme.json" ] &&
		jq -r 'to_entries[] | "dwm.col_\(.key): \(.value)"' "$cs_dir/$scheme.json" >>"$file"

	mkdir -p "$HOME/.local/state/dwm"
	echo "$mode" >"$HOME/.local/state/dwm/current-theme"

	local cursor_theme cursor_size dpi
	cursor_theme=$(jq -r '.cursor.theme // empty' "$THEME_CONF")
	cursor_size=$(jq -r '.cursor.size // empty' "$THEME_CONF")
	dpi=$(jq -r '.dpi // empty' "$THEME_CONF")
	[ -n "$cursor_theme" ] && _ensure_config_line "$file" "^Xcursor.theme:.*" "Xcursor.theme: $cursor_theme"
	[ -n "$cursor_size" ] && _ensure_config_line "$file" "^Xcursor.size:.*" "Xcursor.size: $cursor_size"
	[ -n "$dpi" ] && _ensure_config_line "$file" "^Xft.dpi:.*" "Xft.dpi: $dpi"
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

_get_darkreader_shortcut() {
	local settings_json="$1"
	[ -z "$settings_json" ] || [ ! -f "$settings_json" ] && echo "Alt+Shift+D" && return
	jq -r '[.commands | to_entries[] | .value.precedenceList[]?
		| select(.id == "addon@darkreader.org")] | .[0].value.shortcut // "Alt+Shift+D"' \
		"$settings_json" 2>/dev/null
}

set_firefox_theme() {
	local mode="$1"
	[ -z "$mode" ] && return
	command -v xdotool >/dev/null || return
	command -v jq >/dev/null || return

	local profile_dir
	profile_dir=$(ls -d "$HOME/.mozilla/firefox/"*.default-release 2>/dev/null | head -1)
	[ -z "$profile_dir" ] && return

	local ext_json="$profile_dir/extensions.json"
	[ -f "$ext_json" ] || return
	jq -e '.addons | any(.id == "addon@darkreader.org")' "$ext_json" >/dev/null 2>&1 || return

	local state_file="/tmp/dwm-darkreader-state"
	local cur_state
	read -r cur_state <"$state_file" 2>/dev/null || true

	[ "$cur_state" = "$mode" ] && return

	local win_id shortcut
	win_id=$(xdotool search --name "Mozilla Firefox" 2>/dev/null | head -1)
	[ -z "$win_id" ] && return
	shortcut=$(_get_darkreader_shortcut "$profile_dir/extension-settings.json")
	xdotool key --window "$win_id" --clearmodifiers "$shortcut"
	echo "$mode" >"$state_file"
}

# ---------- theme apply ----------

_do_theme_change() {
	local mode="$1"
	[ -z "$mode" ] && return

	set_dwm_theme "$mode"
	set_rofi_theme "$mode"
	set_kitty_theme "$mode" &
	set_qt_theme "$mode"
	set_gtk_theme "$mode"
	set_fcitx5_theme "$mode"
	set_firefox_theme "$mode"

	[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

	set_dunst_theme "$mode"

	# Wait for all theme changes to settle (especially fcitx5 restart,
	# xrdb merge, and GTK/Qt theme reload) before the SIGHUP that
	# follows. Otherwise dwm restart races with tray client re-init,
	# causing blank icons and frozen Electron/GTK clients (e.g. xunlei).
	sleep 0.3
}

# ---------- auto theme ----------

get_auto_config() {
	local key="$1"
	jq -r ".$key // empty" "$THEME_CONF" 2>/dev/null
}

get_sun_times() {
	local cache="$HOME/.local/state/dwm/cache/sun-times" today
	today=$(date +%F)
	local cdate sr_ep ss_ep sr2_ep
	if [ -f "$cache" ]; then
		IFS='|' read -r cdate sr_ep ss_ep sr2_ep <"$cache"
		if [ "$cdate" = "$today" ] && [ -n "$sr_ep" ] && [ -n "$ss_ep" ] && [ -n "$sr2_ep" ]; then
			echo "$sr_ep $ss_ep $sr2_ep"
			return 0
		fi
	fi

	local lock="$HOME/.local/state/dwm/cache/sun-times.fetching"
	if [ -f "$lock" ] && find "$lock" -mmin -1 2>/dev/null | grep -q .; then
		return 1
	fi
	rm -f "$lock"

	mkdir -p "$(dirname "$lock")"
	touch "$lock"
	(
		IFS=, read LAT LON < <(curl -m 2 -fsS https://ipinfo.io/loc) || exit
		local json tz sr1 ss1 sr2
		json=$(curl -m 5 -fsS "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&daily=sunrise,sunset&forecast_days=2&timezone=auto") || exit
		tz=$(echo "$json" | jq -r '.timezone // "UTC"')
		sr1=$(echo "$json" | jq -r '.daily.sunrise[0]')
		ss1=$(echo "$json" | jq -r '.daily.sunset[0]')
		sr2=$(echo "$json" | jq -r '.daily.sunrise[1]')
		sr_ep=$(TZ="$tz" date -d "$sr1" +%s)
		ss_ep=$(TZ="$tz" date -d "$ss1" +%s)
		sr2_ep=$(TZ="$tz" date -d "$sr2" +%s)
		mkdir -p "$(dirname "$cache")"
		printf '%s|%s|%s|%s\n' "$today" "$sr_ep" "$ss_ep" "$sr2_ep" >"${cache}.tmp" && mv "${cache}.tmp" "$cache"
		rm -f "$lock"
	) &
	disown
	return 1
}

auto_daemon() {
	local auto
	auto=$(get_auto_config "auto.enabled")
	[ "$auto" = "true" ] || exit 0

	while true; do
		auto=$(get_auto_config "auto.enabled")
		[ "$auto" = "true" ] || exit 0

		local times sunrise sunset next_sunrise
		if times=$(get_sun_times 2>/dev/null); then
			read sunrise sunset next_sunrise <<<"$times"
		fi
		[ -n "$sunrise" ] && [ -n "$sunset" ] && [ -n "$next_sunrise" ] || {
			sleep 1800
			continue
		}

		local rise_off set_off
		rise_off=$(get_auto_config "auto.sun_rise_offset")
		rise_off=$((${rise_off:-0} * 60))
		set_off=$(get_auto_config "auto.sun_set_offset")
		set_off=$((${set_off:-0} * 60))

		local now desired next_switch
		now=$(date +%s)

		if [ "$now" -lt "$((sunrise + rise_off))" ]; then
			desired="dark"
			next_switch="$((sunrise + rise_off))"
		elif [ "$now" -lt "$((sunset + set_off))" ]; then
			desired="light"
			next_switch="$((sunset + set_off))"
		else
			desired="dark"
			next_switch="$((next_sunrise + rise_off))"
		fi

		local cur
		cur=$(get_current_theme)
		if [ "$cur" != "$desired" ]; then
			while pgrep -x i3lock >/dev/null 2>&1; do
				sleep 5
			done
			_do_theme_change "$desired"
			tool-notify low "Auto Theme" "switched to $desired theme"
			pkill -SIGHUP dwm
			sleep 0.5
		fi

		if [ "$next_switch" -gt "$now" ]; then
			sleep $((next_switch - now))
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
apply)
	mode="$2"
	[ -z "$mode" ] && exit 1
	_do_theme_change "$mode"
	pkill -SIGHUP dwm
	[ "$(get_auto_config "auto.enabled")" = "true" ] && "$0" auto off
	;;
auto)
	pf="/tmp/dwm-status/autostart-launch-theme-auto.pid"
	case "$2" in
	on)
		jq '.auto.enabled = true' "$THEME_CONF" >"${THEME_CONF}.tmp" &&
			mv "${THEME_CONF}.tmp" "$THEME_CONF"
		local pid
		[ -f "$pf" ] && pid=$(cat "$pf")
		[ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && exit 0
		"$0" auto >/dev/null 2>&1 &
		mkdir -p "$(dirname "$pf")"
		echo $! >"$pf"
		tool-notify low "Auto Theme" "auto switch enabled"
		;;
	off)
		jq '.auto.enabled = false' "$THEME_CONF" >"${THEME_CONF}.tmp" &&
			mv "${THEME_CONF}.tmp" "$THEME_CONF"
		[ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null
		rm -f "$pf"
		tool-notify low "Auto Theme" "auto switch disabled"
		;;
	*) auto_daemon ;;
	esac
	;;
esac
