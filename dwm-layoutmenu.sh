#!/bin/sh

# Dwm layout menu file
# Don't edit if you don't know what are you doing

cat <<EOF | xmenu
[]=  Tiled	0
><>  Floating	1
[M]  Monocle	2
[@]  Spiral	3
[\\] Dwindle	4
H[]  Deck	5
TTT  BStack	6
===  BStackHoriz	7
HHH  Grid	8
###  NRowGrid	9
---  HorizGrid	10
:::  GapLessGrid	11
|M|  CenteredMaster	12
>M>  CenteredFloatingMaster	13
EOF
