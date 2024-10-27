#!/bin/bash

# Termina Manager
# launch command in file config.h varialbe termcmd

Type=$1

# new different termina by $Type
case "$Type" in
float)
	st -i -g 130x40 -f "CaskaydiaCove Nerd Font:style=Regular:size=10" &
	;;
*)
	WINIT_X11_SCALE_FACTOR=1 alacritty -o 'font.size=17' &
	;;
esac
