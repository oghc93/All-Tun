#!/bin/bash
# ============================================================
#  CHANELOG VPN SCRIPT - SESSION LIMITER (PRO)
#  Jalan via cron tiap 2 menit. Batasi jumlah SESI AKTIF
#  BERSAMAAN per akun SSH (bukan per-IP -- lihat catatan di
#  README/pesan instalasi kenapa session-count yang dipakai,
#  bukan IP, untuk jalur SSH-SSL/SSH-WS yang lewat proxy).
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

STATE_DIR="$SCRIPT_DIR/.session-limiter-state"
mkdir -p "$STATE_DIR"
COOLDOWN_SEC=3600   # jangan notify user yang sama lebih dari 1x/jam

while IFS='|' read -r user pass exp created limit; do
  [[ -z "$user" ]] && continue
  limit="${limit:-$SESSION_LIMIT_DEFAULT}"

  # limit <= 0 (atau bukan angka) = unlimited, skip akun ini
  [[ "$limit" =~ ^[0-9]+$ ]] || continue
  [[ "$limit" -eq 0 ]] && continue

  count=$(pgrep -u "$user" 2>/dev/null | wc -l)

  if [[ "$count" -gt "$limit" ]]; then
    pkill -9 -u "$user" 2>/dev/null
    logger -t vpn-script "session-limiter: '$user' melebihi limit ($count/$limit sesi), semua sesi diputus"

    state_file="$STATE_DIR/$user"
    last=$(cat "$state_file" 2>/dev/null || echo 0)
    now=$(date +%s)
    if (( now - last >= COOLDOWN_SEC )); then
      tg_notify "🚫 <b>Session Limit Terlampaui</b>

Username: <code>$user</code>
Sesi aktif: <code>$count</code> (limit: <code>$limit</code>)
Aksi: semua sesi diputus, user perlu reconnect"
      echo "$now" > "$state_file"
    fi
  fi
done < <(list_ssh)
