# CloudWatcher MQTT

Die Lunatico-Solo sendet Messwerte per MQTT an diesen Server. `collector.py` speichert jede Nachricht unverändert in SQLite. `webapp.py` zeigt die numerischen Felder als Tagesdiagramme (Europe/Berlin).

## Solo

| Einstellung | Wert |
| --- | --- |
| Broker | `142.132.166.43` |
| Port | `1883` (ohne TLS) |
| Benutzer | `solo` |
| Topic | `sternwarte/cloudwatcher` |
| QoS | 1 |

Das Passwort steht auf dem Server in `CREDENTIALS.txt` (nicht im Git).

## Installation

Auf dem Server, im Checkout:

```bash
sudo bash deploy/install.sh
```

Das Skript ist wiederholbar. Zertifikat und nginx-TLS-VHost entstehen, sobald `cloudwatcher.mussenbrock.net` auf diesen Host zeigt.

## Pfade

| Pfad | Inhalt |
| --- | --- |
| `/opt/cloudwatcher/` | Programm und Python-venv |
| `/var/lib/cloudwatcher/data.db` | SQLite (WAL) |
| `/etc/cloudwatcher/collector.env` | MQTT-Zugang des Collectors |
| `/etc/cloudwatcher/secrets.env` | Passwörter |
| `/etc/mosquitto/conf.d/solo.conf` | Broker |
| `/etc/mosquitto/acl` | Rechte `solo` (nur Schreiben) und `collector` (nur Lesen) |
| `/etc/nginx/sites-available/cloudwatcher.mussenbrock.net` | HTTPS und Basic Auth |

Die Web-App hört nur auf `127.0.0.1:8095`.

## Dienste

- `mosquitto`
- `cloudwatcher-collector.service` (Benutzer `cloudwatcher`, `Restart=always`)
- `cloudwatcher-web.service` (derselbe Benutzer, nur localhost)

Nach einem Neustart des Servers starten sie von selbst.

Prüfung, ob die Solo ankommt:

```bash
mosquitto_sub -h localhost -u collector -P '…' -t 'sternwarte/#' -v
```

Die Seite ist `https://cloudwatcher.mussenbrock.net` (Basic Auth, Benutzer `sternwarte`).

## Beispielnachricht

Empfangen am 2026-09-24 auf `sternwarte/cloudwatcher`. Die Rohzeichenfolge wird unverändert gespeichert; die Web-App macht das JSON-Objekt flach und zeichnet jedes numerische Feld.

```json
{
  "dataGMTTime": "2026/09/23 22:59:18",
  "cwinfo": "Serial: 1953, FW: 5.83",
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

## Feldbedeutungen

| Feld | Bedeutung |
| --- | --- |
| `dataGMTTime` | Zeitstempel der Solo, GMT |
| `cwinfo` | Seriennummer und Firmware |
| `slddata` | Rohzeile der Solo, nicht numerisch ausgewertet |
| `clouds` | Himmelstemperatur, °C |
| `temp` | Umgebungstemperatur, °C |
| `rawir` | Unkorrigierte Infrarottemperatur, °C |
| `wind`, `gust` | Wind und Böen |
| `rain` | Regensensor, Rohwert (höher ist trockener) |
| `light` | Helligkeit, Rohwert |
| `switch` | Schaltausgang |
| `safe` | `1` = Beobachtung freigegeben |
| `hum`, `dewp` | Luftfeuchte in % und Taupunkt; `-1` / fehlender Sensor |
| `abspress`, `relpress` | Luftdruck; `0` = kein Sensor |
