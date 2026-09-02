#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - REBUILD OS VPS
#   Menjalankan script rebuild OS yang disediakan admin.
#   SANGAT DESTRUKTIF: install ulang OS, semua data & akun VPN
#   di VPS ini akan HILANG. Makanya pakai gate konfirmasi ketik
#   kata kunci, sama seperti menu Uninstall.
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

REBUILD_URL="https://raw.githubusercontent.com/RidwanzAnphelibelll/RebuildVPS/main/rebuild.sh"

rebuild_menu() {
  clear
  echo -e "${RED}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}!! REBUILD OS VPS !!${NC}"
  echo -e "${RED}$UI_BOX_MID${NC}"
  ui_line "${RED}PERINGATAN! TINDAKAN INI TIDAK DAPAT DIBATALKAN!${NC}"
  echo -e "${RED}$UI_BOX_BOT${NC}"
  echo ""
  echo -e "  ${WHITE}Yang akan terjadi:${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${RED}✗${NC}  OS VPS akan di-install ulang (rebuild) dari awal"
  echo -e "  ${RED}✗${NC}  SEMUA data di VPS ini hilang (akun VPN, config, dll)"
  echo -e "  ${RED}✗${NC}  Script VPN manager ini juga ikut terhapus"
  echo -e "  ${RED}✗${NC}  Koneksi SSH kemungkinan terputus di tengah proses"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Script yang akan dijalankan (disediakan admin):${NC}"
  echo -e "  ${DIM}$REBUILD_URL${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${RED}Ketik 'REBUILD' untuk konfirmasi${NC}: "
  read -r confirm

  if [[ "$confirm" != "REBUILD" ]]; then
    echo -e "\n  ${YELLOW}[!] Rebuild dibatalkan${NC}"
    sleep 2; bash "$SCRIPT_DIR/menu.sh"; return
  fi

  echo ""
  echo -ne "  ${RED}${BOLD}Yakin sekali? Ketik 'YA' untuk lanjut${NC}: "
  read -r confirm2
  if [[ "$confirm2" != "YA" ]]; then
    echo -e "\n  ${YELLOW}[!] Rebuild dibatalkan${NC}"
    sleep 2; bash "$SCRIPT_DIR/menu.sh"; return
  fi

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[*]${NC} Mengunduh & menjalankan script rebuild..."
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""

  wget -q "$REBUILD_URL" -O /tmp/rebuild.sh
  if [[ ! -s /tmp/rebuild.sh ]]; then
    echo -e "  ${RED}[!] Gagal mengunduh script rebuild dari:${NC}"
    echo -e "  ${DIM}$REBUILD_URL${NC}"
    echo -e "  ${YELLOW}Cek koneksi internet VPS / URL script, lalu coba lagi.${NC}"
    echo ""
    echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
    bash "$SCRIPT_DIR/menu.sh"; return
  fi

  bash /tmp/rebuild.sh
}

rebuild_menu
