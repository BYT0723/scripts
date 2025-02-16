#!/bin/bash

# sync kcptun and trojan configuration from remote server

source $(dirname $0)/util.sh

# 基本所在路径
dir=$(dirname $0)
# 注册私钥邮箱
email="$(cat /etc/hostname)@syncer.com"
# 私钥路径
key_path="$dir/syncer"
# 服务器地址
host=proxy.byt0723.xyz
# 用户名
user=root
# 服务器ssh端口
port="29793"
# 服务器中kcptun server配置路径
remote_server_config="/usr/local/kcptun/server-config.json"
# 服务器中ssh授权文件
remote_auth_path="/root/.ssh/authorized_keys"
# 本地kcptun client配置路径
local_config="/etc/kcptun/config.json"
# service 路径
service_path="/etc/systemd/system/kcptun_client.service"
service_name=$(basename $service_path)

# 检查本地配置文件写入权限
if [[ $UID != 0 ]]; then
	log ERROR "Need run with root user"
	exit 1
fi

# 如果私钥不存在，则生成
if [ ! -f "$key_path" ]; then
	# 在本地生成ssh public key
	echo "\n\n" | ssh-keygen -t rsa -b 2048 -C "$email" -f $key_path
fi

pk=$(cat "${key_path}.pub")
# 如果私钥不在远程服务器中,则托送上去
ssh $user@$host -p $port -i $key_path "\
if [ ! -d \"$(dirname $remote_auth_path)\" ] || [ ! -f \"$remote_auth_path\" ] || [ -z \"\$(grep \"$pk\" \"$remote_auth_path\")\" ]; then \
    mkdir -p \"$(dirname $remote_auth_path)\" && touch \"$remote_auth_path\" && echo \"$pk\" | tee -a \"$remote_auth_path\"; \
fi" >>/dev/null

log INFO "当前KcpTun连接: "$(jq -r '.localaddr + " ===> " + .remoteaddr' /etc/kcptun/config.json)

if [[ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -L 'https://www.google.com')" == "200" ]]; then
	log INFO "您的网络连接正常!!!"
	read -p "是否继续(y/n): " -n 1 -r ok && echo
	if [[ ! $ok =~ ^[Yy]$ ]]; then
		exit 0
	fi
fi

tmpFile="/tmp/kcptun/config/"$(echo $HOST | md5sum | cut -d ' ' -f 1)".json"

ssh -t -q -p $port $user@$host -i $key_path '
    dir=/usr/local/kcptun
    echo 
    printf "%-10s\t%-15s\t%-15s\n" "Config[ID]" "Local_Addr" "Remote_Addr"
    for cfg in $(ls $dir | grep "server-config[0-9]*.json" | sort);do
        printf "%-10s\t%-15s\t%-15s\n" "$(echo $cfg | cut -d '.' -f 1 | cut -d '-' -f 2)" "$(cat $dir/$cfg | jq -r ".listen")" "$(cat $dir/$cfg | jq -r ".target")"
    done
    echo
    read -p "选择配置ID: " -r id

    file=$dir/server-config$id.json
    if [ ! -f "$file" ]; then
        echo "无效的配置ID"
        exit 1
    fi

    mkdir -p $(dirname '$tmpFile')
    cp $file '$tmpFile

# 检测上一个ssh命令的exitCode, 非0则退出
[ $? -ne 0 ] && exit || true

client_config=$(echo $(ssh -p $port $user@$host -i $key_path "cat $tmpFile") | jq --arg remote_host "$host" '{
  localaddr: ":\(.target | split(":")[1])",
  remoteaddr: "\($remote_host):\(.listen | split(":")[1])",
  key: .key,
  crypt: .crypt,
  mode: .mode,
  mtu: .mtu,
  sndwnd: .rcvwnd,
  rcvwnd: .sndwnd,
  datashard: .datashard,
  parityshard: .parityshard,
  dscp: .dscp,
  nocomp: .nocomp,
  quiet: .quiet,
  tcp: .tcp
} | del(.pprof)')

if [ ! -z "$client_config" ]; then
	>$local_config
	echo $client_config | jq >>$local_config
fi

if [ ! -z "$(command -v kcptun-client)" ]; then
	if [ ! -f "$service_path" ]; then
		log INFO "create kcptun client服务..."
		echo "[Unit]
Description=Kcptun Server Service
After=network.target

[Service]
Type=simple
ExecStart="$(command -v kcptun-client)" -c "$local_config"
Restart=on-failure
User=nobody
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target" >>$service_path
		log INFO "enable $service_name服务..."
		systemctl enable $service_name 2>&1 >>/dev/null
		systemctl daemon-reload
		log INFO "start $service_name服务..."
		systemctl start $service_name
	else
		# 重启kcptun_client
		log INFO "重启本地$service_name服务..."
		systemctl restart $service_name
	fi
fi

if [[ "$(systemctl is-active trojan)" == "active" ]]; then
	trojan_config=$(cat /etc/trojan/config.json)
	>/etc/trojan/config.json
	echo $trojan_config | jq --argjson local_port $(jq -r '(.localaddr | split(":")[1])' /etc/kcptun/config.json) '.remote_addr = "127.0.0.1" | .remote_port = $local_port' >>/etc/trojan/config.json

	log INFO "重启本地trojan服务..."
	systemctl restart trojan
fi

# cat /etc/shadowsocks/bandwagon.json
# {
#   "server": "127.0.0.1",
#   "server_port": 29595,
#   "local_address": "127.0.0.1",
#   "local_port": 1080,
#   "password": "wangtao",
#   "timeout": 300,
#   "method": "aes-256-gcm",
#   "fast_open": false,
#   "workers": 8,
#   "prefer_ipv6": false
# }
if [[ "$(systemctl is-active shadowsocks@bandwagon)" == "active" ]]; then
	shadowsocks_config=$(cat /etc/shadowsocks/bandwagon.json)
	>/etc/shadowsocks/bandwagon.json
	echo $shadowsocks_config | jq --argjson local_port $(jq -r '(.localaddr | split(":")[1])' /etc/kcptun/config.json) '.server = "127.0.0.1" | .server_port = $local_port' >>/etc/shadowsocks/bandwagon.json

	log INFO "重启本地shadowsocks@bandwagon服务..."
	systemctl restart shadowsocks@bandwagon
fi

log INFO "[Done]"
