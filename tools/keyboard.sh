#!/bin/bash

# # Set Xorg
# if [ ! -z "$(pgrep Xorg)" ]; then
# 	# Set Xorg Keyboard Configuration
# 	if [ ! -z "$(command -v setxkbmap)" ]; then
# 		# For other keymaps, see: `/usr/share/X11/xkb/rules/base.lst`
# 		setxkbmap us -option "caps:swapescape,altwin:swap_lalt_lwin" # setxkbmap need `xorg-xkb-utils` package
# 	fi
# fi

source "$(dirname $0)/../utils/notify.sh"

[ -z "$(command -v setxkbmap)" ] && system-notify critical "Tool Not Found" "setxkbmap not be found, please install xorg-setxkbmap" && exit
[ -z "$(command -v xset)" ] && system-notify critical "Tool Not Found" "xset not be found, please install xorg-xset" && exit

read DELAY RATE <<<"$(xset q | awk -F'[: ]+' '/auto repeat delay/ {print $5, $8}')"

set_kb_option() {
	# setxkbmap need `xorg-xkb-utils` package
	[ -z "$(command -v setxkbmap)" ] && echo "setxkbmap not found" && exit 1
	setxkbmap us -option "caps:swapescape,altwin:swap_lalt_lwin"
}

list() {
	local module=$1
	case "$module" in
	"help" | "")
		echo "Support SubCommand:"
		awk '/^!/ {sub(/^![[:space:]]*/, ""); print "  " $0}' /usr/share/X11/xkb/rules/base.lst
		;;
	*)
		[ -z "$(grep "^! *" /usr/share/X11/xkb/rules/base.lst | grep $module)" ] && echo "Unsupport SubCommand." && exit 1
		awk "/^! $module/{f=1;next} f&&NF==0{f=0} f" /usr/share/X11/xkb/rules/base.lst
		;;
	esac
}

set() {
	local cur_layout=$(setxkbmap -query | grep layout | awk -F ' ' '{print $2}')

	local sub=$1

	case "$sub" in
	"delay")
		delay=${2:-$DELAY}
		xset r rate $delay $RATE
		;;
	"rate")
		[ -z "$(command -v xset)" ] && echo "xset not found" && exit 1
		rate=${2:-$RATE}
		xset r rate $DELAY $rate
		;;
	"layout")
		layout=${2:-$cur_layout}
		setxkbmap $layout
		;;
	"option-set")
		shift
		setxkbmap $cur_layout -option ""
		setxkbmap $cur_layout -option "$@"
		;;
	"option-add")
		shift
		setxkbmap $cur_layout -option "$@"
		;;
	*)
		echo "subcommand:"
		echo "    delay"
		echo "    rate"
		echo "    layout"
		echo "    option-add"
		echo "    option-set"
		;;
	esac
}

case "$1" in
"list")
	shift
	list $@
	;;
"set")
	shift
	set $@
	;;
*) ;;
esac
