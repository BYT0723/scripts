#!/bin/bash

source "$(dirname $0)/../utils/notify.sh"

[ -z "$(command -v offlineimap)" ] && system-notify critical "Tool Not Found" "please install offlineimap" && exit
[ -z "$(command -v notmuch)" ] && system-notify critical "Tool Not Found" "please install notmuch" && exit

output=$(offlineimap -o >>/dev/null)
if [ ! -z "$output" ]; then
	notify-send -u critical -i mail-unread-symbolic "Mailbox synchronization failed:"$output
	exit 0
fi

if [ ! -z $(command -v notmuch) ]; then
	notmuch new
	unread=$(notmuch count tag:unread)
	if [ $unread -gt 0 ]; then
		notify-send -i mail-unread-symbolic "$(notmuch search --output=files tag:unread | cut -d/ -f5 | sort | uniq -c | awk '{print "[" $2 "] \t" $1 "封新邮件"}')"
	fi
fi
