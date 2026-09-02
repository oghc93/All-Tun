#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - LIBRARY FUNCTIONS (ALL-IN-ONE)
#   Supports: VMess, VLess, Trojan, Shadowsocks, SSH-WS, HAProxy
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
DB_DIR="$SCRIPT_DIR/db"
XRAY_CONFIG="/etc/xray/config.json"

# ─── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════
#  UI HELPERS -- box-drawing terminal yang presisi (dipakai
#  menu.sh + SEMUA menu/*.sh biar tampilannya konsisten).
#  Sengaja cuma pakai box-drawing/ASCII polos (bukan emoji/
#  Nerd Font) karena lebar-karakternya konsisten di semua
#  client SSH (PuTTY/Termux/MobaXterm/dll).
# ════════════════════════════════════════════════════════════
UI_BOX_TOP="╭──────────────────────────────────────────────────────────╮"
UI_BOX_MID="├──────────────────────────────────────────────────────────┤"
UI_BOX_BOT="╰──────────────────────────────────────────────────────────╯"
UI_CONTENT_W=56
UI_COL_W=27

# Hitung lebar visible (tanpa kode ANSI) -- bash ${#str} ngitung byte,
# bukan karakter, jadi bisa salah di locale non-UTF-8.
ui_visible_len() {
  local plain
  plain=$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')
  local n
  n=$(python3 -c "import sys; print(len(sys.argv[1]))" "$plain" 2>/dev/null)
  [[ -z "$n" ]] && n=${#plain}
  echo "$n"
}

# Tambah spasi di akhir teks berwarna sampai visible_len == width.
ui_pad_visible() {
  local text="$1" width="$2"
  local vlen=$(ui_visible_len "$text")
  local pad=$((width - vlen))
  ((pad < 0)) && pad=0
  printf "%b%*s" "$text" "$pad" ""
}

# Cetak satu baris dalam box, auto-pad ke UI_CONTENT_W.
ui_line() {
  local text="$1"
  local vlen=$(ui_visible_len "$text")
  if (( vlen > UI_CONTENT_W )); then
    local plain=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    text=$(echo "$plain" | cut -c1-$((UI_CONTENT_W-1)))"…"
  fi
  printf "│  %s│\n" "$(ui_pad_visible "$text" "$UI_CONTENT_W")"
}

# Baris rata-tengah (judul header/section). Area center = CONTENT_W+2
# supaya lebar totalnya sama persis dengan ui_line (yang punya margin
# 2 spasi built-in).
ui_line_center() {
  local text="$1"
  local inner_w=$((UI_CONTENT_W + 2))
  local vlen=$(ui_visible_len "$text")
  local pad_l=$(( (inner_w - vlen) / 2 )); ((pad_l < 0)) && pad_l=0
  local pad_r=$(( inner_w - vlen - pad_l )); ((pad_r < 0)) && pad_r=0
  printf "│%*s%b%*s│\n" "$pad_l" "" "$text" "$pad_r" ""
}

# Baris "label ..... value" model daftar isi -- presisi walau
# panjang label/value beda-beda.
ui_kv() {
  local label="$1" value="$2" leader_w=22
  local llen=${#label}
  local dots="" n=$((leader_w - llen))
  ((n < 3)) && n=3
  for ((i=0;i<n;i++)); do dots+="."; done
  ui_line "${YELLOW}${label}${NC} ${DIM}${dots}${NC} ${WHITE}${value}${NC}"
}

# Baris dua kolom presisi (grid menu/status). Tiap kolom persis
# UI_COL_W(27) karakter visible, dipisah 2 spasi -> 56 total.
ui_2col() {
  local c1="$1" c2="$2"
  local col1=$(ui_pad_visible "$c1" "$UI_COL_W")
  local col2=$(ui_pad_visible "$c2" "$UI_COL_W")
  ui_line "${col1}  ${col2}"
}

ui_dot() { [[ "$1" == "1" ]] && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}"; }

# Mini progress bar ASCII 14 kotak -- '#'/'.' polos, aman di semua terminal.
ui_bar() {
  local pct="${1:-0}"
  [[ "$pct" =~ ^[0-9]+$ ]] || { echo -e "${DIM}n/a${NC}"; return; }
  local width=14
  local filled=$(( pct * width / 100 )); ((filled > width)) && filled=$width
  local empty=$((width - filled))
  local color="${GREEN}"
  ((pct >= 60)) && color="${YELLOW}"
  ((pct >= 85)) && color="${RED}"
  local bar=""
  for ((i=0;i<filled;i++)); do bar+="#"; done
  for ((i=0;i<empty;i++)); do bar+="."; done
  echo -e "${color}${bar}${NC} ${WHITE}$(printf '%3s' "$pct")%${NC}"
}

ui_section() {
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_line "${CYAN}${BOLD}${1}${NC}"
}

ui_menu_num() {
  local num="$1" label="$2" color="${3:-$YELLOW}"
  echo -e "${color}[$(printf '%-2s' "$num")]${NC} $label"
}

# Header ringkas dipakai submenu (SSH/VMess/dll): judul + garis bawah.
ui_submenu_header() {
  local title="$1"
  clear
  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}${title}${NC}"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
}


# ─── Get Domain ────────────────────────────────────────────
get_domain() {
  cat $SCRIPT_DIR/domain 2>/dev/null || echo "unknown"
}

# ─── Payload string WS (dipakai tampilan menu & notif Telegram) ─
ws_payload_string() {
  local domain="$1"
  local port="${2:-80}"
  local path="${3:-/ssh-ws}"
  printf 'GET %s HTTP/1.1[crlf]Host: %s[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]' "$path" "$domain"
}

# ─── Trial per jam (durasi presisi jam, bukan hari) ─────────
# useradd/chage cuma presisi hari, jadi utk SSH exp OS-level
# dibulatkan ke atas per hari (jaring pengaman), TAPI penghapusan
# akun yang presisi (per jam) tetap jalan lewat delete_expired
# (jadwalnya di-cron tiap 5 menit) berdasarkan datetime lengkap
# yang disimpan di kolom "exp" pada db.
get_exp_datetime_hours() {
  local hours="$1"
  date -d "+${hours} hours" +"%Y-%m-%d %H:%M:%S"
}

get_exp_date_from_hours() {
  local hours="$1"
  date -d "+${hours} hours" +"%Y-%m-%d"
}

# Format sisa waktu yang enak dibaca, presisi jam/menit kalau < 1 hari
fmt_remaining() {
  local exp="$1"
  local now=$(date +%s)
  local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
  local diff=$(( expd - now ))
  if (( diff < 0 )); then echo "Expired"; return; fi
  if (( diff < 86400 )); then
    echo "$(( diff / 3600 )) jam $(( (diff % 3600) / 60 )) menit"
  else
    echo "$(( diff / 86400 )) hari"
  fi
}

# ─── PRO Config (limit device/IP, limit kuota, Telegram bot) ─
PRO_CONFIG="$SCRIPT_DIR/.pro-config"
load_pro_config() {
  SESSION_LIMIT_DEFAULT=2      # default limit device/IP akun SSH (concurrent session)
  IP_LIMIT_DEFAULT=2           # default limit device/IP akun Xray (vmess/vless/trojan/ss)
  QUOTA_DEFAULT_MB=0           # default kuota per akun dalam MB, 0 = unlimited
  TRIAL_HOURS_DEFAULT=1        # default durasi trial (jam), dipakai saat admin pilih mode trial
  TELEGRAM_BOT_TOKEN=""
  TELEGRAM_CHAT_ID=""
  TG_NOTIFY_CREATE=1           # notif saat akun baru dibuat
  TG_NOTIFY_DELETE=1           # notif saat akun dihapus (manual/expired)
  TG_NOTIFY_LIMIT=1            # notif saat limit device/IP/kuota kelampauan
  [[ -f "$PRO_CONFIG" ]] && source "$PRO_CONFIG"
}
load_pro_config

# ─── Simpan .pro-config (dipakai menu/telegram.sh & addon/sshws-pro.sh) ─
save_pro_config() {
  cat > "$PRO_CONFIG" << EOF
SESSION_LIMIT_DEFAULT=${SESSION_LIMIT_DEFAULT:-2}
IP_LIMIT_DEFAULT=${IP_LIMIT_DEFAULT:-2}
QUOTA_DEFAULT_MB=${QUOTA_DEFAULT_MB:-0}
TRIAL_HOURS_DEFAULT=${TRIAL_HOURS_DEFAULT:-1}
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
TG_NOTIFY_CREATE=${TG_NOTIFY_CREATE:-1}
TG_NOTIFY_DELETE=${TG_NOTIFY_DELETE:-1}
TG_NOTIFY_LIMIT=${TG_NOTIFY_LIMIT:-1}
EOF
  load_pro_config
}

# ─── Telegram Notify (silent no-op kalau belum diconfig) ────
# tipe (opsional): create|delete|limit -- dicek terhadap toggle TG_NOTIFY_*
# supaya bisa dimatikan per jenis event dari menu Bot Telegram.
tg_notify() {
  local msg="$1"
  local tipe="${2:-}"
  [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 0
  case "$tipe" in
    create) [[ "${TG_NOTIFY_CREATE:-1}" == "1" ]] || return 0 ;;
    delete) [[ "${TG_NOTIFY_DELETE:-1}" == "1" ]] || return 0 ;;
    limit)  [[ "${TG_NOTIFY_LIMIT:-1}"  == "1" ]] || return 0 ;;
  esac
  curl -s --fail --max-time 8 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${msg}" \
    --data-urlencode "parse_mode=HTML" >/dev/null 2>&1
}

# ─── Format angka MB jadi label yang enak dibaca ────────────
fmt_quota() {
  local mb="$1"
  [[ -z "$mb" || "$mb" == "0" || ! "$mb" =~ ^[0-9]+$ ]] && { echo "Unlimited"; return; }
  if (( mb >= 1024 )); then
    python3 -c "print(f'{$mb/1024:.2f} GB')" 2>/dev/null || echo "$((mb/1024)) GB"
  else
    echo "${mb} MB"
  fi
}

# ─── Format angka limit device/IP (0 = unlimited) ───────────
fmt_limit() {
  local n="$1"
  [[ -z "$n" || "$n" == "0" || ! "$n" =~ ^[0-9]+$ ]] && { echo "Unlimited"; return; }
  echo "$n"
}

# ─── Get Server IP ─────────────────────────────────────────
get_server_ip() {
  curl -s4 --max-time 3 https://ifconfig.me 2>/dev/null || \
  curl -s4 --max-time 3 https://api.ipify.org 2>/dev/null || \
  hostname -I | awk '{print $1}'
}

# ─── Get VPS Info ──────────────────────────────────────────
get_cpu_info() {
  grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//'
}

get_cpu_cores() {
  nproc
}

get_cpu_usage() {
  top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1 2>/dev/null || echo "N/A"
}

get_mem_usage() {
  free -m | awk 'NR==2{printf "%sMB / %sMB (%.0f%%)", $3, $2, $3*100/$2}'
}

get_disk_usage() {
  df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}'
}

get_uptime() {
  uptime -p 2>/dev/null | sed 's/up //' || uptime | awk '{print $3,$4}' | sed 's/,//'
}

get_os_info() {
  . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || cat /etc/issue | head -1
}

get_kernel() {
  uname -r
}

get_load_avg() {
  uptime | awk -F'load average: ' '{print $2}'
}

get_network_usage() {
  local iface=$(ip route | grep default | awk '{print $5}' | head -1)
  if [[ -n "$iface" ]]; then
    local rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    echo "↓$(numfmt --to=iec $rx 2>/dev/null || echo ${rx}B) ↑$(numfmt --to=iec $tx 2>/dev/null || echo ${tx}B)"
  else
    echo "N/A"
  fi
}

# ─── Service Status ────────────────────────────────────────
service_status() {
  local svc="$1"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -e "${GREEN}● ON${NC}"
  else
    echo -e "${RED}● OFF${NC}"
  fi
}

service_status_text() {
  local svc="$1"
  systemctl is-active --quiet "$svc" 2>/dev/null && echo "ON" || echo "OFF"
}

# ─── UUID Generator ────────────────────────────────────────
gen_uuid() {
  cat /proc/sys/kernel/random/uuid 2>/dev/null || \
  uuid 2>/dev/null || \
  python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
  openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/'
}

# ─── Password Generator ────────────────────────────────────
gen_password() {
  openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16
}

# ─── Date Helpers ──────────────────────────────────────────
get_exp_date() {
  local days="$1"
  date -d "+${days} days" +"%Y-%m-%d"
}

days_until_exp() {
  local exp="$1"
  local today=$(date +%s)
  local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
  echo $(( (expd - today) / 86400 ))
}

is_expired() {
  local exp="$1"
  local days=$(days_until_exp "$exp")
  [[ $days -lt 0 ]]
}

# ════════════════════════════════════════════════════════════
#  XRAY STATS API (dasar utk limit device/IP & limit kuota)
#  ─────────────────────────────────────────────────────────
#  Xray-WS di script ini selalu di-proxy lewat Nginx (127.0.0.1),
#  jadi Xray gak pernah lihat IP asli client (sama persis dengan
#  alasan kenapa SSH-WS pakai session-count, bukan IP -- lihat
#  addon/session-limiter.sh). Makanya "limit IP/device" utk Xray
#  di sini diimplementasikan sebagai LIMIT DEVICE AKTIF BERSAMAAN
#  (statsUserOnline via Xray Stats API), bukan hitung IP unik --
#  secara praktik hasilnya sama: membatasi berapa device yang
#  boleh connect bersamaan per akun. Kuota dihitung dari
#  statsUserUplink/Downlink (byte terpakai per email client).
#  Butuh Xray-core >= 1.8.0 (subcommand `xray api statsquery`).
# ════════════════════════════════════════════════════════════
XRAY_API_ADDR="127.0.0.1:10085"

# Tambal config.json biar Stats API aktif (idempotent, aman dipanggil berkali-kali)
ensure_xray_stats_api() {
  [[ -f "$XRAY_CONFIG" ]] || return 1
  jq -e '.stats and .api and .policy' "$XRAY_CONFIG" >/dev/null 2>&1 && return 0

  local tmp=$(mktemp)
  jq '
    .stats = (.stats // {}) |
    .api = (.api // {"tag":"api","services":["StatsService"]}) |
    .policy = (.policy // {}) |
    .policy.levels = ((.policy.levels // {}) * {"0":{"statsUserUplink":true,"statsUserDownlink":true,"statsUserOnline":true}}) |
    .policy.system = ((.policy.system // {}) * {"statsInboundUplink":true,"statsInboundDownlink":true}) |
    .inbounds = (
      if any(.inbounds[]?; .tag == "api")
      then .inbounds
      else .inbounds + [{"tag":"api","port":10085,"listen":"127.0.0.1","protocol":"dokodemo-door","settings":{"address":"127.0.0.1"}}]
      end
    ) |
    .routing = (.routing // {"rules":[]}) |
    .routing.rules = (
      if any(.routing.rules[]?; .inboundTag[0]? == "api")
      then .routing.rules
      else [{"type":"field","inboundTag":["api"],"outboundTag":"api"}] + .routing.rules
      end
    ) |
    .outbounds = (
      if any(.outbounds[]?; .tag == "api")
      then .outbounds
      else .outbounds + [{"protocol":"freedom","tag":"api","settings":{}}]
      end
    )
  ' "$XRAY_CONFIG" > "$tmp" 2>/dev/null && mv "$tmp" "$XRAY_CONFIG" || { rm -f "$tmp"; return 1; }

  systemctl restart xray 2>/dev/null
  sleep 1
  return 0
}

# Query mentah ke Xray Stats API. Return kosong kalau xray-core belum support.
xray_stat_query() {
  local pattern="$1"
  command -v xray >/dev/null 2>&1 || return 1
  xray api statsquery --server="$XRAY_API_ADDR" -pattern "$pattern" 2>/dev/null
}

# Total byte (uplink+downlink) yang sudah dipakai satu email/username Xray
get_xray_user_traffic_mb() {
  local email="$1"
  local json total_bytes=0
  json=$(xray_stat_query "user>>>${email}>>>traffic")
  [[ -z "$json" ]] && { echo 0; return; }
  total_bytes=$(echo "$json" | jq '[.stat[]?.value | tonumber] | add // 0' 2>/dev/null)
  [[ -z "$total_bytes" || "$total_bytes" == "null" ]] && total_bytes=0
  echo $(( total_bytes / 1024 / 1024 ))
}

# Jumlah device/koneksi yang lagi online bersamaan utk satu email Xray
get_xray_user_online() {
  local email="$1"
  local json count=0
  json=$(xray_stat_query "user>>>${email}>>>online")
  [[ -z "$json" ]] && { echo 0; return; }
  count=$(echo "$json" | jq '[.stat[]?.value | tonumber] | add // 0' 2>/dev/null)
  [[ -z "$count" || "$count" == "null" ]] && count=0
  echo "$count"
}

# Reset counter kuota (uplink+downlink) satu email -- dipakai saat renew/edit
reset_xray_user_traffic() {
  local email="$1"
  command -v xray >/dev/null 2>&1 || return 1
  xray api statsquery --server="$XRAY_API_ADDR" -reset -pattern "user>>>${email}>>>traffic" >/dev/null 2>&1
}

# ════════════════════════════════════════════════════════════
#  SSH QUOTA ACCOUNTING (iptables OUTPUT, per-UID, best-effort)
#  ─────────────────────────────────────────────────────────
#  Dropbear/OpenSSH menjalankan proses akun sebagai UID user itu
#  sendiri setelah autentikasi, jadi -m owner --uid-owner di chain
#  OUTPUT bisa dipakai buat menghitung trafik yang dikirim balik
#  ke client per akun. Ini pendekatan umum dipakai script sejenis
#  utk "limit kuota SSH", TAPI sifatnya best-effort/approksimasi
#  (menghitung arah download client, bukan байт persis dua arah).
#  Uji dulu di VPS asli sebelum dipakai produksi besar-besaran.
# ════════════════════════════════════════════════════════════
ssh_quota_chain() {
  echo "VPNQ_$(echo "$1" | tr -cd 'A-Za-z0-9_' | cut -c1-20)"
}

setup_ssh_quota_accounting() {
  local username="$1"
  command -v iptables >/dev/null 2>&1 || return 1
  local uid; uid=$(id -u "$username" 2>/dev/null) || return 1
  local chain=$(ssh_quota_chain "$username")

  iptables -N "$chain" 2>/dev/null
  iptables -C OUTPUT -m owner --uid-owner "$uid" -j "$chain" 2>/dev/null || \
    iptables -I OUTPUT -m owner --uid-owner "$uid" -j "$chain" 2>/dev/null
  iptables -C "$chain" -j RETURN 2>/dev/null || iptables -A "$chain" -j RETURN 2>/dev/null
}

get_ssh_usage_mb() {
  local username="$1"
  command -v iptables >/dev/null 2>&1 || { echo 0; return; }
  local chain=$(ssh_quota_chain "$username")
  local bytes
  bytes=$(iptables -L "$chain" -v -x -n 2>/dev/null | awk '/RETURN/{sum+=$2} END{print sum+0}')
  echo $(( ${bytes:-0} / 1024 / 1024 ))
}

reset_ssh_usage() {
  local username="$1"
  local chain=$(ssh_quota_chain "$username")
  iptables -Z "$chain" 2>/dev/null
}

teardown_ssh_quota_accounting() {
  local username="$1"
  command -v iptables >/dev/null 2>&1 || return 0
  local uid; uid=$(id -u "$username" 2>/dev/null)
  local chain=$(ssh_quota_chain "$username")
  [[ -n "$uid" ]] && iptables -D OUTPUT -m owner --uid-owner "$uid" -j "$chain" 2>/dev/null
  iptables -F "$chain" 2>/dev/null
  iptables -X "$chain" 2>/dev/null
}

# ════════════════════════════════════════════════════════════
#  QUOTA ENFORCEMENT HELPERS (dipakai addon/quota-limiter.sh)
#  Akun yang kena suspend krn kuota habis DITANDAI (bukan
#  dihapus dari db) supaya gampang di-reaktivasi begitu admin
#  naikin kuota lewat menu "Edit Limit".
# ════════════════════════════════════════════════════════════
QUOTA_DISABLED_DIR="$SCRIPT_DIR/.quota-disabled"
mkdir -p "$QUOTA_DISABLED_DIR" 2>/dev/null

mark_quota_disabled()  { touch "$QUOTA_DISABLED_DIR/${1}_${2}" 2>/dev/null; }
clear_quota_disabled() { rm -f "$QUOTA_DISABLED_DIR/${1}_${2}" 2>/dev/null; }
is_quota_disabled()    { [[ -f "$QUOTA_DISABLED_DIR/${1}_${2}" ]]; }

# Hapus client dari inbound Xray (dipakai saat kuota habis) tanpa
# menyentuh database akun -- akun tetap "ada", cuma gak bisa connect.
xray_disable_client() {
  local tag_prefix="$1" email="$2"
  local tmp=$(mktemp)
  jq --arg email "$email" --arg tp "$tag_prefix" \
    '(.inbounds[] | select(.tag | startswith($tp)) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
}

# Aktifkan lagi client yang sempat disable karena kuota (pakai
# UUID/password yang SUDAH ada di db, bukan bikin baru).
reactivate_xray_client() {
  local proto="$1" username="$2"
  local tmp=$(mktemp)
  case "$proto" in
    vmess)
      local uuid=$(get_vmess_info "$username" | cut -d'|' -f2)
      [[ -z "$uuid" ]] && return 1
      jq --arg uuid "$uuid" --arg email "$username" \
        '(.inbounds[] | select(.tag == "vmess-ws-tls" or .tag == "vmess-ws-ntls") | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $email}]' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG" ;;
    vless)
      local uuid=$(get_vless_info "$username" | cut -d'|' -f2)
      [[ -z "$uuid" ]] && return 1
      jq --arg uuid "$uuid" --arg email "$username" \
        '(.inbounds[] | select(.tag == "vless-ws-tls" or .tag == "vless-ws-ntls" or .tag == "vless-grpc-tls") | .settings.clients) += [{"id": $uuid, "email": $email, "flow": ""}]' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG" ;;
    trojan)
      local pass=$(get_trojan_info "$username" | cut -d'|' -f2)
      [[ -z "$pass" ]] && return 1
      jq --arg pass "$pass" --arg email "$username" \
        '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) += [{"password": $pass, "email": $email}]' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG" ;;
    ss)
      local pass=$(get_ss_info "$username" | cut -d'|' -f2)
      local method=$(get_ss_info "$username" | cut -d'|' -f3)
      [[ -z "$pass" ]] && return 1
      jq --arg pass "$pass" --arg method "$method" \
        '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) += [{"method": $method, "password": $pass}]' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG" ;;
    *) return 1 ;;
  esac
  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
  reset_xray_user_traffic "$username"
  clear_quota_disabled "$proto" "$username"
}

# ════════════════════════════════════════════════════════════
#  VMESS ACCOUNT MANAGEMENT
# ════════════════════════════════════════════════════════════
DB_VMESS="$DB_DIR/vmess.db"

create_vmess() {
  local username="$1"
  local days="$2"
  local ip_limit="${3:-$IP_LIMIT_DEFAULT}"
  local quota_mb="${4:-$QUOTA_DEFAULT_MB}"
  local trial_hours="${5:-0}"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || ip_limit="${IP_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  [[ "$trial_hours" =~ ^[0-9]+$ ]] || trial_hours=0
  local uuid=$(gen_uuid)
  local exp masa_label
  if [[ "$trial_hours" -gt 0 ]]; then
    exp=$(get_exp_datetime_hours "$trial_hours")
    masa_label="Trial ${trial_hours} jam"
  else
    exp=$(get_exp_date "$days")
    masa_label="${days} hari"
  fi
  local created=$(date +"%Y-%m-%d")

  echo "$username|$uuid|$exp|$created|$ip_limit|$quota_mb" >> "$DB_VMESS"

  local tmp=$(mktemp)
  jq --arg uuid "$uuid" --arg email "$username" \
    '(.inbounds[] | select(.tag == "vmess-ws-tls" or .tag == "vmess-ws-ntls") | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $email}]' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null

  local domain=$(get_domain)
  local link_tls=$(gen_vmess_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vmess_link "$username" "$uuid" "$domain" "ntls")

  tg_notify "✅ <b>AKUN VMESS BERHASIL DIBUAT</b>

<b>Username</b>        : <code>$username</code>
<b>UUID</b>            : <code>$uuid</code>
<b>Domain</b>          : <code>$domain</code>
<b>Expired</b>         : <code>$exp</code> ($masa_label)
<b>Limit Device/IP</b> : <code>$(fmt_limit "$ip_limit")</code>
<b>Limit Kuota</b>     : <code>$(fmt_quota "$quota_mb")</code>

<b>── WS TLS (443, path /vmess-ws) ──</b>
<code>$link_tls</code>

<b>── WS nTLS (80, path /vmess-ntls) ──</b>
<code>$link_ntls</code>" "create"

  echo "$uuid"
}

delete_vmess() {
  local username="$1"
  sed -i "/^$username|/d" "$DB_VMESS"

  local tmp=$(mktemp)
  jq --arg email "$username" \
    '(.inbounds[] | select(.tag | startswith("vmess")) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_vmess() {
  local username="$1"
  local days="$2"
  local exp=$(get_exp_date "$days")
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|$exp|\3/" "$DB_VMESS"
}

get_vmess_info() {
  local username="$1"
  grep "^$username|" "$DB_VMESS"
}

list_vmess() {
  cat "$DB_VMESS" 2>/dev/null
}

count_vmess() {
  wc -l < "$DB_VMESS" 2>/dev/null || echo 0
}

# ip_limit = field 5, quota_mb = field 6 (kosong di akun lama = pakai default)
get_vmess_ip_limit()  { get_vmess_info "$1" | cut -d'|' -f5; }
get_vmess_quota_mb()  { get_vmess_info "$1" | cut -d'|' -f6; }

# Rewrite pakai awk (bukan sed capture-group) supaya tetap aman dipakai
# di akun lama yang dibuat sebelum kolom ip_limit/quota_mb ada (cuma 4 field).
edit_vmess_limits() {
  local username="$1" ip_limit="$2" quota_mb="$3"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || ip_limit="${IP_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  grep -q "^$username|" "$DB_VMESS" 2>/dev/null || return 1
  local tmp=$(mktemp)
  awk -F'|' -v u="$username" -v ip="$ip_limit" -v q="$quota_mb" \
    'BEGIN{OFS="|"} $1==u {print $1,$2,$3,$4,ip,q; next} {print}' \
    "$DB_VMESS" > "$tmp" && mv "$tmp" "$DB_VMESS"
  reset_xray_user_traffic "$username"
  is_quota_disabled "vmess" "$username" && reactivate_xray_client "vmess" "$username"
}

# ════════════════════════════════════════════════════════════
#  VLESS ACCOUNT MANAGEMENT
# ════════════════════════════════════════════════════════════
DB_VLESS="$DB_DIR/vless.db"

create_vless() {
  local username="$1"
  local days="$2"
  local ip_limit="${3:-$IP_LIMIT_DEFAULT}"
  local quota_mb="${4:-$QUOTA_DEFAULT_MB}"
  local trial_hours="${5:-0}"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || ip_limit="${IP_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  [[ "$trial_hours" =~ ^[0-9]+$ ]] || trial_hours=0
  local uuid=$(gen_uuid)
  local exp masa_label
  if [[ "$trial_hours" -gt 0 ]]; then
    exp=$(get_exp_datetime_hours "$trial_hours")
    masa_label="Trial ${trial_hours} jam"
  else
    exp=$(get_exp_date "$days")
    masa_label="${days} hari"
  fi
  local created=$(date +"%Y-%m-%d")

  echo "$username|$uuid|$exp|$created|$ip_limit|$quota_mb" >> "$DB_VLESS"

  local tmp=$(mktemp)
  jq --arg uuid "$uuid" --arg email "$username" \
    '(.inbounds[] | select(.tag == "vless-ws-tls" or .tag == "vless-ws-ntls" or .tag == "vless-grpc-tls") | .settings.clients) += [{"id": $uuid, "email": $email, "flow": ""}]' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null

  local domain=$(get_domain)
  local link_tls=$(gen_vless_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vless_link "$username" "$uuid" "$domain" "ntls")
  local link_grpc=$(gen_vless_grpc_link "$username" "$uuid" "$domain")

  tg_notify "✅ <b>AKUN VLESS BERHASIL DIBUAT</b>

<b>Username</b>        : <code>$username</code>
<b>UUID</b>            : <code>$uuid</code>
<b>Domain</b>          : <code>$domain</code>
<b>Expired</b>         : <code>$exp</code> ($masa_label)
<b>Limit Device/IP</b> : <code>$(fmt_limit "$ip_limit")</code>
<b>Limit Kuota</b>     : <code>$(fmt_quota "$quota_mb")</code>

<b>── WS TLS (443, path /vless-ws) ──</b>
<code>$link_tls</code>

<b>── WS nTLS (80, path /vless-ntls) ──</b>
<code>$link_ntls</code>

<b>── gRPC TLS (443, service vless-grpc) ──</b>
<code>$link_grpc</code>" "create"

  echo "$uuid"
}

delete_vless() {
  local username="$1"
  sed -i "/^$username|/d" "$DB_VLESS"

  local tmp=$(mktemp)
  jq --arg email "$username" \
    '(.inbounds[] | select(.tag | startswith("vless")) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_vless() {
  local username="$1"
  local days="$2"
  local exp=$(get_exp_date "$days")
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|$exp|\3/" "$DB_VLESS"
}

get_vless_info() {
  local username="$1"
  grep "^$username|" "$DB_VLESS"
}

list_vless() {
  cat "$DB_VLESS" 2>/dev/null
}

count_vless() {
  wc -l < "$DB_VLESS" 2>/dev/null || echo 0
}

get_vless_ip_limit()  { get_vless_info "$1" | cut -d'|' -f5; }
get_vless_quota_mb()  { get_vless_info "$1" | cut -d'|' -f6; }

edit_vless_limits() {
  local username="$1" ip_limit="$2" quota_mb="$3"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || ip_limit="${IP_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  grep -q "^$username|" "$DB_VLESS" 2>/dev/null || return 1
  local tmp=$(mktemp)
  awk -F'|' -v u="$username" -v ip="$ip_limit" -v q="$quota_mb" \
    'BEGIN{OFS="|"} $1==u {print $1,$2,$3,$4,ip,q; next} {print}' \
    "$DB_VLESS" > "$tmp" && mv "$tmp" "$DB_VLESS"
  reset_xray_user_traffic "$username"
  is_quota_disabled "vless" "$username" && reactivate_xray_client "vless" "$username"
}

# ════════════════════════════════════════════════════════════
#  TROJAN ACCOUNT MANAGEMENT
# ════════════════════════════════════════════════════════════
DB_TROJAN="$DB_DIR/trojan.db"

create_trojan() {
  local username="$1"
  local days="$2"
  local ip_limit="${3:-$IP_LIMIT_DEFAULT}"
  local quota_mb="${4:-$QUOTA_DEFAULT_MB}"
  local trial_hours="${5:-0}"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || ip_limit="${IP_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  [[ "$trial_hours" =~ ^[0-9]+$ ]] || trial_hours=0
  local password=$(gen_password)
  local exp masa_label
  if [[ "$trial_hours" -gt 0 ]]; then
    exp=$(get_exp_datetime_hours "$trial_hours")
    masa_label="Trial ${trial_hours} jam"
  else
    exp=$(get_exp_date "$days")
    masa_label="${days} hari"
  fi
  local created=$(date +"%Y-%m-%d")

  echo "$username|$password|$exp|$created|$ip_limit|$quota_mb" >> "$DB_TROJAN"

  local tmp=$(mktemp)
  jq --arg pass "$password" --arg email "$username" \
    '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) += [{"password": $pass, "email": $email}]' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null

  local domain=$(get_domain)
  local link_ws=$(gen_trojan_link "$username" "$password" "$domain" "ws")
  local link_grpc=$(gen_trojan_link "$username" "$password" "$domain" "grpc")

  tg_notify "✅ <b>AKUN TROJAN BERHASIL DIBUAT</b>

<b>Username</b>        : <code>$username</code>
<b>Password</b>        : <code>$password</code>
<b>Domain</b>          : <code>$domain</code>
<b>Expired</b>         : <code>$exp</code> ($masa_label)
<b>Limit Device/IP</b> : <code>$(fmt_limit "$ip_limit")</code>
<b>Limit Kuota</b>     : <code>$(fmt_quota "$quota_mb")</code>

<b>── WS TLS (443, path /trojan-ws) ──</b>
<code>$link_ws</code>

<b>── gRPC TLS (443, service trojan-grpc) ──</b>
<code>$link_grpc</code>" "create"

  echo "$password"
}

delete_trojan() {
  local username="$1"
  local password=$(grep "^$username|" "$DB_TROJAN" | cut -d'|' -f2)
  sed -i "/^$username|/d" "$DB_TROJAN"

  local tmp=$(mktemp)
  jq --arg pass "$password" \
    '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) |= map(select(.password != $pass))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_trojan() {
  local username="$1"
  local days="$2"
  local exp=$(get_exp_date "$days")
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|$exp|\3/" "$DB_TROJAN"
}

get_trojan_info() {
  local username="$1"
  grep "^$username|" "$DB_TROJAN"
}

list_trojan() {
  cat "$DB_TROJAN" 2>/dev/null
}

count_trojan() {
  wc -l < "$DB_TROJAN" 2>/dev/null || echo 0
}

get_trojan_ip_limit()  { get_trojan_info "$1" | cut -d'|' -f5; }
get_trojan_quota_mb()  { get_trojan_info "$1" | cut -d'|' -f6; }

edit_trojan_limits() {
  local username="$1" ip_limit="$2" quota_mb="$3"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || ip_limit="${IP_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  grep -q "^$username|" "$DB_TROJAN" 2>/dev/null || return 1
  local tmp=$(mktemp)
  awk -F'|' -v u="$username" -v ip="$ip_limit" -v q="$quota_mb" \
    'BEGIN{OFS="|"} $1==u {print $1,$2,$3,$4,ip,q; next} {print}' \
    "$DB_TROJAN" > "$tmp" && mv "$tmp" "$DB_TROJAN"
  reset_xray_user_traffic "$username"
  is_quota_disabled "trojan" "$username" && reactivate_xray_client "trojan" "$username"
}

# ════════════════════════════════════════════════════════════
#  SHADOWSOCKS ACCOUNT MANAGEMENT
# ════════════════════════════════════════════════════════════
DB_SS="$DB_DIR/ss.db"

create_ss() {
  local username="$1"
  local days="$2"
  local ip_limit="${3:-$IP_LIMIT_DEFAULT}"
  local quota_mb="${4:-$QUOTA_DEFAULT_MB}"
  local trial_hours="${5:-0}"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || ip_limit="${IP_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  [[ "$trial_hours" =~ ^[0-9]+$ ]] || trial_hours=0
  local password=$(gen_password)
  local method="aes-128-gcm"
  local exp masa_label
  if [[ "$trial_hours" -gt 0 ]]; then
    exp=$(get_exp_datetime_hours "$trial_hours")
    masa_label="Trial ${trial_hours} jam"
  else
    exp=$(get_exp_date "$days")
    masa_label="${days} hari"
  fi
  local created=$(date +"%Y-%m-%d")

  echo "$username|$password|$method|$exp|$created|$ip_limit|$quota_mb" >> "$DB_SS"

  local tmp=$(mktemp)
  jq --arg pass "$password" --arg method "$method" \
    '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) += [{"method": $method, "password": $pass}]' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null

  local domain=$(get_domain)
  local link_ws=$(gen_ss_link "$username" "$password" "$domain" "ws")
  local link_grpc=$(gen_ss_link "$username" "$password" "$domain" "grpc")

  tg_notify "✅ <b>AKUN SHADOWSOCKS BERHASIL DIBUAT</b>

<b>Username</b>        : <code>$username</code>
<b>Password</b>        : <code>$password</code>
<b>Method</b>          : <code>$method</code>
<b>Domain</b>          : <code>$domain</code>
<b>Expired</b>         : <code>$exp</code> ($masa_label)
<b>Limit Device/IP</b> : <code>$(fmt_limit "$ip_limit")</code>
<b>Limit Kuota</b>     : <code>$(fmt_quota "$quota_mb")</code>

<b>── WS TLS (443, path /ss-ws) ──</b>
<code>$link_ws</code>

<b>── gRPC TLS (443, service ss-grpc) ──</b>
<code>$link_grpc</code>" "create"

  echo "$password"
}

delete_ss() {
  local username="$1"
  local password=$(grep "^$username|" "$DB_SS" | cut -d'|' -f2)
  sed -i "/^$username|/d" "$DB_SS"

  local tmp=$(mktemp)
  jq --arg pass "$password" \
    '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) |= map(select(.password != $pass))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_ss() {
  local username="$1"
  local days="$2"
  local exp=$(get_exp_date "$days")
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|\2|$exp|\4/" "$DB_SS"
}

get_ss_info() {
  local username="$1"
  grep "^$username|" "$DB_SS"
}

list_ss() {
  cat "$DB_SS" 2>/dev/null
}

count_ss() {
  wc -l < "$DB_SS" 2>/dev/null || echo 0
}

get_ss_ip_limit()  { get_ss_info "$1" | cut -d'|' -f6; }
get_ss_quota_mb()  { get_ss_info "$1" | cut -d'|' -f7; }

edit_ss_limits() {
  local username="$1" ip_limit="$2" quota_mb="$3"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || ip_limit="${IP_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  grep -q "^$username|" "$DB_SS" 2>/dev/null || return 1
  local tmp=$(mktemp)
  awk -F'|' -v u="$username" -v ip="$ip_limit" -v q="$quota_mb" \
    'BEGIN{OFS="|"} $1==u {print $1,$2,$3,$4,$5,ip,q; next} {print}' \
    "$DB_SS" > "$tmp" && mv "$tmp" "$DB_SS"
  reset_xray_user_traffic "$username"
  is_quota_disabled "ss" "$username" && reactivate_xray_client "ss" "$username"
}

# ════════════════════════════════════════════════════════════
#  DELETE EXPIRED ACCOUNTS
# ════════════════════════════════════════════════════════════
delete_expired() {
  local today=$(date +%s)
  local domain=$(get_domain)

  # VMess
  while IFS='|' read -r user uuid exp created; do
    [[ -z "$user" ]] && continue
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [[ $expd -lt $today ]]; then
      delete_vmess "$user"
      echo "[$(date)] Deleted expired VMess: $user (exp: $exp)"
      tg_notify "⛔ <b>Akun VMess Expired &amp; Dihapus</b>

Username: <code>$user</code>
Domain: <code>$domain</code>
Expired: <code>$exp</code>" "delete"
    fi
  done < <(cat "$DB_VMESS" 2>/dev/null)

  # VLess
  while IFS='|' read -r user uuid exp created; do
    [[ -z "$user" ]] && continue
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [[ $expd -lt $today ]]; then
      delete_vless "$user"
      echo "[$(date)] Deleted expired VLess: $user (exp: $exp)"
      tg_notify "⛔ <b>Akun VLess Expired &amp; Dihapus</b>

Username: <code>$user</code>
Domain: <code>$domain</code>
Expired: <code>$exp</code>" "delete"
    fi
  done < <(cat "$DB_VLESS" 2>/dev/null)

  # Trojan
  while IFS='|' read -r user pass exp created; do
    [[ -z "$user" ]] && continue
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [[ $expd -lt $today ]]; then
      delete_trojan "$user"
      echo "[$(date)] Deleted expired Trojan: $user (exp: $exp)"
      tg_notify "⛔ <b>Akun Trojan Expired &amp; Dihapus</b>

Username: <code>$user</code>
Domain: <code>$domain</code>
Expired: <code>$exp</code>" "delete"
    fi
  done < <(cat "$DB_TROJAN" 2>/dev/null)

  # Shadowsocks
  while IFS='|' read -r user pass method exp created; do
    [[ -z "$user" ]] && continue
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [[ $expd -lt $today ]]; then
      delete_ss "$user"
      echo "[$(date)] Deleted expired SS: $user (exp: $exp)"
      tg_notify "⛔ <b>Akun Shadowsocks Expired &amp; Dihapus</b>

Username: <code>$user</code>
Domain: <code>$domain</code>
Expired: <code>$exp</code>" "delete"
    fi
  done < <(cat "$DB_SS" 2>/dev/null)

  # SSH
  delete_expired_ssh
}

# ════════════════════════════════════════════════════════════
#  GENERATE LINKS
# ════════════════════════════════════════════════════════════

# ─── VMess Link ────────────────────────────────────────────
gen_vmess_link() {
  local user="$1"
  local uuid="$2"
  local domain="$3"
  local type="${4:-tls}"
  local remark="$5"

  local port path
  if [[ "$type" == "tls" ]]; then
    port=443; path="/vmess-ws"
  else
    port=80; path="/vmess-ntls"
  fi

  local json="{\"v\":\"2\",\"ps\":\"${remark:-$user-vmess-$type}\",\"add\":\"$domain\",\"port\":\"$port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"$path\",\"tls\":\"$type\"}"
  echo "vmess://$(echo -n "$json" | base64 -w 0)"
}

# ─── VLess Link ────────────────────────────────────────────
gen_vless_link() {
  local user="$1"
  local uuid="$2"
  local domain="$3"
  local type="${4:-tls}"
  local remark="$5"

  local port path security
  if [[ "$type" == "tls" ]]; then
    port=443; path="/vless-ws"; security="tls"
  else
    port=80; path="/vless-ntls"; security="none"
  fi

  echo "vless://${uuid}@${domain}:${port}?encryption=none&security=${security}&type=ws&host=${domain}&path=${path}&sni=${domain}#${remark:-$user-vless-$type}"
}

# ─── VLess gRPC Link ───────────────────────────────────────
gen_vless_grpc_link() {
  local user="$1"
  local uuid="$2"
  local domain="$3"
  local remark="$4"

  echo "vless://${uuid}@${domain}:443?encryption=none&security=tls&type=grpc&serviceName=vless-grpc&sni=${domain}#${remark:-$user-vless-grpc}"
}

# ─── Trojan Link ───────────────────────────────────────────
gen_trojan_link() {
  local user="$1"
  local pass="$2"
  local domain="$3"
  local type="${4:-ws}"
  local remark="$5"

  local path
  if [[ "$type" == "grpc" ]]; then
    path="trojan-grpc"
    echo "trojan://${pass}@${domain}:443?security=tls&type=grpc&serviceName=${path}&sni=${domain}#${remark:-$user-trojan-grpc}"
  else
    path="/trojan-ws"
    echo "trojan://${pass}@${domain}:443?security=tls&type=ws&host=${domain}&path=${path}&sni=${domain}#${remark:-$user-trojan-ws}"
  fi
}

# ─── Shadowsocks Link ──────────────────────────────────────
gen_ss_link() {
  local user="$1"
  local pass="$2"
  local domain="$3"
  local type="${4:-ws}"
  local remark="$5"

  local method="aes-128-gcm"
  local path
  if [[ "$type" == "grpc" ]]; then
    path="ss-grpc"
    local base="${method}:${pass}"
    echo "ss://$(echo -n "$base" | base64 -w 0)@${domain}:443?security=tls&type=grpc&serviceName=${path}&sni=${domain}#${remark:-$user-ss-grpc}"
  else
    path="/ss-ws"
    local base="${method}:${pass}"
    echo "ss://$(echo -n "$base" | base64 -w 0)@${domain}:443?security=tls&type=ws&host=${domain}&path=${path}&sni=${domain}#${remark:-$user-ss-ws}"
  fi
}

# ════════════════════════════════════════════════════════════
#  CHANGE DOMAIN
# ════════════════════════════════════════════════════════════
change_domain() {
  local new_domain="$1"
  local old_domain=$(get_domain)

  sed -i "s/$old_domain/$new_domain/g" /etc/nginx/conf.d/xray.conf 2>/dev/null

  systemctl stop nginx 2>/dev/null
  /root/.acme.sh/acme.sh --issue --standalone -d "$new_domain" \
    --keylength ec-256 --httpport 80 2>/dev/null

  /root/.acme.sh/acme.sh --installcert -d "$new_domain" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > /etc/ssl/xray/xray.pem 2>/dev/null; chmod 600 /etc/ssl/xray/xray.pem; systemctl restart xray nginx 2>/dev/null; systemctl reload haproxy 2>/dev/null" 2>/dev/null

  # Selalu pastikan file gabungan (dibutuhkan HAProxy: SSH-SSL port 444 & multiplex 443)
  # ada dan sinkron, terlepas dari apakah reloadcmd di atas sempat kepanggil atau tidak.
  cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > /etc/ssl/xray/xray.pem 2>/dev/null
  chmod 600 /etc/ssl/xray/xray.pem 2>/dev/null

  echo "$new_domain" > $SCRIPT_DIR/domain

  nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null
  systemctl restart xray 2>/dev/null
  systemctl reload haproxy 2>/dev/null
}

# ════════════════════════════════════════════════════════════
#  REGENERATE NGINX CONFIG (single source of truth)
#  Dipakai untuk retrofit VPS yang xray.conf-nya belum punya
#  location /ssh-ws (port benar) & /ssh-ws-ssh. Aman dijalankan
#  berkali-kali: backup otomatis + nginx -t + rollback bila error.
# ════════════════════════════════════════════════════════════
regenerate_nginx_conf() {
  local domain="$1"
  [[ -z "$domain" ]] && domain=$(get_domain)
  local conf="/etc/nginx/conf.d/xray.conf"
  local backup="${conf}.bak.$(date +%Y%m%d%H%M%S)"

  [[ -f "$conf" ]] && cp "$conf" "$backup"
  mkdir -p /etc/nginx/conf.d /var/www/html

  # Kalau addon multiplex (port 443 SSH-SSL + Xray bareng) aktif, https block
  # harus bind ke internal 127.0.0.1:8443 (public 443 dipegang stream{} block)
  local https_listen_lines
  if [[ -f /etc/vpn-script/.multiplex-443-active ]]; then
    https_listen_lines="listen 127.0.0.1:8443 ssl http2;"
  else
    https_listen_lines="listen 443 ssl http2;
    listen [::]:443 ssl http2;"
  fi

  cat > "$conf" <<EOF2
# ============================================================
#   CHANELOG VPN - NGINX ALL-IN-ONE CONFIG (regenerated)
#   Port 80  : VMess nTLS | VLess nTLS | SSH-WS nTLS | SSH-WS-SSH nTLS
#   Port 443 : VMess TLS | VLess TLS | Trojan TLS | SS TLS
#              VMess gRPC | VLess gRPC | Trojan gRPC | SS gRPC
#              SSH-WS TLS | SSH-WS-SSH TLS
#   Port 8880/8080/2080/2082 : SSH-WS / SSH-WS-SSH nTLS (alternatif)
# ============================================================

# ─── Port 80 — non-TLS ───
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location /vmess-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /vless-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10004;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /ssh-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${WS_DROPBEAR_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /ssh-ws-ssh {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${WS_OPENSSH_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF2

  local alt_port
  for alt_port in 8880 8080 2080 2082; do
    cat >> "$conf" <<EOF2

# ─── Port ${alt_port} — SSH-WS / SSH-WS-SSH nTLS (alt) ───
server {
    listen ${alt_port};
    listen [::]:${alt_port};
    server_name ${domain};

    location /ssh-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${WS_DROPBEAR_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /ssh-ws-ssh {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${WS_OPENSSH_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF2
  done

  cat >> "$conf" <<EOF2

# ─── Port 443 — HTTPS/TLS (ALL PROTOCOLS) ───
server {
    ${https_listen_lines}
    server_name ${domain};

    ssl_certificate /etc/ssl/xray/xray.crt;
    ssl_certificate_key /etc/ssl/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    location /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10005;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /trojan-grpc {
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$host;
        grpc_pass grpc://127.0.0.1:10006;
        grpc_connect_timeout 60s;
        grpc_read_timeout 3600s;
    }

    location /ss-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10007;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /ss-grpc {
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$host;
        grpc_pass grpc://127.0.0.1:10008;
        grpc_connect_timeout 60s;
        grpc_read_timeout 3600s;
    }

    location /vless-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /vless-grpc {
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$host;
        grpc_pass grpc://127.0.0.1:10009;
        grpc_connect_timeout 60s;
        grpc_read_timeout 3600s;
    }

    location /vmess-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /vmess-grpc {
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$host;
        grpc_pass grpc://127.0.0.1:10010;
        grpc_connect_timeout 60s;
        grpc_read_timeout 3600s;
    }

    location /ssh-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${WS_DROPBEAR_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location /ssh-ws-ssh {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${WS_OPENSSH_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 3600s;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF2

  if [[ ! -f /var/www/html/index.html ]]; then
    cat > /var/www/html/index.html <<EOF3
<!DOCTYPE html>
<html>
<head><title>${domain}</title></head>
<body style="background:#1a1a2e;color:#e0e0e0;font-family:monospace;text-align:center;padding:50px">
<h1 style="color:#00d4ff">Server Running</h1>
<p>Secure VPN Tunnel Server</p>
</body>
</html>
EOF3
  fi

  if nginx -t 2>/tmp/nginx_test_err.txt; then
    systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null
    rm -f /tmp/nginx_test_err.txt
    return 0
  else
    echo -e "${RED}[GAGAL]${NC} Konfigurasi nginx baru error, rollback..." >&2
    cat /tmp/nginx_test_err.txt >&2
    [[ -f "$backup" ]] && cp "$backup" "$conf"
    systemctl reload nginx 2>/dev/null
    return 1
  fi
}

# ════════════════════════════════════════════════════════════
#  SSH / SSH-WS / SSH-SSL (ADDON)
# ════════════════════════════════════════════════════════════
DB_SSH="$DB_DIR/ssh.db"

# Port backend proxy SSH-WS (dipakai systemd ws-dropbear/ws-openssh
# DAN oleh konfigurasi Nginx di bawah — HARUS selalu sinkron)
WS_DROPBEAR_PORT=2095   # nginx /ssh-ws      -> ws-dropbear -> dropbear:109
WS_OPENSSH_PORT=2093    # nginx /ssh-ws-ssh  -> ws-openssh  -> sshd:22
SSH_BACKEND_PORT=143    # stunnel4/HAProxy (SSL, SNI-only, tanpa payload) -> dropbear:143 LANGSUNG
STUNNEL_SSL_PORT=777    # Dropbear SSL (stunnel4, SNI-only) - konvensi umum komunitas SSH-WS
HAPROXY_SSL_PORT=444     # OpenSSH SSL (haproxy, SNI-only) - konvensi umum komunitas SSH-WS

gen_ssh_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 10 || \
  openssl rand -base64 8 | tr -dc 'A-Za-z0-9' | head -c 10
}

create_ssh() {
  local username="$1"
  local days="$2"
  local password="${3:-$(gen_ssh_password)}"
  local session_limit="${4:-$SESSION_LIMIT_DEFAULT}"
  local quota_mb="${5:-$QUOTA_DEFAULT_MB}"
  local trial_hours="${6:-0}"
  [[ "$session_limit" =~ ^[0-9]+$ ]] || session_limit="${SESSION_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  [[ "$trial_hours" =~ ^[0-9]+$ ]] || trial_hours=0

  local exp exp_useradd masa_label
  if [[ "$trial_hours" -gt 0 ]]; then
    exp=$(get_exp_datetime_hours "$trial_hours")
    exp_useradd=$(get_exp_date_from_hours "$trial_hours")
    masa_label="Trial ${trial_hours} jam"
  else
    exp=$(get_exp_date "$days")
    exp_useradd="$exp"
    masa_label="${days} hari"
  fi
  local created=$(date +"%Y-%m-%d")

  # Jaring pengaman: Dropbear menolak login (tampak sebagai 'password salah')
  # untuk akun dengan shell yang gak terdaftar di /etc/shells.
  grep -qxF "/bin/false" /etc/shells 2>/dev/null || echo "/bin/false" >> /etc/shells

  useradd -e "$exp_useradd" -s /bin/false -M "$username" 2>/dev/null
  echo "$username:$password" | chpasswd 2>/dev/null

  echo "$username|$password|$exp|$created|$session_limit|$quota_mb" >> "$DB_SSH"
  [[ "$quota_mb" -gt 0 ]] && setup_ssh_quota_accounting "$username"

  local domain=$(get_domain)
  local payload_ws=$(ws_payload_string "$domain" "80" "/ssh-ws")
  local payload_ws_ssh=$(ws_payload_string "$domain" "80" "/ssh-ws-ssh")

  tg_notify "✅ <b>AKUN SSH BERHASIL DIBUAT</b>

<b>Username</b>        : <code>$username</code>
<b>Password</b>        : <code>$password</code>
<b>Domain/IP</b>       : <code>$domain</code>
<b>Expired</b>         : <code>$exp</code> ($masa_label)
<b>Limit Sesi</b>      : <code>$(fmt_limit "$session_limit")</code>
<b>Limit Kuota</b>     : <code>$(fmt_quota "$quota_mb")</code>

<b>── Port Koneksi ──</b>
SSH Direct   : 442 / 109 / 143
SSH-SSL      : $STUNNEL_SSL_PORT (Dropbear) / $HAPROXY_SSL_PORT (OpenSSH) — SNI bebas, tanpa payload
SSH-WS nTLS  : 80 / 8880 / 8080 / 2080 / 2082
SSH-WS TLS   : 443
Path         : /ssh-ws (Dropbear) atau /ssh-ws-ssh (OpenSSH)

<b>── Payload WS ──</b>
Dropbear:
<code>$payload_ws</code>

OpenSSH:
<code>$payload_ws_ssh</code>" "create"

  echo "$password"
}

get_ssh_quota_mb() { get_ssh_info "$1" | cut -d'|' -f6; }

edit_ssh_limits() {
  local username="$1" session_limit="$2" quota_mb="$3"
  [[ "$session_limit" =~ ^[0-9]+$ ]] || session_limit="${SESSION_LIMIT_DEFAULT:-2}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || quota_mb="${QUOTA_DEFAULT_MB:-0}"
  grep -q "^$username|" "$DB_SSH" 2>/dev/null || return 1
  local tmp=$(mktemp)
  awk -F'|' -v u="$username" -v s="$session_limit" -v q="$quota_mb" \
    'BEGIN{OFS="|"} $1==u {print $1,$2,$3,$4,s,q; next} {print}' \
    "$DB_SSH" > "$tmp" && mv "$tmp" "$DB_SSH"
  [[ "$quota_mb" -gt 0 ]] && setup_ssh_quota_accounting "$username"
  reset_ssh_usage "$username"
  if is_quota_disabled "ssh" "$username"; then
    usermod -U "$username" 2>/dev/null
    clear_quota_disabled "ssh" "$username"
  fi
}

delete_ssh() {
  local username="$1"
  userdel -f "$username" 2>/dev/null
  teardown_ssh_quota_accounting "$username"
  sed -i "/^$username|/d" "$DB_SSH"
}

renew_ssh() {
  local username="$1"
  local days="$2"
  local exp=$(get_exp_date "$days")
  chage -E "$exp" "$username" 2>/dev/null
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|$exp|\3/" "$DB_SSH"
}

get_ssh_info() {
  local username="$1"
  grep "^$username|" "$DB_SSH" 2>/dev/null
}

list_ssh() {
  cat "$DB_SSH" 2>/dev/null
}

count_ssh() {
  wc -l < "$DB_SSH" 2>/dev/null || echo 0
}

delete_expired_ssh() {
  local today=$(date +%s)
  local domain=$(get_domain)
  while IFS='|' read -r user pass exp created limit; do
    [[ -z "$user" ]] && continue
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [[ $expd -lt $today ]]; then
      delete_ssh "$user"
      echo "[$(date)] Deleted expired SSH: $user (exp: $exp)"
      tg_notify "⛔ <b>Akun SSH Expired &amp; Dihapus</b>

Username: <code>$user</code>
Domain: <code>$domain</code>
Expired: <code>$exp</code>" "delete"
    fi
  done < <(list_ssh)
}

# ════════════════════════════════════════════════════════════
#  SERVICE MANAGEMENT
# ════════════════════════════════════════════════════════════
MANAGED_SERVICES=(xray nginx dropbear stunnel4 ws-dropbear ws-openssh haproxy)

service_display_name() {
  case "$1" in
    xray)        echo "Xray (All Protocols)" ;;
    nginx)       echo "Nginx" ;;
    dropbear)    echo "Dropbear SSH" ;;
    stunnel4)    echo "Stunnel4 (SSH-SSL, langsung ke Dropbear)" ;;
    ws-dropbear) echo "SSH-WS -> Dropbear" ;;
    ws-openssh)  echo "SSH-WS-SSH -> OpenSSH" ;;
    haproxy)     echo "HAProxy (SSH-SSL -> OpenSSH, port $HAPROXY_SSL_PORT)" ;;
    *)           echo "$1" ;;
  esac
}

is_service_installed() {
  local svc="$1"
  systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service" && return 0
  command -v "$svc" &>/dev/null && return 0
  return 1
}

service_toggle_start()   { systemctl start   "$1" 2>/dev/null || service "$1" start   2>/dev/null; }
service_toggle_stop()    { systemctl stop    "$1" 2>/dev/null || service "$1" stop    2>/dev/null; }
service_toggle_restart() { systemctl restart "$1" 2>/dev/null || service "$1" restart 2>/dev/null; }

# ════════════════════════════════════════════════════════════
#  AUTO-UPDATE
# ════════════════════════════════════════════════════════════
UPDATE_RAW="https://raw.githubusercontent.com/oghc93/All-Tun/main"
VERSION_FILE="$SCRIPT_DIR/VERSION"

get_local_version() {
  cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0"
}

get_remote_version() {
  curl -s --max-time 10 "$UPDATE_RAW/VERSION" 2>/dev/null
}

check_update_available() {
  local local_v remote_v
  local_v=$(get_local_version)
  remote_v=$(get_remote_version)
  [[ -z "$remote_v" ]] && return 1
  [[ "$local_v" != "$remote_v" ]] && { echo "$remote_v"; return 0; }
  return 1
}

UPDATE_FILES=(
  "lib.sh"
  "menu.sh"
  "menu/vmess.sh"
  "menu/vless.sh"
  "menu/trojan.sh"
  "menu/ss.sh"
  "menu/nginx.sh"
  "menu/dropbear.sh"
  "menu/haproxy.sh"
  "menu/sysinfo.sh"
  "menu/changedomain.sh"
  "menu/uninstall.sh"
  "menu/sshws.sh"
  "menu/services.sh"
  "menu/update.sh"
  "menu/telegram.sh"
  "menu/rebuild.sh"
)

update_fetch_file() {
  local relpath="$1"
  local tmp
  tmp=$(mktemp)
  if wget -q --timeout=30 "$UPDATE_RAW/$relpath" -O "$tmp" && [[ -s "$tmp" ]]; then
    mkdir -p "$(dirname "$SCRIPT_DIR/$relpath")"
    cp "$tmp" "$SCRIPT_DIR/$relpath"
    chmod +x "$SCRIPT_DIR/$relpath" 2>/dev/null
    rm -f "$tmp"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

update_fetch_addon_bin() {
  local tmp
  tmp=$(mktemp)
  if wget -q --timeout=30 "$UPDATE_RAW/addon/install-sshws.sh" -O "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mkdir -p "$SCRIPT_DIR/addon"
    cp "$tmp" "$SCRIPT_DIR/addon/install-sshws.sh"
    chmod +x "$SCRIPT_DIR/addon/install-sshws.sh"
    rm -f "$tmp"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

update_fetch_haproxy_addon() {
  local tmp
  tmp=$(mktemp)
  if wget -q --timeout=30 "$UPDATE_RAW/addon/haproxy-sshws-ssl.sh" -O "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mkdir -p "$SCRIPT_DIR/addon"
    cp "$tmp" "$SCRIPT_DIR/addon/haproxy-sshws-ssl.sh"
    chmod +x "$SCRIPT_DIR/addon/haproxy-sshws-ssl.sh"
    rm -f "$tmp"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

update_fetch_multiplex_addon() {
  local tmp
  tmp=$(mktemp)
  if wget -q --timeout=30 "$UPDATE_RAW/addon/enable-ssl-multiplex.sh" -O "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mkdir -p "$SCRIPT_DIR/addon"
    cp "$tmp" "$SCRIPT_DIR/addon/enable-ssl-multiplex.sh"
    chmod +x "$SCRIPT_DIR/addon/enable-ssl-multiplex.sh"
    rm -f "$tmp"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

update_fetch_limiter_addons() {
  local f ok=true
  for f in xray-device-limiter.sh quota-limiter.sh; do
    local tmp; tmp=$(mktemp)
    if wget -q --timeout=30 "$UPDATE_RAW/addon/$f" -O "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
      mkdir -p "$SCRIPT_DIR/addon"
      cp "$tmp" "$SCRIPT_DIR/addon/$f"
      chmod +x "$SCRIPT_DIR/addon/$f"
    else
      ok=false
    fi
    rm -f "$tmp"
  done
  [[ "$ok" == "true" ]]
}

run_update() {
  local remote_v="$1"
  local ok=true
  local f
  for f in "${UPDATE_FILES[@]}"; do
    echo -ne "  Updating $f..."
    if update_fetch_file "$f"; then
      echo -e " ${GREEN}OK${NC}"
    else
      echo -e " ${YELLOW}SKIP${NC}"
      ok=false
    fi
  done

  echo -ne "  Updating addon/install-sshws.sh..."
  if update_fetch_addon_bin; then
    echo -e " ${GREEN}OK${NC}"
  else
    echo -e " ${YELLOW}SKIP${NC}"
  fi

  echo -ne "  Updating addon/haproxy-sshws-ssl.sh..."
  if update_fetch_haproxy_addon; then
    echo -e " ${GREEN}OK${NC}"
  else
    echo -e " ${YELLOW}SKIP${NC}"
  fi

  echo -ne "  Updating addon/enable-ssl-multiplex.sh..."
  if update_fetch_multiplex_addon; then
    echo -e " ${GREEN}OK${NC}"
  else
    echo -e " ${YELLOW}SKIP${NC}"
  fi

  echo -ne "  Updating addon/xray-device-limiter.sh & quota-limiter.sh..."
  if update_fetch_limiter_addons; then
    echo -e " ${GREEN}OK${NC}"
  else
    echo -e " ${YELLOW}SKIP${NC}"
  fi

  ensure_xray_stats_api

  echo "$remote_v" > "$VERSION_FILE"
  [[ "$ok" == "true" ]]
}

# Make functions available when sourced
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && "$@"
