#!/bin/sh
# One-time: stop the root-owned system units and run the same programs as the
# login user's systemd services. After this, deploy/deploy.sh needs no sudo.
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run once as root: sudo sh deploy/handoff.sh" >&2
  exit 1
fi

OWNER=${SUDO_USER:-}
if [ -z "$OWNER" ] || [ "$OWNER" = root ]; then
  echo "Run via sudo from the account that deploys, not from a root shell." >&2
  exit 1
fi

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
CONFIG_DIR=${CONFIG_DIR:-/etc/cloudwatcher}
DATA_DIR=${DATA_DIR:-/var/lib/cloudwatcher}
uid=$(id -u "$OWNER")
home=$(getent passwd "$OWNER" | cut -d: -f6)
unit_dir=$home/.config/systemd/user

if [ ! -f "$CONFIG_DIR/web.env" ] || [ ! -f "$CONFIG_DIR/collector.env" ]; then
  echo "Missing $CONFIG_DIR/web.env or collector.env. Run deploy/install.sh first." >&2
  exit 1
fi
if ! id cloudwatcher >/dev/null 2>&1; then
  echo "System account cloudwatcher is missing. Run deploy/install.sh first." >&2
  exit 1
fi

usermod -aG cloudwatcher "$OWNER"
chmod 770 "$DATA_DIR"
chmod g+rw "$DATA_DIR"/data.db "$DATA_DIR"/data.db-wal "$DATA_DIR"/data.db-shm 2>/dev/null || true
chgrp cloudwatcher "$CONFIG_DIR/web.env" "$CONFIG_DIR/collector.env"
chmod 640 "$CONFIG_DIR/web.env" "$CONFIG_DIR/collector.env"

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now cloudwatcher-web.service cloudwatcher-collector.service 2>/dev/null || true
  # mask refuses to replace a real unit file, which is what install.sh writes.
  rm -f /etc/systemd/system/cloudwatcher-web.service /etc/systemd/system/cloudwatcher-collector.service
  systemctl daemon-reload
  systemctl mask cloudwatcher-web.service cloudwatcher-collector.service
fi

install -d -o "$OWNER" -g "$OWNER" -m 755 "$unit_dir"
render() {
  sed \
    -e "s|@CHECKOUT@|$ROOT|g" \
    -e "s|@CONFIG_DIR@|$CONFIG_DIR|g" \
    "$1" > "$2"
  chown "$OWNER:$OWNER" "$2"
  chmod 644 "$2"
}
render "$ROOT/deploy/cloudwatcher-web.user.service" "$unit_dir/cloudwatcher-web.service"
render "$ROOT/deploy/cloudwatcher-collector.user.service" "$unit_dir/cloudwatcher-collector.service"

printf '%s\n' "$ROOT" > "$CONFIG_DIR/user-services"
chmod 644 "$CONFIG_DIR/user-services"

loginctl enable-linger "$OWNER"
systemctl restart "user@$uid"
i=0
while [ ! -S "/run/user/$uid/systemd/private" ]; do
  i=$((i + 1))
  if [ "$i" -gt 50 ]; then
    echo "user systemd for $OWNER did not come back" >&2
    exit 1
  fi
  sleep 0.1
done

sudo -u "$OWNER" env XDG_RUNTIME_DIR="/run/user/$uid" \
  "$ROOT/deploy/deploy.sh"
sudo -u "$OWNER" env XDG_RUNTIME_DIR="/run/user/$uid" \
  systemctl --user enable --now cloudwatcher-web.service cloudwatcher-collector.service

echo "Handoff done. Further updates: git push origin main"
