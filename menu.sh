#!/bin/bash
# ============================================================
#   CHANELOG VPN TUNNEL MANAGER — PRO EDITION
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

show_header() {
  clear
  local domain=$(get_domain)
  local ip=$(get_server_ip)
  local os=$(get_os_info)
  local mem=$(get_mem_usage)
  local disk=$(get_disk_usage)
  local uptime=$(get_uptime)
  local load=$(get_load_avg)
  local cpu_cores=$(get_cpu_cores)
  local vmess_count=$(count_vmess)
  local vless_count=$(count_vless)
  local trojan_count=$(count_trojan)
  local ss_count=$(count_ss)
  local ssh_count=$(count_ssh)
  local total_akun=$((vmess_count + vless_count + trojan_count + ss_count + ssh_count))

  local mem_pct=$(echo "$mem" | grep -oP '\d+(?=%\))')
  local disk_pct=$(echo "$disk" | grep -oP '\d+(?=%\))')

  local xray_on=0 nginx_on=0 db_on=0 stunnel_on=0 haproxy_on=0
  systemctl is-active --quiet xray     && xray_on=1
  systemctl is-active --quiet nginx    && nginx_on=1
  systemctl is-active --quiet dropbear && db_on=1
  systemctl is-active --quiet stunnel4 2>/dev/null && stunnel_on=1
  systemctl is-active --quiet haproxy  2>/dev/null && haproxy_on=1

  local mux_badge="${DIM}nonaktif${NC}"
  [[ -f "$SCRIPT_DIR/.multiplex-443-active" ]] && mux_badge="${GREEN}aktif${NC}"

  local pro_badge="${DIM}belum di-setup${NC}"
  if [[ -f "$PRO_CONFIG" ]]; then
    if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
      pro_badge="${GREEN}aktif${NC}"
    else
      pro_badge="${GREEN}aktif${NC}"
    fi
  fi

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}CHANELOG VPN TUNNEL MANAGER${NC}"
  ui_line_center "${DIM}${PURPLE}BY CHANEL OG${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Domain"        "$domain"
  ui_kv "IP VPS"        "$ip"
  ui_kv "OS"            "$os"
  ui_kv "Uptime"        "$uptime"
  ui_kv "Load Average"  "$load"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${YELLOW}RAM ${NC} $(ui_bar "$mem_pct")  ${DIM}${mem}${NC}"
  ui_line "${YELLOW}Disk${NC} $(ui_bar "$disk_pct")  ${DIM}${disk}${NC}"
  ui_kv "CPU"           "${cpu_cores} core"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_2col "$(ui_dot $xray_on) Xray" "$(ui_dot $nginx_on) Nginx"
  ui_2col "$(ui_dot $db_on) Dropbear" "$(ui_dot $stunnel_on) Stunnel4"
  ui_2col "$(ui_dot $haproxy_on) HAProxy" ""
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Multiplex 443" "$mux_badge"
  ui_kv "Fitur"     "$pro_badge"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${WHITE}${BOLD}${total_akun}${NC}${WHITE} akun aktif${NC}"
  ui_line "${DIM}VMess ${vmess_count} · VLess ${vless_count} · Trojan ${trojan_count} · SS ${ss_count} · SSH ${ssh_count}${NC}"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
}

main_menu() {
  show_header
  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}MENU UTAMA${NC}"
  ui_section "  PROTOKOL"
  ui_2col "$(ui_menu_num 1 'SSH / SSH-WS')" "$(ui_menu_num 2 'VMess WS')"
  ui_2col "$(ui_menu_num 3 'VLess WS')"     "$(ui_menu_num 4 'Trojan WS/gRPC')"
  ui_2col "$(ui_menu_num 5 'Shadowsocks')"  ""
  ui_section "  SISTEM"
  ui_2col "$(ui_menu_num 6 'Nginx')"           "$(ui_menu_num 7 'Dropbear')"
  ui_2col "$(ui_menu_num 8 'HAProxy SSL')"     "$(ui_menu_num 9 'Change Domain')"
  ui_2col "$(ui_menu_num 10 'Update Script')"  "$(ui_menu_num 11 'Status Layanan')"
  ui_2col "$(ui_menu_num 12 'System Info')"    "$(ui_menu_num 13 'Bot Telegram')"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${PURPLE}${BOLD}  LAINNYA${NC}"
  ui_2col "$(ui_menu_num 14 'Uninstall' "$RED")" "$(ui_menu_num 15 'Rebuild OS' "$RED")"
  ui_line "$(ui_menu_num 0 'Exit' "$DIM")"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -ne "  ${WHITE}${BOLD}Pilih menu [0-15]${NC} ${DIM}›${NC} "
  read -r choice

  case "$choice" in
    1) bash $SCRIPT_DIR/menu/sshws.sh ;;
    2) bash $SCRIPT_DIR/menu/vmess.sh ;;
    3) bash $SCRIPT_DIR/menu/vless.sh ;;
    4) bash $SCRIPT_DIR/menu/trojan.sh ;;
    5) bash $SCRIPT_DIR/menu/ss.sh ;;
    6) bash $SCRIPT_DIR/menu/nginx.sh ;;
    7) bash $SCRIPT_DIR/menu/dropbear.sh ;;
    8) bash $SCRIPT_DIR/menu/haproxy.sh ;;
    9) bash $SCRIPT_DIR/menu/changedomain.sh ;;
    10) bash $SCRIPT_DIR/menu/update.sh ;;
    11) bash $SCRIPT_DIR/menu/services.sh ;;
    12) bash $SCRIPT_DIR/menu/sysinfo.sh ;;
    13) bash $SCRIPT_DIR/menu/telegram.sh ;;
    14) bash $SCRIPT_DIR/menu/uninstall.sh ;;
    15) bash $SCRIPT_DIR/menu/rebuild.sh ;;
    0) clear; exit 0 ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid!${NC}"; sleep 1; main_menu ;;
  esac
}

main_menu
