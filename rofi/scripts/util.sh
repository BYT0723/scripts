#!/bin/bash

icon() {
	local icons
	if [[ "$1" == "toggle" ]]; then
		icons=(" " " ")
	else
		icons=(" " " ")
	fi

	local idx=0
	case "$2" in
	app) [[ -n $(pgrep $3) ]] && idx=1 ;;
	service) [[ "inactive" != $(systemctl status $3 | grep Active | awk '{print $2}') ]] && idx=1 ;;
	conf)
		if [ "$3" = "wallpaper" ]; then
			local w_conf="$HOME/.config/dwm/wallpaper.json"
			local val=""
			[ "$6" != "ALL" ] && [ -n "$6" ] && val=$(jq -r ".monitors[\"$6\"].\"$4\" // empty" "$w_conf" 2>/dev/null)
			[ -z "$val" ] && val=$(jq -r ".defaults.\"$4\" // empty" "$w_conf" 2>/dev/null)
			[ "$val" != "$(typeToValue $5)" ] && [ -n "$val" ] && idx=1
		else
			[[ -n $(grep -E "^$4\s*=\s*$(typeToValue $5)" ${confPath[$3]}) ]] || idx=1
		fi
		;;
	cmd)
		[[ -n $(ps ax | grep "$3" | grep -v grep) ]] && idx=1
		;;
	esac
	echo ${icons[$idx]}
}

typeToValue() {
	case "$1" in
	bool) echo false ;;
	number) echo 0 ;;
	wallpaper_type) echo "image" ;;
	esac
}

toggleConf() {
	if [ "$1" = "wallpaper" ]; then
		local key="$2" type="$3" monitor="${4:-}"
		local conf="$HOME/.config/dwm/wallpaper.json"
		local path=".defaults"
		[ "$monitor" != "ALL" ] && [ -n "$monitor" ] && path=".monitors[\"$monitor\"]"

		local def=$(typeToValue "$type")
		local cur=$(jq -r "${path}.${key} // empty" "$conf" 2>/dev/null)
		if [ "$cur" = "$def" ] || [ -z "$cur" ]; then
			[ "$type" = "wallpaper_type" ] && jq "${path}.${key} = \"video\"" "$conf" >"$conf.tmp" ||
				jq "${path}.${key} = 1" "$conf" >"$conf.tmp"
		else
			[ "$type" = "wallpaper_type" ] && jq "${path}.${key} = \"image\"" "$conf" >"$conf.tmp" ||
				jq "${path}.${key} = 0" "$conf" >"$conf.tmp"
		fi
		mv "$conf.tmp" "$conf"
		return
	fi

	local def=$(typeToValue "$3") val
	if grep -qE "^$2\s*=\s*$def" "${confPath[$1]}"; then
		case "$3" in bool) val=true ;; number) val=1 ;; wallpaper_type) val=video ;; esac
	else
		case "$3" in bool) val=false ;; number) val=0 ;; wallpaper_type) val=image ;; esac
	fi
	sed -i "s|^$2\s*=\s*[^ ]*|$2\ =\ $val|g" "${confPath[$1]}"
}

getConfig() {
	if [ "$1" = "wallpaper" ]; then
		local key="$2" monitor="$3" conf="$HOME/.config/dwm/wallpaper.json"
		local val=""
		[ "$monitor" != "ALL" ] && [ -n "$monitor" ] && val=$(jq -r ".monitors[\"$monitor\"].\"$key\" // empty" "$conf" 2>/dev/null)
		[ -n "$val" ] && echo "$val" && return
		jq -r ".defaults.\"$key\" // empty" "$conf" 2>/dev/null
		return
	fi
	grep -E "^$2\s*=" "${confPath[$1]}" | tail -1 | awk -F '=' '{print $2}' | grep -o "[^ ]\+\( \+[^ ]\+\)*"
}
