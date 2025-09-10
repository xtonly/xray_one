#!/bin/bash

# =================================================================
# VLESS+REALITY & Shadowsocks (SS2022) 配置生成脚本 (v4 - 健壮版)
#
# 该脚本会生成可直接导入客户端的分享链接。
# VLESS 节点备注为服务器的 hostname。
# Shadowsocks 节点备注为服务器的 hostname-SS。
#
# v4 更新日志:
# - 大幅增强公网 IP 检测的稳定性。
# - 轮询多个 IP 查询服务 (ipinfo.io, api.ipify.org, etc.)。
# - 对检测结果进行有效性验证，过滤掉 HTML 错误页面等无效内容。
# - 增加手动输入 IP 地址的 fallback 机制，确保脚本可用性。
# =================================================================

# --- 函数定义 ---

# 打印彩色信息
print_color() {
    case $1 in
        "green")
            echo -e "\033[32m$2\033[0m"
            ;;
        "red")
            echo -e "\033[31m$2\033[0m"
            ;;
        "yellow")
            echo -e "\033[33m$2\033[0m"
            ;;
        *)
            echo "$2"
            ;;
    esac
}

# 检查依赖
check_deps() {
    for cmd in curl openssl base64; do
        if ! command -v $cmd &> /dev/null; then
            print_color "red" "错误: 命令 '$cmd' 未找到。请先安装它。"
            exit 1
        fi
    done
    if ! command -v xray &> /dev/null; then
        print_color "yellow" "警告: 未检测到 xray。将使用 'openssl' 生成密钥。"
    fi
}

# 获取公网 IP 地址 (v4 增强版)
get_public_ip() {
    print_color "yellow" "正在检测服务器公网 IP 地址..."
    # 定义多个 IP 查询服务
    IP_SERVICES=(
        "https://ipinfo.io/ip"
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
        "https://ifconfig.me"
        "https://ip.sb"
    )
    
    PUBLIC_IP=""
    for service in "${IP_SERVICES[@]}"; do
        # 使用 curl 获取 IP，设置5秒超时，并模拟浏览器 User-Agent
        IP_CANDIDATE=$(curl -s -A "Mozilla/5.0" --connect-timeout 5 "$service")
        # 验证获取的是否为合法的 IP 地址格式
        if [[ "$IP_CANDIDATE" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            PUBLIC_IP=$IP_CANDIDATE
            break
        fi
    done

    # 如果自动检测失败，则请求用户手动输入
    if [ -z "$PUBLIC_IP" ]; then
        print_color "red" "自动检测公网 IP 失败。"
        read -p "请输入您的服务器公网 IP 地址: " PUBLIC_IP
        if [[ ! "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            print_color "red" "输入的 IP 地址格式不正确！"
            exit 1
        fi
    fi
    print_color "green" "服务器公网 IP: $PUBLIC_IP"
}


# --- 主逻辑开始 ---

clear
print_color "green" "============================================================"
print_color "green" "  VLESS+REALITY 和 Shadowsocks (SS2022) 配置生成器 (v4) "
print_color "green" "============================================================"
echo

# 检查依赖
check_deps

# --- 获取服务器信息 ---
get_public_ip
SERVER_ADDR="$PUBLIC_IP"
SERVER_HOSTNAME=$(hostname)
if [ -z "$SERVER_HOSTNAME" ]; then
    SERVER_HOSTNAME="MyServer" # 如果获取不到 hostname, 使用默认值
fi

echo

# --- VLESS + REALITY 配置 ---

print_color "yellow" "--- 正在生成 VLESS + REALITY 配置 ---"

UUID=$(cat /proc/sys/kernel/random/uuid)

if command -v xray &> /dev/null; then
    KEY_PAIR=$(xray x25519)
    PUBLIC_KEY=$(echo "$KEY_PAIR" | grep 'Public key' | awk '{print $3}')
else
    PUBLIC_KEY=$(openssl genpkey -algorithm x25519 -pubout -outform DER | base64 -w 0)
fi

SHORT_ID=$(openssl rand -hex 8)

read -p "请输入 VLESS 服务的端口 (默认 443): " VLESS_PORT
VLESS_PORT=${VLESS_PORT:-443}

read -p "请输入一个真实的、可访问的目标网站域名 (如 www.microsoft.com): " SNI
if [ -z "$SNI" ]; then
    print_color "red" "目标网站域名不能为空！"
    exit 1
fi

VLESS_REMARK="$SERVER_HOSTNAME"
VLESS_LINK="vless://${UUID}@${SERVER_ADDR}:${VLESS_PORT}?encryption=none&security=reality&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${VLESS_REMARK}"

echo
print_color "green" "✅ VLESS + REALITY 配置已生成！"
echo

# --- Shadowsocks 2022 配置 ---

print_color "yellow" "--- 正在生成 Shadowsocks (SS2022) 配置 ---"

echo "请选择 SS2022 加密方法:"
echo "1) 2022-blake3-aes-128-gcm (推荐)"
echo "2) 2022-blake3-aes-256-gcm"
read -p "请输入选项 [1-2] (默认 1): " SS_METHOD_CHOICE
case $SS_METHOD_CHOICE in
    2)
        SS_METHOD="2022-blake3-aes-256-gcm"
        ;;
    *)
        SS_METHOD="2022-blake3-aes-128-gcm"
        ;;
esac

if [[ "$SS_METHOD" == "2022-blake3-aes-128-gcm" ]]; then
    SS_PASSWORD=$(openssl rand -base64 16)
else
    SS_PASSWORD=$(openssl rand -base64 32)
fi

read -p "请输入 Shadowsocks 服务的端口 (默认 8443): " SS_PORT
SS_PORT=${SS_PORT:-8443}

USER_INFO_RAW="${SS_METHOD}:${SS_PASSWORD}"
USER_INFO_B64=$(echo -n "$USER_INFO_RAW" | base64 -w 0)

SS_REMARK="${SERVER_HOSTNAME}-SS"
SS_LINK="ss://${USER_INFO_B64}@${SERVER_ADDR}:${SS_PORT}#${SS_REMARK}"

echo
print_color "green" "✅ Shadowsocks (SS2022) 配置已生成！"
echo

# --- 显示结果 ---

print_color "green" "========================= 配置信息 (v4) ========================="
echo
print_color "yellow" "[VLESS + REALITY 节点链接]"
echo "${VLESS_LINK}"
echo
print_color "yellow" "[Shadowsocks (SS2022) 节点链接]"
echo "${SS_LINK}"
echo
print_color "green" "===================================================================="
print_color "green" "将以上链接直接复制到您的客户端中即可使用。"
echo
print_color "yellow" "注意：此脚本仅生成配置信息，您仍需在服务器上正确部署并运行相应的服务 (如 Xray) 以使节点生效。"
echo
