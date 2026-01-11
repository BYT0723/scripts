#!/usr/bin/env bash

# [ "$(id -u)" -ne 0 ] && echo "user root be required!" && exit 1

DIR=/usr/share/sddm/themes/sddm-astronaut-theme

set() {
	local theme=$1
	sed -i "s|ConfigFile=.*|ConfigFile=Themes/$theme.conf|" "$DIR/metadata.desktop"
}

edit() {
	local theme=$1
	eval "/usr/bin/env $EDITOR "
}

current() {
	echo "$(basename "$(cat "$DIR/metadata.desktop" | grep ConfigFile | cut -d '/' -f 2)" .conf)"
}

list() {
	for f in "$DIR/Themes"/*.conf; do
		echo -e "$1$(basename "$f" .conf)"
	done
}

info() {
	echo "Current Theme: $(current)"
	echo "Theme List:"
	list "  "
}

edit() {
	$EDITOR "$DIR/Themes/$(current).conf"
}

case "$1" in
"info")
	info
	;;
"set")
	shift
	set $@
	;;
"cur")
	current
	;;
"curp")
	echo "$DIR/Themes/$(current).conf"
	;;
"list")
	list
	;;
"edit")
	edit
	;;
*)
	info
	;;
esac
