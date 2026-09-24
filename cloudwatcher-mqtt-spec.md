# Mini-Spec: CloudWatcher-Datenerfassung per MQTT mit Web-Anzeige

## Ziel

Eine Lunatico AAG CloudWatcher mit Solo-Einheit sendet ihre Messwerte per MQTT an einen Unix-Server. Dort werden sie dauerhaft gespeichert und über eine kleine Webseite als Tagesdiagramme angezeigt, mit frei wählbarem Datum.

Bewusst einfach halten: keine Zeitreihendatenbank, kein Grafana, keine Container, sofern nicht ohnehin vorhanden.

## Architektur

```
Solo --MQTT, Port 1883--> Mosquitto
                                          |
                                   collector.py (abonniert, schreibt)
                                          |
                                   SQLite-Datei
                                          |
                                   webapp.py (liest, zeigt Diagramme)
                                          |
                               Reverse Proxy (HTTPS + Basic Auth)
```

## Rahmenbedingungen

- Die Solo unterstützt kein TLS. Verbindung Solo zu Broker ist unverschlüsselt auf Port 1883. Daher eigener Benutzer für die Solo, der nur in seinen Topic schreiben darf.
- Die Solo sendet in einem einstellbaren Intervall (Minimum 15 s), QoS 1, clean session.
- Topic auf der Solo: frei wählbar, Voreinstellung `cloudwatcher` (der Collector abonniert `cloudwatcher/#`).
- Das Nachrichtenformat der Solo ist JSON. Der Code setzt keine festen Feldnamen voraus; numerische Felder werden beim Lesen erkannt.
- Zeitstempel intern immer UTC. Anzeige und Tagesgrenzen in Europe/Berlin.

## Teil 1: Mosquitto

- Paket `mosquitto` aus der Distribution installieren.
- Datei `/etc/mosquitto/conf.d/solo.conf`:

```
listener 1883
allow_anonymous false
password_file /etc/mosquitto/passwd
acl_file /etc/mosquitto/acl
persistence true
```

- Datei `/etc/mosquitto/acl`:

```
user solo
topic write cloudwatcher/#

user collector
topic read cloudwatcher/#
```

- Benutzer `solo` und `collector` mit `mosquitto_passwd` anlegen. Passwörter nicht ins Repository, sondern in eine Datei außerhalb von Git.
- Port 1883 in der Firewall des Hosts öffnen, wenn die Solo nicht lokal ist. Nur 1883, keine anderen MQTT-Ports.

## Teil 2: collector.py

- Python 3, Bibliothek `paho-mqtt` (Version 2.x).
- Verbindet sich als `collector` mit dem lokalen Broker (`localhost:1883`), abonniert das konfigurierte Topic (Voreinstellung `cloudwatcher/#`).
- Reconnect automatisch bei Verbindungsverlust; Verbindungsauf- und -abbau loggen.
- Pro empfangener Nachricht eine Zeile in SQLite:

```sql
CREATE TABLE IF NOT EXISTS messages (
  id        INTEGER PRIMARY KEY,
  ts_utc    TEXT NOT NULL,     -- Empfangszeit, ISO 8601, UTC
  topic     TEXT NOT NULL,
  payload   TEXT NOT NULL      -- Rohnachricht unverändert
);
CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages(ts_utc);
```

- **Rohnachricht immer unverändert speichern.** Auswertung erst beim Lesen. So geht nichts verloren, auch wenn sich das Format später ändert.
- Enthält die Nachricht einen eigenen Zeitstempel der Solo, zusätzlich in Spalte `ts_device` ablegen (Spalte erst ergänzen, wenn das Format bekannt ist).
- SQLite im WAL-Modus (erlaubt gleichzeitiges Lesen durch die Webapp).
- Datenbankpfad per Umgebungsvariable, Standard `/var/lib/cloudwatcher/data.db`.
- Als systemd-Dienst `cloudwatcher-collector.service`, `Restart=always`, eigener Systembenutzer ohne Login.

## Teil 3: webapp.py

- Python 3, Flask oder FastAPI (Entwickler wählt), liest dieselbe SQLite-Datei nur lesend.
- Eigener systemd-Dienst `cloudwatcher-web.service`, lauscht nur auf `127.0.0.1`.
- Erreichbar über vorhandenen Reverse Proxy auf dem Server mit HTTPS und Basic Auth. Falls keiner vorhanden: Caddy.

### API

- `GET /api/days` liefert die Liste der Tage (Europe/Berlin), für die Daten vorliegen.
- `GET /api/data?date=YYYY-MM-DD` liefert alle Nachrichten dieses Tages (00:00 bis 24:00 Europe/Berlin) als Zeitreihen:
  - Payload als JSON parsen, verschachtelte Objekte flach machen (`a.b.c`).
  - Jedes Feld mit numerischem Wert wird eine Zeitreihe: `{ "feld": [[ts, wert], ...], ... }`.
  - Nicht parsebare Nachrichten überspringen und zählen; Anzahl in der Antwort mitliefern.

### Seite

- Eine einzige HTML-Seite, kein Build-Schritt.
- Oben: Datumsauswahl (Kalenderfeld), Knöpfe „Vortag“, „Heute“, „Folgetag“. Standard: heute.
- Darunter ein Diagramm pro Feld, Zeitachse 0 bis 24 Uhr lokale Zeit, untereinander angeordnet (ähnlich der Solo-Weboberfläche).
- Auswahl, welche Felder angezeigt werden (Checkboxen), gewählte Auswahl in `localStorage` merken.
- Sinnvolle Gruppierung, sobald das Format bekannt ist: Wind und Böen in ein Diagramm; Himmelstemperatur und Umgebungstemperatur in ein Diagramm.
- Diagramm-Bibliothek: Chart.js, lokal ausgeliefert (nicht per CDN).
- Muss auf dem Handy lesbar sein.

## Reihenfolge

1. Mosquitto einrichten, Benutzer anlegen, Port öffnen.
2. Broker, Topic und Benutzer `solo` in der Solo eintragen und MQTT aktivieren.
3. Mit `mosquitto_sub -u collector -P ... -t 'cloudwatcher/#' -v` prüfen, dass Nachrichten ankommen, und die Feldnamen im README dokumentieren.
4. collector.py mit systemd.
5. webapp.py mit systemd und Proxy.

## Abnahme

- Nach Neustart des Servers laufen beide Dienste ohne Eingriff weiter.
- Verbindungsabbruch der Solo (Stecker ziehen, 5 min warten, wieder einstecken) führt nur zu einer Datenlücke, nicht zu einem Fehler.
- Webseite zeigt für heute und für einen beliebigen vergangenen Tag die Diagramme; Tage ohne Daten zeigen einen klaren Hinweis statt leerer Achsen.
- README mit: Installationsschritten, Pfaden, Dienstnamen, Beispielnachricht, Feldbedeutungen.

## Nicht im Umfang

- TLS zwischen Solo und Broker (von der Solo nicht unterstützt).
- Warnungen, Benachrichtigungen, Verknüpfung mit N.I.N.A.-Guiding-Daten (spätere Ausbaustufe).
- Datenlöschung. Menge bei 15-s-Intervall grob 2 GB pro Jahr, unkritisch.
