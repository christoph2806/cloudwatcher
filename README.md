# CloudWatcher MQTT

A Lunatico Solo publishes readings over MQTT. `collector.py` stores each message unchanged in SQLite. `webapp.py` draws the numeric fields as day charts (Europe/Berlin). The pages are English and German; the language is chosen under Settings and stored in the browser.

## Solo

| Setting | Value |
| --- | --- |
| Broker | this host, port `1883` (no TLS) |
| User | `solo` |
| Topic | the topic chosen at install (default `cloudwatcher`) |
| QoS | 1 |

The password is written on the server to `CREDENTIALS.txt` (not in git).

## Requirements

`deploy/install.sh` does not install operating-system packages and does not target a particular distribution. Install these with the host's own package manager:

- Python 3, including the `venv` module, and OpenSSL
- Mosquitto, if this host should be the broker (`mosquitto_passwd` on `PATH`)
- optional: nginx, certbot, and systemd

Open TCP port 1883 on the host firewall when the Solo is not on the same machine.

## Installation

From a checkout, as root:

```sh
sudo MQTT_TOPIC='cloudwatcher/#' WEB_USER=viewer \
     SERVER_NAME=weather.example.com sh deploy/install.sh
```

`MQTT_TOPIC` is the collector subscription (default `cloudwatcher/#`). `WEB_USER` is the basic-auth user (default `viewer`). Without `SERVER_NAME`, nginx and certificates are left untouched and the UI stays on `127.0.0.1:8095`. Re-running keeps existing passwords and, when the variables are omitted, the topic and web user already installed.

## Paths

| Path | Contents |
| --- | --- |
| `/opt/cloudwatcher/` | program and Python venv (`PREFIX`) |
| `/var/lib/cloudwatcher/data.db` | SQLite (WAL) |
| `/etc/cloudwatcher/collector.env` | collector MQTT settings |
| `/etc/cloudwatcher/secrets.env` | passwords |
| Mosquitto `conf.d/cloudwatcher.conf` | broker listener, when Mosquitto is installed |
| nginx `conf.d/cloudwatcher.conf` | reverse proxy, when `SERVER_NAME` is set |

The web app listens only on `127.0.0.1:8095` unless `WEB_HOST` and `WEB_PORT` say otherwise.

## Services

When systemd is running, the script enables:

- `mosquitto` (if the broker was configured here)
- `cloudwatcher-collector.service` (user `cloudwatcher`, `Restart=always`)
- `cloudwatcher-web.service` (same user, localhost only)

Otherwise it prints the two commands to run under any supervisor.

## Deploy

Pushes to `main` update a checkout on the server and restart the app. The GitHub Action only SSHes in; it does not use sudo. The programs then run as your login's systemd user services, so a later push can restart them.

Once, on the server, from that checkout:

```sh
sudo sh deploy/handoff.sh
```

That stops the root system units, grants your login access to the database and env files, and enables the user services. `deploy/install.sh` will not start the system units again after this.

The action needs these repository secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PORT`, `DEPLOY_SSH_KEY`. The key's public half is an `authorized_keys` entry whose command is `deploy/deploy.sh`. The server pulls with a read-only deploy key at `~/.ssh/cloudwatcher_repo`.

Check that the Solo is publishing:

```sh
mosquitto_sub -h localhost -u collector -P '…' -t 'cloudwatcher/#' -v
```

## Example message

The raw text is stored unchanged. The web app flattens the JSON object and charts every numeric field.

```json
{
  "dataGMTTime": "2026/09/23 22:59:18",
  "cwinfo": "Serial: 1, FW: 5.83",
  "slddata": "2026-09-24 00:59:24.00 C K  -12.9    9.5    9.5    0.0  -1  -20.0  33 0 0 00000 046289.04125 2 1 1 2 0 0",
  "clouds": -12.88,
  "temp": 9.54,
  "wind": 0,
  "gust": 0,
  "rain": 4189,
  "light": 11401,
  "switch": 1,
  "safe": 1,
  "hum": -1,
  "dewp": -20.0,
  "rawir": -10.36,
  "abspress": 0.0,
  "relpress": 0.0
}
```

## Fields

| Field | Meaning |
| --- | --- |
| `dataGMTTime` | Solo timestamp, GMT |
| `cwinfo` | Serial number and firmware |
| `slddata` | Solo raw line, not parsed as a number |
| `clouds` | Sky temperature, °C |
| `temp` | Ambient temperature, °C |
| `rawir` | Uncorrected infrared temperature, °C |
| `wind`, `gust` | Wind and gusts, drawn on one chart |
| `rain` | Rain sensor, raw value (higher is drier) |
| `light` | Brightness, raw value |
| `switch` | Switch output |
| `safe` | `1` means observing is allowed |
| `hum`, `dewp` | Humidity in % and dew point; `-1` means no sensor |
| `abspress`, `relpress` | Pressure; `0` means no sensor |
