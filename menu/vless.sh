#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - VLESS MENU (ALL-IN-ONE)
#   Supports: WS (TLS + nTLS) + gRPC (TLS)
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

vless_header() {
  clear
  local domain=$(get_domain)
  local count=$(count_vless)
  local xray_st
  systemctl is-active --quiet xray \
    && xray_st="${GREEN}RUNNING${NC}" || xray_st="${RED}STOPPED${NC}"

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}VLESS WEBSOCKET${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Domain"      "$domain"
  ui_kv "Status Xray" "$xray_st"
  ui_kv "WS TLS"      "443 - /vless-ws"
  ui_kv "WS nTLS"     "80 - /vless-ntls"
  ui_kv "gRPC TLS"    "443 - vless-grpc"
  ui_kv "Total Akun"  "$count akun"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
}

vless_menu() {
  vless_header
  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_2col "$(ui_menu_num 1 'Buat Akun' "$GREEN")"    "$(ui_menu_num 2 'Info Akun' "$GREEN")"
  ui_2col "$(ui_menu_num 3 'Detail Akun' "$GREEN")"  "$(ui_menu_num 4 'Hapus Akun' "$RED")"
  ui_2col "$(ui_menu_num 5 'Perpanjang Akun')"        "$(ui_menu_num 6 'List Semua Akun' "$CYAN")"
  ui_2col "$(ui_menu_num 7 'Edit Limit & Kuota')"    "$(ui_menu_num 0 'Kembali' "$DIM")"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -ne "  ${WHITE}${BOLD}Pilih [0-7]${NC} ${DIM}›${NC} "
  read -r choice

  case "$choice" in
    1) do_create_vless ;;
    2) do_info_vless ;;
    3) do_detail_vless ;;
    4) do_delete_vless ;;
    5) do_renew_vless ;;
    6) do_list_vless ;;
    7) do_edit_limit_vless ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; vless_menu ;;
  esac
}

do_create_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}BUAT AKUN VLESS BARU${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username     ${NC}: "; read -r username
  [[ -z "$username" ]] && { echo -e "  ${RED}[!] Username kosong!${NC}"; sleep 2; vless_menu; return; }
  grep -q "^$username|" "$DB_VLESS" 2>/dev/null && { echo -e "  ${RED}[!] Username sudah ada!${NC}"; sleep 2; vless_menu; return; }
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Tipe Akun${NC}: ${GREEN}[1]${NC} Reguler (hari)   ${YELLOW}[2]${NC} Trial (jam)"
  echo -ne "  ${WHITE}Pilih [1/2]${NC} [default: 1]: "
  read -r tipe; tipe="${tipe:-1}"

  local days=0 trial_hours=0
  if [[ "$tipe" == "2" ]]; then
    echo -ne "  ${YELLOW}Durasi trial (jam)${NC} [default: ${TRIAL_HOURS_DEFAULT:-1}]: "
    read -r trial_hours; trial_hours="${trial_hours:-${TRIAL_HOURS_DEFAULT:-1}}"
    [[ ! "$trial_hours" =~ ^[0-9]+$ ]] && trial_hours="${TRIAL_HOURS_DEFAULT:-1}"
  else
    echo -ne "  ${YELLOW}Masa aktif (hari)${NC}: "
    read -r days; days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "  ${RED}[!] Harus angka!${NC}"; sleep 2; vless_menu; return; }
  fi

  echo -ne "  ${YELLOW}Limit Device/IP${NC} [default: ${IP_LIMIT_DEFAULT:-2}, 0=unlimited]: "
  read -r ip_limit; ip_limit="${ip_limit:-${IP_LIMIT_DEFAULT:-2}}"
  [[ ! "$ip_limit" =~ ^[0-9]+$ ]] && ip_limit="${IP_LIMIT_DEFAULT:-2}"

  echo -ne "  ${YELLOW}Limit Kuota (GB)${NC} [default: $(fmt_quota "$QUOTA_DEFAULT_MB"), 0=unlimited]: "
  read -r quota_gb
  local quota_mb
  if [[ -z "$quota_gb" ]]; then quota_mb="${QUOTA_DEFAULT_MB:-0}"
  elif [[ "$quota_gb" =~ ^[0-9]+$ ]]; then quota_mb=$(( quota_gb * 1024 ))
  else quota_mb="${QUOTA_DEFAULT_MB:-0}"; fi

  local uuid=$(create_vless "$username" "$days" "$ip_limit" "$quota_mb" "$trial_hours")
  local domain=$(get_domain)
  local exp masa_label
  if [[ "$trial_hours" -gt 0 ]]; then
    exp=$(get_vless_info "$username" | cut -d'|' -f3)
    masa_label="Trial ${trial_hours} jam"
  else
    exp=$(get_exp_date "$days")
    masa_label="${days} hari"
  fi
  local link_tls=$(gen_vless_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vless_link "$username" "$uuid" "$domain" "ntls")
  local link_grpc=$(gen_vless_grpc_link "$username" "$uuid" "$domain")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}           ✓  AKUN VLESS BERHASIL DIBUAT${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username        ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}UUID            ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${YELLOW}Domain          ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Dibuat          ${NC}: ${WHITE}$(date +"%Y-%m-%d")${NC}"
  echo -e "  ${YELLOW}Expired         ${NC}: ${WHITE}$exp${NC} ($masa_label)"
  echo -e "  ${YELLOW}Limit Device/IP ${NC}: ${WHITE}$(fmt_limit "$ip_limit")${NC}"
  echo -e "  ${YELLOW}Limit Kuota     ${NC}: ${WHITE}$(fmt_quota "$quota_mb")${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS TLS     ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Path ${WHITE}/vless-ws${NC}  TLS ${GREEN}ON${NC}"
  echo -e "  ${WHITE}WS nTLS    ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}80${NC}   Path ${WHITE}/vless-ntls${NC}  TLS ${RED}OFF${NC}"
  echo -e "  ${WHITE}gRPC TLS   ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Service ${WHITE}vless-grpc${NC}  TLS ${GREEN}ON${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS TLS:${NC}"
  echo -e "  ${GREEN}$link_tls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS nTLS:${NC}"
  echo -e "  ${YELLOW}$link_ntls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link gRPC TLS:${NC}"
  echo -e "  ${GREEN}$link_grpc${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vless_menu
}

do_info_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}INFO AKUN VLESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_vless_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }

  local uuid=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local ip_limit=$(echo "$info" | cut -d'|' -f5); ip_limit="${ip_limit:-${IP_LIMIT_DEFAULT:-2}}"
  local quota_mb=$(echo "$info" | cut -d'|' -f6); quota_mb="${quota_mb:-0}"
  local online=$(get_xray_user_online "$username")
  local used_mb=$(get_xray_user_traffic_mb "$username")
  local remaining=$(days_until_exp "$exp")
  local sc="${GREEN}"; local st="AKTIF"
  [[ $remaining -lt 0 ]] && { sc="${RED}";     st="EXPIRED"; }
  [[ $remaining -le 3 && $remaining -ge 0 ]] && { sc="${YELLOW}"; st="SEGERA EXPIRED"; }
  is_quota_disabled "vless" "$username" && { sc="${RED}"; st="SUSPENDED (kuota habis)"; }

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username        ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}UUID            ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${YELLOW}Dibuat          ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired         ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa            ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "  ${YELLOW}Status          ${NC}: ${sc}● $st${NC}"
  echo -e "  ${YELLOW}Device Aktif    ${NC}: ${WHITE}$online${NC} / ${WHITE}$(fmt_limit "$ip_limit")${NC}"
  echo -e "  ${YELLOW}Kuota Terpakai  ${NC}: ${WHITE}$(fmt_quota "$used_mb")${NC} / ${WHITE}$(fmt_quota "$quota_mb")${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vless_menu
}

do_edit_limit_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}EDIT LIMIT DEVICE/IP & KUOTA${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_vless_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }

  local cur_ip=$(echo "$info" | cut -d'|' -f5); cur_ip="${cur_ip:-${IP_LIMIT_DEFAULT:-2}}"
  local cur_quota=$(echo "$info" | cut -d'|' -f6); cur_quota="${cur_quota:-0}"

  echo -ne "  ${YELLOW}Limit Device/IP baru${NC} [saat ini: $(fmt_limit "$cur_ip")]: "
  read -r new_ip; new_ip="${new_ip:-$cur_ip}"; [[ ! "$new_ip" =~ ^[0-9]+$ ]] && new_ip="$cur_ip"

  echo -ne "  ${YELLOW}Limit Kuota baru (GB)${NC} [saat ini: $(fmt_quota "$cur_quota")]: "
  read -r new_gb
  local new_quota
  if [[ -z "$new_gb" ]]; then new_quota="$cur_quota"
  elif [[ "$new_gb" =~ ^[0-9]+$ ]]; then new_quota=$(( new_gb * 1024 ))
  else new_quota="$cur_quota"; fi

  edit_vless_limits "$username" "$new_ip" "$new_quota"
  echo -e "  ${GREEN}[✓] Limit '$username' diperbarui: device/IP=$(fmt_limit "$new_ip"), kuota=$(fmt_quota "$new_quota")${NC}"
  sleep 2
  vless_menu
}

do_detail_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}DETAIL AKUN VLESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_vless_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }

  local uuid=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local domain=$(get_domain)
  local remaining=$(days_until_exp "$exp")
  local link_tls=$(gen_vless_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vless_link "$username" "$uuid" "$domain" "ntls")
  local link_grpc=$(gen_vless_grpc_link "$username" "$uuid" "$domain")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DETAIL AKUN VLESS  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}UUID       ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${YELLOW}Encryption ${NC}: ${WHITE}none${NC}"
  echo -e "  ${YELLOW}Network    ${NC}: ${WHITE}WebSocket / gRPC${NC}"
  echo -e "  ${YELLOW}Dibuat     ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa       ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS TLS     ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Path ${WHITE}/vless-ws${NC}  TLS ${GREEN}ON${NC}"
  echo -e "  ${WHITE}WS nTLS    ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}80${NC}   Path ${WHITE}/vless-ntls${NC}  TLS ${RED}OFF${NC}"
  echo -e "  ${WHITE}gRPC TLS   ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Service ${WHITE}vless-grpc${NC}  TLS ${GREEN}ON${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS TLS:${NC}"
  echo -e "  ${GREEN}$link_tls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS nTLS:${NC}"
  echo -e "  ${YELLOW}$link_ntls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link gRPC TLS:${NC}"
  echo -e "  ${GREEN}$link_grpc${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vless_menu
}

do_delete_vless() {
  vless_header
  echo ""
  echo -e "  ${RED}HAPUS AKUN VLESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${YELLOW}Username yang dihapus${NC}: "; read -r username
  [[ -z "$(get_vless_info "$username")" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }
  echo -ne "  ${RED}Konfirmasi hapus '$username'? [y/N]${NC}: "; read -r c
  [[ ! "$c" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; vless_menu; return; }
  delete_vless "$username"
  echo -e "  ${GREEN}[✓] Akun '$username' dihapus!${NC}"; sleep 2; vless_menu
}

do_renew_vless() {
  vless_header
  echo ""
  echo -e "  ${YELLOW}PERPANJANG AKUN VLESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_vless_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }
  local old_exp=$(echo "$info" | cut -d'|' -f3)
  echo -e "  ${YELLOW}Expired saat ini${NC}: ${WHITE}$old_exp${NC}"
  echo -ne "  ${YELLOW}Perpanjang (hari)${NC}: "; read -r days; days=${days:-30}
  renew_vless "$username" "$days"
  echo -e "  ${GREEN}[✓] Diperpanjang hingga ${WHITE}$(get_exp_date "$days")${NC}"; sleep 2; vless_menu
}

do_list_vless_simple() {
  local count=0
  printf "  ${CYAN}%-20s %-36s %-12s %-8s${NC}\n" "USERNAME" "UUID" "EXPIRED" "LIMIT"
  echo -e "  ${CYAN}$LINE${NC}"
  while IFS='|' read -r user uuid exp created ip_limit quota_mb; do
    [[ -z "$user" ]] && continue
    local r=$(days_until_exp "$exp")
    local c="${WHITE}"
    [[ $r -lt 0 ]] && c="${RED}"
    [[ $r -le 3 && $r -ge 0 ]] && c="${YELLOW}"
    printf "  ${c}%-20s %-36s %-12s %-8s${NC}\n" "$user" "$uuid" "$exp" "$(fmt_limit "$ip_limit")"
    ((count++))
  done < <(list_vless)
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Total${NC}: ${WHITE}$count akun${NC}"
}

do_list_vless() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DAFTAR AKUN VLESS  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vless_menu
}

vless_menu
