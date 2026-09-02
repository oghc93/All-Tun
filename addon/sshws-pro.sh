#!/bin/bash
# ============================================================
#  CHANELOG VPN SCRIPT - SSH-WS/SSH-SSL "PRO" ORCHESTRATOR
#
#  Satu pintu buat:
#   - Install lengkap (dropbear/stunnel4/ws-dropbear/ws-openssh
#     + multiplex 443 content-based, semua lewat script yang
#     udah ada -- ini gak nulis ulang, cuma orkestrasi + harden)
#   - Setup Session Limit & notifikasi Telegram
#   - Systemd auto-restart utk SEMUA service terkait (bukan cuma
#     HAProxy)
#   - Diagnostic bawaan (gak perlu paste script terpisah lagi)
#   - Uninstall bersih
#
#  Pemakaian:
#    bash sshws-pro.sh install       (default kalau tanpa argumen)
#    bash sshws-pro.sh config        (setup ulang limit/telegram)
#    bash sshws-pro.sh diagnostic
#    bash sshws-pro.sh uninstall
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

ACTION="${1:-install}"
CRON_MARKER="# vpn-script-pro-session-limiter"

line() { echo -e "${CYAN}══════════════════════════════════════════════════${NC}"; }

# ── Systemd hardening (Restart=on-failure) utk service manapun ──
harden_service() {
  local svc="$1"
  systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service" || return 0
  local dropin="/etc/systemd/system/${svc}.service.d/override.conf"
  if [[ -f "$dropin" ]] && grep -q "Restart=on-failure" "$dropin" 2>/dev/null; then
    return 0
  fi
  mkdir -p "/etc/systemd/system/${svc}.service.d"
  cat > "$dropin" << 'EOF'
[Service]
Restart=on-failure
RestartSec=3
EOF
  echo -e "  ${GREEN}[OK]${NC} Auto-restart dipasang: $svc"
}

action_harden_all() {
  echo -e "${CYAN}[*]${NC} Memasang auto-restart utk semua service terkait..."
  for svc in dropbear stunnel4 ws-dropbear ws-openssh haproxy xray nginx badvpn-udpgw; do
    harden_service "$svc"
  done
  systemctl daemon-reload
}

# ── Setup wizard: session limit default + Telegram ──
action_config() {
  clear
  line
  echo -e "${WHITE}   SETUP: Session Limit & Notifikasi Telegram${NC}"
  line
  echo ""
  local cur_limit="${SESSION_LIMIT_DEFAULT:-2}"
  echo -ne "  ${YELLOW}Limit sesi default per akun${NC} [saat ini: $cur_limit] (0 = unlimited): "
  read -r new_limit
  new_limit="${new_limit:-$cur_limit}"
  [[ ! "$new_limit" =~ ^[0-9]+$ ]] && new_limit=2

  echo ""
  echo -e "  ${DIM}Cara bikin bot Telegram (skip kalau gak mau pakai notifikasi):${NC}"
  echo -e "  ${DIM}1. Chat @BotFather di Telegram -> /newbot -> ikuti instruksi -> dapat TOKEN${NC}"
  echo -e "  ${DIM}2. Chat @userinfobot -> catat 'Id' kamu -> itu CHAT ID${NC}"
  echo ""
  echo -ne "  ${YELLOW}Bot Token${NC} [Enter = skip/matikan]: "
  read -r bot_token
  echo -ne "  ${YELLOW}Chat ID${NC}  [Enter = skip/matikan]: "
  read -r chat_id

  SESSION_LIMIT_DEFAULT="$new_limit"
  TELEGRAM_BOT_TOKEN="$bot_token"
  TELEGRAM_CHAT_ID="$chat_id"
  save_pro_config
  echo -e "  ${GREEN}[OK]${NC} Config disimpan di $PRO_CONFIG"
  echo -e "  ${DIM}Tips: limit device/IP Xray & limit kuota sekarang ada di menu utama${NC}"
  echo -e "  ${DIM}[14] Bot Telegram & Limit Akun (Pro).${NC}"

  if [[ -n "$bot_token" && -n "$chat_id" ]]; then
    load_pro_config
    echo -ne "  ${CYAN}[*]${NC} Test kirim notifikasi... "
    if tg_notify "✅ <b>Setup Berhasil</b>

Notifikasi Telegram utk domain <code>$(get_domain)</code> sudah aktif."; then
      echo -e "${GREEN}terkirim, cek Telegram kamu.${NC}"
    else
      echo -e "${RED}GAGAL${NC} -- cek lagi Bot Token/Chat ID-nya, mungkin salah."
    fi
  fi
  echo ""
}

# ── Cron: session limiter tiap 2 menit ──
action_install_cron() {
  echo -e "${CYAN}[*]${NC} Memasang cron session-limiter (tiap 2 menit)..."
  crontab -l 2>/dev/null | grep -v "$CRON_MARKER" > /tmp/crontab.tmp
  echo "*/2 * * * * bash $SCRIPT_DIR/addon/session-limiter.sh >> /var/log/vpn-session-limiter.log 2>&1 $CRON_MARKER" >> /tmp/crontab.tmp
  crontab /tmp/crontab.tmp
  rm -f /tmp/crontab.tmp
  echo -e "  ${GREEN}[OK]${NC} Cron terpasang"
}

# ── Install lengkap: orkestrasi script yang sudah ada ──
action_install() {
  clear
  line
  echo -e "${WHITE}   SSH-WS / SSH-SSL PRO -- INSTALL LENGKAP${NC}"
  line
  echo ""

  if [[ ! -f /usr/local/bin/ws-dropbear || ! -f /usr/local/bin/ws-openssh ]]; then
    echo -e "${CYAN}[1/5]${NC} Menginstall komponen dasar SSH-WS/SSH-SSL..."
    bash "$SCRIPT_DIR/addon/install-sshws.sh"
  else
    echo -e "${CYAN}[1/5]${NC} Komponen dasar SSH-WS/SSH-SSL sudah ada, skip."
  fi
  echo ""

  echo -e "${CYAN}[2/5]${NC} Mengaktifkan multiplex 443 (SNI bebas, routing by payload)..."
  bash "$SCRIPT_DIR/addon/enable-ssl-multiplex.sh" enable
  echo ""

  echo -e "${CYAN}[3/5]${NC} Menginstall BadVPN UDPGW (UDP relay utk VC/telepon)..."
  bash "$SCRIPT_DIR/addon/badvpn-udpgw.sh" install
  echo ""

  echo -e "${CYAN}[4/5]${NC} Hardening systemd (auto-restart semua service)..."
  action_harden_all
  echo ""

  echo -e "${CYAN}[5/5]${NC} Setup Session Limit & Telegram..."
  if [[ ! -f "$PRO_CONFIG" ]]; then
    action_config
  else
    echo -e "  ${DIM}Config sudah ada ($PRO_CONFIG), skip wizard.${NC}"
    echo -e "  ${DIM}Jalankan 'bash sshws-pro.sh config' kalau mau ubah.${NC}"
  fi
  action_install_cron

  echo ""
  line
  echo -e "${GREEN}   INSTALL PRO SELESAI${NC}"
  line
  echo -e "  Diagnostic   : bash $SCRIPT_DIR/addon/sshws-pro.sh diagnostic"
  echo -e "  Ubah config  : bash $SCRIPT_DIR/addon/sshws-pro.sh config"
  echo -e "  Uninstall    : bash $SCRIPT_DIR/addon/sshws-pro.sh uninstall"
  line
}

# ── Diagnostic bawaan ──
action_diagnostic() {
  local domain=$(get_domain)
  clear
  line
  echo -e "${WHITE}   DIAGNOSTIC: SSH-WS / SSH-SSL / Multiplex / Pro Features${NC}"
  line
  echo -e "  Domain: ${WHITE}$domain${NC}"
  echo ""

  echo -e "${WHITE}[1] STATUS SERVICE${NC}"
  for svc in nginx dropbear stunnel4 haproxy ws-dropbear ws-openssh xray badvpn-udpgw; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      st="${GREEN}RUNNING${NC}"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      st="${RED}STOPPED${NC}"
    else
      st="${YELLOW}BELUM TERINSTALL${NC}"
    fi
    printf "  %-14s : %b\n" "$svc" "$st"
  done
  echo ""

  echo -e "${WHITE}[2] AUTO-RESTART (systemd)${NC}"
  for svc in dropbear stunnel4 ws-dropbear ws-openssh haproxy; do
    if [[ -f "/etc/systemd/system/${svc}.service.d/override.conf" ]]; then
      echo -e "  $svc : ${GREEN}terpasang${NC}"
    else
      echo -e "  $svc : ${YELLOW}belum${NC}"
    fi
  done
  echo ""

  echo -e "${WHITE}[3] MULTIPLEX 443${NC}"
  if [[ -f /etc/vpn-script/.multiplex-443-active ]]; then
    echo -e "  Status: ${GREEN}AKTIF${NC} (content-based, SNI bebas)"
  else
    echo -e "  Status: ${YELLOW}TIDAK AKTIF${NC}"
  fi
  if command -v openssl >/dev/null 2>&1; then
    resp_http=$(timeout 5 bash -c "printf 'GET / HTTP/1.1\r\nHost: $domain\r\nConnection: close\r\n\r\n' | openssl s_client -connect 127.0.0.1:443 -servername 'random-check-1.test' -quiet 2>/dev/null")
    [[ "$resp_http" == *"HTTP/"* ]] && echo -e "  Test payload GET (SNI acak) -> Nginx : ${GREEN}OK${NC}" || echo -e "  Test payload GET (SNI acak) -> Nginx : ${RED}GAGAL${NC}"
    resp_raw=$(timeout 8 bash -c "printf 'PING-TEST-BUKAN-HTTP\r\n' | openssl s_client -connect 127.0.0.1:443 -servername 'random-check-2.test' -quiet 2>/dev/null")
    [[ "$resp_raw" == *"SSH-"* ]] && echo -e "  Test raw SSH (SNI acak) -> Dropbear  : ${GREEN}OK${NC}" || echo -e "  Test raw SSH (SNI acak) -> Dropbear  : ${RED}GAGAL${NC}"
  fi
  if ss -tlnp 2>/dev/null | grep -q "127.0.0.1:7300"; then
    echo -e "  BadVPN UDPGW (VC/telepon)            : ${GREEN}OK${NC} (port 7300 listening)"
  else
    echo -e "  BadVPN UDPGW (VC/telepon)            : ${RED}TIDAK AKTIF${NC}"
  fi
  echo ""

  echo -e "${WHITE}[4] FITUR PRO${NC}"
  if [[ -f "$PRO_CONFIG" ]]; then
    echo -e "  Config              : ${GREEN}ada${NC} ($PRO_CONFIG)"
    echo -e "  Session limit default: ${WHITE}${SESSION_LIMIT_DEFAULT:-2}${NC}"
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
      echo -e "  Telegram            : ${GREEN}aktif${NC}"
    else
      echo -e "  Telegram            : ${YELLOW}tidak aktif${NC}"
    fi
  else
    echo -e "  Config              : ${YELLOW}belum di-setup${NC} (jalankan: bash $0 config)"
  fi
  if crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
    echo -e "  Cron session-limiter: ${GREEN}terpasang${NC}"
  else
    echo -e "  Cron session-limiter: ${RED}TIDAK terpasang${NC}"
  fi
  if crontab -l 2>/dev/null | grep -q "delete_expired"; then
    echo -e "  Cron auto-expire     : ${GREEN}terpasang${NC}"
  else
    echo -e "  Cron auto-expire     : ${RED}TIDAK terpasang${NC}"
  fi
  line
}

# ── Uninstall (cron + config, TIDAK uninstall dropbear/stunnel/dll) ──
action_uninstall() {
  echo -e "${YELLOW}[*]${NC} Menghapus cron session-limiter & config pro..."
  crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab -
  rm -f "$PRO_CONFIG"
  rm -rf "$SCRIPT_DIR/.session-limiter-state"
  echo -e "${GREEN}[OK]${NC} Fitur pro (session-limit + telegram) dinonaktifkan."
  echo -e "${DIM}    Dropbear/Stunnel4/HAProxy/Multiplex TIDAK ikut di-uninstall.${NC}"
  echo -e "${DIM}    Pakai 'enable-ssl-multiplex.sh disable' kalau mau matikan multiplex.${NC}"
}

case "$ACTION" in
  install)    action_install ;;
  config)     action_config ;;
  diagnostic) action_diagnostic ;;
  uninstall)  action_uninstall ;;
  *) echo "Pemakaian: bash $0 [install|config|diagnostic|uninstall]" ;;
esac
