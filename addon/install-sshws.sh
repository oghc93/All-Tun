#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - ADDON INSTALLER (ALL-IN-ONE)
#   Fitur: SSH-WS (WebSocket) via Dropbear & OpenSSH, SSH-SSL (Stunnel4)
#   Multi-port: 80, 8880, 8080, 2080, 2082 (nTLS) + 443 (TLS)
#   Path : /ssh-ws (backend Dropbear) & /ssh-ws-ssh (backend OpenSSH)
#   Bersifat ADITIF: tidak menghapus/mengganti konfigurasi
#   Nginx/Xray/Dropbear yang sudah berjalan.
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

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   INSTALL ADDON: SSH-WS / SSH-WS-TLS / SSH-SSL   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# --- 1. Dependensi ---
echo -e "\n${CYAN}[*]${NC} Menginstall dependensi (python3, stunnel4)..."
apt-get update -qq 2>/dev/null
apt-get install -y -qq python3 stunnel4 2>/dev/null
echo -e "${GREEN}[OK]${NC} Dependensi terinstall"

# --- 2. Buat direktori DB SSH bila belum ada ---
mkdir -p "$DB_DIR"
touch "$DB_SSH"

# --- 3. Bersihkan instalasi ws-proxy versi lama (jika ada) ---
if [[ -f /usr/local/bin/ws-proxy.py || -f /etc/systemd/system/ws-proxy.service ]]; then
  echo -e "\n${CYAN}[*]${NC} Menghapus ws-proxy (versi lama)..."
  systemctl stop ws-proxy 2>/dev/null
  systemctl disable ws-proxy 2>/dev/null
  rm -f /etc/systemd/system/ws-proxy.service
  rm -f /usr/local/bin/ws-proxy.py
  systemctl daemon-reload
  echo -e "${GREEN}[OK]${NC} ws-proxy (lama) dibersihkan"
fi

# --- 4a. Deploy ws-dropbear (SSH-WS -> Dropbear) ---
echo -e "\n${CYAN}[*]${NC} Memasang ws-dropbear (SSH-WS -> Dropbear)..."

cat > /usr/local/bin/ws-dropbear <<'PYEOF1'
#!/usr/bin/env python3
# ============================================================
#  ws-dropbear - SSH-WS proxy (backend: Dropbear)
#  Port default (systemd): 2095  ->  backend 127.0.0.1:109
#  Ported to Python 3 (originally Python 2) for CHANELOG VPN SCRIPT.
# ============================================================
import socket
import threading
import select
import sys
import time
import getopt

# Listen
LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2095

# Pass
PASS = ''

# CONST
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:109'
RESPONSE = ('HTTP/1.1 101 WebSocket <font color="lime">Yaddy Kakkoii </font>'
            '<font color="yellow">Tampan </font><font color="red">Maksimal</font>\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            'Sec-WebSocket-Accept: foo\r\n\r\n')


class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, int(self.port)))
        self.soc.listen(0)
        self.running = True

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(True)
                except socket.timeout:
                    continue

                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        with self.logLock:
            print(log)

    def addConn(self, conn):
        with self.threadsLock:
            if self.running:
                self.threads.append(conn)

    def removeConn(self, conn):
        with self.threadsLock:
            if conn in self.threads:
                self.threads.remove(conn)

    def close(self):
        self.running = False
        with self.threadsLock:
            threads = list(self.threads)
        for c in threads:
            c.close()


class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = 'Connection: ' + str(addr)

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except Exception:
            pass
        finally:
            self.clientClosed = True

        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except Exception:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            head = self.client_buffer.decode('latin-1', 'ignore')

            hostPort = self.findHeader(head, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST

            split = self.findHeader(head, 'X-Split')
            if split != '':
                self.client.recv(BUFLEN)

            if hostPort != '':
                passwd = self.findHeader(head, 'X-Pass')

                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find(header + ': ')
        if aux == -1:
            return ''
        aux = head.find(':', aux)
        head = head[aux + 2:]
        aux = head.find('\r\n')
        if aux == -1:
            return ''
        return head[:aux]

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i + 1:])
            host = host[:i]
        else:
            port = 22

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]

        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode('latin-1'))
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    sent = self.target.send(data)
                                    data = data[sent:]
                            count = 0
                        else:
                            error = True
                            break
                    except Exception:
                        error = True
                        break
            if count == TIMEOUT:
                error = True
            if error:
                break


def print_usage():
    print('Usage: ws-dropbear -p <port>')
    print('       ws-dropbear -b <bindAddr> -p <port>')
    print('       ws-dropbear -b 0.0.0.0 -p 2095')


def parse_args(argv):
    global LISTENING_ADDR, LISTENING_PORT
    try:
        opts, args = getopt.getopt(argv, "hb:p:", ["bind=", "port="])
    except getopt.GetoptError:
        print_usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_usage()
            sys.exit()
        elif opt in ("-b", "--bind"):
            LISTENING_ADDR = arg
        elif opt in ("-p", "--port"):
            LISTENING_PORT = int(arg)


def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    print("\n:------- Ws-Dropbear (SSH-WS) -------:\n")
    print("Listening addr: " + host)
    print("Listening port: " + str(port) + "\n")
    print(":--------------------------------------:\n")
    server = Server(host, port)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping...')
            server.close()
            break


if __name__ == '__main__':
    main()
PYEOF1
chmod +x /usr/local/bin/ws-dropbear

cat > /etc/systemd/system/ws-dropbear.service <<EOF2
[Unit]
Description=Websocket-Dropbear By YaddyKakkoii
Documentation=https://google.com
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-dropbear $WS_DROPBEAR_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reload
systemctl enable ws-dropbear 2>/dev/null
systemctl restart ws-dropbear 2>/dev/null
sleep 1
if systemctl is-active --quiet ws-dropbear; then
  echo -e "${GREEN}[OK]${NC} ws-dropbear aktif di 0.0.0.0:$WS_DROPBEAR_PORT -> 127.0.0.1:109 (Dropbear)"
else
  echo -e "${RED}[GAGAL]${NC} ws-dropbear tidak aktif! Cek: journalctl -u ws-dropbear -n 20 --no-pager"
  journalctl -u ws-dropbear -n 10 --no-pager 2>/dev/null
fi

# --- 4b. Deploy ws-openssh (SSH-WS -> OpenSSH) ---
echo -e "\n${CYAN}[*]${NC} Memasang ws-openssh (SSH-WS -> OpenSSH)..."

cat > /usr/local/bin/ws-openssh <<'PYEOF2'
#!/usr/bin/env python3
# ============================================================
#  ws-openssh - SSH-WS proxy (backend: OpenSSH / sshd)
#  Port default (systemd): 2093  ->  backend 127.0.0.1:22
#  Ported to Python 3 (originally Python 2) for CHANELOG VPN SCRIPT.
# ============================================================
import socket
import threading
import select
import sys
import time
import getopt

# Listen
LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2093

# Pass
PASS = ''

# CONST
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:22'
RESPONSE = ('HTTP/1.1 101 WebSocket <font color="lime">Yaddy Kakkoii </font>'
            '<font color="yellow">Tampan </font><font color="red">Maksimal</font>\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            'Sec-WebSocket-Accept: foo\r\n\r\n')


class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, int(self.port)))
        self.soc.listen(0)
        self.running = True

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(True)
                except socket.timeout:
                    continue

                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        with self.logLock:
            print(log)

    def addConn(self, conn):
        with self.threadsLock:
            if self.running:
                self.threads.append(conn)

    def removeConn(self, conn):
        with self.threadsLock:
            if conn in self.threads:
                self.threads.remove(conn)

    def close(self):
        self.running = False
        with self.threadsLock:
            threads = list(self.threads)
        for c in threads:
            c.close()


class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = 'Connection: ' + str(addr)

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except Exception:
            pass
        finally:
            self.clientClosed = True

        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except Exception:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            head = self.client_buffer.decode('latin-1', 'ignore')

            hostPort = self.findHeader(head, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST

            split = self.findHeader(head, 'X-Split')
            if split != '':
                self.client.recv(BUFLEN)

            if hostPort != '':
                passwd = self.findHeader(head, 'X-Pass')

                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find(header + ': ')
        if aux == -1:
            return ''
        aux = head.find(':', aux)
        head = head[aux + 2:]
        aux = head.find('\r\n')
        if aux == -1:
            return ''
        return head[:aux]

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i + 1:])
            host = host[:i]
        else:
            port = 22

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]

        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode('latin-1'))
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    sent = self.target.send(data)
                                    data = data[sent:]
                            count = 0
                        else:
                            error = True
                            break
                    except Exception:
                        error = True
                        break
            if count == TIMEOUT:
                error = True
            if error:
                break


def print_usage():
    print('Usage: ws-openssh -p <port>')
    print('       ws-openssh -b <bindAddr> -p <port>')
    print('       ws-openssh -b 0.0.0.0 -p 2093')


def parse_args(argv):
    global LISTENING_ADDR, LISTENING_PORT
    try:
        opts, args = getopt.getopt(argv, "hb:p:", ["bind=", "port="])
    except getopt.GetoptError:
        print_usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_usage()
            sys.exit()
        elif opt in ("-b", "--bind"):
            LISTENING_ADDR = arg
        elif opt in ("-p", "--port"):
            LISTENING_PORT = int(arg)


def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    print("\n:------- Ws-OpenSSH (SSH-WS) -------:\n")
    print("Listening addr: " + host)
    print("Listening port: " + str(port) + "\n")
    print(":-------------------------------------:\n")
    server = Server(host, port)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping...')
            server.close()
            break


if __name__ == '__main__':
    main()
PYEOF2
chmod +x /usr/local/bin/ws-openssh

cat > /etc/systemd/system/ws-openssh.service <<EOF3
[Unit]
Description=Websocket-OpenSSH By YaddyKakkoii
Documentation=https://google.com
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-openssh $WS_OPENSSH_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF3

systemctl daemon-reload
systemctl enable ws-openssh 2>/dev/null
systemctl restart ws-openssh 2>/dev/null
sleep 1
if systemctl is-active --quiet ws-openssh; then
  echo -e "${GREEN}[OK]${NC} ws-openssh aktif di 0.0.0.0:$WS_OPENSSH_PORT -> 127.0.0.1:22 (OpenSSH)"
else
  echo -e "${RED}[GAGAL]${NC} ws-openssh tidak aktif! Cek: journalctl -u ws-openssh -n 20 --no-pager"
  journalctl -u ws-openssh -n 10 --no-pager 2>/dev/null
fi

# --- 4c. Bersihkan ws-stunnel (obsolete — stunnel4/HAProxy sekarang connect
#     LANGSUNG ke Dropbear, tanpa payload HTTP, sesuai standar SSH-SSL SNI-only) ---
if systemctl list-unit-files 2>/dev/null | grep -q "^ws-stunnel.service"; then
  echo -e "\n${CYAN}[*]${NC} Membersihkan ws-stunnel (sudah tidak dipakai)..."
  systemctl stop ws-stunnel 2>/dev/null
  systemctl disable ws-stunnel 2>/dev/null
  rm -f /etc/systemd/system/ws-stunnel.service /usr/local/bin/ws-stunnel
  systemctl daemon-reload
  echo -e "${GREEN}[OK]${NC} ws-stunnel dihapus (stunnel4/HAProxy sekarang langsung ke Dropbear:$SSH_BACKEND_PORT)"
fi

# --- 5. Setup Nginx untuk SSH-WS (semua port) ---
NGINX_CONF="/etc/nginx/conf.d/xray.conf"
echo -e "\n${CYAN}[*]${NC} Memeriksa & memperbaiki konfigurasi Nginx untuk SSH-WS..."

NEED_REGEN=false
if [[ ! -f "$NGINX_CONF" ]]; then
  echo -e "${YELLOW}[WARN]${NC} $NGINX_CONF tidak ditemukan, akan dibuat baru."
  NEED_REGEN=true
elif ! grep -q "location /ssh-ws-ssh" "$NGINX_CONF" 2>/dev/null; then
  echo -e "${YELLOW}[WARN]${NC} Location /ssh-ws-ssh (backend OpenSSH) belum ada di Nginx."
  NEED_REGEN=true
elif grep -q "proxy_pass http://127.0.0.1:700;" "$NGINX_CONF" 2>/dev/null; then
  echo -e "${YELLOW}[WARN]${NC} Location /ssh-ws masih mengarah ke port lama (700, sudah tidak dipakai)."
  NEED_REGEN=true
else
  echo -e "${GREEN}[OK]${NC} Konfigurasi Nginx untuk /ssh-ws dan /ssh-ws-ssh sudah benar"
fi

if [[ "$NEED_REGEN" == "true" ]]; then
  echo -e "${CYAN}[*]${NC} Meregenerasi $NGINX_CONF (backup otomatis dibuat)..."
  if regenerate_nginx_conf "$DOMAIN"; then
    echo -e "${GREEN}[OK]${NC} Nginx berhasil diperbarui: /ssh-ws -> ws-dropbear:$WS_DROPBEAR_PORT, /ssh-ws-ssh -> ws-openssh:$WS_OPENSSH_PORT"
  else
    echo -e "${RED}[ERROR]${NC} Gagal meregenerasi Nginx, config lama di-rollback. Cek 'nginx -t' manual."
  fi
fi

# --- 6. Setup Stunnel4 untuk SSH-SSL ---
echo -e "\n${CYAN}[*]${NC} Mengkonfigurasi Stunnel4 (SSH-SSL)..."

if [[ -f /etc/ssl/xray/xray.crt && -f /etc/ssl/xray/xray.key ]]; then
  cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > /etc/stunnel/stunnel.pem 2>/dev/null
else
  echo -e "${YELLOW}[WARN]${NC} Sertifikat Xray tidak ditemukan, membuat self-signed untuk stunnel..."
  openssl req -x509 -newkey rsa:2048 -keyout /tmp/stunnel.key -out /tmp/stunnel.crt \
    -days 365 -nodes -subj "/CN=${DOMAIN:-localhost}" 2>/dev/null
  cat /tmp/stunnel.crt /tmp/stunnel.key > /etc/stunnel/stunnel.pem
  rm -f /tmp/stunnel.key /tmp/stunnel.crt
fi
chmod 600 /etc/stunnel/stunnel.pem

# Pastikan directive global 'pid' ada SEBELUM section pertama.
# Tanpa ini, stunnel4 gak nulis pidfile sama sekali -> systemd/init.d gak
# bisa lacak & matiin proses lama pas restart -> restart berikutnya SELALU
# gagal "Address already in use" karena proses lama masih nyangkut di port.
touch /etc/stunnel/stunnel.conf
if ! grep -q "^pid" /etc/stunnel/stunnel.conf 2>/dev/null; then
  { echo "pid = /var/run/stunnel4.pid"; echo ""; cat /etc/stunnel/stunnel.conf; } > /tmp/stunnel.conf.pidfix
  mv /tmp/stunnel.conf.pidfix /etc/stunnel/stunnel.conf
fi

# Bersihkan proses stunnel4 nyasar (dari restart gagal sebelumnya akibat bug
# di atas) sebelum start ulang, supaya gak nabrak port yang sama lagi.
pkill -9 -f "stunnel4 /etc/stunnel/stunnel.conf" 2>/dev/null
rm -f /var/run/stunnel4.pid
sleep 1

if grep -q "\[ssh-ssl\]" /etc/stunnel/stunnel.conf 2>/dev/null; then
  echo -e "${YELLOW}[UPDATE]${NC} Block [ssh-ssl] sudah ada, memperbarui..."
  awk '
    /^\[ssh-ssl\]/ { skip=1; next }
    /^\[/ && skip { skip=0 }
    !skip { print }
  ' /etc/stunnel/stunnel.conf > /tmp/stunnel.conf.new
  cp /tmp/stunnel.conf.new /etc/stunnel/stunnel.conf
  rm -f /tmp/stunnel.conf.new
fi

cat >> /etc/stunnel/stunnel.conf <<EOF5

[ssh-ssl]
accept = 0.0.0.0:$STUNNEL_SSL_PORT
connect = 127.0.0.1:$SSH_BACKEND_PORT
cert = /etc/stunnel/stunnel.pem
EOF5

sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
grep -q "^ENABLED=" /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" >> /etc/default/stunnel4

systemctl enable stunnel4 2>/dev/null
systemctl restart stunnel4 2>/dev/null
sleep 1
if systemctl is-active --quiet stunnel4; then
  echo -e "${GREEN}[OK]${NC} Stunnel4 aktif di port $STUNNEL_SSL_PORT -> 127.0.0.1:$SSH_BACKEND_PORT (Dropbear, langsung)"
else
  echo -e "${RED}[GAGAL]${NC} Stunnel4 tidak aktif! Kemungkinan port $STUNNEL_SSL_PORT dipakai proses lain, atau config error."
  echo -e "${YELLOW}[INFO]${NC} Cek manual: systemctl status stunnel4 ; journalctl -u stunnel4 -n 20 --no-pager ; ss -tlnp | grep $STUNNEL_SSL_PORT"
  journalctl -u stunnel4 -n 10 --no-pager 2>/dev/null
fi

# --- 7. Firewall (aditif, tidak menutup port lain) ---
echo -e "\n${CYAN}[*]${NC} Membuka port firewall untuk fitur baru..."
iptables -I INPUT -p tcp --dport "$STUNNEL_SSL_PORT" -j ACCEPT 2>/dev/null
iptables -I INPUT -p tcp --dport "$WS_DROPBEAR_PORT" -j ACCEPT 2>/dev/null
iptables -I INPUT -p tcp --dport "$WS_OPENSSH_PORT" -j ACCEPT 2>/dev/null
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null
echo -e "${GREEN}[OK]${NC} Port $STUNNEL_SSL_PORT, $WS_DROPBEAR_PORT, $WS_OPENSSH_PORT dibuka"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   BERHASIL: ADDON SSH-WS / SSH-SSL TERPASANG   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  SSH-WS Dropbear (nTLS) : port 80/8880/8080/2080/2082  path /ssh-ws      (nginx -> ws-dropbear:$WS_DROPBEAR_PORT)"
echo -e "  SSH-WS Dropbear (TLS)  : port 443                     path /ssh-ws      (nginx -> ws-dropbear:$WS_DROPBEAR_PORT)"
echo -e "  SSH-WS OpenSSH  (nTLS) : port 80/8880/8080/2080/2082  path /ssh-ws-ssh  (nginx -> ws-openssh:$WS_OPENSSH_PORT)"
echo -e "  SSH-WS OpenSSH  (TLS)  : port 443                     path /ssh-ws-ssh  (nginx -> ws-openssh:$WS_OPENSSH_PORT)"
echo -e "  SSH-SSL (Dropbear)     : port $STUNNEL_SSL_PORT (stunnel4 -> dropbear:$SSH_BACKEND_PORT, langsung/SNI-only, tanpa payload)"
echo -e "  SSH-SSL (OpenSSH)      : port $HAPROXY_SSL_PORT (HAProxy -> openssh:22, langsung/SNI-only, tanpa payload — aktifkan di menu [8])"
echo -e "  Direct (opsional)      : ws-dropbear di :$WS_DROPBEAR_PORT, ws-openssh di :$WS_OPENSSH_PORT"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
