#!/bin/bash

# =================================================================
# VLESS+REALITY & Shadowsocks (SS2022) 配置生成脚本
#
# 该脚本会生成可直接导入客户端的分享链接。
# VLESS 节点备注为服务器的 hostname。
# Shadowsocks 节点备注为服务器的 hostname-SS。
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
    if ! command -v xray &> /dev/null; then
        print_color "yellow" "警告: 未检测到 xray。将使用 'openssl' 生成密钥，这可能不适用于所有 xray 版本。"
        if ! command -v openssl &> /dev/null; then
            print_color "red" "错误: 'openssl' 也未安装。请先安装 'openssl' 或 'xray'。"
            exit 1
        fi
    fi
}

# --- 主逻辑开始 ---

clear
print_color "green" "============================================================"
print_color "green" "      VLESS+REALITY 和 Shadowsocks (SS2022) 配置生成器     "
print_color "green" "============================================================"
echo

# 检查依赖
check_deps

# --- VLESS + REALITY 配置 ---

print_color "yellow" "--- 正在生成 VLESS + REALITY 配置 ---"

# 获取服务器 IP 或主机名 (优先使用 hostname)
SERVER_HOST=$(hostname)
if [ -z "$SERVER_HOST" ]; then
    print_color "red" "无法获取服务器主机名，请检查您的系统配置。"
    exit 1
fi

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
# 格式: vless://uuid@hostname:port?encryption=none&security=reality&sni=sni_domain&pbk=public_key&sid=short_id&type=tcp#remark
VLESS_LINK="vless://${UUID}@${SERVER_HOST}:${VLESS_PORT}?encryption=none&security=reality&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${SERVER_HOST}"

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

# 组装 SS2022 链接
# 格式: ss://method:password@hostname:port#remark
SS_REMARK="${SERVER_HOST}-SS"
SS_LINK="ss://${SS_METHOD}:${SS_PASSWORD}@${SERVER_HOST}:${SS_PORT}#${SS_REMARK}"

echo
print_color "green" "✅ Shadowsocks (SS2022) 配置已生成！"
echo

# --- 显示结果 ---

print_color "green" "======================= 配置信息 ======================="
echo
print_color "yellow" "[VLESS + REALITY 节点链接]"
echo "${VLESS_LINK}"
echo
print_color "yellow" "[Shadowsocks (SS2022) 节点链接]"
echo "${SS_LINK}"
echo
print_color "green" "=========================================================="
print_color "green" "将以上链接直接复制到您的客户端中即可使用。"
echo
print_color "yellow" "注意：此脚本仅生成配置信息，您仍需在服务器上正确部署并运行相应的服务 (如 Xray) 以使节点生效。"
echo
