#!/bin/bash

#====================================================================================
#
#          FILE: xray_manager.sh
#
#         USAGE: bash xray_manager.sh
#
#   DESCRIPTION: An all-in-one script for installing, configuring, managing, and uninstalling Xray.
#                Supports VLESS+REALITY and Shadowsocks-2022.
#
#      REVISION: 2.0 - [Feature Update & Fix] Addressed VLESS connectivity issues and
#                      incorporated new features from recent Xray versions.
#                      Updated cipher suites and improved configuration options.
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

# --- Function Definitions ---

# Print colorful information
color_echo() {
    echo -e "${!1}${2}${PLAIN}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        color_echo RED "Error: This script must be run as root!"
        exit 1
    fi
}

# Pause the script and wait for user input
pause() {
    read -rp "Press [Enter] to return to the main menu..."
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

# Get the public IP address
get_public_ip() {
    color_echo YELLOW "Detecting server public IP address..."
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
        color_echo RED "Failed to detect public IP. Please check your network or try again later."
        exit 1
    fi
    color_echo GREEN "Server Public IP: $PUBLIC_IP"
}

# Install Xray
install_xray() {
    color_echo BLUE ">>> Installing Xray..."
    if command -v xray &>/dev/null; then
        color_echo GREEN "Xray is already installed. An update will be performed."
    fi
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    if ! command -v xray &>/dev/null; then
        color_echo RED "Xray installation failed or not found in PATH! Please check the installation log."
        exit 1
    fi
    systemctl enable xray
    color_echo GREEN "Xray installed/updated successfully!"
}

# Configure Xray and generate node information
configure_and_generate_links() {
    color_echo BLUE ">>> Configuring Xray and generating nodes for you..."

    read -rp "Enter VLESS service port (default 443): " VLESS_PORT
    VLESS_PORT=${VLESS_PORT:-443}
    read -rp "Enter Shadowsocks service port (default 8443): " SS_PORT
    SS_PORT=${SS_PORT:-8443}
    read -rp "Enter a real, accessible destination domain (e.g., www.microsoft.com): " SNI
    if [ -z "$SNI" ]; then
        color_echo RED "Destination domain cannot be empty!"
        return 1
    fi
    read -rp "Enter xver value for REALITY (0 for no forwarding, 1 for forwarding, default 0): " XVER
    XVER=${XVER:-0}

    UUID=$(xray uuid)
    KEY_PAIR=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | grep -i "private" | cut -d':' -f2 | xargs)
    PUBLIC_KEY=$(echo "$KEY_PAIR" | grep -i "public" | cut -d':' -f2 | xargs)

    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        color_echo RED "Error: Failed to generate REALITY key pair! Please run 'xray x25519' manually to check for errors."
        return 1
    fi

    SHORT_ID=$(openssl rand -hex 8)
    SS_METHOD="2022-blake3-aes-128-gcm"
    SS_PASSWORD=$(openssl rand -base64 16)

    color_echo YELLOW "Writing server configuration file..."
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
          "show": false, "dest": "${SNI}:443", "xver": ${XVER},
          "serverNames": [ "${SNI}" ],
          "privateKey": "${PRIVATE_KEY}", "shortIds": [ "${SHORT_ID}" ]
        }
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
SS_METHOD="${SS_METHOD}"
SS_PASSWORD="${SS_PASSWORD}"
SERVER_IP="${PUBLIC_IP}"
HOSTNAME="${SERVER_HOSTNAME}"
EOF

    color_echo GREEN "Server configuration written successfully!"

    color_echo YELLOW "Configuring firewall..."
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
        color_echo GREEN "Xray started successfully!"
    else
        color_echo RED "Xray failed to start! Please use menu option 5 to view logs and diagnose the issue."
        return 1
    fi

    view_links
}

# View node information
view_links() {
    if [ ! -f "$NODE_INFO_FILE" ]; then
        color_echo RED "Node information file not found. Please run the installation and configuration first."
        return
    fi

    source "$NODE_INFO_FILE"

    VLESS_REMARK_ENCODED=$(url_encode "${HOSTNAME}")
    SS_REMARK_ENCODED=$(url_encode "${HOSTNAME}-SS")

    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&security=reality&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${VLESS_REMARK_ENCODED}"

    SS_USER_INFO_B64=$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w 0)
    SS_LINK="ss://${SS_USER_INFO_B64}@${SERVER_IP}:${SS_PORT}#${SS_REMARK_ENCODED}"

    color_echo GREEN "====================== Your Node Information ======================"
    color_echo YELLOW "[VLESS + REALITY Node Link]"
    echo "${VLESS_LINK}"
    echo ""
    color_echo YELLOW "[Shadowsocks (SS2022) Node Link]"
    echo "${SS_LINK}"
    color_echo GREEN "=========================================================="
}

# Uninstall Xray
uninstall_xray() {
    read -rp "Are you sure you want to uninstall Xray? (y/N): " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        color_echo YELLOW "Uninstall operation canceled."
        return
    fi

    systemctl stop xray
    systemctl disable xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    rm -rf "$XRAY_CONFIG_DIR"
    color_echo GREEN "Xray has been successfully uninstalled!"
}

# Main menu
show_menu() {
    clear
    color_echo GREEN "=========================================================="
    color_echo GREEN "          Xray All-in-One Management Script v2.0 (VLESS/SS)"
    color_echo GREEN "=========================================================="
    color_echo BLUE "  1. Install and Configure Xray (Select for first time/reconfiguration)"
    color_echo BLUE "  2. View Node Information"
    color_echo BLUE "  3. Restart Xray Service"
    color_echo BLUE "  4. Stop Xray Service"
    color_echo BLUE "  5. View Xray Status and Logs"
    color_echo YELLOW "  6. Uninstall Xray"
    color_echo PLAIN "  0. Exit Script"
    color_echo GREEN "=========================================================="
    read -rp "Please enter your choice [0-6]: " choice

    case $choice in
        1) install_xray && configure_and_generate_links; pause ;;
        2) view_links; pause ;;
        3) systemctl restart xray; color_echo GREEN "Xray service has been restarted."; sleep 2 ;;
        4) systemctl stop xray; color_echo GREEN "Xray service has been stopped."; sleep 2 ;;
        5) color_echo YELLOW "Viewing real-time Xray logs, press Ctrl+C to exit..."; journalctl -u xray -f --no-pager; pause ;;
        6) uninstall_xray; pause ;;
        0) exit 0 ;;
        *) color_echo RED "Invalid option, please enter a correct number."; sleep 2 ;;
    esac
}

# --- Script Main Entry ---
check_root
while true; do
    show_menu
done
