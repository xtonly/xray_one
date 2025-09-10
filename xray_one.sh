#!/bin/bash

#====================================================================================
#
#          FILE: xray_manager.sh
#
#         USAGE: bash xray_manager.sh
#
#   DESCRIPTION: 一个集安装、配置、管理和卸载于一体的 Xray 全功能脚本。
#                支持 VLESS+REALITY 和 Shadowsocks-2022。
#
#      REVISION: 1.1 - 修复了SS节点别名在某些客户端下为空的问题 (URL编码)
#
#====================================================================================

# --- 颜色定义 ---
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

# --- 全局变量 ---
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="$XRAY_CONFIG_DIR/config.json"
NODE_INFO_FILE="$XRAY_CONFIG_DIR/node_info.json"

# --- 函数定义 ---

# 打印彩色信息
color_echo() {
    echo -e "${!1}${2}${PLAIN}"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        color_echo RED "错误：此脚本必须以 root 身份运行！"
        exit 1
    fi
}

# 暂停脚本，等待用户输入
pause() {
    read -rp "按 [Enter] 键返回主菜单..."
}

# URL编码函数 (修复别名问题)
url_encode() {
    local string="$1"
    local encoded=""
    local char
    for (( i=0; i<${#string}; i++ )); do
        char=${string:i:1}
        case "$char" in
            [-_.~a-zA-Z0-9]) encoded+="$char" ;;
            *) encoded+=$(printf '%%%02X' "'$char") ;;
        esac
    done
    echo "$encoded"
}


# 获取公网 IP 地址
get_public_ip() {
    color_echo YELLOW "正在检测服务器公网 IP 地址..."
    IP_SERVICES=(
        "https://ipinfo.io/ip"
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )
    PUBLIC_IP=""
    for service in "${IP_SERVICES[@]}"; do
        IP_CANDIDATE=$(curl -s -A "Mozilla/5.0" --connect-timeout 5 "$service")
        if [[ "$IP_CANDIDATE" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            PUBLIC_IP=$IP_CANDIDATE
            break
        fi
    done

    if [ -z "$PUBLIC_IP" ]; then
        color_echo RED "自动检测公网 IP 失败。请检查网络或稍后重试。"
        exit 1
    fi
    color_echo GREEN "服务器公网 IP: $PUBLIC_IP"
}

# 安装 Xray
install_xray() {
    color_echo BLUE ">>> 正在安装 Xray..."
    if command -v xray &>/dev/null; then
        color_echo GREEN "Xray 已安装。将执行更新操作。"
    fi
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    if [ $? -ne 0 ]; then
        color_echo RED "Xray 安装失败！请检查错误信息。"
        exit 1
    fi
    systemctl enable xray
    color_echo GREEN "Xray 安装/更新成功！"
}

# 配置 Xray 并生成节点信息
configure_and_generate_links() {
    color_echo BLUE ">>> 正在为您配置 Xray 并生成节点..."
    
    # 1. 获取用户输入
    read -rp "请输入 VLESS 服务的端口 (默认 443): " VLESS_PORT
    VLESS_PORT=${VLESS_PORT:-443}
    
    read -rp "请输入 Shadowsocks 服务的端口 (默认 8443): " SS_PORT
    SS_PORT=${SS_PORT:-8443}

    read -rp "请输入一个真实的、可访问的目标网站域名 (例如 www.microsoft.com): " SNI
    if [ -z "$SNI" ]; then
        color_echo RED "目标网站域名不能为空！"
        return 1
    fi

    # 2. 生成所需参数
    UUID=$(xray uuid)
    KEY_PAIR=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | grep 'Private key' | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEY_PAIR" | grep 'Public key' | awk '{print $3}')
    SHORT_ID=$(openssl rand -hex 8)
    SS_METHOD="2022-blake3-aes-128-gcm"
    SS_PASSWORD=$(openssl rand -base64 16)
    
    # 3. 生成 Xray 配置文件
    color_echo YELLOW "正在写入服务器配置文件..."
    cat > "$XRAY_CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${VLESS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": [ "${SNI}" ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [ "${SHORT_ID}" ]
        }
      }
    },
    {
      "listen": "0.0.0.0",
      "port": ${SS_PORT},
      "protocol": "shadowsocks",
      "settings": {
        "method": "${SS_METHOD}",
        "password": "${SS_PASSWORD}"
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF

    # 4. 保存节点信息，方便后续查看
    get_public_ip
    SERVER_HOSTNAME=$(hostname)
    cat > "$NODE_INFO_FILE" <<EOF
{
  "vless_port": "${VLESS_PORT}",
  "ss_port": "${SS_PORT}",
  "uuid": "${UUID}",
  "public_key": "${PUBLIC_KEY}",
  "short_id": "${SHORT_ID}",
  "sni": "${SNI}",
  "ss_method": "${SS_METHOD}",
  "ss_password": "${SS_PASSWORD}",
  "server_ip": "${PUBLIC_IP}",
  "hostname": "${SERVER_HOSTNAME}"
}
EOF

    color_echo GREEN "服务器配置写入成功！"

    # 5. 开放防火墙
    color_echo YELLOW "正在配置防火墙..."
    if command -v ufw &>/dev/null; then
        ufw allow ${VLESS_PORT}/tcp
        ufw allow ${SS_PORT}/tcp
        ufw reload
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --zone=public --add-port=${VLESS_PORT}/tcp --permanent
        firewall-cmd --zone=public --add-port=${SS_PORT}/tcp --permanent
        firewall-cmd --reload
    else
        color_echo YELLOW "未检测到 ufw 或 firewalld，请手动开放端口 ${VLESS_PORT} 和 ${SS_PORT}！"
    fi

    # 6. 重启 Xray 并显示结果
    systemctl restart xray
    if systemctl is-active --quiet xray; then
        color_echo GREEN "Xray 已成功启动！"
    else
        color_echo RED "Xray 启动失败！请使用 'systemctl status xray' 查看日志。"
        return 1
    fi
    
    view_links
}

# 查看节点信息
view_links() {
    if [ ! -f "$NODE_INFO_FILE" ]; then
        color_echo RED "未找到节点信息文件。请先执行安装与配置。"
        return
    fi
    
    # 从文件中读取信息
    VLESS_PORT=$(grep "vless_port" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    SS_PORT=$(grep "ss_port" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    UUID=$(grep "uuid" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    PUBLIC_KEY=$(grep "public_key" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    SHORT_ID=$(grep "short_id" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    SNI=$(grep "sni" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    SS_METHOD=$(grep "ss_method" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    SS_PASSWORD=$(grep "ss_password" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    SERVER_IP=$(grep "server_ip" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')
    HOSTNAME=$(grep "hostname" "$NODE_INFO_FILE" | awk -F'"' '{print $4}')

    # 【v1.1 修正】对别名进行 URL 编码
    VLESS_REMARK_ENCODED=$(url_encode "${HOSTNAME}")
    SS_REMARK_ENCODED=$(url_encode "${HOSTNAME}-SS")

    # 生成 VLESS 链接
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&security=reality&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${VLESS_REMARK_ENCODED}"
    
    # 生成 Shadowsocks 链接
    SS_USER_INFO_B64=$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w 0)
    SS_LINK="ss://${SS_USER_INFO_B64}@${SERVER_IP}:${SS_PORT}#${SS_REMARK_ENCODED}"
    
    color_echo GREEN "====================== 您的节点信息 ======================"
    color_echo YELLOW "[VLESS + REALITY 节点链接]"
    echo "${VLESS_LINK}"
    echo ""
    color_echo YELLOW "[Shadowsocks (SS2022) 节点链接]"
    echo "${SS_LINK}"
    color_echo GREEN "=========================================================="
}

# 卸载 Xray
uninstall_xray() {
    read -rp "您确定要卸载 Xray 吗？这将删除所有相关文件和配置！(y/N): " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        color_echo YELLOW "卸载操作已取消。"
        return
    fi
    
    color_echo BLUE ">>> 正在卸载 Xray..."
    systemctl stop xray
    systemctl disable xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    rm -rf "$XRAY_CONFIG_DIR"
    
    color_echo GREEN "Xray 已成功卸载！"
}

# 主菜单
show_menu() {
    clear
    color_echo GREEN "=========================================================="
    color_echo GREEN "          Xray 全功能管理脚本 v1.1 (VLESS/SS)"
    color_echo GREEN "=========================================================="
    color_echo BLUE "  1. 安装并配置 Xray (首次/重新配置请选此项)"
    color_echo BLUE "  2. 查看节点信息"
    color_echo BLUE "  3. 重启 Xray 服务"
    color_echo BLUE "  4. 停止 Xray 服务"
    color_echo BLUE "  5. 查看 Xray 状态与日志"
    color_echo YELLOW "  6. 卸载 Xray"
    color_echo PLAIN "  0. 退出脚本"
    color_echo GREEN "=========================================================="
    read -rp "请输入选项 [0-6]: " choice
    
    case $choice in
        1)
            install_xray
            configure_and_generate_links
            pause
            ;;
        2)
            view_links
            pause
            ;;
        3)
            systemctl restart xray
            color_echo GREEN "Xray 服务已重启。"
            sleep 2
            ;;
        4)
            systemctl stop xray
            color_echo GREEN "Xray 服务已停止。"
            sleep 2
            ;;
        5)
            color_echo YELLOW "正在查看 Xray 实时日志，按 Ctrl+C 退出..."
            journalctl -u xray -f --no-pager
            pause
            ;;
        6)
            uninstall_xray
            pause
            ;;
        0)
            exit 0
            ;;
        *)
            color_echo RED "无效选项，请输入正确的数字。"
            sleep 2
            ;;
    esac
}

# --- 脚本主入口 ---
check_root
while true; do
    show_menu
done
