#/use/bin/env /bin/bash

source "$(dirname "$0")/utils/notify.sh"

cal() {
	[ -z "$(command -v cal)" ] && system-notify normal "Tool Not Found" "please install cal" && return
	st \
		-t calendar \
		-c float-term \
		-g 67x36-0+0 \
		-f "CaskaydiaCove Nerd Font:style=Regular:pixelsize=20:antialias=true:autohint=true" \
		-e sh -c 'LC_ALL=en_US.UTF-8 cal --color=always -sy | less -R'
}

ccal() {
	[ -z "$(command -v ccal)" ] && system-notify normal "Tool Not Found" "please install ccal" && return
	st \
		-t calendar-lunar \
		-c float-term \
		-g 70x36-0+0 \
		-e sh -c "ccal -u $(date +%Y) | less -R"
}

case "$1" in
lunar) ccal ;;
*) cal ;;
esac
