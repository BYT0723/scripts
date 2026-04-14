#!/bin/sh

WORK_DIR=$(dirname $0)

case "$1" in
before)
	[ -f $HOME/.Xresources ] && xrdb -merge $HOME/.Xresources
	;;
after)
	/bin/bash $WORK_DIR/dwm-status.sh reboot
	;;
esac
