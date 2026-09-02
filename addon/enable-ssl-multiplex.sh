#!/bin/bash
# ============================================================
#  MULTIPLEX 443 v2 — routing berdasarkan ISI KONEKSI (payload),
#  BUKAN SNI. Xray/SSH-WS-TLS (kirim "GET ...") dan SSH-SSL
#  (kirim raw SSH, tanpa payload) SAMA-SAMA bebas pakai SNI apapun.
#
#  Kenapa content-based, bukan SNI-based:
#  HAProxy cuma bisa baca SNI SEBELUM TLS didekripsi. Kalau dua
#  kategori trafik (Xray/WS vs SSH-SSL) sama-sama harus nerima SNI
#  bebas apa aja, gak ada cara bedain dari SNI doang. Makanya di sini
#  HAProxy yang pegang & buka sendiri sertifikatnya (persis kayak
#  haproxy-sshws-ssl.sh di port 444), baru INTIP ISI datanya:
#    - Diawali "GET " / HTTP2 preface  -> diteruskan ke Nginx (Xray/WS)
#    - Selain itu (raw SSH)            -> langsung ke Dropbear
#  SNI jadi gak relevan sama sekali buat routing di sini.
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Harus dijalankan sebagai root"
  exit 1
fi

DOMAIN=$(get_domain)
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}[ERROR]${NC} Domain belum ter-set. Jalankan 'Change Domain' dulu."
  exit 1
fi

CERT_PEM="/etc/ssl/xray/xray.pem"
MARKER="/etc/vpn-script/.multiplex-443-active"
HAPROXY_CONF="/etc/haproxy/haproxy.cfg"
MARKER_START="# >>> MULTIPLEX-443-ADDON (jangan edit manual, dikelola addon) >>>"
MARKER_END="# <<< MULTIPLEX-443-ADDON <<<"

ACTION="${1:-enable}"

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   MULTIPLEX PORT 443 v2: routing by PAYLOAD (SNI bebas)   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

remove_haproxy_block() {
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0==start {skip=1; next}
    skip && $0==end {skip=0; next}
    !skip {print}
  ' "$HAPROXY_CONF" > "$HAPROXY_CONF.tmp" && mv "$HAPROXY_CONF.tmp" "$HAPROXY_CONF"
}

if [[ "$ACTION" == "disable" ]]; then
  echo -e "${CYAN}[*]${NC} Menonaktifkan multiplex, mengembalikan port 443 ke Nginx langsung..."
  rm -f "$MARKER"
  cp "$HAPROXY_CONF" "$HAPROXY_CONF.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null
  remove_haproxy_block

  if ! haproxy -c -f "$HAPROXY_CONF" > /tmp/haproxy_check.log 2>&1; then
    echo -e "${RED}[GAGAL]${NC} haproxy.cfg invalid setelah dibersihkan, cek manual:"
    cat /tmp/haproxy_check.log
  else
    systemctl reload haproxy 2>/dev/null || systemctl restart haproxy 2>/dev/null
  fi

  if regenerate_nginx_conf "$DOMAIN"; then
    echo -e "${GREEN}[OK]${NC} Multiplex dimatikan. Port 443 kembali murni Nginx (Xray/WS)."
  else
    echo -e "${RED}[GAGAL]${NC} Regenerate config Nginx gagal, cek manual: nginx -t"
    exit 1
  fi
  exit 0
fi

# --- 1. HAProxy terpasang ---
if ! command -v haproxy >/dev/null 2>&1; then
  echo -e "${CYAN}[*]${NC} Menginstall HAProxy..."
  apt-get install -y -qq haproxy 2>/dev/null
fi
if ! command -v haproxy >/dev/null 2>&1; then
  echo -e "${RED}[GAGAL]${NC} HAProxy gagal terinstall. Batal."
  exit 1
fi

# --- 2. Auto-restart HAProxy kalau crash (biar Xray gak ikut mati permanen) ---
if [[ ! -f /etc/systemd/system/haproxy.service.d/override.conf ]]; then
  mkdir -p /etc/systemd/system/haproxy.service.d
  cat > /etc/systemd/system/haproxy.service.d/override.conf << 'OVERRIDE_EOF'
[Service]
Restart=on-failure
RestartSec=3
OVERRIDE_EOF
  systemctl daemon-reload
  echo -e "${GREEN}[OK]${NC} Auto-restart HAProxy terpasang (Restart=on-failure)"
fi

# --- 3. Cert gabungan buat HAProxy (self-healing: bikin kalau belum ada/rusak) ---
if [[ ! -s "$CERT_PEM" ]]; then
  echo -e "${YELLOW}[*]${NC} $CERT_PEM belum ada, mencoba bikin dari crt+key..."
  if [[ -f /etc/ssl/xray/xray.crt && -f /etc/ssl/xray/xray.key ]]; then
    cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > "$CERT_PEM"
    chmod 600 "$CERT_PEM"
    echo -e "${GREEN}[OK]${NC} Cert gabungan dibuat dari xray.crt + xray.key"
  else
    echo -e "${YELLOW}[WARN]${NC} xray.crt/xray.key juga gak ada, bikin self-signed sementara..."
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
      -keyout /tmp/haproxy.key -out /tmp/haproxy.crt \
      -days 365 -nodes -subj "/CN=${DOMAIN}" 2>/dev/null
    cat /tmp/haproxy.crt /tmp/haproxy.key > "$CERT_PEM"
    chmod 600 "$CERT_PEM"
    rm -f /tmp/haproxy.key /tmp/haproxy.crt
    echo -e "${YELLOW}[OK]${NC} Self-signed cert dibuat (ganti begitu cert asli tersedia)"
  fi
fi

if ! systemctl is-active --quiet dropbear; then
  echo -e "${RED}[GAGAL]${NC} Dropbear belum aktif. Jalankan addon SSH-WS dulu (install-sshws.sh)."
  exit 1
fi
echo -e "${GREEN}[OK]${NC} Prasyarat lengkap (HAProxy, cert, Dropbear)"

# --- 4. Backup ---
BACKUP_DIR="/etc/vpn-script/.backup-multiplex-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$HAPROXY_CONF" "$BACKUP_DIR/haproxy.cfg" 2>/dev/null
cp /etc/nginx/conf.d/xray.conf "$BACKUP_DIR/xray.conf" 2>/dev/null
echo -e "${GREEN}[OK]${NC} Backup dibuat di $BACKUP_DIR"

rollback() {
  echo -e "${RED}[GAGAL]${NC} $1"
  echo -e "${YELLOW}[*]${NC} Rollback ke config sebelumnya..."
  rm -f "$MARKER"
  [[ -f "$BACKUP_DIR/haproxy.cfg" ]] && cp "$BACKUP_DIR/haproxy.cfg" "$HAPROXY_CONF"
  [[ -f "$BACKUP_DIR/xray.conf" ]] && cp "$BACKUP_DIR/xray.conf" /etc/nginx/conf.d/xray.conf
  systemctl reload haproxy 2>/dev/null || systemctl restart haproxy 2>/dev/null
  systemctl reload nginx 2>/dev/null
  echo -e "${YELLOW}[INFO]${NC} Sudah dikembalikan ke config semula."
  exit 1
}

# --- 5. Nginx internal (tetap SSL - HAProxy connect ke sini sbg klien TLS) ---
touch "$MARKER"
echo -e "${CYAN}[*]${NC} Meregenerasi Nginx (https block -> internal 127.0.0.1:8443)..."
if ! regenerate_nginx_conf "$DOMAIN"; then
  rollback "nginx -t gagal setelah regenerate config"
fi
sleep 1
if ! systemctl is-active --quiet nginx; then
  rollback "Nginx tidak aktif setelah reload"
fi
echo -e "${GREEN}[OK]${NC} Nginx aktif di internal 127.0.0.1:8443"

# --- 6. Sisipkan frontend/backend: TLS di-terminate HAProxy, routing by payload ---
echo -e "${CYAN}[*]${NC} Menyisipkan config multiplex (content-based) ke haproxy.cfg..."
remove_haproxy_block

{
  echo ""
  echo "$MARKER_START"
  cat <<HAPROXY_EOF
frontend multiplex_443
  bind *:443 ssl crt $CERT_PEM
  mode tcp
  tcp-request inspect-delay 5s
  tcp-request content accept if { req.len ge 4 }

  acl looks_like_http req.payload(0,4) -m str "GET "
  acl looks_like_h2   req.payload(0,16) -m str "PRI * HTTP/2.0"

  use_backend multiplex_xray if looks_like_http or looks_like_h2
  default_backend multiplex_sshssl

backend multiplex_xray
  mode tcp
  server nginx-internal 127.0.0.1:8443 ssl verify none check

backend multiplex_sshssl
  mode tcp
  server dropbear-direct 127.0.0.1:143 check
HAPROXY_EOF
  echo "$MARKER_END"
} >> "$HAPROXY_CONF"

if ! haproxy -c -f "$HAPROXY_CONF" > /tmp/haproxy_check.log 2>&1; then
  cat /tmp/haproxy_check.log
  rollback "haproxy.cfg invalid setelah sisip config multiplex v2"
fi

systemctl reload haproxy 2>/dev/null || systemctl restart haproxy 2>/dev/null
sleep 1
if ! systemctl is-active --quiet haproxy; then
  rollback "HAProxy tidak aktif setelah reload"
fi
echo -e "${GREEN}[OK]${NC} HAProxy aktif, TLS di-terminate langsung di HAProxy (port 443)"

# --- 7. Verifikasi fungsional (SNI SENGAJA diacak & beda-beda) ---
echo -e "${CYAN}[*]${NC} Verifikasi routing berdasarkan payload (SNI diacak, harus tetap jalan)..."

ok_http=false
ok_raw=false

resp_http=$(timeout 5 bash -c "printf 'GET / HTTP/1.1\r\nHost: $DOMAIN\r\nConnection: close\r\n\r\n' | openssl s_client -connect 127.0.0.1:443 -servername 'random-sni-1-siapa-aja.test' -quiet 2>/dev/null")
[[ "$resp_http" == *"HTTP/"* ]] && ok_http=true

# Kirim >=4 byte SEKALIGUS (bukan cuma newline kosong) supaya HAProxy langsung
# bisa mutusin arah tanpa perlu nunggu penuh tcp-request inspect-delay 5s.
resp_raw=$(timeout 8 bash -c "printf 'PING-TEST-BUKAN-HTTP\r\n' | openssl s_client -connect 127.0.0.1:443 -servername 'random-sni-2-bug-host-lain.test' -quiet 2>/dev/null")
[[ "$resp_raw" == *"SSH-"* ]] && ok_raw=true

if [[ "$ok_http" == "true" && "$ok_raw" == "true" ]]; then
  echo -e "${GREEN}[OK]${NC} Terverifikasi: SNI bebas apapun, routing tetap benar (payload GET->Nginx, raw->Dropbear)"
else
  rollback "Verifikasi gagal (payload HTTP->Nginx: $ok_http, raw->Dropbear: $ok_raw)"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   MULTIPLEX PORT 443 v2 AKTIF (routing by payload)   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}Xray + SSH-WS TLS${NC} : $DOMAIN:443, SNI BEBAS apa aja, payload/WS wajib (bawaan protokolnya)"
echo -e "  ${YELLOW}SSH-SSL${NC}           : $DOMAIN:443, SNI BEBAS apa aja, payload KOSONG (raw)"
echo -e "  Kalau mau matikan fitur ini: bash /etc/vpn-script/addon/enable-ssl-multiplex.sh disable"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
