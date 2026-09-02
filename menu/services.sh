#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - SERVICE STATUS ON/OFF MENU (ADDON)
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

services_header() {
  clear
  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}STATUS LAYANAN (ON/OFF)${NC}"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  printf "  ${WHITE}%-4s %-24s %-14s %-10s${NC}\n" "NO" "LAYANAN" "STATUS" "INSTALLED"
  echo -e "  ${CYAN}$LINE${NC}"

  local i=1
  for svc in "${MANAGED_SERVICES[@]}"; do
    local name=$(service_display_name "$svc")
    local st inst
    if is_service_installed "$svc"; then
      inst="${GREEN}YA${NC}"
      systemctl is-active --quiet "$svc" && st="${GREEN}● ON${NC}" || st="${RED}● OFF${NC}"
    else
      inst="${DIM}TIDAK${NC}"
      st="${DIM}- N/A -${NC}"
    fi
    printf "  ${WHITE}[%-2s]${NC} %-24s " "$i" "$name"
    echo -ne "$st"
    printf "%*s" 6 ""
    echo -e "$inst"
    ((i++))
  done
  echo -e "  ${CYAN}$LINE${NC}"
}

services_menu() {
  services_header
  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_2col "$(ui_menu_num 1 'Start Layanan' "$GREEN")"     "$(ui_menu_num 2 'Stop Layanan' "$RED")"
  ui_2col "$(ui_menu_num 3 'Restart Layanan')"             "$(ui_menu_num 4 'Enable Auto-Start')"
  ui_2col "$(ui_menu_num 5 'Disable Auto-Start')"          ""
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "$(ui_menu_num 0 'Kembali ke Menu Utama' "$DIM")"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -ne "  ${WHITE}${BOLD}Pilih aksi [0-5]${NC} ${DIM}›${NC} "
  read -r action

  [[ "$action" == "0" ]] && { bash "$SCRIPT_DIR/menu.sh"; return; }
  if [[ ! "$action" =~ ^[1-5]$ ]]; then
    echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; services_menu; return
  fi

  echo ""
  echo -e "  ${WHITE}Pilih layanan (bisa lebih dari satu, pisahkan spasi, atau 'all'):${NC}"
  local i=1
  for svc in "${MANAGED_SERVICES[@]}"; do
    echo -e "    ${YELLOW}[$i]${NC} $(service_display_name "$svc")"
    ((i++))
  done
  echo -ne "  ${WHITE}Pilihan${NC}: "
  read -r picks

  local targets=()
  if [[ "$picks" == "all" ]]; then
    targets=("${MANAGED_SERVICES[@]}")
  else
    for p in $picks; do
      [[ "$p" =~ ^[0-9]+$ ]] && [[ $p -ge 1 && $p -le ${#MANAGED_SERVICES[@]} ]] \
        && targets+=("${MANAGED_SERVICES[$((p-1))]}")
    done
  fi

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo -e "  ${RED}[!] Tidak ada layanan valid dipilih${NC}"; sleep 2; services_menu; return
  fi

  echo ""
  for svc in "${targets[@]}"; do
    if ! is_service_installed "$svc"; then
      echo -e "  ${YELLOW}[!] $(service_display_name "$svc") belum terinstall, dilewati${NC}"
      continue
    fi
    case "$action" in
      1) service_toggle_start "$svc";   echo -e "  ${GREEN}[✓] $(service_display_name "$svc") distart${NC}" ;;
      2) service_toggle_stop "$svc";    echo -e "  ${YELLOW}[✓] $(service_display_name "$svc") dihentikan${NC}" ;;
      3) service_toggle_restart "$svc"; echo -e "  ${GREEN}[✓] $(service_display_name "$svc") direstart${NC}" ;;
      4) systemctl enable "$svc" 2>/dev/null;  echo -e "  ${GREEN}[✓] $(service_display_name "$svc") auto-start diaktifkan${NC}" ;;
      5) systemctl disable "$svc" 2>/dev/null; echo -e "  ${YELLOW}[✓] $(service_display_name "$svc") auto-start dinonaktifkan${NC}" ;;
    esac
  done

  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  services_menu
}

services_menu
