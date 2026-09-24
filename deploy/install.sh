#!/bin/sh
# Install the collector, the web UI, and, when the tools exist, Mosquitto and nginx.
# Does not install OS packages and does not assume a distribution.
#
#   sudo MQTT_TOPIC='cloudwatcher/#' WEB_USER=viewer \
#        SERVER_NAME=weather.example.com sh deploy/install.sh
#
# MQTT_TOPIC   subscription pattern (default cloudwatcher/#, or the value already installed)
# WEB_USER     basic-auth user (default viewer, or the value already installed)
# SERVER_NAME  public hostname; without it, nginx and certificates are left untouched
# CERTBOT_EMAIL  optional account mail for a new Let's Encrypt account
# PREFIX DATA_DIR CONFIG_DIR RUN_USER WEB_HOST WEB_PORT  override the default paths
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo sh deploy/install.sh" >&2
  exit 1
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

need python3
need openssl

PREFIX=${PREFIX:-/opt/cloudwatcher}
DATA_DIR=${DATA_DIR:-/var/lib/cloudwatcher}
CONFIG_DIR=${CONFIG_DIR:-/etc/cloudwatcher}
RUN_USER=${RUN_USER:-cloudwatcher}
WEB_HOST=${WEB_HOST:-127.0.0.1}
WEB_PORT=${WEB_PORT:-8095}
ACME_ROOT=${ACME_ROOT:-$PREFIX/acme}
SECRETS=$CONFIG_DIR/secrets.env
HTPASSWD=${HTPASSWD:-/etc/nginx/cloudwatcher.htpasswd}

secret_get() {
  key=$1
  file=$2
  if [ ! -f "$file" ]; then
    return 0
  fi
  sed -n "s/^${key}=//p" "$file" | head -n 1
}

rand_pw() {
  openssl rand -base64 24 | tr -d '\n/=+' | cut -c 1-24
}

if [ -z "${MQTT_TOPIC:-}" ]; then
  MQTT_TOPIC=$(secret_get MQTT_TOPIC "$CONFIG_DIR/collector.env" || true)
fi
if [ -z "${MQTT_TOPIC:-}" ]; then
  MQTT_TOPIC="cloudwatcher/#"
fi
case $MQTT_TOPIC in
  *\#) TOPIC_PATTERN=$MQTT_TOPIC ;;
  */) TOPIC_PATTERN=${MQTT_TOPIC}\# ;;
  *) TOPIC_PATTERN=${MQTT_TOPIC}/\# ;;
esac
PUBLISH_TOPIC=${TOPIC_PATTERN%/#}

if [ -z "${WEB_USER:-}" ]; then
  WEB_USER=$(secret_get WEB_USER "$SECRETS" || true)
fi
if [ -z "${WEB_USER:-}" ]; then
  WEB_USER=viewer
fi

install -d -m 755 "$CONFIG_DIR" "$PREFIX" "$ACME_ROOT"

nologin=$(command -v nologin || true)
if [ -z "$nologin" ]; then
  nologin=/usr/sbin/nologin
fi
if ! id "$RUN_USER" >/dev/null 2>&1; then
  if command -v useradd >/dev/null 2>&1; then
    useradd --system --home-dir "$DATA_DIR" --create-home --shell "$nologin" --user-group "$RUN_USER" \
      || useradd -r -d "$DATA_DIR" -m -s "$nologin" "$RUN_USER"
  elif command -v adduser >/dev/null 2>&1; then
    adduser --system --group --home "$DATA_DIR" --shell "$nologin" "$RUN_USER" \
      || adduser -S -D -h "$DATA_DIR" -s "$nologin" "$RUN_USER"
  else
    echo "Create a system account named $RUN_USER, then re-run." >&2
    exit 1
  fi
fi
RUN_GROUP=$(id -gn "$RUN_USER")
install -d -o "$RUN_USER" -g "$RUN_GROUP" -m 750 "$DATA_DIR"

SOLO_PASSWORD=$(secret_get SOLO_PASSWORD "$SECRETS" || true)
COLLECTOR_PASSWORD=$(secret_get COLLECTOR_PASSWORD "$SECRETS" || true)
WEB_PASSWORD=$(secret_get WEB_PASSWORD "$SECRETS" || true)
if [ -z "$SOLO_PASSWORD" ]; then
  SOLO_PASSWORD=solo-$(rand_pw)
fi
if [ -z "$COLLECTOR_PASSWORD" ]; then
  COLLECTOR_PASSWORD=collector-$(rand_pw)
fi
if [ -z "$WEB_PASSWORD" ]; then
  WEB_PASSWORD=web-$(rand_pw)
fi
umask 077
cat > "$SECRETS" <<EOF
SOLO_PASSWORD=$SOLO_PASSWORD
COLLECTOR_PASSWORD=$COLLECTOR_PASSWORD
WEB_USER=$WEB_USER
WEB_PASSWORD=$WEB_PASSWORD
EOF
chmod 600 "$SECRETS"
umask 022

cat > "$CONFIG_DIR/collector.env" <<EOF
CLOUDWATCHER_DB=$DATA_DIR/data.db
MQTT_HOST=localhost
MQTT_PORT=1883
MQTT_USER=collector
MQTT_PASSWORD=$COLLECTOR_PASSWORD
MQTT_TOPIC=$TOPIC_PATTERN
EOF
cat > "$CONFIG_DIR/web.env" <<EOF
CLOUDWATCHER_DB=$DATA_DIR/data.db
WEB_HOST=$WEB_HOST
WEB_PORT=$WEB_PORT
EOF
chown "root:$RUN_GROUP" "$CONFIG_DIR/collector.env" "$CONFIG_DIR/web.env"
chmod 640 "$CONFIG_DIR/collector.env" "$CONFIG_DIR/web.env"

install -m 644 "$ROOT/collector.py" "$ROOT/webapp.py" "$ROOT/requirements.txt" "$PREFIX/"
install -d -m 755 "$PREFIX/static"
for file in "$ROOT"/static/*; do
  install -m 644 "$file" "$PREFIX/static/"
done
if [ ! -x "$PREFIX/venv/bin/python" ]; then
  if ! python3 -m venv "$PREFIX/venv"; then
    echo "python3 -m venv failed. Install this system's Python venv package and re-run." >&2
    exit 1
  fi
fi
"$PREFIX/venv/bin/pip" install -r "$PREFIX/requirements.txt"

render() {
  sed \
    -e "s|@PREFIX@|$PREFIX|g" \
    -e "s|@CONFIG_DIR@|$CONFIG_DIR|g" \
    -e "s|@RUN_USER@|$RUN_USER|g" \
    -e "s|@RUN_GROUP@|$RUN_GROUP|g" \
    -e "s|@SERVER_NAME@|${SERVER_NAME:-}|g" \
    -e "s|@WEB_HOST@|$WEB_HOST|g" \
    -e "s|@WEB_PORT@|$WEB_PORT|g" \
    -e "s|@ACME_ROOT@|$ACME_ROOT|g" \
    -e "s|@HTPASSWD@|$HTPASSWD|g" \
    -e "s|@CERT_DIR@|${CERT_DIR:-}|g" \
    "$1" > "$2"
}

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  render "$ROOT/deploy/cloudwatcher-collector.service" /etc/systemd/system/cloudwatcher-collector.service
  render "$ROOT/deploy/cloudwatcher-web.service" /etc/systemd/system/cloudwatcher-web.service
  systemctl daemon-reload
  systemctl enable cloudwatcher-collector.service cloudwatcher-web.service
  systemctl restart cloudwatcher-collector.service cloudwatcher-web.service
else
  echo "systemd is not running. Start the programs under any supervisor:" >&2
  echo "  set -a; . $CONFIG_DIR/collector.env; set +a; $PREFIX/venv/bin/python $PREFIX/collector.py" >&2
  echo "  set -a; . $CONFIG_DIR/web.env; set +a; $PREFIX/venv/bin/python $PREFIX/webapp.py" >&2
fi

mosq_dir=""
for dir in /etc/mosquitto /usr/local/etc/mosquitto /opt/local/etc/mosquitto; do
  if [ -d "$dir/conf.d" ]; then
    mosq_dir=$dir
    break
  fi
done
if [ -n "$mosq_dir" ] && command -v mosquitto_passwd >/dev/null 2>&1; then
  mosq_group=root
  if grep -q '^mosquitto:' /etc/group 2>/dev/null; then
    mosq_group=mosquitto
  fi
  cat > "$mosq_dir/conf.d/cloudwatcher.conf" <<EOF
listener 1883
allow_anonymous false
password_file $mosq_dir/passwd
acl_file $mosq_dir/acl
persistence true
EOF
  rm -f "$mosq_dir/conf.d/solo.conf"
  cat > "$mosq_dir/acl" <<EOF
user solo
topic write $TOPIC_PATTERN

user collector
topic read $TOPIC_PATTERN
EOF
  : > "$mosq_dir/passwd"
  mosquitto_passwd -b "$mosq_dir/passwd" solo "$SOLO_PASSWORD"
  mosquitto_passwd -b "$mosq_dir/passwd" collector "$COLLECTOR_PASSWORD"
  chown "root:$mosq_group" "$mosq_dir/passwd" "$mosq_dir/acl"
  chmod 640 "$mosq_dir/passwd" "$mosq_dir/acl"
  if [ -f "$mosq_dir/mosquitto.conf" ] && ! grep -q 'conf.d' "$mosq_dir/mosquitto.conf"; then
    echo "Include $mosq_dir/conf.d in $mosq_dir/mosquitto.conf and restart the broker." >&2
  fi
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl enable mosquitto
    systemctl restart mosquitto
  elif command -v service >/dev/null 2>&1; then
    service mosquitto restart
  else
    echo "Restart mosquitto so it reads $mosq_dir/conf.d/cloudwatcher.conf" >&2
  fi
else
  echo "Mosquitto was not configured. Install it, then re-run, or point MQTT_HOST at an existing broker." >&2
fi

echo "Open TCP port 1883 on this host's firewall if the weather station is not on localhost." >&2

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && command -v mosquitto_pub >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  i=0
  while [ "$i" -lt 20 ]; do
    if systemctl is-active --quiet cloudwatcher-collector && systemctl is-active --quiet cloudwatcher-web; then
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  i=0
  while [ "$i" -lt 20 ]; do
    if journalctl -u cloudwatcher-collector --since "5 min ago" --no-pager 2>/dev/null | grep -q "subscribed to"; then
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  SMOKE='{"install_smoke":1,"sky":{"temp":-4.5}}'
  mosquitto_pub -h 127.0.0.1 -u solo -P "$SOLO_PASSWORD" -t "$PUBLISH_TOPIC" -q 1 -m "$SMOKE"
  DAY=$(TZ=Europe/Berlin date +%F)
  smoke_ok=0
  i=0
  while [ "$i" -lt 15 ]; do
    if curl -fsS "http://127.0.0.1:${WEB_PORT}/api/data?date=${DAY}" \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if "install_smoke" in d.get("series", {}) else 1)'; then
      smoke_ok=1
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  if [ "$smoke_ok" -ne 1 ]; then
    echo "Smoke test failed." >&2
    exit 1
  fi
  "$PREFIX/venv/bin/python" - "$DATA_DIR/data.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("DELETE FROM messages WHERE payload LIKE ?", ("%install_smoke%",))
conn.commit()
PY
  chown -R "$RUN_USER:$RUN_GROUP" "$DATA_DIR"
  echo "smoke ok"
fi

nginx_dir=""
for dir in /etc/nginx/conf.d /etc/nginx/http.d /usr/local/etc/nginx/conf.d /opt/local/etc/nginx/conf.d; do
  if [ -d "$dir" ]; then
    nginx_dir=$dir
    break
  fi
done

write_htpasswd() {
  hash=$(openssl passwd -apr1 "$WEB_PASSWORD")
  install -d -m 755 "$(dirname "$HTPASSWD")"
  printf '%s:%s\n' "$WEB_USER" "$hash" > "$HTPASSWD"
  nginx_user=""
  if command -v nginx >/dev/null 2>&1; then
    nginx_user=$(nginx -T 2>/dev/null | awk '/^user[[:space:]]/ { gsub(/;/,"",$2); print $2; exit }')
  fi
  ht_group=root
  if [ -n "$nginx_user" ]; then
    ht_group=$(id -gn "$nginx_user" 2>/dev/null || echo root)
  fi
  if [ "$ht_group" = root ]; then
    chmod 644 "$HTPASSWD"
  else
    chown "root:$ht_group" "$HTPASSWD"
    chmod 640 "$HTPASSWD"
  fi
}

reload_nginx() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    nginx -t
    systemctl reload nginx
  elif command -v nginx >/dev/null 2>&1; then
    nginx -t
    nginx -s reload
  fi
}

if [ -n "${SERVER_NAME:-}" ] && [ -n "$nginx_dir" ] && command -v nginx >/dev/null 2>&1; then
  write_htpasswd
  CERT_DIR=/etc/letsencrypt/live/$SERVER_NAME
  render "$ROOT/deploy/nginx-cloudwatcher-http.conf" "$nginx_dir/cloudwatcher.conf"
  reload_nginx
  have_cert=0
  if [ -f "$CERT_DIR/fullchain.pem" ]; then
    have_cert=1
  elif command -v certbot >/dev/null 2>&1; then
    if python3 - "$SERVER_NAME" <<'PY'
import socket, sys
name = sys.argv[1]
try:
    dns = {item[4][0] for item in socket.getaddrinfo(name, None, socket.AF_INET)}
except socket.gaierror:
    sys.exit(1)
local = set()
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    sock.connect(("1.1.1.1", 80))
    local.add(sock.getsockname()[0])
except OSError:
    pass
finally:
    sock.close()
try:
    local.update(item[4][0] for item in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET))
except socket.gaierror:
    pass
sys.exit(0 if dns & local else 1)
PY
    then
      set -- certbot certonly --webroot -w "$ACME_ROOT" -d "$SERVER_NAME" \
        --non-interactive --agree-tos --keep-until-expiring
      if [ -n "${CERTBOT_EMAIL:-}" ]; then
        set -- "$@" --email "$CERTBOT_EMAIL"
      elif [ ! -d /etc/letsencrypt/accounts ]; then
        set -- "$@" --register-unsafely-without-email
      fi
      if "$@"; then
        have_cert=1
      else
        echo "certbot failed; the site stays on HTTP until a certificate exists" >&2
      fi
    else
      echo "DNS for $SERVER_NAME does not point at this host; skipped certbot" >&2
    fi
  fi
  if [ "$have_cert" -eq 1 ]; then
    render "$ROOT/deploy/nginx-cloudwatcher.conf" "$nginx_dir/cloudwatcher.conf"
    reload_nginx
  fi
elif [ -n "${SERVER_NAME:-}" ]; then
  echo "nginx was not found; $SERVER_NAME was not configured. Proxy $WEB_HOST:$WEB_PORT yourself." >&2
fi

HOST_IP=$(python3 - <<'PY'
import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    sock.connect(("1.1.1.1", 80))
    print(sock.getsockname()[0])
except OSError:
    print("127.0.0.1")
finally:
    sock.close()
PY
)
if [ -n "${SERVER_NAME:-}" ] && [ -f "/etc/letsencrypt/live/$SERVER_NAME/fullchain.pem" ]; then
  WEB_URL="https://$SERVER_NAME"
elif [ -n "${SERVER_NAME:-}" ]; then
  WEB_URL="http://$SERVER_NAME"
else
  WEB_URL="http://$WEB_HOST:$WEB_PORT"
fi
CRED="$ROOT/CREDENTIALS.txt"
umask 077
cat > "$CRED" <<EOF
MQTT broker: ${HOST_IP}:1883
MQTT user solo: ${SOLO_PASSWORD}
MQTT user collector: ${COLLECTOR_PASSWORD}
Topic: ${PUBLISH_TOPIC}

Web: ${WEB_URL}
Web user: ${WEB_USER}
Web password: ${WEB_PASSWORD}
EOF
if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" >/dev/null 2>&1; then
  chown "$SUDO_USER" "$CRED"
fi
chmod 600 "$CRED"
echo "credentials written to ${CRED}"
