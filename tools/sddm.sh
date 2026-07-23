#!/usr/bin/env bash

# [ "$(id -u)" -ne 0 ] && echo "user root be required!" && exit 1

SDDM_CFG=/etc/sddm.conf
CURRENT_THEME=$(awk -F= '
    /^\[Theme\]/ {theme=1; next}
    /^\[/ {theme=0}
    theme && $1=="Current" {
        gsub(/^[ \t]+|[ \t]+$/, "", $2)
        print $2
        exit
    }
' $SDDM_CFG)

BASE="/usr/share/sddm/themes"
DIR="$BASE/${CURRENT_THEME}"
CFG_PATH="$(dirname $(cat "$DIR/metadata.desktop" | grep '^ConfigFile=' | cut -d '=' -f 2))"

cur_theme() {
	echo "$CURRENT_THEME ($(cur_cfg))"
}

set_theme() {
	local theme=$1
	sed -i "s|Current=.*|Current=$theme|" "$SDDM_CFG"
}

list_theme() {
	for d in $BASE/*; do
		echo -e "$1$(basename $d)"
	done
}

set_cfg() {
	local config=$1
	sed -i "s|^ConfigFile=.*|ConfigFile=$CFG_PATH/$config.conf|" "$DIR/metadata.desktop"
}

cur_cfg() {
	echo "$(basename "$(cat "$DIR/metadata.desktop" | grep '^ConfigFile=' | cut -d '/' -f 2)" .conf)"
}

cur_cfg_path() {
	echo "$DIR/$CFG_PATH/$(cur_cfg).conf"
}

list_config() {
	for f in $DIR/$CFG_PATH/*.conf; do
		echo -e "$1$(basename "$f" .conf)"
	done
}

info() {
	echo "Current Theme: $(cur_theme)"
	echo "Current Theme Configs:"
	list_config "  "
	echo "Themes:"
	list_theme "  "
}

edit_config() {
	$EDITOR "$(cur_cfg_path)"
}

case "$1" in
"info")
	info
	;;
"cur_theme")
	cur_theme
	;;
"set_theme")
	shift
	set_theme "$@"
	;;
"list_theme")
	shift
	list_theme
	;;
"set_cfg")
	shift
	set_cfg "$@"
	;;
"cur_cfg_path")
	cur_cfg_path
	;;
"list_cfg")
	list_config
	;;
"edit_cfg")
	edit_config
	;;
"preview")
	sddm-greeter-qt6 --test-mode --theme $DIR
	;;
"install")
	# install theme sddm-astronaut-theme
	curl -fsSL https://raw.githubusercontent.com/keyitdev/sddm-astronaut-theme/master/setup.sh | bash
	rm -rf ./sddm-astronaut-theme
	# install theme silent
	git clone -b main --depth=1 https://github.com/uiriansan/SilentSDDM && cd SilentSDDM && ./install.sh
	cd ..
	rm -rf SilentSDDM
	;;
*)
	info
	;;
esac
