# CHANGELOG - v1.5.0 (Limit Device/IP, Limit Kuota & Bot Telegram Pro)

## Fitur Baru

### 1. Limit Device/IP (SSH-WS & Xray: VMess/VLess/Trojan/Shadowsocks)
- SSH-WS: memakai mekanisme session-count yang sudah ada (`addon/session-limiter.sh`),
  sekarang diekspos sebagai "Limit Device/IP" di menu buat akun & menu edit limit.
- Xray (VMess/VLess/Trojan/SS): limit baru berdasarkan **jumlah device aktif
  bersamaan** (Xray Stats API `statsUserOnline`), dijalankan oleh cron baru
  `addon/xray-device-limiter.sh` tiap 2 menit.
  > Catatan teknis: karena semua trafik Xray-WS di-proxy lewat Nginx (127.0.0.1),
  > Xray tidak pernah melihat IP asli client — sama seperti alasan SSH-WS
  > memakai session-count, bukan IP asli. Jadi "limit IP" di sini secara
  > teknis diimplementasikan sebagai limit device aktif bersamaan, yang secara
  > praktik mencapai tujuan yang sama (membatasi berapa device boleh connect
  > bersamaan per akun).
- Bisa di-set saat create akun & diedit kapan saja lewat menu "Edit Limit
  Device/IP & Kuota" di masing-masing menu protokol.

### 2. Limit Kuota per Akun (SSH-WS & Xray)
- Bisa di-set saat create akun (dalam GB, 0 = unlimited) & diedit lewat menu
  edit limit.
- Xray: dihitung dari Xray Stats API (uplink+downlink per email client) —
  presisi karena API resmi Xray.
- SSH: dihitung dari iptables OUTPUT accounting per-UID — **best-effort/
  approksimasi**, disarankan diuji dulu di VPS sungguhan sebelum dipakai
  produksi dalam skala besar.
- Cron baru `addon/quota-limiter.sh` (tiap 10 menit) akan **suspend otomatis**
  akun yang kuotanya habis (bukan dihapus), kirim notifikasi Telegram, dan
  **otomatis aktif lagi** begitu admin menaikkan kuota lewat menu edit limit.

### 3. Notifikasi Telegram Detail saat Akun Dibuat
- Semua protokol (SSH-WS, VMess, VLess, Trojan, Shadowsocks) sekarang kirim
  notifikasi Telegram otomatis saat akun baru dibuat, isinya mirip info yang
  ditampilkan di panel: username, password/UUID, domain, expired, limit
  device/IP, dan limit kuota.
- Notifikasi juga dikirim saat limit device/IP atau kuota kelampauan.
- Tiap jenis notifikasi (akun baru / akun hapus / limit habis) bisa
  di-toggle on/off terpisah.

### 4. Menu "Bot Telegram & Limit Akun (Pro)" di Menu Utama
- Menu baru `menu/telegram.sh`, diakses langsung dari menu utama (`[14]`),
  gak perlu masuk ke submenu SSH-WS lagi.
- Setup/ubah Bot Token & Chat ID, test kirim notifikasi, ubah default limit
  device/IP (terpisah utk SSH & Xray), ubah default limit kuota, dan toggle
  jenis notifikasi.
- Menu lama di SSH-WS (`[7] Pengaturan Pro`) masih ada dan tetap kompatibel
  (sekarang cuma "wrapper" tipis yang menyimpan ke config yang sama).

## Perubahan Skema Database (auto-kompatibel dengan akun lama)
- `ssh.db`      : `user|pass|exp|created|session_limit|quota_mb`
- `vmess.db`    : `user|uuid|exp|created|ip_limit|quota_mb`
- `vless.db`    : `user|uuid|exp|created|ip_limit|quota_mb`
- `trojan.db`   : `user|pass|exp|created|ip_limit|quota_mb`
- `ss.db`       : `user|pass|method|exp|created|ip_limit|quota_mb`

Akun yang dibuat sebelum update ini otomatis dianggap pakai nilai default
(`IP_LIMIT_DEFAULT`/`SESSION_LIMIT_DEFAULT` & `QUOTA_DEFAULT_MB`, bisa diubah
di menu Bot Telegram) sampai di-edit manual lewat menu "Edit Limit".

## File Baru
- `addon/xray-device-limiter.sh` — cron 2 menit
- `addon/quota-limiter.sh` — cron 10 menit
- `menu/telegram.sh` — menu utama baru

## Catatan Penting Sebelum Pakai di Server Produksi
1. Fitur ini dikembangkan & di-review kodenya secara statis (tanpa akses ke
   VPS sungguhan untuk uji langsung). **Wajib diuji dulu** di VPS
   test/staging sebelum dipakai di server produksi banyak user.
2. Xray Stats API butuh **Xray-core >= 1.8.0**. Cek versi dengan `xray version`.
   Kalau versi lebih lama, fitur limit device/kuota Xray tidak akan aktif
   (gagal secara silent, gak akan merusak akun yang sudah ada).
3. Limit kuota SSH pakai teknik `iptables -m owner --uid-owner` di chain
   OUTPUT — teknik umum dipakai di banyak script sejenis, tapi sifatnya
   approksimasi (menghitung arah download ke client). Disarankan dites dulu.
4. `install.sh`/`update.sh` men-download file dari repo GitHub milikmu
   (raw.githubusercontent.com/...) — jangan lupa upload/push file-file yang
   sudah diupdate ini ke repo yang dipakai `install.sh`, kalau tidak, VPS
   yang install/update akan tetap dapat versi lama.

## Update Tambahan (revisi setelah feedback)

### 5. Notifikasi Telegram Dirapikan
- Pesan Telegram saat akun SSH-WS dibuat sekarang berisi detail lengkap
  bergaya panel: port koneksi (SSH Direct/SSL/WS nTLS/WS TLS) + payload WS
  (Dropbear & OpenSSH), diformat rapi pakai HTML Telegram (bold + monospace),
  bukan ASCII box seperti tampilan terminal.
- Pesan Telegram saat akun VMess/VLess/Trojan/Shadowsocks dibuat sekarang
  menyertakan semua link koneksi (WS TLS, WS nTLS, gRPC) sekaligus.
- Notifikasi "akun expired & dihapus" sekarang juga aktif utk VMess/VLess/
  Trojan/Shadowsocks (sebelumnya cuma SSH).

### 6. Trial per Jam (SSH-WS & Xray)
- Semua flow buat akun (SSH, VMess, VLess, Trojan, SS) sekarang punya
  pilihan Tipe Akun: Reguler (hari) atau Trial (jam).
- Durasi trial default bisa diatur admin lewat menu Bot Telegram ->
  "Ubah Default Durasi Trial (jam)".
- Cron `delete_expired` diubah dari sekali sehari (`0 0 * * *`) jadi
  tiap 5 menit (`*/5 * * * *`) supaya trial per jam ditegakkan presisi
  (bukan cuma presisi hari seperti expired reguler).
- Catatan: `useradd -e`/`chage -E` di Linux cuma presisi hari, jadi utk
  SSH expired OS-level dibulatkan ke tanggal, TAPI penghapusan akun trial
  yang presisi jam tetap jalan lewat cron `delete_expired` di atas
  (berdasarkan datetime lengkap yang disimpan di kolom `exp`).

### 7. Menu SSH-WS Dirapikan
- Item "[7] Pengaturan Pro (Session Limit & Telegram)" dihapus dari
  submenu SSH-WS karena sudah digantikan menu utama "[14] Bot Telegram &
  Limit Akun (Pro)", dan limit device/IP sudah diatur langsung saat
  pembuatan akun.
- Menu di-renumber: [7] Diagnostic, [8] Edit Limit Device/IP & Kuota.

### 8. Desain UI Konsisten di SEMUA Menu (bukan cuma menu utama)
- Helper box-drawing (ui_line, ui_kv, ui_2col, ui_bar, dll) dipindah
  ke lib.sh supaya bisa dipakai bersama oleh SEMUA file menu/*.sh.
- Header + body menu di SSH-WS, VMess, VLess, Trojan, Shadowsocks,
  Bot Telegram, Nginx, Dropbear, HAProxy, Status Layanan, System
  Info, Change Domain, Update Script, dan Uninstall sekarang semua
  pakai gaya box melengkung yang sama persis dengan menu utama.
- Info VPS di menu utama sekarang menampilkan OS (dari get_os_info).
- Bug alignment title (kurang 2 karakter) sudah diperbaiki dan
  divalidasi ulang -- semua baris box sekarang presisi 60 karakter
  di semua menu, bukan cuma menu utama.

### 9. Menu Rebuild OS VPS (menu utama, [15])
- Menjalankan script rebuild yang disediakan admin:
  https://raw.githubusercontent.com/RidwanzAnphelibelll/RebuildVPS/main/rebuild.sh
- Karena SANGAT destruktif (install ulang OS, semua data hilang),
  dipasang double-confirmation: ketik 'REBUILD' lalu ketik 'YA' --
  pola yang sama seperti menu Uninstall.
- Kalau URL gagal diunduh (network/URL berubah), langsung dibatalkan
  dengan pesan error, tidak lanjut eksekusi apa pun.
