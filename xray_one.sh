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
#      REVISION: 1.6 - [FEATURE] Added multilingual support (English/Chinese).
#                      The user is prompted to select a language at startup.
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

# --- Language Selection ---
select_language() {
    echo -e "${BLUE}Please select a language / 请选择语言:${PLAIN}"
    echo "1. English"
    echo "2. 中文"
    read -rp "Enter your choice [1-2]: " lang_choice

    case $lang_choice in
        1)
            source <(curl -sL https://raw.githubusercontent.com/spiritLHLS/ চর/main/language/xray_manager_en.sh)
            ;;
        2)
            source <(curl -sL https://raw.githubusercontent.com/spiritLHLS/ চর/main/language/xray_manager_zh.sh)
            ;;
        *)
            echo -e "${RED}Invalid selection, defaulting to English.${PLAIN}"
            source <(curl -sL https://raw.githubusercontent.com/spiritLHLS/ চর/main/language/xray_manager_en.sh)
            ;;
    esac
}

# --- Function Definitions ---

# Print colored information
color_echo() {
    echo -e "${!1}${2}${PLAIN}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        color_echo RED "$ERROR_MUST_BE_ROOT"
        exit 1
    fi
}

# Pause script and wait for user input
pause() {
    read -rp "$PRESS_ENTER_TO_CONTINUE"
}

# URL encode a string
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

# Get public IP address
get_public_ip() {
    color_echo YELLOW "$DETECTING_IP"
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
        color_echo RED "$ERROR_IP_DETECTION_FAILED"
        exit 1
    fi
    color_echo GREEN "$SERVER_IP_IS: $PUBLIC_IP"
}

# Install Xray
install_xray() {
    color_echo BLUE "$INSTALLING_XRAY"
    if command -v xray &>/dev/null; then
        color_echo GREEN "$XRAY_ALREADY_INSTALLED"
    fi
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    if ! command -v xray &>/dev/null; then
        color_echo RED "$ERROR_XRAY_INSTALL_FAILED"
        exit 1
    fi
    systemctl enable xray
    color_echo GREEN "$SUCCESS_XRAY_INSTALLED"
}

# Configure Xray and generate node information
configure_and_generate_links() {
    color_echo BLUE "$CONFIGURING_XRAY"

    read -rp "$PROMPT_VLESS_PORT" VLESS_PORT
    VLESS_PORT=${VLESS_PORT:-443}
    read -rp "$PROMPT_SS_PORT" SS_PORT
    SS_PORT=${SS_PORT:-8443}
    read -rp "$PROMPT_SNI" SNI
    if [ -z "$SNI" ]; then
        color_echo RED "$ERROR_SNI_EMPTY"
        return 1
    fi
    read -rp "$PROMPT_SNIFFING" SNIFFING_CHOICE
    SNIFFING_ENABLED="false"
    if [[ "${SNIFFING_CHOICE,,}" == "y" ]]; then
        SNIFFING_ENABLED="true"
    fi

    UUID=$(xray uuid)
    KEY_PAIR=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | grep -i "private" | cut -d':' -f2 | xargs)
    PUBLIC_KEY=$(echo "$KEY_PAIR" | grep -i "public" | cut -d':' -f2 | xargs)

    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        color_echo RED "$ERROR_KEY_GENERATION_FAILED"
        return 1
    fi

    SHORT_ID=$(openssl rand -hex 8)
    SS_METHOD="2022-blake3-aes-128-gcm"
    SS_PASSWORD=$(openssl rand -base64 16)
    FINGERPRINT="chrome"

    color_echo YELLOW "$WRITING_CONFIG"
    cat > "$XRAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0", "port": ${VLESS_PORT}, "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "show": false, "dest": "${SNI}:443", "xver": 0,
          "serverNames": [ "${SNI}" ],
          "privateKey": "${PRIVATE_KEY}", "shortIds": [ "${SHORT_ID}" ]
        }
      },
      "sniffing": {
        "enabled": ${SNIFFING_ENABLED},
        "destOverride": ["http", "tls"]
      }
    },
    {
      "listen": "0.0.0.0", "port": ${SS_PORT}, "protocol": "shadowsocks",
      "settings": { "method": "${SS_METHOD}", "password": "${SS_PASSWORD}" },
      "streamSettings": { "network": "tcp" }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "blocked" } ]
}
EOF

    get_public_ip
    SERVER_HOSTNAME=$(hostname)
    cat > "$NODE_INFO_FILE" <<EOF
VLESS_PORT="${VLESS_PORT}"
SS_PORT="${SS_PORT}"
UUID="${UUID}"
PUBLIC_KEY="${PUBLIC_KEY}"
SHORT_ID="${SHORT_ID}"
SNI="${SNI}"
FINGERPRINT="${FINGERPRINT}"
SS_METHOD="${SS_METHOD}"
SS_PASSWORD="${SS_PASSWORD}"
SERVER_IP="${PUBLIC_IP}"
HOSTNAME="${SERVER_HOSTNAME}"
EOF

    color_echo GREEN "$SUCCESS_CONFIG_WRITTEN"

    color_echo YELLOW "$CONFIGURING_FIREWALL"
    if command -v ufw &>/dev/null; then
        ufw allow ${VLESS_PORT}/tcp >/dev/null 2>&1
        ufw allow ${SS_PORT}/tcp >/dev/null 2>&1
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --zone=public --add-port=${VLESS_PORT}/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=${SS_PORT}/tcp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi

    systemctl restart xray
    if systemctl is-active --quiet xray; then
        color_echo GREEN "$SUCCESS_XRAY_STARTED"
    else
        color_echo RED "$ERROR_XRAY_START_FAILED"
        return 1
    fi

    view_links
}

# View node information
view_links() {
    if [ ! -f "$NODE_INFO_FILE" ]; then
        color_echo RED "$ERROR_NODE_FILE_NOT_FOUND"
        return
    fi

    source "$NODE_INFO_FILE"

    VLESS_REMARK_ENCODED=$(url_encode "${HOSTNAME}")
    SS_REMARK_ENCODED=$(url_encode "${HOSTNAME}-SS")

    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${VLESS_REMARK_ENCODED}"

    SS_USER_INFO_B64=$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w 0)
    SS_LINK="ss://${SS_USER_INFO_B64}@${SERVER_IP}:${SS_PORT}#${SS_REMARK_ENCODED}"

    color_echo GREEN "$NODE_INFO_HEADER"
    color_echo YELLOW "$VLESS_NODE_LINK"
    echo "${VLESS_LINK}"
    echo ""
    color_echo YELLOW "$SS_NODE_LINK"
    echo "${SS_LINK}"
    color_echo GREEN "$NODE_INFO_FOOTER"
}

# Uninstall Xray
uninstall_xray() {
    read -rp "$PROMPT_UNINSTALL_CONFIRM" confirm
    if [[ "${confirm,,}" != "y" ]]; then
        color_echo YELLOW "$UNINSTALL_CANCELLED"
        return
    fi

    systemctl stop xray
    systemctl disable xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    rm -rf "$XRAY_CONFIG_DIR"
    color_echo GREEN "$SUCCESS_XRAY_UNINSTALLED"
}

# Main menu
show_menu() {
    clear
    color_echo GREEN "$MENU_HEADER_1"
    color_echo GREEN "$MENU_HEADER_2"
    color_echo GREEN "$MENU_HEADER_1"
    color_echo BLUE "  1. $MENU_OPTION_1"
    color_echo BLUE "  2. $MENU_OPTION_2"
    color_echo BLUE "  3. $MENU_OPTION_3"
    color_echo BLUE "  4. $MENU_OPTION_4"
    color_echo BLUE "  5. $MENU_OPTION_5"
    color_echo YELLOW "  6. $MENU_OPTION_6"
    color_echo PLAIN "  0. $MENU_OPTION_0"
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
while true; do
    show_menu
done
