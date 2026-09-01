#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - UPDATE SCRIPT MENU (ADDON)
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

update_menu() {
  clear
  local local_v=$(get_local_version)

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}UPDATE SCRIPT${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Versi Terpasang" "$local_v"
  ui_kv "Sumber Update"   "$UPDATE_RAW"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -e "  ${CYAN}[*]${NC} Mengecek update terbaru..."

  local remote_v
  remote_v=$(check_update_available)
  local status=$?

  if [[ $status -ne 0 ]]; then
    echo -e "  ${GREEN}[✓] Sudah menggunakan versi terbaru, atau server update tidak terjangkau.${NC}"
    echo ""
    echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
    bash "$SCRIPT_DIR/menu.sh"
    return
  fi

  echo -e "  ${YELLOW}[!] Update tersedia${NC}: ${WHITE}$local_v${NC} → ${GREEN}$remote_v${NC}"
  echo ""
  echo -e "  ${WHITE}Catatan:${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  - Setiap file didownload ke lokasi sementara dahulu."
  echo -e "  - File yang sedang berjalan hanya diganti jika download berhasil."
  echo -e "  - Database akun (VMess/VLess/SSH) dan konfigurasi Nginx/Xray/SSL"
  echo -e "    yang sudah ada TIDAK akan dihapus atau ditimpa oleh update ini."
  echo -e "  - Jika sebuah file baru gagal didownload, file lama tetap dipakai."
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Lanjutkan update sekarang? [y/N]${NC}: "
  read -r c
  if [[ ! "$c" =~ ^[Yy]$ ]]; then
    echo -e "  ${YELLOW}Update dibatalkan${NC}"
    sleep 1; bash "$SCRIPT_DIR/menu.sh"; return
  fi

  echo ""
  echo -e "  ${CYAN}[*]${NC} Membackup konfigurasi sebelum update..."
  local backup_dir="/var/backups/vpn-script-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$backup_dir"
  cp -a "$SCRIPT_DIR" "$backup_dir/vpn-script" 2>/dev/null
  echo -e "  ${GREEN}[✓]${NC} Backup disimpan di ${WHITE}$backup_dir${NC}"
  echo ""

  run_update "$remote_v"

  echo ""
  echo -e "${GREEN}$LINE${NC}"
  echo -e "${WHITE}      ✓  UPDATE SELESAI (versi $remote_v)  ${NC}"
  echo -e "${GREEN}$LINE${NC}"
  echo -e "  Jika ada masalah, konfigurasi lama ada di:"
  echo -e "  ${WHITE}$backup_dir${NC}"
  echo -e "${GREEN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk membuka menu (versi baru)...${NC}"; read -r
  bash "$SCRIPT_DIR/menu.sh"
}

update_menu
