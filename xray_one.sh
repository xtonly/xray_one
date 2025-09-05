#!/bin/bash
# Xray_One 多功能管理脚本 v1.0.4-custom (支持 Xray 25.9.5)
set -euo pipefail

readonly SCRIPT_VERSION="1.0.4 (Custom for Xray 25.9.5)"
readonly xray_config_path="/usr/local/etc/xray/config.json"
readonly xray_binary_path="/usr/local/bin/xray"
readonly xray_install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

# 颜色
readonly red='\e[91m' green='\e[92m' yellow='\e[93m' magenta='\e[95m' cyan='\e[96m' none='\e[0m'
xray_status_info=""; is_quiet=false

error()   { echo -e "\n${red}[✖] $1${none}\n" >&2; }
info()    { [[ "$is_quiet" = false ]] && echo -e "\n${yellow}[!] $1${none}\n"; }
success() { [[ "$is_quiet" = false ]] && echo -e "\n${green}[✔] $1${none}\n"; }

spinner(){
  local pid=$1; local spin='|/-\'
  while ps -p $pid &>/dev/null; do
    printf " [%c] " "${spin:0:1}"
    spin=${spin:1}${spin:0:1}; sleep .1; printf "\r"
  done; printf " \r"
}

get_public_ip(){
  for cmd in "curl -4s --max-time 5" "wget -4qO- --timeout=5"; do
    for url in "https://api.ipify.org" "https://ip.sb" "https://checkip.amazonaws.com"; do
      ip=$($cmd "$url" 2>/dev/null) && [[ -n "$ip" ]] && echo "$ip" && return
    done
  done
  for cmd in "curl -6s --max-time 5" "wget -6qO- --timeout=5"; do
    for url in "https://api64.ipify.org" "https://ip.sb"; do
      ip=$($cmd "$url" 2>/dev/null) && [[ -n "$ip" ]] && echo "$ip" && return
    done
  done
}

pre_check(){
  [[ "$(id -u)" != 0 ]] && error "请以 root 身份运行。" && exit 1
  [[ ! -f /etc/debian_version ]] && error "仅支持 Debian/Ubuntu 系统。" && exit 1
  for bin in jq curl; do
    if ! command -v "$bin" &>/dev/null; then
      info "安装缺失依赖：$bin"
      DEBIAN_FRONTEND=noninteractive apt-get update &>/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y jq curl &>/dev/null
      break
    fi
  done
}

check_xray_status(){
  if [[ ! -x "$xray_binary_path" ]]; then
    xray_status_info=" Xray 状态: ${red}未安装${none}"
  else
    ver=$("$xray_binary_path" version 2>/dev/null|head -n1|awk '{print $2}')
    st=$(systemctl is-active --quiet xray && echo "${green}运行中${none}" || echo "${yellow}未运行${none}")
    xray_status_info=" Xray 状态: ${green}已安装${none} | $st | 版本: ${cyan}$ver${none}"
  fi
}

# 写入配置
write_config(){
  local inb="$1"
  jq -n --argjson inbounds "$inb" \
    '{
      log:{loglevel:"warning"},
      inbounds:$inbounds,
      outbounds:[{protocol:"freedom",settings:{domainStrategy:"UseIPv4v6"}}]
    }' >"$xray_config_path"
}

generate_ss_key(){ openssl rand -base64 16; }

build_vless_inbound(){
  local p=$1 uuid=$2 d=$3 prikey=$4 pubkey=$5 sid="20220701"
  jq -n --argjson port "$p" \
        --arg uuid "$uuid" --arg domain "$d" \
        --arg private_key "$prikey" --arg public_key "$pubkey" \
        --arg shortid "$sid" \
  '{
    listen:"0.0.0.0",port:$port,protocol:"vless",
    settings:{clients:[{id:$uuid,flow:"xtls-rprx-vision"}],decryption:"none"},
    streamSettings:{
      network:"tcp",security:"reality",
      realitySettings:{
        show:false,dest:($domain+":443"),xver:0,
        serverNames:[$domain],privateKey:$private_key,
        publicKey:$public_key,shortIds:[$shortid]
      }
    },
    sniffing:{enabled:true,destOverride:["http","tls","quic"]}
  }'
}

build_ss_inbound(){
  local p=$1 pwd=$2
  jq -n --argjson port "$p" --arg password "$pwd" \
  '{
    listen:"0.0.0.0",port:$port,protocol:"shadowsocks",
    settings:{
      method:"2022-blake3-chacha20-poly1305",
      password:$password,
      mux:{enabled:false}
    }
  }'
}

run_core_install(){
  info "安装 Xray 核心..."
  curl -sL "$xray_install_script_url" | bash -s install &>/dev/null & spinner $!
  curl -sL "$xray_install_script_url" | bash -s install-geodata &>/dev/null & spinner $!
  success "Xray 核心及数据已安装。"
}

is_valid_port(){ [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
is_valid_domain(){ [[ "$1" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; }

restart_xray(){
  systemctl restart xray && success "Xray 重启成功。" || error "Xray 重启失败。"
}

view_all_info(){
  [[ ! -f "$xray_config_path" ]] && error "配置文件不存在。" && return
  clear; echo -e "${cyan} Xray 配置及订阅信息 ${none}"
  echo "───────────────────────────────────────────────────"
  local ip=$(get_public_ip) host=$(hostname)
  # VLESS
  local v=$(jq '.inbounds[]|select(.protocol=="vless")' "$xray_config_path"||echo)
  if [[ -n "$v" ]]; then
    local uuid=$(jq -r '.settings.clients[0].id' <<<"$v")
    local port=$(jq -r '.port'<<<"$v")
    local domain=$(jq -r '.streamSettings.realitySettings.serverNames[0]'<<<"$v")
    local pubkey=$(jq -r '.streamSettings.realitySettings.publicKey'<<<"$v")
    local sid=$(jq -r '.streamSettings.realitySettings.shortIds[0]'<<<"$v")
    echo -e "${green}[VLESS]${none}"
    echo " 地址: $ip"; echo " 端口: $port"; echo " UUID: $uuid"
    echo " 流控: xtls-rprx-vision"; echo " 安全: reality"; echo " SNI: $domain"
    echo " PublicKey: ${pubkey:0:20}..."; echo " ShortId: $sid"
    echo
  fi
  # SS
  local s=$(jq '.inbounds[]|select(.protocol=="shadowsocks")' "$xray_config_path"||echo)
  if [[ -n "$s" ]]; then
    local sp=$(jq -r '.port'<<<"$s")
    local method=$(jq -r '.settings.method'<<<"$s")
    local pwd=$(jq -r '.settings.password'<<<"$s")
    echo -e "${green}[Shadowsocks-2022]${none}"
    echo " 地址: $ip"; echo " 端口: $sp"; echo " 加密: $method"; echo " 密码: $pwd"
  fi
  echo "───────────────────────────────────────────────────"
}

# 安装函数
run_install_vless(){
  run_core_install
  info "生成 Reality 密钥对..."
  local kp=$("$xray_binary_path" x25519)
  local prikey=$(awk '/PrivateKey:/ {print $2}'<<<"$kp")
  local pubkey=$(awk '/PublicKey:/{print $2}'<<<"$kp")
  local p=$1 uuid=$2 d=$3
  local vb=$(build_vless_inbound "$p" "$uuid" "$d" "$prikey" "$pubkey")
  write_config "[$vb]"
  restart_xray; success "VLESS 安装完成！"; view_all_info
}

run_install_ss(){
  run_core_install
  local p=$1 pwd=$2
  local sb=$(build_ss_inbound "$p" "$pwd")
  write_config "[$sb]"
  restart_xray; success "Shadowsocks-2022 安装完成！"; view_all_info
}

run_install_dual(){
  run_core_install
  info "生成 Reality 密钥对..."
  local kp=$("$xray_binary_path" x25519)
  local prikey=$(awk '/PrivateKey:/ {print $2}'<<<"$kp")
  local pubkey=$(awk '/PublicKey:/{print $2}'<<<"$kp")
  local vp=$1 uuid=$2 d=$3 sp=$4 pwd=$5
  local vb=$(build_vless_inbound "$vp" "$uuid" "$d" "$prikey" "$pubkey")
  local sb=$(build_ss_inbound "$sp" "$pwd")
  write_config "[$vb,$sb]"
  restart_xray; success "双协议安装完成！"; view_all_info
}

# 菜单
main_menu(){
  while true; do
    clear
    echo -e "${cyan} Xray_One 管理脚本 ${none}   版本: $SCRIPT_VERSION"
    echo "───────────────────────────────────────────────────"
    check_xray_status; echo "$xray_status_info"; echo "───────────────────────────────────────────────────"
    echo "1. 安装/追加 VLESS   2. 安装/追加 SS"
    echo "3. 安装双协议       4. 更新 Xray"
    echo "5. 卸载 Xray       6. 查看日志"
    echo "7. 查看订阅信息     0. 退出"
    read -p "请选择 [0-7]: " c
    case $c in
      1) install_menu_vless;;
      2) install_menu_ss;;
      3) install_menu_dual;;
      4) run_core_install; press_any;;
      5) uninstall_xray; press_any;;
      6) journalctl -u xray -f; ;;
      7) view_all_info; press_any;;
      0) exit 0;;
      *) error "无效选项";;
    esac
  done
}

install_menu_vless(){
  read -p "VLESS 端口(默认25433): " vp; vp=${vp:-25433}
  read -p "UUID(留空自动生成): " uuid; uuid=${uuid:-$(cat /proc/sys/kernel/random/uuid)}
  read -p "SNI 域名(默认www.icloud.com): " d; d=${d:-www.icloud.com}
  run_install_vless "$vp" "$uuid" "$d"
}

install_menu_ss(){
  read -p "SS 端口(默认25338): " sp; sp=${sp:-25338}
  read -p "密码(留空自动生成): " pwd; pwd=${pwd:-$(generate_ss_key)}
  run_install_ss "$sp" "$pwd"
}

install_menu_dual(){
  read -p "VLESS 端口(默认25433): " vp; vp=${vp:-25433}
  read -p "UUID(留空自动): " uuid; uuid=${uuid:-$(cat /proc/sys/kernel/random/uuid)}
  read -p "SNI(默认www.icloud.com): " d; d=${d:-www.icloud.com}
  read -p "SS 端口(默认25338): " sp; sp=${sp:-25338}
  read -p "SS 密码(留空自动): " pwd; pwd=${pwd:-$(generate_ss_key)}
  run_install_dual "$vp" "$uuid" "$d" "$sp" "$pwd"
}

uninstall_xray(){
  read -p "确定卸载 Xray？[y/N]: " ans
  [[ $ans =~ ^[yY]$ ]] && bash <(curl -sL "$xray_install_script_url") remove --purge && rm -f "$xray_config_path"
}

press_any(){ read -n1 -rsp $'\n按任意键继续...' || true; }

# 主流程
pre_check
main_menu
