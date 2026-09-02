#!/bin/bash
# ============================================================
#  CHANELOG VPN SCRIPT - QUOTA LIMITER (PRO)
#  Jalan via cron tiap 10 menit. Cek pemakaian data per akun
#  (SSH + VMess/VLess/Trojan/Shadowsocks) lawan limit kuota yang
#  di-set saat bikin akun / lewat menu Edit Limit. Kalau lampau,
#  akun di-suspend (bukan dihapus) + notifikasi Telegram. Admin
#  tinggal naikin kuota lewat menu utk otomatis reaktivasi.
#
#  Catatan kuota SSH: dihitung dari iptables OUTPUT accounting
#  per-UID (lihat lib.sh) -- best-effort/approksimasi, bukan
#  ukuran byte dua-arah yang presisi 100%.
#  Catatan kuota Xray: dari Xray Stats API (statsUserUplink/
#  Downlink), presisi karena memang API resmi Xray.
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

STATE_DIR="$SCRIPT_DIR/.quota-limiter-state"
mkdir -p "$STATE_DIR"
COOLDOWN_SEC=3600

notify_quota_habis() {
  local proto="$1" user="$2" used="$3" limit="$4"
  local state_file="$STATE_DIR/${proto}_${user}"
  local last=$(cat "$state_file" 2>/dev/null || echo 0)
  local now=$(date +%s)
  logger -t vpn-script "quota-limiter: [$proto] '$user' kuota habis ($(fmt_quota "$used") / $(fmt_quota "$limit")), akun disuspend"
  if (( now - last >= COOLDOWN_SEC )); then
    tg_notify "📵 <b>Kuota Habis - Akun Disuspend</b>

Protokol: <code>$proto</code>
Username: <code>$user</code>
Terpakai: <code>$(fmt_quota "$used")</code> / Limit: <code>$(fmt_quota "$limit")</code>
Aksi: akun disuspend. Naikkan kuota lewat menu utk aktifkan lagi." "limit"
    echo "$now" > "$state_file"
  fi
}

# ── SSH ──
while IFS='|' read -r user pass exp created slimit quota_mb; do
  [[ -z "$user" ]] && continue
  quota_mb="${quota_mb:-0}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || continue
  [[ "$quota_mb" -eq 0 ]] && continue
  is_quota_disabled "ssh" "$user" && continue
  used=$(get_ssh_usage_mb "$user")
  if [[ "$used" -ge "$quota_mb" ]]; then
    usermod -L "$user" 2>/dev/null
    pkill -9 -u "$user" 2>/dev/null
    mark_quota_disabled "ssh" "$user"
    notify_quota_habis "SSH/SSH-WS" "$user" "$used" "$quota_mb"
  fi
done < <(list_ssh)

# ── VMess ──
while IFS='|' read -r user uuid exp created ip_limit quota_mb; do
  [[ -z "$user" ]] && continue
  quota_mb="${quota_mb:-0}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || continue
  [[ "$quota_mb" -eq 0 ]] && continue
  is_quota_disabled "vmess" "$user" && continue
  used=$(get_xray_user_traffic_mb "$user")
  if [[ "$used" -ge "$quota_mb" ]]; then
    xray_disable_client "vmess" "$user"
    mark_quota_disabled "vmess" "$user"
    notify_quota_habis "VMess" "$user" "$used" "$quota_mb"
  fi
done < <(list_vmess)

# ── VLess ──
while IFS='|' read -r user uuid exp created ip_limit quota_mb; do
  [[ -z "$user" ]] && continue
  quota_mb="${quota_mb:-0}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || continue
  [[ "$quota_mb" -eq 0 ]] && continue
  is_quota_disabled "vless" "$user" && continue
  used=$(get_xray_user_traffic_mb "$user")
  if [[ "$used" -ge "$quota_mb" ]]; then
    xray_disable_client "vless" "$user"
    mark_quota_disabled "vless" "$user"
    notify_quota_habis "VLess" "$user" "$used" "$quota_mb"
  fi
done < <(list_vless)

# ── Trojan ──
while IFS='|' read -r user pass exp created ip_limit quota_mb; do
  [[ -z "$user" ]] && continue
  quota_mb="${quota_mb:-0}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || continue
  [[ "$quota_mb" -eq 0 ]] && continue
  is_quota_disabled "trojan" "$user" && continue
  used=$(get_xray_user_traffic_mb "$user")
  if [[ "$used" -ge "$quota_mb" ]]; then
    xray_disable_client "trojan" "$user"
    mark_quota_disabled "trojan" "$user"
    notify_quota_habis "Trojan" "$user" "$used" "$quota_mb"
  fi
done < <(list_trojan)

# ── Shadowsocks ──
while IFS='|' read -r user pass method exp created ip_limit quota_mb; do
  [[ -z "$user" ]] && continue
  quota_mb="${quota_mb:-0}"
  [[ "$quota_mb" =~ ^[0-9]+$ ]] || continue
  [[ "$quota_mb" -eq 0 ]] && continue
  is_quota_disabled "ss" "$user" && continue
  used=$(get_xray_user_traffic_mb "$user")
  if [[ "$used" -ge "$quota_mb" ]]; then
    xray_disable_client "ss-" "$user"
    mark_quota_disabled "ss" "$user"
    notify_quota_habis "Shadowsocks" "$user" "$used" "$quota_mb"
  fi
done < <(list_ss)

systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
