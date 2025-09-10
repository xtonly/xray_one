#!/bin/bash

#====================================================================================
#
#          FILE: xray_manager.sh
#
#         USAGE: bash xray_manager.sh
#
#   DESCRIPTION: A comprehensive, multilingual script for installing, configuring,
#                managing, and uninstalling Xray. Supports VLESS+REALITY and
#                Shadowsocks-2022.
#
#      REVISION: 1.8 - [FINAL FIX] Used 'export' to define language variables,
#                      forcefully resolving the variable scope issue that caused
#                      invisible menu text. This ensures variables are globally
#                      accessible throughout the script's execution.
#
#====================================================================================

# --- Color Definitions ---
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

# --- Global Variables ---
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="$XRAY_CONFIG_DIR/config.json"
NODE_INFO_FILE="$XRAY_CONFIG_DIR/node_info.conf"

# --- Embedded Language Functions ---

load_lang_en() {
    export ERROR_MUST_BE_ROOT="Error: This script must be run as root!"
    export PRESS_ENTER_TO_CONTINUE="Press [Enter] to return to the main menu..."
    export DETECTING_IP="Detecting server public IP address..."
    export ERROR_IP_DETECTION_FAILED="Failed to detect public IP. Please check your network or try again later."
    export SERVER_IP_IS="Server Public IP:"
    export INSTALLING_XRAY=">>> Installing Xray..."
    export XRAY_ALREADY_INSTALLED="Xray is already installed. An update will be performed."
    export ERROR_XRAY_INSTALL_FAILED="Xray installation failed or not found in PATH! Please check the installation log."
    export SUCCESS_XRAY_INSTALLED="Xray installed/updated successfully!"
    export CONFIGURING_XRAY=">>> Configuring Xray and generating nodes..."
    export PROMPT_VLESS_PORT="Enter VLESS service port (default 443): "
    export PROMPT_SS_PORT="Enter Shadowsocks service port (default 8443): "
    export PROMPT_SNI="Enter a real, accessible destination domain (e.g., www.microsoft.com): "
    export ERROR_SNI_EMPTY="Destination domain cannot be empty!"
    export PROMPT_SNIFFING="Enable sniffing for client-side traffic diversion? (y/N): "
    export ERROR_KEY_GENERATION_FAILED="Error: Failed to generate REALITY key pair! Please run 'xray x25519' manually to check for errors."
    export WRITING_CONFIG="Writing server configuration file..."
    export SUCCESS_CONFIG_WRITTEN="Server configuration written successfully!"
    export CONFIGURING_FIREWALL="Configuring firewall..."
    export SUCCESS_XRAY_STARTED="Xray started successfully!"
    export ERROR_XRAY_START_FAILED="Xray failed to start! Please use menu option 5 to view logs and diagnose the issue."
    export ERROR_NODE_FILE_NOT_FOUND="Node information file not found. Please perform the installation and configuration first."
    export NODE_INFO_HEADER="====================== Your Node Information ======================"
    export VLESS_NODE_LINK="[VLESS + REALITY Node Link]"
    export SS_NODE_LINK="[Shadowsocks (SS2022) Node Link]"
    export NODE_INFO_FOOTER="================================================================="
    export PROMPT_UNINSTALL_CONFIRM="Are you sure you want to uninstall Xray? (y/N): "
    export UNINSTALL_CANCELLED="Uninstall operation canceled."
    export SUCCESS_XRAY_UNINSTALLED="Xray has been successfully uninstalled!"
    export MENU_HEADER_1="================================================================="
    export MENU_HEADER_2="          Xray All-in-One Management Script v1.8 (VLESS/SS)"
    export MENU_OPTION_1="Install and Configure Xray (Select for first time/reconfiguration)"
    export MENU_OPTION_2="View Node Information"
    export MENU_OPTION_3="Restart Xray Service"
    export MENU_OPTION_4="Stop Xray Service"
    export MENU_OPTION_5="View Xray Status and Logs"
    export MENU_OPTION_6="Uninstall Xray"
    export MENU_OPTION_0="Exit Script"
    export PROMPT_MENU_CHOICE="Please enter an option [0-6]: "
    export XRAY_SERVICE_RESTARTED="Xray service has been restarted."
    export XRAY_SERVICE_STOPPED="Xray service has been stopped."
    export VIEWING_LOGS="Viewing real-time Xray logs, press Ctrl+C to exit..."
    export ERROR_INVALID_OPTION="Invalid option, please enter a correct number."
}

load_lang_zh() {
    export ERROR_MUST_BE_ROOT="错误：此脚本必须以 root 身份运行！"
    export PRESS_ENTER_TO_CONTINUE="按 [Enter] 键返回主菜单..."
    export DETECTING_IP="正在检测服务器公网 IP 地址..."
    export ERROR_IP_DETECTION_FAILED="自动检测公网 IP 失败。请检查网络或稍后重试。"
    export SERVER_IP_IS="服务器公网 IP:"
    export INSTALLING_XRAY=">>> 正在安装 Xray..."
    export XRAY_ALREADY_INSTALLED="Xray 已安装。将执行更新操作。"
    export ERROR_XRAY_INSTALL_FAILED="Xray 安装失败或未在 PATH 中找到！请检查安装日志。"
    export SUCCESS_XRAY_INSTALLED="Xray 安装/更新成功！"
    export CONFIGURING_XRAY=">>> 正在为您配置 Xray 并生成节点..."
    export PROMPT_VLESS_PORT="请输入 VLESS 服务的端口 (默认 443): "
    export PROMPT_SS_PORT="请输入 Shadowsocks 服务的端口 (默认 8443): "
    export PROMPT_SNI="请输入一个真实的、可访问的目标网站域名 (例如 www.microsoft.com): "
    export ERROR_SNI_EMPTY="目标网站域名不能为空！"
    export PROMPT_SNIFFING="是否为客户端开启流量嗅探(sniffing)功能？(y/N): "
    export ERROR_KEY_GENERATION_FAILED="错误：生成 REALITY 密钥对失败！请手动运行 'xray x25519' 查看报错。"
    export WRITING_CONFIG="正在写入服务器配置文件..."
    export SUCCESS_CONFIG_WRITTEN="服务器配置写入成功！"
    export CONFIGURING_FIREWALL="正在配置防火墙..."
    export SUCCESS_XRAY_STARTED="Xray 已成功启动！"
    export ERROR_XRAY_START_FAILED="Xray 启动失败！请使用菜单 5 查看日志以定位问题。"
    export ERROR_NODE_FILE_NOT_FOUND="未找到节点信息文件。请先执行安装与配置。"
    export NODE_INFO_HEADER="====================== 您的节点信息 ======================"
    export VLESS_NODE_LINK="[VLESS + REALITY 节点链接]"
    export SS_NODE_LINK="[Shadowsocks (SS2022) 节点链接]"
    export NODE_INFO_FOOTER="=========================================================="
    export PROMPT_UNINSTALL_CONFIRM="您确定要卸载 Xray 吗？(y/N): "
    export UNINSTALL_CANCELLED="卸载操作已取消。"
    export SUCCESS_XRAY_UNINSTALLED="Xray 已成功卸载！"
    export MENU_HEADER_1="=========================================================="
    export MENU_HEADER_2="          Xray 全功能管理脚本 v1.8 (VLESS/SS)"
    export MENU_OPTION_1="安装并配置 Xray (首次/重新配置请选此项)"
    export MENU_OPTION_2="查看节点信息"
    export MENU_OPTION_3="重启 Xray 服务"
    export MENU_OPTION_4="停止 Xray 服务"
    export MENU_OPTION_5="查看 Xray 状态与日志"
    export MENU_OPTION_6="卸载 Xray"
    export MENU_OPTION_0="退出脚本"
    export PROMPT_MENU_CHOICE="请输入选项 [0-6]: "
    export XRAY_SERVICE_RESTARTED="Xray 服务已重启。"
    export XRAY_SERVICE_STOPPED="Xray 服务已停止。"
    export VIEWING_LOGS="正在查看 Xray 实时日志，按 Ctrl+C 退出..."
    export ERROR_INVALID_OPTION="无效选项，请输入正确的数字。"
}

select_language() {
    echo -e "${BLUE}Please select a language / 请选择语言:${PLAIN}"
    echo "1. English"
    echo "2. 中文"
    read -rp "Enter your choice [1-2]: " lang_choice

    case $lang_choice in
        1)
            load_lang_en
            ;;
        2)
            load_lang_zh
            ;;
        *)
            echo -e "${RED}Invalid selection, defaulting to English.${PLAIN}"
            load_lang_en
            ;;
    esac
}

# --- Function Definitions ---

color_echo() { echo -e "${!1}${2}${PLAIN}"; }
check_root() { if [ "$EUID" -ne 0 ]; then color_echo RED "$ERROR_MUST_BE_ROOT"; exit 1; fi; }
pause() { read -rp "$PRESS_ENTER_TO_CONTINUE"; }

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

get_public_ip() {
    color_echo YELLOW "$DETECTING_IP"
    PUBLIC_IP=$(curl -s -4 --connect-timeout 5 https://ipinfo.io/ip || curl -s -4 --connect-timeout 5 https://api.ipify.org)
    if [ -z "$PUBLIC_IP" ]; then
        color_echo RED "$ERROR_IP_DETECTION_FAILED"
        exit 1
    fi
    color_echo GREEN "$SERVER_IP_IS $PUBLIC_IP"
}

install_xray() {
    color_echo BLUE "$INSTALLING_XRAY"
    if command -v xray &>/dev/null; then color_echo GREEN "$XRAY_ALREADY_INSTALLED"; fi
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    if ! command -v xray &>/dev/null; then color_echo RED "$ERROR_XRAY_INSTALL_FAILED"; exit 1; fi
    systemctl enable xray
    color_echo GREEN "$SUCCESS_XRAY_INSTALLED"
}

configure_and_generate_links() {
    color_echo BLUE "$CONFIGURING_XRAY"
    read -rp "$PROMPT_VLESS_PORT" VLESS_PORT; VLESS_PORT=${VLESS_PORT:-443}
    read -rp "$PROMPT_SS_PORT" SS_PORT; SS_PORT=${SS_PORT:-8443}
    read -rp "$PROMPT_SNI" SNI
    if [ -z "$SNI" ]; then color_echo RED "$ERROR_SNI_EMPTY"; return 1; fi
    read -rp "$PROMPT_SNIFFING" SNIFFING_CHOICE
    [[ "${SNIFFING_CHOICE,,}" == "y" ]] && SNIFFING_ENABLED="true" || SNIFFING_ENABLED="false"

    UUID=$(xray uuid)
    KEY_PAIR=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | grep 'Private key' | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEY_PAIR" | grep 'Public key' | awk '{print $3}')
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then color_echo RED "$ERROR_KEY_GENERATION_FAILED"; return 1; fi

    SHORT_ID=$(openssl rand -hex 8)
    SS_METHOD="2022-blake3-aes-128-gcm"
    SS_PASSWORD=$(openssl rand -base64 16)
    FINGERPRINT="chrome"

    color_echo YELLOW "$WRITING_CONFIG"
    cat > "$XRAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning" }, "inbounds": [
    { "listen": "0.0.0.0", "port": ${VLESS_PORT}, "protocol": "vless",
      "settings": { "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision" } ], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "reality",
        "realitySettings": { "show": false, "dest": "${SNI}:443", "xver": 0, "serverNames": [ "${SNI}" ], "privateKey": "${PRIVATE_KEY}", "shortIds": [ "${SHORT_ID}" ] }
      }, "sniffing": { "enabled": ${SNIFFING_ENABLED}, "destOverride": ["http", "tls"] }
    },
    { "listen": "0.0.0.0", "port": ${SS_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "${SS_METHOD}", "password": "${SS_PASSWORD}" }, "streamSettings": { "network": "tcp" }
    }
  ], "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "blocked" } ]
}
EOF

    get_public_ip
    SERVER_HOSTNAME=$(hostname)
    cat > "$NODE_INFO_FILE" <<EOF
VLESS_PORT="${VLESS_PORT}"; SS_PORT="${SS_PORT}"; UUID="${UUID}"; PUBLIC_KEY="${PUBLIC_KEY}"; SHORT_ID="${SHORT_ID}"; SNI="${SNI}"; FINGERPRINT="${FINGERPRINT}"; SS_METHOD="${SS_METHOD}"; SS_PASSWORD="${SS_PASSWORD}"; SERVER_IP="${PUBLIC_IP}"; HOSTNAME="${SERVER_HOSTNAME}"
EOF

    color_echo GREEN "$SUCCESS_CONFIG_WRITTEN"
    color_echo YELLOW "$CONFIGURING_FIREWALL"
    if command -v ufw &>/dev/null; then ufw allow ${VLESS_PORT}/tcp >/dev/null 2>&1 && ufw allow ${SS_PORT}/tcp >/dev/null 2>&1;
    elif command -v firewall-cmd &>/dev/null; then firewall-cmd --permanent --add-port=${VLESS_PORT}/tcp >/dev/null 2>&1 && firewall-cmd --permanent --add-port=${SS_PORT}/tcp >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1; fi

    systemctl restart xray
    if systemctl is-active --quiet xray; then color_echo GREEN "$SUCCESS_XRAY_STARTED"; else color_echo RED "$ERROR_XRAY_START_FAILED"; return 1; fi
    view_links
}

view_links() {
    if [ ! -f "$NODE_INFO_FILE" ]; then color_echo RED "$ERROR_NODE_FILE_NOT_FOUND"; return; fi
    source "$NODE_INFO_FILE"
    VLESS_REMARK_ENCODED=$(url_encode "${HOSTNAME}")
    SS_REMARK_ENCODED=$(url_encode "${HOSTNAME}-SS")
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${VLESS_REMARK_ENCODED}"
    SS_USER_INFO_B64=$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w 0)
    SS_LINK="ss://${SS_USER_INFO_B64}@${SERVER_IP}:${SS_PORT}#${SS_REMARK_ENCODED}"

    color_echo GREEN "$NODE_INFO_HEADER"
    color_echo YELLOW "$VLESS_NODE_LINK"; echo "${VLESS_LINK}"; echo ""
    color_echo YELLOW "$SS_NODE_LINK"; echo "${SS_LINK}"
    color_echo GREEN "$NODE_INFO_FOOTER"
}

uninstall_xray() {
    read -rp "$PROMPT_UNINSTALL_CONFIRM" confirm
    if [[ "${confirm,,}" != "y" ]]; then color_echo YELLOW "$UNINSTALL_CANCELLED"; return; fi
    systemctl stop xray && systemctl disable xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    rm -rf "$XRAY_CONFIG_DIR"
    color_echo GREEN "$SUCCESS_XRAY_UNINSTALLED"
}

show_menu() {
    clear
    color_echo GREEN "$MENU_HEADER_1"; color_echo GREEN "$MENU_HEADER_2"; color_echo GREEN "$MENU_HEADER_1"
    echo -e "  ${BLUE}1. $MENU_OPTION_1"
    echo -e "  ${BLUE}2. $MENU_OPTION_2"
    echo -e "  ${BLUE}3. $MENU_OPTION_3"
    echo -e "  ${BLUE}4. $MENU_OPTION_4"
    echo -e "  ${BLUE}5. $MENU_OPTION_5"
    echo -e "  ${YELLOW}6. $MENU_OPTION_6"
    echo -e "  ${PLAIN}0. $MENU_OPTION_0"
    color_echo GREEN "$MENU_HEADER_1"
    read -rp "$PROMPT_MENU_CHOICE" choice

    case $choice in
        1) install_xray && configure_and_generate_links; pause ;;
        2) view_links; pause ;;
        3) systemctl restart xray; color_echo GREEN "$XRAY_SERVICE_RESTARTED"; sleep 2 ;;
        4) systemctl stop xray; color_echo GREEN "$XRAY_SERVICE_STOPPED"; sleep 2 ;;
        5) color_echo YELLOW "$VIEWING_LOGS"; journalctl -u xray -f --no-pager; pause ;;
        6) uninstall_xray; pause ;;
        0) exit 0 ;;
        *) color_echo RED "$ERROR_INVALID_OPTION"; sleep 2 ;;
    esac
}

# --- Script Entry Point ---
check_root
select_language
while true; do show_menu; done
