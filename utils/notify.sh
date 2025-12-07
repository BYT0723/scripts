#!/bin/bash

# system notify
# $1 level [low | normal | critical]
# $2 title
# $3 information
system-notify() {
	notify-send -u "$1" " $2" "\n$3"
}
