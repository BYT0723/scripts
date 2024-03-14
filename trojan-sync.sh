#!/bin/bash

# 基本所在路径
dir=$(dirname $0)
# 注册私钥邮箱
email="$(echo /etc/hostname)@syncer.com"
# 私钥路径
key_path="$dir/syncer"
# 服务器地址
server="root@byt0723.xyz"
# 服务器ssh端口
port="29793"
# 服务器中trojan client配置路径
remote_config="/root/config.json"
# 服务器中ssh授权文件
remote_auth_path="/root/.ssh/authorized_keys"
# 本地trojan client配置路径
local_config="/etc/trojan/config.json"

# 日志函数
log() {
	case "$1" in
	ERROR)
		echo -e "$(date +'%Y-%m-%d %H:%M:%S') \033[31m"[$1] ${@:2}"\033[0m"
		;;
	*)
		echo -e "$(date +'%Y-%m-%d %H:%M:%S') [$1] ${@:2}"
		;;
	esac
}

if [ ! -w "$local_config" ]; then
	log ERROR "您没有$local_config的写权限!!!"
	exit 1
fi

# 如果私钥不存在，则生成
if [ ! -f "$key_path" ]; then
	# 在本地生成ssh public key
	echo "\n\n" | ssh-keygen -t rsa -b 2048 -C "$email" -f $key_path
fi

pk=$(cat "${key_path}.pub")
# 如果私钥不在远程服务器中,则托送上去
ssh $server -p $port -i $key_path "\
if [ ! -d \"$(dirname $remote_auth_path)\" ] || [ ! -f \"$remote_auth_path\" ] || [ -z \"\$(grep \"$pk\" \"$remote_auth_path\")\" ]; then \
    mkdir -p \"$(dirname $remote_auth_path)\" && touch \"$remote_auth_path\" && echo \"$pk\" | tee -a \"$remote_auth_path\"; \
fi" >/dev/null

case "$1" in
'port-change')
	log INFO "更新trojan接口..."
	ssh $server -p $port -i $key_path "trojan port"
	;;
*)
	log INFO "不更新trojan接口"
	;;
esac

# 更新远程Client Config文件
log INFO "更新远程trojan client config..."
echo "6" | ssh -tt $server -p $port -i $key_path -q '(trojan & sleep 1 && kill $!) > /dev/null'

# 拉去最新的Config
log INFO "更新本地trojan client config..."
scp -P 29793 -i $key_path $server:$remote_config $local_config

# 重启trojan
log INFO "重启本地trojan服务..."
systemctl restart trojan
log INFO "[Done]"
