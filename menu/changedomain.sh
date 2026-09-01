#!/bin/bash
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

changedomain_menu() {
  clear
  local current=$(get_domain)
  local ip=$(get_server_ip)

  echo -e "${CYAN}$UI_BOX_TOP${NC}"
  ui_line_center "${WHITE}${BOLD}GANTI DOMAIN${NC}"
  echo -e "${CYAN}$UI_BOX_MID${NC}"
  ui_kv "Domain Aktif" "$current"
  ui_kv "IP Server"    "$ip"
  echo -e "${CYAN}$UI_BOX_BOT${NC}"
  echo ""
  echo -e "  ${YELLOW}⚠  PERHATIAN:${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}1.${NC} Pastikan domain baru sudah arahkan ke IP server"
  echo -e "  ${WHITE}2.${NC} Semua akun yang ada tetap berfungsi"
  echo -e "  ${WHITE}3.${NC} SSL baru akan diminta dari Let's Encrypt"
  echo -e "  ${WHITE}4.${NC} Nginx akan dikonfigurasi ulang otomatis"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Domain baru${NC}: "
  read -r new_domain
  new_domain=$(echo "$new_domain" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ -z "$new_domain" ]]; then
    echo -e "  ${RED}[!] Domain tidak boleh kosong!${NC}"
    sleep 2; bash $SCRIPT_DIR/menu.sh; return
  fi

  if [[ "$new_domain" == "$current" ]]; then
    echo -e "  ${YELLOW}[!] Domain sama dengan yang aktif!${NC}"
    sleep 2; bash $SCRIPT_DIR/menu.sh; return
  fi

  echo ""
  echo -e "  ${CYAN}[*]${NC} Memverifikasi DNS ${WHITE}$new_domain${NC}..."
  local domain_ip=$(dig +short "$new_domain" A 2>/dev/null | grep -E '^[0-9]+\.' | tail -1)

  if [[ -z "$domain_ip" ]]; then
    echo -e "  ${YELLOW}[!]${NC} DNS belum ditemukan."
    echo -ne "  Lanjutkan? [y/N]: "; read -r f
    [[ ! "$f" =~ ^[Yy]$ ]] && { bash $SCRIPT_DIR/menu.sh; return; }
  elif [[ "$domain_ip" != "$ip" ]]; then
    echo -e "  ${YELLOW}[!]${NC} Domain → $domain_ip, Server → $ip"
    echo -ne "  Lanjutkan? [y/N]: "; read -r f
    [[ ! "$f" =~ ^[Yy]$ ]] && { bash $SCRIPT_DIR/menu.sh; return; }
  else
    echo -e "  ${GREEN}[✓]${NC} DNS verified: $new_domain → $ip"
  fi

  echo ""
  echo -ne "  ${WHITE}Konfirmasi ganti domain? [y/N]${NC}: "
  read -r confirm
  [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; bash $SCRIPT_DIR/menu.sh; return; }

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[*]${NC} Mengupdate konfigurasi Nginx..."
  sed -i "s/$current/$new_domain/g" /etc/nginx/conf.d/xray.conf 2>/dev/null

  echo -e "  ${CYAN}[*]${NC} Menghentikan Nginx sementara..."
  systemctl stop nginx 2>/dev/null

  echo -e "  ${CYAN}[*]${NC} Meminta SSL certificate baru..."
  /root/.acme.sh/acme.sh --issue --standalone \
    -d "$new_domain" --keylength ec-256 --httpport 80 --force 2>/dev/null

  /root/.acme.sh/acme.sh --installcert -d "$new_domain" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > /etc/ssl/xray/xray.pem 2>/dev/null; chmod 600 /etc/ssl/xray/xray.pem; systemctl restart xray nginx 2>/dev/null; systemctl reload haproxy 2>/dev/null" 2>/dev/null

  # Selalu pastikan file gabungan (dibutuhkan HAProxy: SSH-SSL port 444 & multiplex 443) sinkron
  cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > /etc/ssl/xray/xray.pem 2>/dev/null
  chmod 600 /etc/ssl/xray/xray.pem 2>/dev/null

  echo "$new_domain" > $SCRIPT_DIR/domain
  systemctl start nginx 2>/dev/null
  systemctl restart xray 2>/dev/null
  systemctl reload haproxy 2>/dev/null

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[✓]${NC} Domain berhasil diganti ke ${WHITE}$new_domain${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  bash $SCRIPT_DIR/menu.sh
}

changedomain_menu
