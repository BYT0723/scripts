#!/bin/bash

# Set Xorg
if [ ! -z "$(pgrep Xorg)" ]; then
	# Set Xorg Keyboard Configuration
	if [ ! -z "$(command -v setxkbmap)" ]; then
		# For other keymaps, see: `/usr/share/X11/xkb/rules/base.lst`
		setxkbmap us -option "caps:swapescape,altwin:swap_lalt_lwin" # setxkbmap need `xorg-xkb-utils` package
	fi
	if [ ! -z "$(command -v xset)" ]; then
		xset r rate 250 35
	fi
fi
