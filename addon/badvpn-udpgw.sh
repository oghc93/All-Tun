#!/bin/bash
# ============================================================
#  CHANELOG VPN SCRIPT - BadVPN UDPGW (ADDON)
#  Daemon UDP Gateway supaya VC/telepon (WhatsApp Call, dll)
#  bisa jalan lewat tunnel SSH-WS/SSH-SSL (yang secara bawaan
#  cuma nerusin TCP, gak bisa UDP tanpa ini).
#
#  Cara kerja: client (app SSH VPN) forward paket UDP lewat
#  tunnel SSH ke daemon ini (listen di 127.0.0.1:7300 di
#  server), daemon nerusin ke tujuan asli & sebaliknya.
#
#  Pemakaian:
#    bash badvpn-udpgw.sh install
#    bash badvpn-udpgw.sh status
#    bash badvpn-udpgw.sh uninstall
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh" 2>/dev/null

ACTION="${1:-install}"
UDPGW_PORT=7300
BIN_PATH="/usr/local/bin/badvpn-udpgw"

RED=${RED:-'\033[0;31m'}; GREEN=${GREEN:-'\033[0;32m'}; YELLOW=${YELLOW:-'\033[1;33m'}
CYAN=${CYAN:-'\033[0;36m'}; WHITE=${WHITE:-'\033[1;37m'}; NC=${NC:-'\033[0m'}

action_install() {
  echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
  echo -e "${WHITE}   INSTALL BadVPN UDPGW (UDP relay utk VC/telepon)   ${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

  if [[ -f "$BIN_PATH" ]]; then
    echo -e "${GREEN}[OK]${NC} BadVPN UDPGW sudah terinstall, skip compile."
  else
    echo -e "${CYAN}[*]${NC} Menginstall dependency build..."
    apt-get update -qq
    apt-get install -y -qq git cmake build-essential >/dev/null 2>&1

    echo -e "${CYAN}[*]${NC} Compile badvpn-udpgw dari source (bisa 1-2 menit)..."
    rm -rf /tmp/badvpn
    if ! git clone --depth 1 -q https://github.com/ambrop72/badvpn.git /tmp/badvpn; then
      echo -e "${RED}[GAGAL]${NC} Gagal clone source badvpn. Cek koneksi internet VPS."
      exit 1
    fi
    mkdir -p /tmp/badvpn/build
    cd /tmp/badvpn/build || exit 1
    if ! cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/tmp/badvpn-cmake.log 2>&1; then
      echo -e "${RED}[GAGAL]${NC} cmake gagal, cek log: /tmp/badvpn-cmake.log"
      exit 1
    fi
    if ! make -j"$(nproc)" >/tmp/badvpn-make.log 2>&1; then
      echo -e "${RED}[GAGAL]${NC} make gagal, cek log: /tmp/badvpn-make.log"
      exit 1
    fi
    cp udpgw/badvpn-udpgw "$BIN_PATH"
    chmod +x "$BIN_PATH"
    cd / && rm -rf /tmp/badvpn
    echo -e "${GREEN}[OK]${NC} Compile selesai: $BIN_PATH"
  fi

  echo -e "${CYAN}[*]${NC} Memasang systemd service..."
  cat > /etc/systemd/system/badvpn-udpgw.service << EOF
[Unit]
Description=BadVPN UDP Gateway (UDP relay utk VC/telepon lewat SSH)
After=network.target

[Service]
ExecStart=$BIN_PATH --listen-addr 127.0.0.1:$UDPGW_PORT --max-clients 1000 --max-connections-for-client 10
Restart=on-failure
RestartSec=3
User=nobody
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable badvpn-udpgw >/dev/null 2>&1
  systemctl restart badvpn-udpgw
  sleep 1

  if systemctl is-active --quiet badvpn-udpgw; then
    echo -e "${GREEN}[OK]${NC} Service badvpn-udpgw aktif & listen di 127.0.0.1:$UDPGW_PORT"
  else
    echo -e "${RED}[GAGAL]${NC} Service gagal start, cek: systemctl status badvpn-udpgw"
    exit 1
  fi

  echo ""
  echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
  echo -e "${WHITE}   BadVPN UDPGW SIAP DIPAKAI   ${NC}"
  echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
  echo -e "  Di app client (HTTP Injector dkk), cari field:"
  echo -e "  ${YELLOW}\"UDPGW\" / \"UDP Forward Server\" / \"BadVPN\"${NC}"
  echo -e "  Isi dengan: ${WHITE}127.0.0.1:$UDPGW_PORT${NC}"
  echo -e "  ${YELLOW}[PENTING]${NC} Ini BUKAN alamat server kamu -- app yang"
  echo -e "  otomatis nerusin lewat tunnel SSH yang udah konek."
  echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
}

action_status() {
  echo -e "${WHITE}Status BadVPN UDPGW:${NC}"
  if systemctl is-active --quiet badvpn-udpgw 2>/dev/null; then
    echo -e "  Service : ${GREEN}RUNNING${NC}"
  else
    echo -e "  Service : ${RED}TIDAK JALAN / belum terinstall${NC}"
  fi
  if ss -tlnp 2>/dev/null | grep -q "127.0.0.1:$UDPGW_PORT"; then
    echo -e "  Port    : ${GREEN}$UDPGW_PORT listening${NC}"
  else
    echo -e "  Port    : ${RED}$UDPGW_PORT TIDAK listening${NC}"
  fi
}

action_uninstall() {
  systemctl stop badvpn-udpgw 2>/dev/null
  systemctl disable badvpn-udpgw 2>/dev/null
  rm -f /etc/systemd/system/badvpn-udpgw.service
  rm -f "$BIN_PATH"
  systemctl daemon-reload
  echo -e "${GREEN}[OK]${NC} BadVPN UDPGW dihapus."
}

case "$ACTION" in
  install)   action_install ;;
  status)    action_status ;;
  uninstall) action_uninstall ;;
  *) echo "Pemakaian: bash $0 [install|status|uninstall]" ;;
esac
