# personal proxy

## 1. 方案

local host: flow -> (system proxy) -> (trojan client) -> (kcptun client) -> [network]

remote host: [network] -> (kcptun server) -> (trojan server) -> target host

## 2. 服务安装

> centos7环境演示
> NOTE: 如果服务器中有nginx服务，先备份nginx配置文件，防止在安装trojan_web时被覆盖

### 2.1 安装trojan server

```bash
source <(curl -sL https://git.io/trojan-install)
# 移除, 当需要重新安装时，移除后重新安装
# source <(curl -sL https://git.io/trojan-install) --remove
```

> NOTE: 申请证书时，切勿占用443端口，以免证书申请失败

#### 2.1.1 修改默认的trojan-web端口

> 当server中还存在其他的web服务时，trojan-web就不能占用443端口

1. 修改`/etc/systemd/system/trojan-web.service`配置文件
2. 在/usr/local/bin/trojan web 后面添加 -p port
3. 重启`trojan-web`服务

#### 2.1.2 定时更新证书

> 定时更形SSL证书，通过crontab定时调用`acme.sh`去检查和更新证书

```bash
# 什么服务占用443端口就暂停什么服务，这里是nginx
0 15 * * * systemctl stop nginx; "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" > /dev/null; systemctl start nginx
```

### 2.2 安装kcptun server

```shell
# 下载安装脚本
wget --no-check-certificate https://github.com/kuoruan/shell-scripts/raw/master/kcptun/kcptun.sh
# 赋予执行权限
chmod +x ./kcptun.sh
```

根据脚本的提示进行安装

### 2.3 配置防火墙

> 通过脚本安装完kcptun server后，脚本会开启防火墙规则，开放22/23/80/443和kcptun server的端口，如果服务器中还有其他服务需要开放端口或者ssh端口并非22，参考如下配置

```bash
# 查看防火墙规则
firewall-cmd --list-all

# 查看所有开放端口
firewall-cmd --list-ports

# 例如你的ssh端口是2222，开放ssh端口
firewall-cmd --zone=public --add-port=2222/tcp --permanent

# 保存防火墙规则
firewall-cmd --reload
```

## 3. 客户端安装

> Arch Linux环境演示

### 3.1 安装trojan client

```bash
# 安装trojan client
sudo pacman -S trojan

# 默认启动trojan client
systemctl enable trojan

# 启动trojan client
systemctl start trojan
```

#### 3.1.1 配置trojan client

运行`trojan-sync.sh`同步远程配置文件

### 3.2 安装kcptun client

```bash
# 安装kcptun client
sudo pacman -S kcptun

# 运行kcptun-sync.sh, 同步远程配置并创建kcptun_client服务
sudo bash kcptun-sync.sh
```

## 4. 设置系统默认代理

见[my's system proxy blog](https://byt0723.xyz/20230314/archlinux-system-proxy/)
