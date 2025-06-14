#!/usr/bin/env bash

#================================================================================
# Xray Ultimate Simplified Script (XUS)
#
# Version: 1.7.0 (Definitive Final Version)
# Author: AI Assistant & wuyou0789
# GitHub: (Host this on your own GitHub repository)
#
# This script installs and manages one specific setup: VLESS-XTLS-uTLS-REALITY.
# Designed to be invoked via a one-liner that handles download, execution, and cleanup.
# New in 1.7.0: Remembers user's domain/IP preference and improves menu display flow.
#================================================================================

# --- Script Environment ---
set -o pipefail
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
readonly SCRIPT_VERSION="1.7.0"
# These URLs are placeholders for the self-update feature.
readonly SCRIPT_URL="https://raw.githubusercontent.com/YourUsername/YourRepo/main/install.sh"
readonly VERSION_CHECK_URL="https://raw.githubusercontent.com/YourUsername/YourRepo/main/version.txt"

# --- Color Codes ---
readonly RED='\033[1;31m'
readonly GREEN='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# --- Configuration Paths ---
readonly SCRIPT_DIR="/usr/local/etc/xus-script"
readonly SCRIPT_SELF_PATH="${SCRIPT_DIR}/menu.sh"
readonly PREFS_FILE="${SCRIPT_DIR}/user_prefs.conf" # NEW: Preference file
readonly XRAY_CONFIG_FILE="/usr/local/etc/xray/config.json"
readonly XRAY_BIN_PATH="/usr/local/bin/xray"
readonly ALIAS_FILE="/etc/profile.d/xus-alias.sh"

# --- Logging and Status Functions ---
_info() { printf "${GREEN}[信息] %s${NC}\n" "$*" >&2; }
_warn() { printf "${YELLOW}[警告] %s${NC}\n" "$*" >&2; }
_error() { printf "${RED}[错误] %s${NC}\n" "$*" >&2; exit 1; }

# --- Prerequisite and Utility Functions ---

check_root() { [[ $EUID -ne 0 ]] && _error "此脚本必须以 root 权限运行。"; }
_exists() { command -v "$1" >/dev/null 2>&1; }
_os() {
    [[ -f "/etc/debian_version" ]] && source /etc/os-release && echo "$ID" && return
    [[ -f "/etc/redhat-release" ]] && echo "centos" && return
}

_install() {
    _info "正在安装软件包: $*"
    case "$(_os)" in
    centos) _exists "dnf" && dnf install -y "$@" || yum install -y "$@";;
    ubuntu|debian) apt-get update && apt-get install -y "$@";;
    *) _error "不支持的操作系统，请手动安装: $*";;
    esac
}

install_dependencies() {
    local pkgs_to_install=""
    ! _exists "curl" && pkgs_to_install+="curl "
    ! _exists "jq" && pkgs_to_install+="jq "
    ! _exists "openssl" && pkgs_to_install+="openssl "
    ! _exists "qrencode" && pkgs_to_install+="qrencode "
    if [[ -n "$pkgs_to_install" ]]; then
        _install $pkgs_to_install
    else
        _info "所需依赖均已安装。"
    fi
}

_systemctl() {
    local action="$1"
    _info "正在 ${action} Xray 服务..."
    systemctl "${action}" xray &>/dev/null
    sleep 1
    if ! systemctl is-active --quiet xray && [[ "$action" != "stop" ]]; then
        _warn "Xray 服务操作后状态异常，请检查日志！"
    else
        _info "Xray 服务 ${action} 完成。"
    fi
}

validate_dest_domain() {
    local prompt="请输入一个真实存在、可访问的【国外】域名作为回落目标 (例如: www.apple.com):"
    local new_dest
    while true; do
        read -p "$prompt " new_dest
        [[ -z "$new_dest" ]] && new_dest="www.apple.com" && _info "使用默认域名: www.apple.com"

        _info "正在严格验证域名 ${new_dest} 对 REALITY 的支持..."
        if echo "QUIT" | openssl s_client -connect "${new_dest}:443" -tls1_3 -servername "${new_dest}" 2>&1 | grep -q "X25519"; then
            _info "域名 ${new_dest} 验证通过！"
            break
        else
            prompt="${RED}域名 ${new_dest} 验证失败 (不支持TLSv1.3或REALITY所需加密套件)，请更换一个域名:${NC}"
        fi
    done
    echo "$new_dest"
}

# --- Core Logic ---

install_xray_core() {
    _info "正在使用官方脚本安装/更新 Xray-core..."
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root; then
        _info "Xray-core 安装成功。"
    else
        _error "Xray-core 安装失败，请检查网络或官方脚本输出。"
    fi
}

generate_xray_config() {
    # This function is now focused solely on generating the Xray config
    _info "--- 开始 Xray 配置向导 ---"
    read -p "请输入 Xray 监听端口 (1-65535, 默认 443): " xray_port
    [[ -z "$xray_port" ]] && xray_port=443
    local fallback_target=$(validate_dest_domain)
    # First, ensure xray binary is executable and available
    if ! _exists "$XRAY_BIN_PATH"; then
      install_xray_core
    fi
    read -p "请输入自定义 UUID (留空将自动生成): " client_uuid
    [[ -z "$client_uuid" ]] && client_uuid=$($XRAY_BIN_PATH uuid)

    local keys=$($XRAY_BIN_PATH x25519)
    local private_key=$(echo "$keys" | awk '/Private key/ {print $3}')
    local short_id=$(openssl rand -hex 8)

    _info "正在创建配置文件: ${XRAY_CONFIG_FILE}"
    mkdir -p /usr/local/etc/xray

    jq -n \
      --argjson port "$xray_port" --arg uuid "$client_uuid" --arg p_key "$private_key" \
      --arg s_id "$short_id" --arg target_domain "$fallback_target" \
      '{
        "log": {"loglevel": "warning"},
        "inbounds": [{
          "listen": "0.0.0.0", "port": $port, "protocol": "vless",
          "settings": {"clients": [{"id": $uuid, "flow": "xtls-rprx-vision"}], "decryption": "none"},
          "streamSettings": {
            "network": "raw", "security": "reality",
            "realitySettings": {
              "show": false, "target": ($target_domain + ":443"), "xver": 0,
              "serverNames": [$target_domain], "privateKey": $p_key, "shortIds": [$s_id]
            }
          },
          "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
        }],
        "outbounds": [
          {"protocol": "freedom", "tag": "direct"},
          {"protocol": "blackhole", "tag": "block"}
        ],
        "routing": {
          "domainStrategy": "AsIs",
          "rules": [
            {"type": "field", "outboundTag": "block", "ip": ["geoip:cn"], "ruleTag": "block-cn-ip"},
            {"type": "field", "outboundTag": "block", "domain": ["geosite:cn"], "ruleTag": "block-cn-domain"},
            {"type": "field", "outboundTag": "block", "protocol": ["bittorrent"], "ruleTag": "block-bittorrent"},
            {"type": "field", "outboundTag": "block", "ip": ["geoip:private"], "ruleTag": "block-private-ip"}
          ]
        }
      }' > "$XRAY_CONFIG_FILE" || _error "使用 jq 生成配置文件失败。"
    
    _info "配置文件生成成功。"
}

# UPDATE: Generic function to display a share link
# Takes address and remark as arguments
display_share_link() {
    local server_address="$1"
    local remark_name="$2"

    local config_data=$(jq -r '[
        .inbounds[0].port, .inbounds[0].settings.clients[0].id, .inbounds[0].streamSettings.realitySettings.privateKey,
        .inbounds[0].streamSettings.realitySettings.serverNames[0], .inbounds[0].streamSettings.realitySettings.shortIds[0]
    ] | @tsv' "$XRAY_CONFIG_FILE")
    read -r xray_port uuid private_key sni short_id <<< "$config_data"
    
    local public_key=$($XRAY_BIN_PATH x25519 -i "${private_key}" | awk '/Public key/ {print $3}')
    local vless_link="vless://${uuid}@${server_address}:${xray_port}?security=reality&encryption=none&pbk=${public_key}&host=${sni}&fp=chrome&sid=${short_id}&type=tcp&flow=xtls-rprx-vision&sni=${sni}#${remark_name}"

    clear
    _info "Xray 配置信息"
    echo -e "
  地址 (Address)   : ${YELLOW}${server_address}${NC}
  端口 (Port)      : ${YELLOW}${xray_port}${NC}
  用户 ID (UUID)   : ${YELLOW}${uuid}${NC}
  公钥 (PublicKey) : ${YELLOW}${public_key}${NC}
  短ID (ShortId)   : ${YELLOW}${short_id}${NC}
  目标域名 (SNI)   : ${YELLOW}${sni}${NC}

${BLUE}---------------- 分享链接 (备注: ${remark_name}) ----------------${NC}
${vless_link}
${BLUE}---------------- 二维码 ------------------${NC}"

    _exists "qrencode" && qrencode -t ANSIUTF8 -m 1 "${vless_link}" || \
    _warn "未找到 qrencode, 无法生成二维码。请运行 'apt install qrencode' 或 'yum install qrencode'。"
    
    echo -e "${BLUE}-------------------------------------------${NC}"
}

# NEW: View existing config based on saved preferences
view_existing_config() {
    [[ ! -f "$XRAY_CONFIG_FILE" ]] && _error "配置文件不存在！" && return
    
    local server_address
    # Read saved address from preference file
    if [[ -f "$PREFS_FILE" ]]; then
        source "$PREFS_FILE" # This will load SHARE_ADDRESS variable
    fi

    # If SHARE_ADDRESS is not set, fallback to auto-detecting IP
    if [[ -z "$SHARE_ADDRESS" ]]; then
        _info "未找到偏好设置，正在自动检测IP地址..."
        server_address=$(curl -s4 ip.sb || curl -s4 icanhazip.com || echo "your_server_ip")
    else
        server_address="$SHARE_ADDRESS"
    fi

    display_share_link "$server_address" "VLESS-XTLS-uTLS-REALITY"
}

# UPDATE: Interactively regenerate a share link and save the preference
regenerate_share_link() {
    [[ ! -f "$XRAY_CONFIG_FILE" ]] && _error "配置文件不存在！" && return
    
    clear
    _info "--- 重新生成分享链接 (交互式) ---"
    
    local server_address
    local auto_ip=$(curl -s4 ip.sb || curl -s4 icanhazip.com || echo "your_server_ip")
    
    read -p "是否为分享链接指定一个域名作为连接地址? (默认使用IP: ${auto_ip}) [y/N]: " use_domain
    if [[ "$use_domain" =~ ^[Yy]$ ]]; then
        read -p "请输入您的域名: " server_address
        [[ -z "$server_address" ]] && _error "域名不能为空！"
    else
        server_address="${auto_ip}"
        _info "使用服务器IP地址: ${server_address}"
    fi

    # NEW: Save the chosen address to the preference file
    echo "SHARE_ADDRESS=\"$server_address\"" > "$PREFS_FILE"
    _info "您的选择 '${server_address}' 已被保存为默认地址。"

    local remark_name
    read -p "请输入分享链接的备注名 (默认: VLESS-XTLS-uTLS-REALITY): " remark_name
    [[ -z "$remark_name" ]] && remark_name="VLESS-XTLS-uTLS-REALITY"

    display_share_link "$server_address" "$remark_name"
}

do_install() {
    check_root
    install_dependencies
    install_xray_core
    generate_xray_config

    mkdir -p "$SCRIPT_DIR"
    if ! cp -f "$0" "$SCRIPT_SELF_PATH"; then
      _error "无法复制脚本自身，请确保使用文件方式运行脚本！"
    fi
    chmod +x "$SCRIPT_SELF_PATH"
    echo "alias xs='bash ${SCRIPT_SELF_PATH}'" > "$ALIAS_FILE"
    source "$ALIAS_FILE"

    systemctl daemon-reload
    systemctl enable xray &>/dev/null
    _systemctl "restart"
    
    regenerate_share_link

    _info "安装完成！"
    _warn "为了确保 'xs' 命令在下次登录时可用，请重新连接您的 SSH 会话。"
}

do_uninstall() {
    check_root
    read -p "$(echo -e ${YELLOW}"确定要完全卸载 Xray 和本脚本吗? (y/n): "${NC})" choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        _systemctl "stop"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
        # Now also removes the preference file
        rm -rf "$SCRIPT_DIR" "$XRAY_CONFIG_FILE" "$ALIAS_FILE" "/etc/sysctl.d/99-xus.conf" "$PREFS_FILE"
        _info "Xray 已成功卸载。"
        _warn "请执行 'source /etc/profile' 或重新登录以移除旧的命令别名。"
    else
        _info "卸载操作已取消。"
    fi
}

# CRITICAL FIX: The main_menu function is now complete and updated.
main_menu() {
    clear
    local xray_status
    systemctl is-active --quiet xray && xray_status="${GREEN}运行中${NC}" || xray_status="${RED}已停止${NC}"

    echo -e "
${BLUE}Xray Ultimate Simplified Script | v${SCRIPT_VERSION}${NC}
${BLUE}===================================================${NC}
 Xray 状态: ${xray_status}
 Xray 版本: $(_exists xray && xray --version | head -n1 | awk '{print $2}' || echo "${RED}未安装${NC}")
 配置文件:  $([[ -f "$XRAY_CONFIG_FILE" ]] && echo "${GREEN}存在${NC}" || echo "${RED}不存在${NC}")
${BLUE}---------------------------------------------------${NC}
${GREEN}1.${NC}  完整安装 (覆盖当前配置)
${GREEN}2.${NC}  ${RED}卸载 Xray 和本脚本${NC}
${GREEN}3.${NC}  更新 Xray 内核至最新版

${GREEN}4.${NC}  启动 Xray      ${GREEN}5.${NC}  停止 Xray      ${GREEN}6.${NC}  重启 Xray
${BLUE}----------------- 配置管理 ------------------${NC}
${GREEN}101.${NC} 查看当前分享链接
${GREEN}102.${NC} 重新生成/自定义链接
${GREEN}103.${NC} 查看实时日志
${GREEN}104.${NC} 修改用户 ID (UUID)
${GREEN}105.${NC} 修改回落目标域名
${BLUE}---------------------------------------------------${NC}
${GREEN}0.${NC}  退出脚本
"
    read -rp "请输入选项: " option

    case "$option" in
    0) exit 0 ;;
    1) do_install ;;
    2) do_uninstall ;;
    3) install_xray_core && _systemctl "restart" ;;
    4) _systemctl "start" ;;
    5) _systemctl "stop" ;;
    6) _systemctl "restart" ;;
    101) view_existing_config ;;
    102) regenerate_share_link ;;
    103) journalctl -u xray -f --no-pager ;;
    104)
        read -p "请输入新 UUID (留空自动生成): " new_uuid
        [[ -z "$new_uuid" ]] && new_uuid=$($XRAY_BIN_PATH uuid)
        jq ".inbounds[0].settings.clients[0].id = \"$new_uuid\"" "$XRAY_CONFIG_FILE" >tmp.json && mv tmp.json "$XRAY_CONFIG_FILE"
        _systemctl "restart" && regenerate_share_link
        ;;
    105)
        local new_dest=$(validate_dest_domain)
        jq ".inbounds[0].streamSettings.realitySettings.target = \"${new_dest}:443\" | .inbounds[0].streamSettings.realitySettings.serverNames = [\"$new_dest\"]" "$XRAY_CONFIG_FILE" >tmp.json && mv tmp.json "$XRAY_CONFIG_FILE"
        _systemctl "restart" && regenerate_share_link
        ;;
    *) _warn "无效的选项。" ;;
    esac
    
    # CRITICAL FIX: The pause logic is now active for all relevant options
    if [[ "$option" != "103" && "$option" != "0" ]]; then
        echo && read -n 1 -s -r -p "按任意键返回主菜单..."
    fi
}


# --- Script Entry Point ---
if [[ "$1" == "install" ]]; then
    do_install
else
    check_root
    if [[ ! -f "$XRAY_CONFIG_FILE" ]]; then
      _warn "未找到 Xray 配置文件。"
      read -p "是否立即开始安装? (y/n): " choice
      [[ "$choice" =~ ^[Yy]$ ]] && do_install
      exit 0
    fi
    while true; do main_menu; done
fi
