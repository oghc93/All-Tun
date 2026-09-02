#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - SSH / SSH-WS / SSH-SSL MENU (ADDON)
#   Multi-port: 80, 8880, 8080, 2080, 2082 (nTLS) + 443 (TLS)
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sshws_addon_missing() {
  [[ ! -f /usr/local/bin/ws-dropbear || ! -f /usr/local/bin/ws-openssh ]] || ! is_service_installed stunnel4
}

sshws_offer_install() {
  clear
  echo -e "${YELLOW}$LINE${NC}"
  echo -e "${WHITE}   FITUR SSH-WS / SSH-SSL BELUM DIINSTALL${NC}"
  echo -e "${YELLOW}$LINE${NC}"
  echo ""
  echo -e "  Fitur ini butuh komponen tambahan (stunnel4 + ws-dropbear/ws-openssh)."
  echo -e "  Instalasi bersifat aditif dan TIDAK mengubah/menghentikan"
  echo -e "  layanan VMess/VLess/Trojan/SS/Nginx/Dropbear yang sudah berjalan."
  echo ""
  echo -ne "  ${WHITE}Install sekarang? [Y/n]${NC}: "
  read -r c
  if [[ "$c" =~ ^[Nn]$ ]]; then
    bash "$SCRIPT_DIR/menu.sh"; return 1
  fi
  bash "$SCRIPT_DIR/addon/install-sshws.sh"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk lanjut...${NC}"; read -r
  return 0
}

sshws_header() {
  clear
  local domain=$(get_domain)
  local count=$(count_ssh)
  local db_st stunnel_st wsd_st wso_st
  systemctl is-active --quiet dropbear     && db_st="${GREEN}RUNNING${NC}"     || db_st="${RED}STOPPED${NC}"
  systemctl is-active --quiet stunnel4     && stunnel_st="${GREEN}RUNNING${NC}" || stunnel_st="${RED}STOPPED${NC}"
  systemctl is-active --quiet ws-dropbear  && wsd_st="${GREEN}RUNNING${NC}"    || wsd_st="${RED}STOPPED${NC}"
  systemctl is-active --quiet ws-openssh   && wso_st="${GREEN}RUNNING${NC}"    || wso_st="${RED}STOPPED${NC}"

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}SSH / SSH-WS / SSH-SSL${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Domain"       "$domain"
  ui_2col "Dropbear  $db_st" "Stunnel4  $stunnel_st"
  ui_2col "WS Dropbear  $wsd_st" "WS OpenSSH  $wso_st"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "SSH Direct"   "442 / 109 / 143"
  ui_kv "SSH-SSL"      "$STUNNEL_SSL_PORT / ${HAPROXY_SSL_PORT:-444}"
  ui_kv "SSH-WS nTLS"  "80 / 8880 / 8080 / 2080 / 2082"
  ui_kv "SSH-WS TLS"   "443"
  ui_kv "Total Akun"   "$count akun"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
}

sshws_menu() {
  if sshws_addon_missing; then
    sshws_offer_install || return
  fi
  sshws_header
  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_2col "$(ui_menu_num 1 'Buat Akun' "$GREEN")"      "$(ui_menu_num 2 'Info Akun' "$GREEN")"
  ui_2col "$(ui_menu_num 3 'Detail Koneksi' "$GREEN")" "$(ui_menu_num 4 'Hapus Akun' "$RED")"
  ui_2col "$(ui_menu_num 5 'Perpanjang Akun')"          "$(ui_menu_num 6 'List Semua Akun' "$CYAN")"
  ui_2col "$(ui_menu_num 7 'Diagnostic' "$PURPLE")"     "$(ui_menu_num 8 'Edit Limit & Kuota')"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "$(ui_menu_num 0 'Kembali ke Menu Utama' "$DIM")"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -ne "  ${WHITE}${BOLD}Pilih [0-8]${NC} ${DIM}›${NC} "
  read -r choice

  case "$choice" in
    1) do_create_ssh ;;
    2) do_info_ssh ;;
    3) do_detail_ssh ;;
    4) do_delete_ssh ;;
    5) do_renew_ssh ;;
    6) do_list_ssh ;;
    7) bash "$SCRIPT_DIR/addon/sshws-pro.sh" diagnostic; echo -ne "  ${DIM}Tekan Enter...${NC}"; read -r; sshws_menu ;;
    8) do_edit_limit_ssh ;;
    0) bash "$SCRIPT_DIR/menu.sh" ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; sshws_menu ;;
  esac
}

do_create_ssh() {
  sshws_header
  echo ""
  echo -e "  ${WHITE}BUAT AKUN SSH BARU${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username     ${NC}: "
  read -r username
  [[ -z "$username" ]] && { echo -e "  ${RED}[!] Username kosong!${NC}"; sleep 2; sshws_menu; return; }
  grep -q "^$username|" "$DB_SSH" 2>/dev/null && { echo -e "  ${RED}[!] Username sudah ada!${NC}"; sleep 2; sshws_menu; return; }

  echo -ne "  ${YELLOW}Password (kosongkan = random)${NC}: "
  read -r password

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
    [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "  ${RED}[!] Harus angka!${NC}"; sleep 2; sshws_menu; return; }
  fi

  echo -ne "  ${YELLOW}Limit Sesi${NC} [default: ${SESSION_LIMIT_DEFAULT:-2}, 0=unlimited]: "
  read -r session_limit
  session_limit="${session_limit:-${SESSION_LIMIT_DEFAULT:-2}}"
  [[ ! "$session_limit" =~ ^[0-9]+$ ]] && session_limit="${SESSION_LIMIT_DEFAULT:-2}"

  echo -ne "  ${YELLOW}Limit Kuota (GB)${NC} [default: $(fmt_quota "$QUOTA_DEFAULT_MB"), 0=unlimited]: "
  read -r quota_gb
  local quota_mb
  if [[ -z "$quota_gb" ]]; then
    quota_mb="${QUOTA_DEFAULT_MB:-0}"
  elif [[ "$quota_gb" =~ ^[0-9]+$ ]]; then
    quota_mb=$(( quota_gb * 1024 ))
  else
    quota_mb="${QUOTA_DEFAULT_MB:-0}"
  fi

  local pass
  pass=$(create_ssh "$username" "$days" "$password" "$session_limit" "$quota_mb" "$trial_hours")
  local domain=$(get_domain)
  local exp masa_label
  if [[ "$trial_hours" -gt 0 ]]; then
    exp=$(get_ssh_info "$username" | cut -d'|' -f3)
    masa_label="Trial ${trial_hours} jam"
  else
    exp=$(get_exp_date "$days")
    masa_label="${days} hari"
  fi

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}           ✓  AKUN SSH BERHASIL DIBUAT${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username        ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}Password        ${NC}: ${WHITE}$pass${NC}"
  echo -e "  ${YELLOW}Domain/IP       ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Expired         ${NC}: ${WHITE}$exp${NC} ($masa_label)"
  echo -e "  ${YELLOW}Limit Sesi      ${NC}: ${WHITE}$(fmt_limit "$session_limit")${NC}"
  echo -e "  ${YELLOW}Limit Kuota     ${NC}: ${WHITE}$(fmt_quota "$quota_mb")${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}SSH Direct  ${NC}: port 442 / 109 / 143"
  echo -e "  ${WHITE}SSH-SSL     ${NC}: port $STUNNEL_SSL_PORT / ${HAPROXY_SSL_PORT:-444}  (SNI bebas, tanpa payload)"
  echo -e "  ${WHITE}SSH-WS nTLS ${NC}: port 80 / 8880 / 8080 / 2080 / 2082"
  echo -e "  ${WHITE}SSH-WS TLS  ${NC}: port 443"
  echo -e "  ${WHITE}Path        ${NC}: /ssh-ws (Dropbear)  atau  /ssh-ws-ssh (OpenSSH)"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Payload WS - Dropbear${NC}:"
  echo -e "  ${WHITE}$(ws_payload_string "$domain" "80" "/ssh-ws")${NC}"
  echo -e "  ${YELLOW}Payload WS - OpenSSH${NC}:"
  echo -e "  ${WHITE}$(ws_payload_string "$domain" "80" "/ssh-ws-ssh")${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  sshws_menu
}

do_info_ssh() {
  sshws_header
  echo ""
  echo -e "  ${WHITE}INFO AKUN SSH${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username

  local info=$(get_ssh_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }

  local pass=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local slimit=$(echo "$info" | cut -d'|' -f5)
  local quota_mb=$(echo "$info" | cut -d'|' -f6)
  slimit="${slimit:-${SESSION_LIMIT_DEFAULT:-2}}"
  quota_mb="${quota_mb:-0}"
  local active=$(pgrep -u "$username" 2>/dev/null | wc -l)
  local used_mb=$(get_ssh_usage_mb "$username")
  local remaining=$(days_until_exp "$exp")
  local sc="${GREEN}"; local st="AKTIF"
  [[ $remaining -lt 0 ]] && { sc="${RED}";     st="EXPIRED"; }
  [[ $remaining -le 3 && $remaining -ge 0 ]] && { sc="${YELLOW}"; st="SEGERA EXPIRED"; }
  is_quota_disabled "ssh" "$username" && { sc="${RED}"; st="SUSPENDED (kuota habis)"; }

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username        ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}Password        ${NC}: ${WHITE}$pass${NC}"
  echo -e "  ${YELLOW}Dibuat          ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired         ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa            ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "  ${YELLOW}Status          ${NC}: ${sc}● $st${NC}"
  echo -e "  ${YELLOW}Sesi Aktif      ${NC}: ${WHITE}$active${NC} / ${WHITE}$(fmt_limit "$slimit")${NC}"
  echo -e "  ${YELLOW}Kuota Terpakai  ${NC}: ${WHITE}$(fmt_quota "$used_mb")${NC} / ${WHITE}$(fmt_quota "$quota_mb")${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  sshws_menu
}

do_edit_limit_ssh() {
  sshws_header
  echo ""
  echo -e "  ${WHITE}EDIT LIMIT SESI & KUOTA${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_ssh_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }

  local cur_slimit=$(echo "$info" | cut -d'|' -f5); cur_slimit="${cur_slimit:-${SESSION_LIMIT_DEFAULT:-2}}"
  local cur_quota=$(echo "$info" | cut -d'|' -f6); cur_quota="${cur_quota:-0}"

  echo -ne "  ${YELLOW}Limit Sesi baru${NC} [saat ini: $(fmt_limit "$cur_slimit")]: "
  read -r new_slimit; new_slimit="${new_slimit:-$cur_slimit}"
  [[ ! "$new_slimit" =~ ^[0-9]+$ ]] && new_slimit="$cur_slimit"

  echo -ne "  ${YELLOW}Limit Kuota baru (GB)${NC} [saat ini: $(fmt_quota "$cur_quota")]: "
  read -r new_gb
  local new_quota
  if [[ -z "$new_gb" ]]; then
    new_quota="$cur_quota"
  elif [[ "$new_gb" =~ ^[0-9]+$ ]]; then
    new_quota=$(( new_gb * 1024 ))
  else
    new_quota="$cur_quota"
  fi

  edit_ssh_limits "$username" "$new_slimit" "$new_quota"
  echo -e "  ${GREEN}[✓] Limit '$username' diperbarui: sesi=$(fmt_limit "$new_slimit"), kuota=$(fmt_quota "$new_quota")${NC}"
  sleep 2
  sshws_menu
}

do_detail_ssh() {
  sshws_header
  echo ""
  echo -e "  ${WHITE}DETAIL KONEKSI SSH${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username

  local info=$(get_ssh_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }

  local pass=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local domain=$(get_domain)
  local ip=$(get_server_ip)

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DETAIL KONEKSI SSH  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username${NC}: ${WHITE}$username${NC}   ${YELLOW}Password${NC}: ${WHITE}$pass${NC}   ${YELLOW}Expired${NC}: ${WHITE}$exp${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}[1] SSH Direct${NC}"
  echo -e "      Host: $domain ($ip)   Port: 442 / 109 / 143"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[2] SSH-SSL -> Dropbear (Stunnel4)${NC}"
  echo -e "      Host: $domain   Port: $STUNNEL_SSL_PORT   TLS: ON (SNI-only, tanpa payload)"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[2b] SSH-SSL -> OpenSSH (HAProxy, opsional)${NC}"
  echo -e "      Host: $domain   Port: ${HAPROXY_SSL_PORT:-444}   TLS: ON (SNI-only, tanpa payload — aktifkan di menu HAProxy)"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[3] SSH-WS (non-TLS) — Port 80${NC}"
  echo -e "      Host: $domain   Port: 80   Path: /ssh-ws   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "80")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[4] SSH-WS (non-TLS) — Port 8880${NC}"
  echo -e "      Host: $domain   Port: 8880  Path: /ssh-ws   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "8880")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[5] SSH-WS (non-TLS) — Port 8080${NC}"
  echo -e "      Host: $domain   Port: 8080  Path: /ssh-ws   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "8080")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[6] SSH-WS (non-TLS) — Port 2080${NC}"
  echo -e "      Host: $domain   Port: 2080  Path: /ssh-ws   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "2080")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[7] SSH-WS (non-TLS) — Port 2082${NC}"
  echo -e "      Host: $domain   Port: 2082  Path: /ssh-ws   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "2082")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[8] SSH-WS (TLS) — Port 443${NC}"
  echo -e "      Host: $domain   Port: 443  Path: /ssh-ws   TLS: ON"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "443" "/ssh-ws")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[9] SSH-WS-SSH (non-TLS, backend OpenSSH) — Port 80${NC}"
  echo -e "      Host: $domain   Port: 80   Path: /ssh-ws-ssh   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "80" "/ssh-ws-ssh")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[10] SSH-WS-SSH (non-TLS, backend OpenSSH) — Port 8880${NC}"
  echo -e "      Host: $domain   Port: 8880  Path: /ssh-ws-ssh   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "8880" "/ssh-ws-ssh")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[11] SSH-WS-SSH (non-TLS, backend OpenSSH) — Port 8080${NC}"
  echo -e "      Host: $domain   Port: 8080  Path: /ssh-ws-ssh   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "8080" "/ssh-ws-ssh")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[12] SSH-WS-SSH (non-TLS, backend OpenSSH) — Port 2080${NC}"
  echo -e "      Host: $domain   Port: 2080  Path: /ssh-ws-ssh   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "2080" "/ssh-ws-ssh")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[13] SSH-WS-SSH (non-TLS, backend OpenSSH) — Port 2082${NC}"
  echo -e "      Host: $domain   Port: 2082  Path: /ssh-ws-ssh   TLS: OFF"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "2082" "/ssh-ws-ssh")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[14] SSH-WS-SSH (TLS, backend OpenSSH) — Port 443${NC}"
  echo -e "      Host: $domain   Port: 443  Path: /ssh-ws-ssh   TLS: ON"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "443" "/ssh-ws-ssh")${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  sshws_menu
}

do_delete_ssh() {
  sshws_header
  echo ""
  echo -e "  ${RED}HAPUS AKUN SSH${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_ssh_simple
  echo ""
  echo -ne "  ${YELLOW}Username yang dihapus${NC}: "; read -r username
  [[ -z "$(get_ssh_info "$username")" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }
  echo -ne "  ${RED}Konfirmasi hapus '$username'? [y/N]${NC}: "; read -r c
  [[ ! "$c" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; sshws_menu; return; }
  delete_ssh "$username"
  tg_notify "🗑️ <b>Akun SSH Dihapus Manual</b>

Username: <code>$username</code>
Domain: <code>$(get_domain)</code>"
  echo -e "  ${GREEN}[✓] Akun '$username' dihapus!${NC}"; sleep 2; sshws_menu
}

do_renew_ssh() {
  sshws_header
  echo ""
  echo -e "  ${YELLOW}PERPANJANG AKUN SSH${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_ssh_simple
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_ssh_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }
  local old_exp=$(echo "$info" | cut -d'|' -f3)
  echo -e "  ${YELLOW}Expired saat ini${NC}: ${WHITE}$old_exp${NC}"
  echo -ne "  ${YELLOW}Perpanjang (hari)${NC}: "; read -r days; days=${days:-30}
  renew_ssh "$username" "$days"
  echo -e "  ${GREEN}[✓] Diperpanjang hingga ${WHITE}$(get_exp_date "$days")${NC}"; sleep 2; sshws_menu
}

do_list_ssh_simple() {
  local count=0
  printf "  ${CYAN}%-20s %-14s %-12s${NC}\n" "USERNAME" "PASSWORD" "EXPIRED"
  echo -e "  ${CYAN}$LINE${NC}"
  while IFS='|' read -r user pass exp created limit; do
    [[ -z "$user" ]] && continue
    local r=$(days_until_exp "$exp")
    local c="${WHITE}"
    [[ $r -lt 0 ]] && c="${RED}"
    [[ $r -le 3 && $r -ge 0 ]] && c="${YELLOW}"
    printf "  ${c}%-20s %-14s %-12s${NC}\n" "$user" "$pass" "$exp"
    ((count++))
  done < <(list_ssh)
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Total${NC}: ${WHITE}$count akun${NC}"
}

do_list_ssh() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DAFTAR AKUN SSH  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  do_list_ssh_simple
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  sshws_menu
}

sshws_menu
