#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - HAProxy Status & Toggle Menu
#   Menampilkan status HAProxy SSH-WS SSL dengan ON/OFF toggle
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

haproxy_header() {
  clear
  local haproxy_status
  if systemctl is-active --quiet haproxy 2>/dev/null; then
    haproxy_status="${GREEN}ON${NC}"
  else
    haproxy_status="${RED}OFF${NC}"
  fi

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}HAPROXY SSH-WS SSL${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Status"     "$haproxy_status"
  ui_kv "Port"       "${HAPROXY_SSL_PORT:-444}"
  ui_kv "Config"     "/etc/haproxy/conf.d/sshws-ssl.cfg"
  ui_kv "Cert"       "/etc/ssl/xray/xray.pem"
  ui_kv "Dashboard"  "127.0.0.1:8404/stats"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
}

haproxy_toggle_menu() {
  haproxy_header
  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_2col "$(ui_menu_num 1 'Start' "$GREEN")"       "$(ui_menu_num 2 'Stop' "$RED")"
  ui_2col "$(ui_menu_num 3 'Restart')"               "$(ui_menu_num 4 'Enable Auto-Start')"
  ui_2col "$(ui_menu_num 5 'Disable Auto-Start')"    "$(ui_menu_num 6 'Lihat Konfigurasi')"
  ui_2col "$(ui_menu_num 7 'Lihat Log')"             "$(ui_menu_num 8 'Check Konfigurasi')"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "$(ui_menu_num 0 'Kembali ke Menu Utama' "$DIM")"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -ne "  ${WHITE}${BOLD}Pilih aksi [0-8]${NC} ${DIM}›${NC} "
  read -r choice

  case "$choice" in
    0)
      bash "$SCRIPT_DIR/menu.sh"
      return
      ;;
    1)
      if [[ ! -f /etc/haproxy/conf.d/sshws-ssl.cfg ]]; then
        echo -e "\n${YELLOW}[*]${NC} HAProxy belum pernah dikonfigurasi, menjalankan setup dulu..."
        bash "$SCRIPT_DIR/addon/haproxy-sshws-ssl.sh"
      else
        echo -e "\n${CYAN}[*]${NC} Starting HAProxy..."
        systemctl start haproxy 2>/dev/null
      fi
      if systemctl is-active --quiet haproxy; then
        echo -e "${GREEN}[✓]${NC} HAProxy started successfully"
      else
        echo -e "${RED}[✗]${NC} HAProxy failed to start"
      fi
      sleep 2
      haproxy_toggle_menu
      ;;
    2)
      echo -e "\n${CYAN}[*]${NC} Stopping HAProxy..."
      systemctl stop haproxy 2>/dev/null
      echo -e "${YELLOW}[✓]${NC} HAProxy stopped"
      sleep 2
      haproxy_toggle_menu
      ;;
    3)
      echo -e "\n${CYAN}[*]${NC} Restarting HAProxy..."
      systemctl restart haproxy 2>/dev/null
      if systemctl is-active --quiet haproxy; then
        echo -e "${GREEN}[✓]${NC} HAProxy restarted successfully"
      else
        echo -e "${RED}[✗]${NC} HAProxy restart failed"
      fi
      sleep 2
      haproxy_toggle_menu
      ;;
    4)
      echo -e "\n${CYAN}[*]${NC} Enabling auto-start on boot..."
      systemctl enable haproxy 2>/dev/null
      echo -e "${GREEN}[✓]${NC} Auto-start enabled"
      sleep 2
      haproxy_toggle_menu
      ;;
    5)
      echo -e "\n${CYAN}[*]${NC} Disabling auto-start on boot..."
      systemctl disable haproxy 2>/dev/null
      echo -e "${YELLOW}[✓]${NC} Auto-start disabled"
      sleep 2
      haproxy_toggle_menu
      ;;
    6)
      echo -e "\n${CYAN}[*]${NC} HAProxy Configuration:"
      echo -e "${CYAN}$LINE${NC}"
      if [[ -f /etc/haproxy/conf.d/sshws-ssl.cfg ]]; then
        cat /etc/haproxy/conf.d/sshws-ssl.cfg
      else
        echo -e "${RED}[!] HAProxy SSH-WS SSL config not found${NC}"
      fi
      echo -e "${CYAN}$LINE${NC}"
      echo ""
      echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
      haproxy_toggle_menu
      ;;
    7)
      echo -e "\n${CYAN}[*]${NC} HAProxy Logs (last 50 lines):"
      echo -e "${CYAN}$LINE${NC}"
      journalctl -u haproxy -n 50 --no-pager 2>/dev/null || echo "No logs available"
      echo -e "${CYAN}$LINE${NC}"
      echo ""
      echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
      haproxy_toggle_menu
      ;;
    8)
      echo -e "\n${CYAN}[*]${NC} Checking HAProxy configuration..."
      echo -e "${CYAN}$LINE${NC}"
      haproxy -f /etc/haproxy/haproxy.cfg -c 2>&1
      echo -e "${CYAN}$LINE${NC}"
      echo ""
      echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
      haproxy_toggle_menu
      ;;
    *)
      echo -e "  ${RED}[!] Pilihan tidak valid${NC}"
      sleep 1
      haproxy_toggle_menu
      ;;
  esac
}

haproxy_toggle_menu
