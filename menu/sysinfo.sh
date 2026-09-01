#!/bin/bash
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sysinfo_menu() {
  clear
  local domain=$(get_domain)
  local ip=$(get_server_ip)
  local os=$(get_os_info)
  local kernel=$(get_kernel)
  local cpu_info=$(get_cpu_info)
  local cpu_cores=$(get_cpu_cores)
  local cpu_usage=$(get_cpu_usage)
  local mem=$(get_mem_usage)
  local disk=$(get_disk_usage)
  local uptime=$(get_uptime)
  local load=$(get_load_avg)
  local net=$(get_network_usage)
  local vmess_count=$(count_vmess)
  local vless_count=$(count_vless)

  local xray_st nginx_st db_st
  systemctl is-active --quiet xray     && xray_st="${GREEN}● RUNNING${NC}"  || xray_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet nginx    && nginx_st="${GREEN}● RUNNING${NC}" || nginx_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet dropbear && db_st="${GREEN}● RUNNING${NC}"    || db_st="${RED}● STOPPED${NC}"

  local ssl_exp="N/A"
  [[ -f /etc/ssl/xray/xray.crt ]] && \
    ssl_exp=$(openssl x509 -enddate -noout -in /etc/ssl/xray/xray.crt 2>/dev/null \
      | sed 's/notAfter=//')

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}INFORMASI SISTEM VPS${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${PURPLE}${BOLD}SERVER${NC}"
  ui_kv "OS"        "$os"
  ui_kv "Kernel"     "$kernel"
  ui_kv "IP Server"  "$ip"
  ui_kv "Domain"     "$domain"
  ui_kv "Uptime"     "$uptime"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${PURPLE}${BOLD}CPU & MEMORY${NC}"
  ui_kv "CPU Model"  "$cpu_info"
  ui_kv "CPU Cores"  "$cpu_cores core"
  ui_kv "CPU Usage"  "$cpu_usage %"
  ui_kv "Load Avg"   "$load"
  ui_kv "Memory"     "$mem"
  ui_kv "Disk"       "$disk"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${PURPLE}${BOLD}NETWORK${NC}"
  ui_kv "Traffic"    "$net"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${PURPLE}${BOLD}SERVICES${NC}"
  ui_2col "Xray  $xray_st" "Nginx  $nginx_st"
  ui_line "Dropbear  $db_st"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${PURPLE}${BOLD}SSL CERTIFICATE${NC}"
  ui_kv "Domain"   "$domain"
  ui_kv "Expired"  "$ssl_exp"
  ui_kv "Cert"     "/etc/ssl/xray/xray.crt"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${PURPLE}${BOLD}TUNNEL ACCOUNTS${NC}"
  ui_2col "VMess $vmess_count akun" "VLess $vless_count akun"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${PURPLE}${BOLD}PORTS${NC}"
  ui_kv "HTTP/nTLS"  "80"
  ui_kv "HTTPS/TLS"  "443"
  ui_kv "Dropbear"   "442, 109, 143"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"
  read -r
  bash $SCRIPT_DIR/menu.sh
}

sysinfo_menu
