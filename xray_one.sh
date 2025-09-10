#!/bin/bash

# =================================================================
# VLESS+REALITY & Shadowsocks (SS2022) 配置生成脚本 (v3 - 最终修正版)
#
# 该脚本会生成可直接导入客户端的分享链接。
# VLESS 节点备注为服务器的 hostname。
# Shadowsocks 节点备注为服务器的 hostname-SS。
#
# v3 更新日志:
# - 修正了服务器地址问题。脚本现在会自动检测并使用公网 IP 地址，
#   而不是使用本地 hostname 作为节点服务器地址。
#
# v2 更新日志:
# - 修正了 Shadowsocks (SS2022) URI 格式问题。
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
        print_color "yellow" "警告: 未检测到 xray。将使用 'openssl' 生成密钥，这可能不适用于所有 xray 版本。"
    fi
}

# 获取公网 IP 地址
get_public_ip() {
    print_color "yellow" "正在检测服务器公网 IP 地址..."
    PUBLIC_IP=$(curl -s https://ip.sb)
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP=$(curl -s https://ifconfig.me)
    fi
    if [ -z "$PUBLIC_IP" ]; then
        print_color "red" "错误: 无法检测到公网 IP 地址。请检查网络连接。"
        exit 1
    fi
    print_color "green" "服务器公网 IP: $PUBLIC_IP"
}


# --- 主逻辑开始 ---

clear
print_color "green" "============================================================"
print_color "green" "  VLESS+REALITY 和 Shadowsocks (SS2022) 配置生成器 (v3) "
print_color "green" "============================================================"
echo

# 检查依赖
check_deps

# --- 获取服务器信息 ---
# 【修正部分】获取公网 IP
get_public_ip
SERVER_ADDR="$PUBLIC_IP"
SERVER_HOSTNAME=$(hostname)
if [ -z "$SERVER_HOSTNAME" ]; then
    SERVER_HOSTNAME="MyServer" # 如果获取不到 hostname, 使用默认值
fi

echo

# --- VLESS + REALITY 配置 ---

print_color "yellow" "--- 正在生成 VLESS + REALITY 配置 ---"

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)

# 生成 X25519 密钥对
if command -v xray &> /dev/null; then
    KEY_PAIR=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEY_PAIR" | grep 'Private key' | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEY_PAIR" | grep 'Public key' | awk '{print $3}')
else
    # Fallback to openssl if xray is not installed
    PRIVATE_KEY=$(openssl genpkey -algorithm x25519 | openssl pkey -print_priv -outform DER | base64 -w 0)
    PUBLIC_KEY=$(openssl genpkey -algorithm x25519 -pubout -outform DER | base64 -w 0)
fi

# 生成 Short ID
SHORT_ID=$(openssl rand -hex 8)

# 提示用户输入端口和目标网站
read -p "请输入 VLESS 服务的端口 (默认 443): " VLESS_PORT
VLESS_PORT=${VLESS_PORT:-443}

read -p "请输入一个真实的、可访问的目标网站域名 (如 www.microsoft.com): " SNI
if [ -z "$SNI" ]; then
    print_color "red" "目标网站域名不能为空！"
    exit 1
fi

# 组装 VLESS 链接
VLESS_REMARK="$SERVER_HOSTNAME"
VLESS_LINK="vless://${UUID}@${SERVER_ADDR}:${VLESS_PORT}?encryption=none&security=reality&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${VLESS_REMARK}"

echo
print_color "green" "✅ VLESS + REALITY 配置已生成！"
echo

# --- Shadowsocks 2022 配置 ---

print_color "yellow" "--- 正在生成 Shadowsocks (SS2022) 配置 ---"

# 选择加密方法
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

# 根据加密方法生成相应长度的密码
if [[ "$SS_METHOD" == "2022-blake3-aes-128-gcm" ]]; then
    SS_PASSWORD=$(openssl rand -base64 16)
else
    SS_PASSWORD=$(openssl rand -base64 32)
fi

# 提示用户输入端口
read -p "请输入 Shadowsocks 服务的端口 (默认 8443): " SS_PORT
SS_PORT=${SS_PORT:-8443}

# 将 method:password 进行 Base64 编码
USER_INFO_RAW="${SS_METHOD}:${SS_PASSWORD}"
USER_INFO_B64=$(echo -n "$USER_INFO_RAW" | base64 -w 0)

# 组装 SS2022 链接
SS_REMARK="${SERVER_HOSTNAME}-SS"
SS_LINK="ss://${USER_INFO_B64}@${SERVER_ADDR}:${SS_PORT}#${SS_REMARK}"

echo
print_color "green" "✅ Shadowsocks (SS2022) 配置已生成！"
echo

# --- 显示结果 ---

print_color "green" "======================= 配置信息 (最终修正版) ======================="
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
