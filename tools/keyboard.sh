#!/bin/bash

source "$(dirname "$0")/../utils/notify.sh"

[ -z "$(command -v setxkbmap)" ] && system-notify critical "Tool Not Found" "setxkbmap not be found, please install xorg-setxkbmap" && exit
[ -z "$(command -v xset)" ] && system-notify critical "Tool Not Found" "xset not be found, please install xorg-xset" && exit

read DELAY RATE <<<"$(xset q | awk -F'[: ]+' '/auto repeat delay/ {print $5, $8}')"

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
    *)
        echo "subcommand:"
        echo "    delay"
        echo "    rate"
        echo "    layout"
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
