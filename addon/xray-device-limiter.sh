#!/bin/bash
# ============================================================
#  CHANELOG VPN SCRIPT - XRAY DEVICE/IP LIMITER (PRO)
#  Jalan via cron tiap 2 menit. Batasi jumlah DEVICE AKTIF
#  BERSAMAAN per akun VMess/VLess/Trojan/Shadowsocks, pakai
#  Xray Stats API (statsUserOnline) -- lihat catatan panjang
#  di lib.sh (bagian "XRAY STATS API") kenapa ini yang dipakai
#  ketimbang hitung IP asli (Xray selalu di belakang Nginx jadi
#  gak pernah lihat IP client sesungguhnya).
#
#  Aksi saat kelampauan: client di-remove lalu di-add ulang
#  dengan UUID/password yang SAMA (bukan generate baru) di
#  config Xray -- ini bikin semua koneksi aktif saat itu putus,
#  akun tetap bisa dipakai lagi begitu reconnect (sama seperti
#  pola pkill di session-limiter.sh utk SSH).
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

STATE_DIR="$SCRIPT_DIR/.device-limiter-state"
mkdir -p "$STATE_DIR"
COOLDOWN_SEC=3600

command -v xray >/dev/null 2>&1 || exit 0
ensure_xray_stats_api || exit 0

kick_client() {
  local tag_prefix="$1" match_field="$2" match_value="$3" email="$4"
  local tmp=$(mktemp)
  jq --arg email "$email" --arg tp "$tag_prefix" \
    '(.inbounds[] | select(.tag | startswith($tp)) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
}

notify_and_log() {
  local proto="$1" user="$2" count="$3" limit="$4"
  logger -t vpn-script "device-limiter: [$proto] '$user' melebihi limit ($count/$limit device), sesi diputus"
  local state_file="$STATE_DIR/${proto}_${user}"
  local last=$(cat "$state_file" 2>/dev/null || echo 0)
  local now=$(date +%s)
  if (( now - last >= COOLDOWN_SEC )); then
    tg_notify "🚫 <b>Limit Device/IP Terlampaui</b>

Protokol: <code>$proto</code>
Username: <code>$user</code>
Device aktif: <code>$count</code> (limit: <code>$limit</code>)
Aksi: sesi diputus, user perlu reconnect" "limit"
    echo "$now" > "$state_file"
  fi
}

# ── VMess ──
while IFS='|' read -r user uuid exp created ip_limit quota_mb; do
  [[ -z "$user" ]] && continue
  ip_limit="${ip_limit:-$IP_LIMIT_DEFAULT}"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || continue
  [[ "$ip_limit" -eq 0 ]] && continue
  online=$(get_xray_user_online "$user")
  if [[ "$online" -gt "$ip_limit" ]]; then
    kick_client "vmess" "id" "$uuid" "$user"
    jq --arg uuid "$uuid" --arg email "$user" \
      '(.inbounds[] | select(.tag == "vmess-ws-tls" or .tag == "vmess-ws-ntls") | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $email}]' \
      "$XRAY_CONFIG" > /tmp/xr.$$ && mv /tmp/xr.$$ "$XRAY_CONFIG"
    notify_and_log "VMess" "$user" "$online" "$ip_limit"
  fi
done < <(list_vmess)

# ── VLess ──
while IFS='|' read -r user uuid exp created ip_limit quota_mb; do
  [[ -z "$user" ]] && continue
  ip_limit="${ip_limit:-$IP_LIMIT_DEFAULT}"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || continue
  [[ "$ip_limit" -eq 0 ]] && continue
  online=$(get_xray_user_online "$user")
  if [[ "$online" -gt "$ip_limit" ]]; then
    kick_client "vless" "id" "$uuid" "$user"
    jq --arg uuid "$uuid" --arg email "$user" \
      '(.inbounds[] | select(.tag == "vless-ws-tls" or .tag == "vless-ws-ntls" or .tag == "vless-grpc-tls") | .settings.clients) += [{"id": $uuid, "email": $email, "flow": ""}]' \
      "$XRAY_CONFIG" > /tmp/xr.$$ && mv /tmp/xr.$$ "$XRAY_CONFIG"
    notify_and_log "VLess" "$user" "$online" "$ip_limit"
  fi
done < <(list_vless)

# ── Trojan ──
while IFS='|' read -r user pass exp created ip_limit quota_mb; do
  [[ -z "$user" ]] && continue
  ip_limit="${ip_limit:-$IP_LIMIT_DEFAULT}"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || continue
  [[ "$ip_limit" -eq 0 ]] && continue
  online=$(get_xray_user_online "$user")
  if [[ "$online" -gt "$ip_limit" ]]; then
    kick_client "trojan" "password" "$pass" "$user"
    jq --arg pass "$pass" --arg email "$user" \
      '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) += [{"password": $pass, "email": $email}]' \
      "$XRAY_CONFIG" > /tmp/xr.$$ && mv /tmp/xr.$$ "$XRAY_CONFIG"
    notify_and_log "Trojan" "$user" "$online" "$ip_limit"
  fi
done < <(list_trojan)

# ── Shadowsocks ──
while IFS='|' read -r user pass method exp created ip_limit quota_mb; do
  [[ -z "$user" ]] && continue
  ip_limit="${ip_limit:-$IP_LIMIT_DEFAULT}"
  [[ "$ip_limit" =~ ^[0-9]+$ ]] || continue
  [[ "$ip_limit" -eq 0 ]] && continue
  online=$(get_xray_user_online "$user")
  if [[ "$online" -gt "$ip_limit" ]]; then
    kick_client "ss-" "password" "$pass" "$user"
    jq --arg pass "$pass" --arg method "$method" \
      '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) += [{"method": $method, "password": $pass}]' \
      "$XRAY_CONFIG" > /tmp/xr.$$ && mv /tmp/xr.$$ "$XRAY_CONFIG"
    notify_and_log "Shadowsocks" "$user" "$online" "$ip_limit"
  fi
done < <(list_ss)

systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
