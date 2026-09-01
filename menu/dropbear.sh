#!/bin/bash
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

dropbear_menu() {
  clear
  local st port1 port2 port3
  systemctl is-active --quiet dropbear \
    && st="${GREEN}● RUNNING${NC}" || st="${RED}● STOPPED${NC}"

  port1=$(grep "DROPBEAR_PORT="    /etc/default/dropbear 2>/dev/null | cut -d= -f2)
  port2=$(grep "DROPBEAR_EXTRA"    /etc/default/dropbear 2>/dev/null | grep -oP '\-p \K[0-9]+' | head -1)
  port3=$(grep "DROPBEAR_EXTRA"    /etc/default/dropbear 2>/dev/null | grep -oP '\-p \K[0-9]+' | tail -1)
  port1=${port1:-442}; port2=${port2:-109}; port3=${port3:-143}

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}DROPBEAR SSH MANAGEMENT${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Status" "$st"
  ui_kv "Ports"  "$port1 / $port2 / $port3"
  ui_kv "Config" "/etc/default/dropbear"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_2col "$(ui_menu_num 1 'Start' "$GREEN")"    "$(ui_menu_num 2 'Stop' "$RED")"
  ui_2col "$(ui_menu_num 3 'Restart')"           "$(ui_menu_num 4 'Lihat Konfigurasi')"
  ui_2col "$(ui_menu_num 5 'Lihat Log')"         "$(ui_menu_num 6 'Ubah Port Utama')"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "$(ui_menu_num 0 'Kembali ke Menu Utama' "$DIM")"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -ne "  ${WHITE}${BOLD}Pilih [0-6]${NC} ${DIM}›${NC} "
  read -r choice

  case "$choice" in
    1)
      systemctl start dropbear 2>/dev/null \
        && echo -e "\n  ${GREEN}[✓] Dropbear berhasil distart${NC}" \
        || { service dropbear start 2>/dev/null; echo -e "\n  ${GREEN}[✓] Dropbear distart${NC}"; }
      sleep 2; dropbear_menu ;;
    2)
      systemctl stop dropbear 2>/dev/null \
        && echo -e "\n  ${YELLOW}[✓] Dropbear dihentikan${NC}" \
        || { service dropbear stop 2>/dev/null; echo -e "\n  ${YELLOW}[✓] Dropbear dihentikan${NC}"; }
      sleep 2; dropbear_menu ;;
    3)
      systemctl restart dropbear 2>/dev/null || service dropbear restart 2>/dev/null
      echo -e "\n  ${GREEN}[✓] Dropbear direstart${NC}"
      sleep 2; dropbear_menu ;;
    4)
      echo ""
      echo -e "  ${CYAN}$LINE${NC}"
      cat /etc/default/dropbear 2>/dev/null | sed 's/^/  /'
      echo -e "  ${CYAN}$LINE${NC}"
      echo -ne "\n  ${DIM}Tekan Enter...${NC}"; read -r; dropbear_menu ;;
    5)
      echo ""
      echo -e "  ${CYAN}$LINE${NC}"
      journalctl -u dropbear -n 20 --no-pager 2>/dev/null | sed 's/^/  /' \
        || tail -20 /var/log/syslog 2>/dev/null | grep -i dropbear | sed 's/^/  /' \
        || echo -e "  ${YELLOW}Tidak ada log tersedia${NC}"
      echo -e "  ${CYAN}$LINE${NC}"
      echo -ne "\n  ${DIM}Tekan Enter...${NC}"; read -r; dropbear_menu ;;
    6)
      echo ""
      echo -ne "  ${YELLOW}Port utama baru${NC}: "
      read -r newport
      if [[ "$newport" =~ ^[0-9]+$ && $newport -gt 0 && $newport -lt 65536 ]]; then
        sed -i "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=$newport/" /etc/default/dropbear
        systemctl restart dropbear 2>/dev/null || service dropbear restart 2>/dev/null
        echo -e "  ${GREEN}[✓] Port diubah ke ${WHITE}$newport${NC}"
      else
        echo -e "  ${RED}[!] Port tidak valid (1-65535)${NC}"
      fi
      sleep 2; dropbear_menu ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; dropbear_menu ;;
  esac
}

dropbear_menu
