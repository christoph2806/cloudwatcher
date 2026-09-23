#!/bin/bash
# Install Mosquitto, the collector, the web UI, and the nginx vhost.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash deploy/install.sh" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y mosquitto mosquitto-clients python3-venv python3-pip apache2-utils
systemctl stop mosquitto

install -d -m 755 /etc/cloudwatcher /opt/cloudwatcher /var/www/html
if ! id cloudwatcher >/dev/null 2>&1; then
  adduser --system --group --home /var/lib/cloudwatcher --shell /usr/sbin/nologin cloudwatcher
fi
install -d -o cloudwatcher -g cloudwatcher -m 750 /var/lib/cloudwatcher

SECRETS=/etc/cloudwatcher/secrets.env
if [[ ! -f "$SECRETS" ]]; then
  rand_pw() { openssl rand -base64 24 | tr -d '\n/=+' | cut -c1-24; }
  umask 077
  cat > "$SECRETS" <<EOF
SOLO_PASSWORD=solo-$(rand_pw)
COLLECTOR_PASSWORD=collector-$(rand_pw)
WEB_USER=sternwarte
WEB_PASSWORD=web-$(rand_pw)
EOF
  chmod 600 "$SECRETS"
fi
set -a
# shellcheck disable=SC1090
source "$SECRETS"
set +a

cat > /etc/cloudwatcher/collector.env <<EOF
CLOUDWATCHER_DB=/var/lib/cloudwatcher/data.db
MQTT_HOST=localhost
MQTT_PORT=1883
MQTT_USER=collector
MQTT_PASSWORD=${COLLECTOR_PASSWORD}
MQTT_TOPIC=sternwarte/cloudwatcher/#
EOF
cat > /etc/cloudwatcher/web.env <<EOF
CLOUDWATCHER_DB=/var/lib/cloudwatcher/data.db
WEB_HOST=127.0.0.1
WEB_PORT=8095
EOF
chown root:cloudwatcher /etc/cloudwatcher/collector.env /etc/cloudwatcher/web.env
chmod 640 /etc/cloudwatcher/collector.env /etc/cloudwatcher/web.env

install -m 644 "$ROOT/deploy/solo.conf" /etc/mosquitto/conf.d/solo.conf
install -o root -g mosquitto -m 640 "$ROOT/deploy/acl" /etc/mosquitto/acl
# mosquitto 1.6 rejects -b together with -c. Create the file, then set passwords.
: > /etc/mosquitto/passwd
mosquitto_passwd -b /etc/mosquitto/passwd solo "$SOLO_PASSWORD"
mosquitto_passwd -b /etc/mosquitto/passwd collector "$COLLECTOR_PASSWORD"
chown root:mosquitto /etc/mosquitto/passwd
chmod 640 /etc/mosquitto/passwd

systemctl enable mosquitto
systemctl restart mosquitto

install -m 644 "$ROOT/collector.py" "$ROOT/webapp.py" "$ROOT/requirements.txt" /opt/cloudwatcher/
install -d /opt/cloudwatcher/static
install -m 644 "$ROOT/static/index.html" "$ROOT/static/chart.umd.min.js" /opt/cloudwatcher/static/
if [[ ! -x /opt/cloudwatcher/venv/bin/python ]]; then
  python3 -m venv /opt/cloudwatcher/venv
fi
/opt/cloudwatcher/venv/bin/pip install --upgrade pip
/opt/cloudwatcher/venv/bin/pip install -r /opt/cloudwatcher/requirements.txt

install -m 644 "$ROOT/deploy/cloudwatcher-collector.service" /etc/systemd/system/cloudwatcher-collector.service
install -m 644 "$ROOT/deploy/cloudwatcher-web.service" /etc/systemd/system/cloudwatcher-web.service
systemctl daemon-reload
systemctl enable cloudwatcher-collector.service cloudwatcher-web.service
systemctl restart cloudwatcher-collector.service cloudwatcher-web.service

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 1883/tcp comment 'cloudwatcher mqtt'
fi
if iptables -S INPUT 2>/dev/null | head -1 | grep -q -- '-P INPUT DROP'; then
  iptables -C INPUT -p tcp --dport 1883 -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p tcp --dport 1883 -j ACCEPT
fi

echo "waiting for services"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if systemctl is-active --quiet cloudwatcher-collector && systemctl is-active --quiet cloudwatcher-web; then
    break
  fi
  sleep 1
done
systemctl is-active mosquitto cloudwatcher-collector cloudwatcher-web

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if journalctl -u cloudwatcher-collector --since "5 min ago" --no-pager | grep -q "subscribed to"; then
    break
  fi
  sleep 1
done
SMOKE='{"install_smoke":1,"sky":{"temp":-4.5}}'
mosquitto_pub -h 127.0.0.1 -u solo -P "$SOLO_PASSWORD" -t sternwarte/cloudwatcher -q 1 -m "$SMOKE"
DAY=$(TZ=Europe/Berlin date +%F)
smoke_ok=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if curl -fsS "http://127.0.0.1:8095/api/data?date=${DAY}" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if "install_smoke" in d.get("series", {}) else 1)'; then
    smoke_ok=1
    break
  fi
  sleep 1
done
[[ "$smoke_ok" == 1 ]]
echo "smoke ok"
/opt/cloudwatcher/venv/bin/python - <<'PY'
import sqlite3
conn = sqlite3.connect("/var/lib/cloudwatcher/data.db")
conn.execute("DELETE FROM messages WHERE payload LIKE ?", ("%install_smoke%",))
conn.commit()
PY
chown -R cloudwatcher:cloudwatcher /var/lib/cloudwatcher

htpasswd -bc /etc/nginx/cloudwatcher.htpasswd "$WEB_USER" "$WEB_PASSWORD"
chown root:www-data /etc/nginx/cloudwatcher.htpasswd
chmod 640 /etc/nginx/cloudwatcher.htpasswd

enable_nginx() {
  local src=$1
  install -m 644 "$src" /etc/nginx/sites-available/cloudwatcher.mussenbrock.net
  ln -sfn /etc/nginx/sites-available/cloudwatcher.mussenbrock.net /etc/nginx/sites-enabled/cloudwatcher.mussenbrock.net
  nginx -t
  systemctl reload nginx
}

enable_nginx "$ROOT/deploy/nginx-cloudwatcher-http.conf"

HOST_IP=$(ip -4 route get 1.1.1.1 | awk '{print $7; exit}')
DNS_IP=$(python3 - <<'PY'
import random, socket, struct
name = "cloudwatcher.mussenbrock.net"
header = struct.pack(">HHHHHH", random.randint(0, 65535), 0x0100, 1, 0, 0, 0)
qname = b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\x00"
query = header + qname + struct.pack(">HH", 1, 1)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(3)
sock.sendto(query, ("8.8.8.8", 53))
data, _ = sock.recvfrom(512)

def skip_name(buf, off):
    while True:
        n = buf[off]
        if n == 0:
            return off + 1
        if n & 0xC0 == 0xC0:
            return off + 2
        off += 1 + n

offset = skip_name(data, 12) + 4
ancount = struct.unpack(">H", data[6:8])[0]
for _ in range(ancount):
    offset = skip_name(data, offset)
    typ, _clas, _ttl, rdlen = struct.unpack(">HHIH", data[offset:offset + 10])
    offset += 10
    rdata = data[offset:offset + rdlen]
    offset += rdlen
    if typ == 1 and rdlen == 4:
        print(".".join(str(b) for b in rdata))
        break
PY
)
echo "dns ${DNS_IP} host ${HOST_IP}"

if [[ -f /etc/letsencrypt/live/cloudwatcher.mussenbrock.net/fullchain.pem ]] || [[ "$DNS_IP" == "$HOST_IP" ]]; then
  CERTBOT=(certbot certonly --webroot -w /var/www/html -d cloudwatcher.mussenbrock.net --non-interactive --agree-tos --keep-until-expiring)
  if [[ ! -d /etc/letsencrypt/accounts ]]; then
    CERTBOT+=(--register-unsafely-without-email)
  fi
  if "${CERTBOT[@]}"; then
    enable_nginx "$ROOT/deploy/nginx-cloudwatcher.conf"
  else
    echo "certbot failed; site stays on the HTTP challenge vhost until the certificate exists" >&2
  fi
else
  echo "DNS does not point at this host yet; skipped certbot" >&2
fi

CRED="$ROOT/CREDENTIALS.txt"
umask 077
cat > "$CRED" <<EOF
MQTT broker: ${HOST_IP}:1883
MQTT user solo: ${SOLO_PASSWORD}
MQTT user collector: ${COLLECTOR_PASSWORD}
Topic: sternwarte/cloudwatcher

Web: https://cloudwatcher.mussenbrock.net
Web user: ${WEB_USER}
Web password: ${WEB_PASSWORD}
EOF
chown christoph:christoph "$CRED"
chmod 600 "$CRED"
echo "credentials written to ${CRED}"
