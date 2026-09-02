#!/bin/bash
#===============================================================================
# limit-all.sh — Anti-Abuse Limiter untuk All-Tun (SSHWS + Xray)
#
# Fungsi:
#   1. Memutus paksa akun SSH/SSHWS (sshd & dropbear) yang sesi aktifnya
#      melebihi MAX_SSH_SESSION.
#   2. Menonaktifkan akun Xray (Vmess/Vless/Trojan) yang diakses dari jumlah
#      IP unik melebihi MAX_XRAY_IP (dibaca dari /var/log/xray/access.log).
#   3. Semua tindakan dicatat ke /var/log/all-tun-limit.log.
#
# Cara pakai   : taruh di /etc/vpn-script/addon/limit-all.sh lalu chmod +x
# Dijalankan   : via cron tiap 1 menit (lihat blok "REGISTRASI CRON" di paling
#                bawah file ini untuk baris yang perlu ditempel ke install.sh)
#
# CATATAN PENTING soal poin 2 (Xray/IP) — WAJIB DIBACA:
#   Berdasarkan install.sh punya kamu, Nginx mem-proxy_pass semua traffic
#   WS/TLS Xray dari port 443 ke port lokal Xray (127.0.0.1:1000x). Karena
#   Nginx yang menerima koneksi client lalu meneruskannya ke Xray, Xray HANYA
#   melihat IP sumber = 127.0.0.1 (alamat Nginx), BUKAN IP asli device client
#   -- ini bukan bug script ini, tapi konsekuensi arsitektur reverse-proxy.
#   Akibatnya, logika "hitung IP unik dari access.log" di bawah TIDAK akan
#   akurat selama kondisi ini belum diperbaiki di sisi Nginx/Xray.
#   Dua opsi perbaikan (pilih salah satu, di luar scope script ini):
#     a) Aktifkan PROXY protocol: `proxy_protocol on;` di listen Nginx +
#        `"acceptProxyProtocol": true` di sockopt inbound Xray, supaya IP asli
#        client ikut diteruskan dan tercatat benar di access.log.
#     b) Pakai pendekatan Xray Stats API (statsUserOnline) seperti yang sudah
#        kamu punya di addon/xray-device-limiter.sh -- ini menghitung jumlah
#        device yang online bersamaan, bukan IP asli, jadi otomatis kebal
#        terhadap masalah reverse-proxy di atas.
#   Script ini tetap dibuat sesuai spesifikasi yang kamu minta (baca
#   access.log), supaya bisa langsung dipakai begitu opsi (a) di atas aktif,
#   atau untuk skenario lain di mana Xray menerima koneksi langsung (tanpa
#   reverse proxy) dan benar-benar melihat IP asli client.
#===============================================================================

# ─────────────────────────────────────────────────────────────
# 1. ATURAN LIMITASI (ubah sesuai kebutuhan)
# ─────────────────────────────────────────────────────────────
MAX_SSH_SESSION=2          # maksimal sesi sshd/dropbear aktif bersamaan per akun
MAX_XRAY_IP=2               # maksimal IP unik aktif bersamaan per akun Xray

XRAY_LOG="/var/log/xray/access.log"     # sumber log akses Xray
XRAY_CONFIG="/etc/xray/config.json"     # config Xray yang akan diedit saat blokir
LOG_FILE="/var/log/all-tun-limit.log"   # log kejadian (siapa kena limit, kapan)
LOCK_FILE="/var/run/all-tun-limit.lock" # lock file anti-tabrakan antar-run cron
XRAY_LOG_LINES=500                      # jumlah baris terakhir access.log yang dibaca

# ─────────────────────────────────────────────────────────────
# GUARD: cegah 2 instance script jalan bersamaan.
# Karena cron memanggil script ini tiap 1 menit, kalau eksekusi
# sebelumnya belum selesai (server lagi berat / log raksasa),
# run baru cukup di-skip saja daripada numpuk proses.
# ─────────────────────────────────────────────────────────────
exec 200>"$LOCK_FILE"
flock -n 200 || exit 0

# ─────────────────────────────────────────────────────────────
# FUNGSI LOGGING
# Menulis satu baris kejadian ke $LOG_FILE lengkap dengan timestamp.
# ─────────────────────────────────────────────────────────────
log_action() {
    local pesan="$1"
    local waktu
    waktu=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$waktu] $pesan" >> "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────
# 2. LOGIKA LIMIT SESI SSHWS (sshd & dropbear)
# ─────────────────────────────────────────────────────────────
limit_sshws() {
    # Ambil semua username lokal dengan UID >= 1000 (akun SSHWS dibuat lewat
    # useradd biasa, jadi otomatis dapat UID >= 1000; UID 65534 = "nobody"
    # sengaja dikecualikan karena itu bukan akun user sungguhan).
    local daftar_user
    daftar_user=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)
    [[ -z "$daftar_user" ]] && return

    # Ambil snapshot SEMUA proses di server HANYA SEKALI (satu kali panggil
    # `ps`), lalu hitung jumlah proses sshd/dropbear per pemilik dengan awk.
    # Ini jauh lebih hemat CPU dibanding memanggil `ps`/`pgrep` satu-persatu
    # untuk tiap user (bayangkan kalau ada 200 akun aktif di server).
    local hasil_hitung
    hasil_hitung=$(ps -eo user:32,comm --no-headers 2>/dev/null \
        | awk '$2 == "sshd" || $2 == "dropbear" {print $1}' \
        | sort | uniq -c)

    # Simpan hasil hitung ke associative array supaya proses "lookup" jumlah
    # sesi per user di bawah tidak perlu fork/exec proses baru lagi.
    local -A jumlah_sesi
    local cnt uname
    while read -r cnt uname; do
        [[ -z "$uname" ]] && continue
        jumlah_sesi["$uname"]=$cnt
    done <<< "$hasil_hitung"

    # Loop tiap user lokal, bandingkan dengan MAX_SSH_SESSION
    local user sesi_aktif
    for user in $daftar_user; do
        sesi_aktif=${jumlah_sesi[$user]:-0}   # default 0 kalau user tidak sedang login
        if (( sesi_aktif > MAX_SSH_SESSION )); then
            # putus paksa semua koneksi sshd/dropbear milik user ini
            pkill -u "$user" -f 'sshd|dropbear' 2>/dev/null
            log_action "SSHWS | user='$user' sesi_aktif=$sesi_aktif (limit=$MAX_SSH_SESSION) -> KONEKSI DIPUTUS PAKSA"
        fi
    done
}

# ─────────────────────────────────────────────────────────────
# FUNGSI: nonaktifkan satu akun Xray dengan menghapus entrinya dari
# config.json. Catatan: format config Xray TIDAK punya field semacam
# "enabled": false per-client -- satu-satunya cara agar Xray benar-benar
# menolak koneksi akun tsb adalah menghapus objek client (berdasarkan
# "email") dari SEMUA array settings.clients di semua inbound
# (vmess/vless/trojan/ss sekalipun ada beberapa protokol sekaligus).
# ─────────────────────────────────────────────────────────────
disable_xray_user() {
    local email="$1"
    [[ -f "$XRAY_CONFIG" ]] || return 1

    if ! command -v jq >/dev/null 2>&1; then
        log_action "XRAY  | GAGAL nonaktifkan '$email': perintah 'jq' tidak ditemukan (install dengan: apt install -y jq)"
        return 1
    fi

    # backup config sebelum diedit -- jaga-jaga kalau perlu restore manual
    cp -f "$XRAY_CONFIG" "${XRAY_CONFIG}.bak-$(date +%s)" 2>/dev/null

    local tmp
    tmp=$(mktemp)
    jq --arg email "$email" '
        .inbounds |= map(
            if (.settings.clients? != null) then
                .settings.clients |= map(select(.email != $email))
            else
                .
            end
        )
    ' "$XRAY_CONFIG" > "$tmp" 2>/dev/null && mv "$tmp" "$XRAY_CONFIG" || { rm -f "$tmp"; return 1; }

    return 0
}

# ─────────────────────────────────────────────────────────────
# 3. LOGIKA LIMIT DEVICE/IP XRAY
# ─────────────────────────────────────────────────────────────
limit_xray() {
    [[ -f "$XRAY_LOG" ]] || return   # skip kalau access.log belum ada

    # Ambil 500 baris terakhir access.log sebagai pendekatan sederhana untuk
    # "aktivitas beberapa menit terakhir" -- sengaja TIDAK parsing timestamp
    # per baris (yang butuh `date -d` per baris = ratusan fork proses baru),
    # supaya script tetap ringan di CPU sesuai permintaan.
    #
    # Format satu baris access.log Xray:
    #   2026/09/01 10:15:23 103.10.20.30:53212 accepted tcp:target:443 [tag] email: user1
    # jadi: $3 = IP:PORT, $4 = status ("accepted"/"rejected"), field setelah
    # literal "email:" = username Xray.
    local pasangan
    pasangan=$(tail -n "$XRAY_LOG_LINES" "$XRAY_LOG" 2>/dev/null | awk '
        {
            ip = ""; email = ""
            if ($4 != "accepted") next          # lewati baris yang bukan koneksi diterima
            ip = $3
            sub(/:[0-9]+$/, "", ip)              # buang ":PORT", sisakan IP saja
            for (i = 5; i <= NF; i++) {
                if ($i == "email:") { email = $(i + 1); break }
            }
            if (ip != "" && email != "") print email, ip
        }')
    [[ -z "$pasangan" ]] && return

    # Hilangkan duplikat pasangan "email ip" (satu IP yang connect berkali-kali
    # cuma dihitung 1x), lalu hitung berapa IP UNIK per email.
    local ip_per_user
    ip_per_user=$(echo "$pasangan" | sort -u | awk '{print $1}' | sort | uniq -c)

    local perlu_restart=0
    local jml_ip email
    while read -r jml_ip email; do
        [[ -z "$email" ]] && continue
        if (( jml_ip > MAX_XRAY_IP )); then
            if disable_xray_user "$email"; then
                log_action "XRAY  | user='$email' ip_unik=$jml_ip (limit=$MAX_XRAY_IP) -> USER DINONAKTIFKAN"
                perlu_restart=1
            fi
        fi
    done <<< "$ip_per_user"

    # Restart Xray SEKALI SAJA di akhir (bukan per-user yang kena blokir)
    # supaya service tidak restart berkali-kali dalam satu run -- lebih
    # efisien dan menghindari drop koneksi user lain yang tidak melanggar.
    if [[ "$perlu_restart" -eq 1 ]]; then
        systemctl restart xray 2>/dev/null
    fi
}

# ─────────────────────────────────────────────────────────────
# 4. EKSEKUSI UTAMA
# ─────────────────────────────────────────────────────────────
limit_sshws
limit_xray

exit 0

#===============================================================================
# REGISTRASI CRON (tempel blok di bawah ini ke dalam install.sh kamu, misalnya
# di bagian akhir fungsi instalasi, setelah semua service selesai di-setup)
#===============================================================================
# LIMIT_SCRIPT="/etc/vpn-script/addon/limit-all.sh"
# chmod +x "$LIMIT_SCRIPT"
#
# # cek dulu biar tidak dobel kalau install.sh dijalankan ulang (reinstall/update)
# if ! grep -qF "$LIMIT_SCRIPT" /etc/crontab 2>/dev/null; then
#     echo "* * * * * root /bin/bash $LIMIT_SCRIPT >> /var/log/all-tun-limit-cron.log 2>&1" >> /etc/crontab
# fi
#
# # restart layanan cron supaya /etc/crontab yang baru langsung dibaca ulang
# systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null
#===============================================================================
