#!/bin/sh
# Update this checkout and restart the user services. No root required.
# The login user must already be allowed to read the env files and write the database
# (deploy/handoff.sh does that once).
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

KEY=$HOME/.ssh/cloudwatcher_repo
if [ -f "$KEY" ]; then
  export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
fi

git fetch origin
git checkout -f main
git reset --hard origin/main

if [ ! -x "$ROOT/.venv/bin/python" ]; then
  python3 -m venv "$ROOT/.venv"
fi
hash=$(sha256sum "$ROOT/requirements.txt" | awk '{print $1}')
stamp=$ROOT/.venv/.req-hash
if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$hash" ]; then
  "$ROOT/.venv/bin/pip" install -r "$ROOT/requirements.txt"
  printf '%s\n' "$hash" > "$stamp"
fi

uid=$(id -u)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$uid}
if [ ! -S "$XDG_RUNTIME_DIR/systemd/private" ]; then
  echo "systemd user session is not running for uid $uid" >&2
  exit 1
fi

if ! systemctl --user cat cloudwatcher-web.service >/dev/null 2>&1; then
  echo "Code is updated. Run once: sudo sh deploy/handoff.sh"
  exit 0
fi

systemctl --user restart cloudwatcher-web.service cloudwatcher-collector.service
systemctl --user is-active --quiet cloudwatcher-web.service
systemctl --user is-active --quiet cloudwatcher-collector.service
