#!/bin/bash
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

uninstall_menu() {
  clear
  echo -e "${RED}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}!! UNINSTALL SCRIPT !!${NC}"
  echo -e "${RED}$UI_BOX_BOT${NC}"
  echo ""
  echo -e "  ${RED}PERINGATAN! TINDAKAN INI TIDAK DAPAT DIBATALKAN!${NC}"
  echo ""
  echo -e "  ${WHITE}Yang akan dihapus:${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${RED}✗${NC}  Xray-core dan semua konfigurasi"
  echo -e "  ${RED}✗${NC}  Konfigurasi Nginx VPN"
  echo -e "  ${RED}✗${NC}  SSL Certificate (/etc/ssl/xray)"
  echo -e "  ${RED}✗${NC}  Semua database akun VMess & VLess"
  echo -e "  ${RED}✗${NC}  Script /etc/vpn-script"
  echo -e "  ${RED}✗${NC}  Command vpn (/usr/local/bin/vpn)"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -e "  ${WHITE}Yang TIDAK dihapus:${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}✓${NC}  User system yang ada"
  echo -e "  ${GREEN}✓${NC}  Nginx (hanya config VPN yang dihapus)"
  echo -e "  ${GREEN}✓${NC}  Dropbear (service tetap ada)"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${RED}Ketik 'HAPUS' untuk konfirmasi${NC}: "
  read -r confirm

  if [[ "$confirm" != "HAPUS" ]]; then
    echo -e "\n  ${YELLOW}[!] Uninstall dibatalkan${NC}"
    sleep 2; bash $SCRIPT_DIR/menu.sh; return
  fi

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[*]${NC} Menghentikan layanan..."
  systemctl stop xray 2>/dev/null
  systemctl disable xray 2>/dev/null

  echo -e "  ${CYAN}[*]${NC} Menghapus Xray..."
  rm -f /usr/local/bin/xray
  rm -rf /etc/xray
  rm -rf /var/log/xray
  rm -f /etc/systemd/system/xray.service

  echo -e "  ${CYAN}[*]${NC} Menghapus konfigurasi Nginx..."
  rm -f /etc/nginx/conf.d/xray.conf
  systemctl restart nginx 2>/dev/null

  echo -e "  ${CYAN}[*]${NC} Menghapus SSL certificate..."
  local dom=$(get_domain)
  /root/.acme.sh/acme.sh --remove -d "$dom" --ecc 2>/dev/null
  rm -rf /etc/ssl/xray

  echo -e "  ${CYAN}[*]${NC} Menghapus script dan database..."
  rm -f /usr/local/bin/vpn
  rm -rf $SCRIPT_DIR

  echo -e "  ${CYAN}[*]${NC} Membersihkan cron jobs..."
  crontab -l 2>/dev/null | grep -v "vpn-script\|acme.sh --cron" | crontab -

  systemctl daemon-reload 2>/dev/null

  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -e "${GREEN}$LINE${NC}"
  echo -e "${WHITE}           ✓  UNINSTALL SELESAI!${NC}"
  echo -e "${GREEN}$LINE${NC}"
  echo -e "  Semua komponen VPN telah dihapus dari sistem."
  echo -e "${GREEN}$LINE${NC}"
  echo ""
  exit 0
}

uninstall_menu
