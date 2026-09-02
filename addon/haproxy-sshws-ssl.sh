#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - HAProxy SSH-WS SSL Configuration
#   Fitur: HAProxy untuk SSH-WS SSL dengan toggle ON/OFF
#   Load Balancing & SSL termination untuk SSH-WS
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Jalankan sebagai root!"
  exit 1
fi

DOMAIN=$(get_domain)
HAPROXY_CONF="/etc/haproxy/haproxy.cfg"
HAPROXY_SSHWS_CONF="/etc/haproxy/conf.d/sshws-ssl.cfg"

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   CONFIGURE HAProxy FOR SSH-WS SSL   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# --- 1. Install HAProxy ---
echo -e "\n${CYAN}[*]${NC} Installing HAProxy..."
apt-get update -qq 2>/dev/null
apt-get install -y -qq haproxy 2>/dev/null
echo -e "${GREEN}[OK]${NC} HAProxy installed"

# --- 2. Create HAProxy config directory ---
mkdir -p /etc/haproxy/conf.d
mkdir -p /var/log/haproxy

# --- 3. Create SSH-WS SSL configuration for HAProxy ---
echo -e "\n${CYAN}[*]${NC} Creating HAProxy SSH-WS SSL configuration..."

cat > "$HAPROXY_SSHWS_CONF" <<HAPROXY_EOF
# ============================================================
#  HAProxy SSH-WS SSL Configuration
#  SSL Termination -> langsung ke OpenSSH (raw, tanpa payload HTTP)
#  Frontend: 0.0.0.0:${HAPROXY_SSL_PORT} (SSH-SSL -> OpenSSH, pasangan dari Stunnel4 -> Dropbear)
#  Backend: 127.0.0.1:22 (OpenSSH / sshd)
#  CATATAN: port frontend ini SENGAJA dibedakan dari Stunnel4 (port ${STUNNEL_SSL_PORT})
#  supaya keduanya bisa jalan berbarengan tanpa rebutan bind port -
#  Stunnel4 (777) -> Dropbear, HAProxy (444) -> OpenSSH.
# ============================================================

frontend sshws-ssl-frontend
  mode tcp
  bind 0.0.0.0:${HAPROXY_SSL_PORT} ssl crt /etc/ssl/xray/xray.pem
  option tcplog
  timeout client 300s

  default_backend openssh-ssl-backend

backend openssh-ssl-backend
  mode tcp
  balance roundrobin
  server openssh-1 127.0.0.1:22 check inter 5s rise 2 fall 3
  timeout connect 60s
  timeout server 300s

listen stats
  mode http
  bind 127.0.0.1:8404
  stats enable
  stats uri /stats
  stats hide-version
  stats show-legends
  stats admin if TRUE
HAPROXY_EOF

echo -e "${GREEN}[OK]${NC} HAProxy SSH-WS SSL configuration created"

# --- 4. Prepare SSL certificate for HAProxy (PEM format) ---
echo -e "\n${CYAN}[*]${NC} Preparing SSL certificate for HAProxy..."
if [[ -f /etc/ssl/xray/xray.crt && -f /etc/ssl/xray/xray.key ]]; then
  cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > /etc/ssl/xray/xray.pem 2>/dev/null
  chmod 600 /etc/ssl/xray/xray.pem
  echo -e "${GREEN}[OK]${NC} SSL certificate prepared for HAProxy"
else
  echo -e "${YELLOW}[WARN]${NC} SSL certificates not found, creating self-signed..."
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
    -keyout /tmp/haproxy.key \
    -out /tmp/haproxy.crt \
    -days 365 -nodes \
    -subj "/CN=${DOMAIN:-localhost}" 2>/dev/null
  cat /tmp/haproxy.crt /tmp/haproxy.key > /etc/ssl/xray/xray.pem
  chmod 600 /etc/ssl/xray/xray.pem
  rm -f /tmp/haproxy.key /tmp/haproxy.crt
  echo -e "${GREEN}[OK]${NC} Self-signed certificate created for HAProxy"
fi

# --- 5. Sisipkan config SSH-SSL langsung ke haproxy.cfg utama ---
# CATATAN: HAProxy TIDAK punya directive 'include' di dalam file config
# (beda dengan Nginx) — memuat banyak file cuma bisa lewat multiple flag
# -f saat invoke binary, yang butuh ubah systemd unit dan gampang rapuh
# di berbagai distro. Makanya config-nya langsung disisipkan ke
# haproxy.cfg pakai marker, supaya idempotent (aman dijalankan berkali-
# kali / update port) tanpa perlu sentuh systemd sama sekali.
echo -e "\n${CYAN}[*]${NC} Menyisipkan config SSH-SSL ke haproxy.cfg..."

[[ ! -f "$HAPROXY_CONF.bak" ]] && cp "$HAPROXY_CONF" "$HAPROXY_CONF.bak"
cp "$HAPROXY_CONF" "$HAPROXY_CONF.bak.$(date +%Y%m%d%H%M%S)"

# Bersihkan sisa baris 'include' dari bug versi lama (HAProxy gak support include,
# baris ini nyangkut di section 'defaults' dan bikin haproxy gagal start)
sed -i '/^include \/etc\/haproxy\/conf\.d\/\*\.cfg$/d; /^# Include additional configurations$/d' "$HAPROXY_CONF"

MARKER_START="# >>> SSHWS-SSL-ADDON (jangan edit manual, dikelola addon) >>>"
MARKER_END="# <<< SSHWS-SSL-ADDON <<<"

# Hapus blok lama kalau ada (biar idempotent saat re-run / ganti port)
awk -v start="$MARKER_START" -v end="$MARKER_END" '
  $0==start {skip=1; next}
  skip && $0==end {skip=0; next}
  !skip {print}
' "$HAPROXY_CONF" > "$HAPROXY_CONF.tmp" && mv "$HAPROXY_CONF.tmp" "$HAPROXY_CONF"

{
  echo ""
  echo "$MARKER_START"
  cat "$HAPROXY_SSHWS_CONF"
  echo "$MARKER_END"
} >> "$HAPROXY_CONF"

# Validasi SEBELUM restart - jangan sampai crash-loop kayak sebelumnya
if ! haproxy -c -f "$HAPROXY_CONF" > /tmp/haproxy_check.log 2>&1; then
  echo -e "${RED}[GAGAL]${NC} Config haproxy.cfg invalid, rollback ke backup..."
  cat /tmp/haproxy_check.log
  cp "$HAPROXY_CONF.bak" "$HAPROXY_CONF"
  exit 1
fi
echo -e "${GREEN}[OK]${NC} Config SSH-SSL tersemat di haproxy.cfg dan tervalidasi"

# --- 6. Enable and start HAProxy ---
echo -e "\n${CYAN}[*]${NC} Enabling and starting HAProxy service..."
systemctl daemon-reload
systemctl enable haproxy 2>/dev/null
systemctl restart haproxy 2>/dev/null

if systemctl is-active --quiet haproxy; then
  echo -e "${GREEN}[OK]${NC} HAProxy service is running"
else
  echo -e "${YELLOW}[WARN]${NC} HAProxy failed to start, checking configuration..."
  haproxy -f "$HAPROXY_CONF" -c 2>&1 | grep -E "Error|error" && exit 1
fi

# --- 7. Open firewall port ---
echo -e "\n${CYAN}[*]${NC} Opening firewall port for HAProxy..."
iptables -I INPUT -p tcp --dport "$HAPROXY_SSL_PORT" -j ACCEPT 2>/dev/null
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null
echo -e "${GREEN}[OK]${NC} Firewall port $HAPROXY_SSL_PORT opened for HAProxy"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   HAProxy SSH-WS SSL Setup Complete!   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}HAProxy SSH-SSL${NC}      : port $HAPROXY_SSL_PORT (SSL, langsung ke OpenSSH)"
echo -e "  ${YELLOW}Backend${NC}             : OpenSSH @ 127.0.0.1:22 (langsung, tanpa payload)"
echo -e "  ${YELLOW}Stats Dashboard${NC}    : http://127.0.0.1:8404/stats"
echo -e "  ${YELLOW}Certificate${NC}        : /etc/ssl/xray/xray.pem"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
