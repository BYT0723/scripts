#!/bin/bash

while true; do
	if [ -f $HOME/.note ] && [ ! -z "$(grep '^[*=]' $HOME/.note)" ]; then
		/bin/bash /home/walter/.dwm/clock.sh PLAN "$(grep '^[*=]' $HOME/.note)"
	fi
	sleep 1800
done

exit 0
