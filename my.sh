#!/bin/bash

# 颜色定义 (已修复补充 white 函数)
red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; blue='\033[0;36m'; bblue='\033[0;34m'; plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}

# 固定配置信息
UUID="ecf009a0-2410-41d6-b9bb-4831ce7c2d5f"
WS_PATH="ecf009a0-2410-41d6-b9bb-4831ce7c2d5f-vm"
PORT=2052
CF_TOKEN="eyJhIjoiYWYyYmU0MWQ2MDAzN2M4MGVhZTAzMTg4OTUxMmMxNTMiLCJ0IjoiZWFlOWMzNmQtZGQ1Ni00NjE1LTg5NzUtNDcxNGNiOWNlN2MwIiwicyI6IlpHSTJaakEzWlRZdE1UWTVOQzAwTm1FNUxXSmpOelV0TURZNVpETXhOamcyTXpOaiJ9"

[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit

# 系统状态检测
vps_status(){
    op=$(cat /etc/os-release | grep -i pretty_name | cut -d \" -f2)
    version=$(uname -r)
    cpu=$(uname -m)
    vi=$(systemd-detect-virt 2>/dev/null)
    bbr=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || echo "未知")
    ipv4=$(curl -s4m5 icanhazip.com || echo "无")
    
    clear
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
    blue "      定制版 Sing-box & Cloudflare 隧道 极简管理脚本"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
    echo -e "系统:$blue$op$plain  内核:$blue$version$plain"
    echo -e "处理器:$blue$cpu$plain  虚拟化:$blue$vi$plain  BBR算法:$blue$bbr$plain"
    echo -e "本地IPV4地址：$blue$ipv4$plain"
    
    if systemctl is-active --quiet sing-box; then
        echo -e "Sing-box 状态：$blue运行中$plain"
    else
        echo -e "Sing-box 状态：$red未启动$plain"
    fi
    
    if systemctl is-active --quiet cloudflared; then
        echo -e "Cloudflare 隧道状态：$blue运行中$plain"
    else
        echo -e "Cloudflare 隧道状态：$red未连接$plain"
    fi
    echo "------------------------------------------------------------------------------------"
    echo -e "🚀【 VMess-WS 】 端口：$yellow$PORT$plain  路径：$yellow/$WS_PATH$plain"
    echo -e "🚀【 UUID 】     $yellow$UUID$plain"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

# 安装 Sing-box (VMess + WS)
install_sb(){
    green "开始安装 Sing-box 内核..."
    case $(uname -m) in aarch64) c=arm64;; x86_64) c=amd64;; *) red "不支持的架构" && exit 1;; esac
    
    v=$(curl -Ls "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    wget -O sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${v}/sing-box-${v}-linux-${c}.tar.gz"
    tar -xzf sb.tar.gz
    mkdir -p /etc/sing-box
    mv sing-box-*/sing-box /usr/local/bin/ && chmod +x /usr/local/bin/sing-box
    rm -rf sb.tar.gz sing-box-*
    
    cat > /etc/sing-box/config.json <<EOF
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{
      "type": "vmess", "listen": "::", "listen_port": $PORT,
      "users": [{"uuid": "$UUID", "alterId": 0}],
      "transport": {"type": "ws", "path": "$WS_PATH", "max_early_data": 2048, "early_data_header_name": "Sec-WebSocket-Protocol"}
  }],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target
[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable sing-box && systemctl restart sing-box
    green "Sing-box 安装完成！"
}

# 安装 Cloudflare 隧道 
install_cf(){
    green "开始安装 Cloudflare 隧道服务..."
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
    sudo apt-get update && sudo apt-get install cloudflared -y
    
    sudo cloudflared service install "$CF_TOKEN" --http2
    systemctl start cloudflared
    green "Cloudflare 隧道安装并启动完成！"
}

# 更新内核
update_kernel(){
    green "正在检测并更新 Sing-box 内核..."
    install_sb
    systemctl restart sing-box
    green "内核更新结束。"
    sleep 2
}

# 脚本自更新 
update_script(){
    green "当前使用的是本地极简版脚本，如需更新功能，请直接替换脚本代码即可。"
    sleep 2
}

# 卸载
uninstall(){
    systemctl stop sing-box cloudflared
    systemctl disable sing-box cloudflared
    rm -rf /etc/sing-box /usr/local/bin/sing-box /etc/systemd/system/sing-box.service
    apt-get remove cloudflared -y
    green "卸载完成！"
}

# 主菜单
menu(){
    vps_status
    echo -e " 1. 一键安装 Sing-box + Cloudflare 隧道" 
    echo -e " 2. 卸载 Sing-box 与 隧道"
    echo -e "----------------------------------------------------------------------------------"
    echo -e " 3. 更新 Sing-box 内核版本"
    echo -e " 4. 更新脚本自身"
    echo -e " 5. 重启服务"
    echo -e " 0. 退出脚本"
    echo -e "----------------------------------------------------------------------------------"
    readp "请输入数字:" Input
    case "$Input" in  
     1 ) install_sb && install_cf && menu;;
     2 ) uninstall && menu;;
     3 ) update_kernel && menu;;
     4 ) update_script && menu;;
     5 ) systemctl restart sing-box cloudflared && menu;;
     * ) exit 
    esac
}

menu
