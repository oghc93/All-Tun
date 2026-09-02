#!/bin/bash
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

nginx_menu() {
  clear
  local domain=$(get_domain)
  local st
  systemctl is-active --quiet nginx \
    && st="${GREEN}● RUNNING${NC}" || st="${RED}● STOPPED${NC}"

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}NGINX MANAGEMENT${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Status" "$st"
  ui_kv "Domain" "$domain"
  ui_kv "Port"   "80 (nTLS) / 443 (TLS)"
  ui_kv "Config" "/etc/nginx/conf.d/xray.conf"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_2col "$(ui_menu_num 1 'Start' "$GREEN")"    "$(ui_menu_num 2 'Stop' "$RED")"
  ui_2col "$(ui_menu_num 3 'Restart')"           "$(ui_menu_num 4 'Reload' "$CYAN")"
  ui_2col "$(ui_menu_num 5 'Test Konfigurasi')"  "$(ui_menu_num 6 'Lihat Error Log')"
  ui_2col "$(ui_menu_num 7 'Lihat Konfigurasi')" "$(ui_menu_num 8 'Renew SSL Cert')"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "$(ui_menu_num 0 'Kembali ke Menu Utama' "$DIM")"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -ne "  ${WHITE}${BOLD}Pilih [0-8]${NC} ${DIM}›${NC} "
  read -r choice

  case "$choice" in
    1)
      systemctl start nginx 2>/dev/null \
        && echo -e "\n  ${GREEN}[✓] Nginx berhasil distart${NC}" \
        || echo -e "\n  ${RED}[!] Gagal start Nginx${NC}"
      sleep 2; nginx_menu ;;
    2)
      systemctl stop nginx 2>/dev/null \
        && echo -e "\n  ${YELLOW}[✓] Nginx dihentikan${NC}" \
        || echo -e "\n  ${RED}[!] Gagal stop Nginx${NC}"
      sleep 2; nginx_menu ;;
    3)
      systemctl restart nginx 2>/dev/null \
        && echo -e "\n  ${GREEN}[✓] Nginx direstart${NC}" \
        || echo -e "\n  ${RED}[!] Gagal restart Nginx${NC}"
      sleep 2; nginx_menu ;;
    4)
      systemctl reload nginx 2>/dev/null \
        && echo -e "\n  ${GREEN}[✓] Nginx direload${NC}" \
        || echo -e "\n  ${RED}[!] Gagal reload Nginx${NC}"
      sleep 2; nginx_menu ;;
    5)
      echo ""
      echo -e "  ${CYAN}$LINE${NC}"
      nginx -t 2>&1 | sed 's/^/  /'
      echo -e "  ${CYAN}$LINE${NC}"
      echo -ne "\n  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    6)
      echo ""
      echo -e "  ${CYAN}$LINE${NC}"
      tail -30 /var/log/nginx/error.log 2>/dev/null | sed 's/^/  /' \
        || echo -e "  ${YELLOW}Log kosong atau tidak ada${NC}"
      echo -e "  ${CYAN}$LINE${NC}"
      echo -ne "\n  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    7)
      echo ""
      echo -e "  ${CYAN}$LINE${NC}"
      cat /etc/nginx/conf.d/xray.conf 2>/dev/null | sed 's/^/  /' \
        || echo -e "  ${RED}[!] File tidak ditemukan${NC}"
      echo -e "  ${CYAN}$LINE${NC}"
      echo -ne "\n  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    8)
      local dom=$(get_domain)
      echo -e "\n  ${CYAN}[*]${NC} Renewing SSL untuk ${WHITE}$dom${NC}..."
      systemctl stop nginx 2>/dev/null
      /root/.acme.sh/acme.sh --renew -d "$dom" --ecc --force 2>/dev/null \
        && echo -e "  ${GREEN}[✓] SSL berhasil diperbarui${NC}" \
        || echo -e "  ${RED}[!] Renew gagal, cek log acme.sh${NC}"
      systemctl start nginx 2>/dev/null
      sleep 2; nginx_menu ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; nginx_menu ;;
  esac
}

nginx_menu
