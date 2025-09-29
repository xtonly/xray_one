#!/bin/bash

#===============================================================================================
#
#          FILE: setup_time.sh
#
#         USAGE: sudo ./setup_time.sh
#
#   DESCRIPTION: 一个用于设置时区为香港、配置香港天文台NTP服务器并同步时间的自动化脚本。
#                支持手动同步和设置后台服务。优先使用 chrony。
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Gemini AI
#       VERSION: 1.5
#       CREATED: 2025-09-27
#      REVISION: 将NTP服务器更换为香港天文台官方服务器 (stdtime.gov.hk, time.hko.hk)。
#
#===============================================================================================

# --- 全局变量和配置 ---
TIMEZONE="Asia/Hong_Kong"
NTP_SERVERS=("stdtime.gov.hk" "time.hko.hk")

CHRONY_CONF="" # 将在此处动态查找路径

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- 函数定义 ---

# 检查脚本是否以root权限运行
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}错误：此脚本必须以 root 权限运行。${NC}"
        echo -e "${YELLOW}请尝试使用 'sudo ./setup_time.sh'${NC}"
        exit 1
    fi
}

# 动态查找 chrony 配置文件
find_chrony_conf() {
    # 仅当 CHRONY_CONF 为空时才查找
    if [ -n "$CHRONY_CONF" ]; then
        return
    fi

    local locations=(
        "/etc/chrony/chrony.conf"
        "/etc/chrony.conf"
    )
    for loc in "${locations[@]}"; do
        if [ -f "$loc" ]; then
            CHRONY_CONF="$loc"
            return
        fi
    done

    # 如果在标准位置未找到，则在 /etc 目录下搜索
    echo -e "${YELLOW}在标准位置未找到配置文件，正在尝试搜索 /etc 目录...${NC}"
    local found_path
    found_path=$(find /etc -name "chrony.conf" 2>/dev/null | head -n 1)
    if [ -n "$found_path" ] && [ -f "$found_path" ]; then
        CHRONY_CONF="$found_path"
        echo -e "${GREEN}成功找到配置文件: $CHRONY_CONF${NC}"
        sleep 1
    else
        CHRONY_CONF="" # 确认设置为空
    fi
}

# 检查并安装依赖
install_deps() {
    if ! command -v chronyc &> /dev/null; then
        echo -e "${YELLOW}未找到 chrony，正在尝试安装...${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y chrony
        elif command -v dnf &> /dev/null; then
            dnf install -y chrony
        elif command -v yum &> /dev/null; then
            yum install -y chrony
        else
            echo -e "${RED}无法确定包管理器，请手动安装 chrony。${NC}"
            exit 1
        fi
        if ! command -v chronyc &> /dev/null; then
             echo -e "${RED}chrony 安装失败，请检查您的系统和网络。${NC}"
             exit 1
        fi
    fi
    echo -e "${GREEN}依赖工具 'chrony' 已准备就绪。${NC}"
}

# 1. 设置系统时区为香港
set_timezone() {
    echo -e "\n${YELLOW}--- 1. 正在设置时区为: $TIMEZONE ---${NC}"
    timedatectl set-timezone "$TIMEZONE"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}时区设置成功！${NC}"
        echo -e "当前系统时间："
        timedatectl
    else
        echo -e "${RED}时区设置失败！${NC}"
    fi
    sleep 2
}

# 2. 立即手动同步时间
sync_now() {
    echo -e "\n${YELLOW}--- 2. 正在手动同步时间... ---${NC}"
    echo "使用服务器: ${NTP_SERVERS[0]}"

    systemctl stop chronyd 2>/dev/null
    systemctl stop ntpd 2>/dev/null

    if command -v ntpdate &> /dev/null; then
        ntpdate -u "${NTP_SERVERS[0]}"
    else
        echo "未找到 ntpdate, 使用 chronyd 进行一次性同步..."
        chronyd -q "server ${NTP_SERVERS[0]} iburst"
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}时间同步成功！${NC}"
    else
        echo -e "${RED}时间同步失败！请检查网络连接或NTP服务器地址。${NC}"
    fi

    if systemctl is-active --quiet chronyd; then
        systemctl start chronyd
    fi
    
    # 检查 hwclock 命令是否存在，如果存在则执行
    if command -v hwclock &> /dev/null; then
        hwclock -w
        echo "系统时间已写入硬件时钟。"
    else
        echo -e "${YELLOW}提示: 'hwclock' 命令未找到，跳过写入硬件时钟。这在容器或最小化系统中是正常的。${NC}"
    fi

    echo "当前时间: $(date)"
    sleep 2
}

# 3. 设置并开启后台自动同步
setup_background_sync() {
    find_chrony_conf
    if [ -z "$CHRONY_CONF" ]; then
        echo -e "${RED}错误：无法自动定位 chrony 配置文件。${NC}"
        return 1
    fi

    echo -e "\n${YELLOW}--- 3. 正在配置后台自动同步服务 (chrony)... ---${NC}"
    echo "使用配置文件: $CHRONY_CONF"

    cp "$CHRONY_CONF" "$CHRONY_CONF.bak.$(date +%F-%H%M%S)"
    echo "配置文件已备份到: $CHRONY_CONF.bak.$(date +%F-%H%M%S)"

    # 注释掉默认的 server/pool 配置
    sed -i -e 's/^\(server .*\)/#\1/g' -e 's/^\(pool .*\)/#\1/g' "$CHRONY_CONF"
    echo "已注释掉旧的服务器配置。"

    # 清理旧的脚本配置
    sed -i '/# Added by setup_time.sh/d' "$CHRONY_CONF"
    sed -i '/ntp.*.aliyun.com/d' "$CHRONY_CONF"
    sed -i '/stdtime.gov.hk/d' "$CHRONY_CONF"
    sed -i '/time.hko.hk/d' "$CHRONY_CONF"

    # 添加香港天文台 NTP 服务器
    {
        echo ""
        echo "# Added by setup_time.sh"
        for server in "${NTP_SERVERS[@]}"; do
            echo "server $server iburst"
        done
    } >> "$CHRONY_CONF"
    echo "已将香港天文台NTP服务器添加到配置文件。"

    echo "正在重启并设置 chrony 服务开机自启..."
    systemctl restart chronyd
    systemctl enable chronyd &>/dev/null # 将 enable 的输出重定向，避免显示 linked unit file 的提示

    if systemctl is-active --quiet chronyd; then
        echo -e "${GREEN}chrony 后台同步服务已成功配置并启动！${NC}"
        echo "等待几秒钟让服务稳定..."
        sleep 5
        chronyc sources
    else
        echo -e "${RED}chrony 服务启动失败！请使用 'systemctl status chronyd' 查看详情。${NC}"
    fi
    sleep 2
}

# 4. 显示当前时间和同步状态
show_status() {
    echo -e "\n${YELLOW}--- 4. 当前系统时间和NTP状态 ---${NC}"
    timedatectl
    echo "----------------------------------------"
    if command -v chronyc &> /dev/null && systemctl is-active --quiet chronyd; then
      echo "Chrony 同步源状态:"
      chronyc sources
    else
      echo "Chrony 服务未运行或未安装。"
    fi
    echo -e "${GREEN}检查完毕。${NC}"
    sleep 2
}

# --- 主菜单 ---
main_menu() {
    while true; do
        clear
        echo "================================================"
        echo "    香港天文台 NTP 时间同步与时区设置脚本 (v1.5)"
        echo "================================================"
        echo -e "请选择操作:"
        echo -e "  ${GREEN}1. 设置时区为 香港 (Asia/Hong_Kong)${NC}"
        echo -e "  ${GREEN}2. [手动] 立即同步一次时间${NC}"
        echo -e "  ${GREEN}3. [自动] 设置并开启后台同步服务 (推荐)${NC}"
        echo -e "  ${GREEN}4. 查看当前状态${NC}"
        echo -e "  ${RED}0. 退出脚本${NC}"
        echo "================================================"
        read -p "请输入选项 [1-4, 0]: " choice

        case $choice in
            1) set_timezone ;;
            2) sync_now ;;
            3) setup_background_sync ;;
            4) show_status ;;
            0) echo "退出脚本。"; exit 0 ;;
            *) echo -e "${RED}无效输入，请输入有效选项。${NC}"; sleep 2 ;;
        esac
        echo -e "\n按任意键返回主菜单..."
        read -n 1
    done
}

# --- 脚本主程序 ---
check_root
install_deps
main_menu
