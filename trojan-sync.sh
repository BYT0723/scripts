#!/bin/bash
#
#echo -e

log() {
	case "$1" in
	ERROR)
		echo -e "\033[31m"[$1] ${@:2}"\033[0m"
		;;
	*)
		echo -e "\033[31m"[$1]"\033[0m ${@:2}"
		;;
	esac
}

dir=$(dirname $0)
email="syncer@byt0723.com"
key_path="$dir/syncer"
server="root@byt0723.xyz"
remote_config="/root/config.json"
remote_auth_path="/root/.ssh/authorized_keys"
port="29793"
local_config="/etc/trojan/config.json"

if [ ! -w "$local_config" ]; then
	log ERROR "您没有$local_config的写权限"
	exit 1
fi

# 如果私钥不存在，则生成
if [ ! -f "$key_path" ]; then
	# 在本地生成ssh public key
	echo "\n\n" | ssh-keygen -t rsa -b 2048 -C "$email" -f $key_path
fi

pk=$(cat "${key_path}.pub")

ssh $server -p $port -i $key_path "\
if [ ! -d $(dirname $remote_auth_path) || ! -f $remote_auth_path || -z "'$(grep $pk $remote_auth_path)'" ]
if [ -z [ -d $(dirname $remote_auth_path) ] && [ -f $remote_auth_path ] && grep "$pk" $remote_auth_path")" ]; then
    ssh $server -p $port -i $key_path "mkdir -p $(dirname $remote_auth_path) && [ ! -f $remote_auth_path ] && touch $remote_auth_path && echo \"$pk\" >>$remote_auth_path"
fi
"

# 如果私钥不在远程服务器中,则托送上去
# if [ -z "$(ssh $server -p $port -i $key_path "[ -d $(dirname $remote_auth_path) ] && [ -f $remote_auth_path ] && grep \"$pk\" $remote_auth_path")" ]; then
# 	ssh $server -p $port -i $key_path "mkdir -p $(dirname $remote_auth_path) && [ ! -f $remote_auth_path ] && touch $remote_auth_path && echo \"$pk\" >> $remote_auth_path"
# fi

# case "$1" in
# 'port-change')
# 	log INFO "更新trojan接口..."
# 	ssh $server -p $port -i $key_path "trojan port"
# 	log INFO "更新完成"
# 	;;
# *)
# 	log INFO "不更新trojan接口"
# 	;;
# esac
#
# # 更新远程Client Config文件
# log INFO "更新远程trojan client config..."
# echo "6" | ssh -tt $server -p $port -i $key_path -q '(trojan & sleep 1 && kill $!) > /dev/null'
# log INFO "更新完成"
#
# # 拉去最新的Config
# log INFO "更新本地trojan client config..."
# scp -P 29793 -i $key_path $server:$remote_config $local_config
# log INFO "更新完成"
#
# # 重启trojan
# log INFO "重启本地trojan服务..."
# systemctl restart trojan
# log INFO "重启完成"
