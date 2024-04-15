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
	# st &
	alacritty -o 'font.size=10' &
	;;
esac
