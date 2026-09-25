#!/usr/bin/env python3
"""Day charts for stored CloudWatcher MQTT messages, plus editable limits."""

import copy
import json
import os
import re
import sqlite3
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:  # Python 3.8 on the server
    from backports.zoneinfo import ZoneInfo

from flask import Flask, jsonify, request, send_from_directory

TZ = ZoneInfo("Europe/Berlin")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
GREEN = "#1f9d3a"
YELLOW = "#e0a100"
RED = "#d1242f"
SWITCH = "#5b2c6f"

# Solo status limits transcribed from the observatory configuration.
# Empty values are not drawn. 999 is the Solo's "very windy" sentinel.
DEFAULT_LIMITS = {
    "clouds": {
        "title": "Himmelstemperatur",
        "unit": "°C",
        "ymin": -40,
        "ymax": 40,
        "lines": [
            {"id": "clear", "label": "Klar", "value": -15, "color": GREEN},
            {"id": "cloudy", "label": "Bewölkt", "value": -5, "color": YELLOW},
            {"id": "overcast", "label": "Bedeckt", "value": 30, "color": RED},
            {"id": "unsafe", "label": "Schalter", "value": 0, "color": SWITCH},
        ],
    },
    "wind": {
        "title": "Wind",
        "unit": "km/h",
        "ymin": 0,
        "ymax": 60,
        "lines": [
            {"id": "calm", "label": "Ruhig", "value": 5, "color": GREEN},
            {"id": "windy", "label": "Windig", "value": 30, "color": YELLOW},
            {"id": "very", "label": "Sehr windig", "value": 999, "color": RED},
            {"id": "unsafe", "label": "Schalter", "value": 25, "color": SWITCH},
        ],
    },
    "gust": {
        "title": "Böen",
        "unit": "km/h",
        "ymin": 0,
        "ymax": 60,
        "lines": [
            {"id": "calm", "label": "Ruhig", "value": 5, "color": GREEN},
            {"id": "windy", "label": "Windig", "value": 30, "color": YELLOW},
            {"id": "very", "label": "Sehr windig", "value": 999, "color": RED},
        ],
    },
    "rain": {
        "title": "Regen",
        "unit": "",
        "ymin": 0,
        "ymax": 5000,
        "lines": [
            {"id": "dry", "label": "Trocken", "value": 3900, "color": GREEN},
            {"id": "wet", "label": "Feucht", "value": 3600, "color": YELLOW},
            {"id": "rain", "label": "Regen", "value": 10, "color": RED},
            {"id": "unsafe", "label": "Schalter", "value": 4000, "color": SWITCH},
        ],
    },
    "light": {
        "title": "Helligkeit",
        "unit": "",
        "ymin": 0,
        "ymax": 80000,
        "lines": [
            {"id": "dark", "label": "Dunkel", "value": 75000, "color": GREEN},
            {"id": "light", "label": "Hell", "value": 250, "color": YELLOW},
            {"id": "very", "label": "Sehr hell", "value": 0, "color": RED},
            {"id": "unsafe", "label": "Schalter", "value": 2100, "color": SWITCH},
        ],
    },
    "abspress": {
        "title": "Absolutdruck",
        "unit": "Pa",
        "ymin": None,
        "ymax": None,
        "lines": [
            {"id": "low", "label": "Niedrig", "value": None, "color": GREEN},
            {"id": "medium", "label": "Mittel", "value": None, "color": YELLOW},
            {"id": "high", "label": "Hoch", "value": None, "color": RED},
            {"id": "unsafe", "label": "Schalter", "value": 1000, "color": SWITCH},
        ],
    },
    "relpress": {
        "title": "Relativdruck",
        "unit": "Pa",
        "ymin": None,
        "ymax": None,
        "lines": [
            {"id": "low", "label": "Niedrig", "value": None, "color": GREEN},
            {"id": "medium", "label": "Mittel", "value": None, "color": YELLOW},
            {"id": "high", "label": "Hoch", "value": None, "color": RED},
            {"id": "unsafe", "label": "Schalter", "value": 1000, "color": SWITCH},
        ],
    },
    "temp": {
        "title": "Temperatur",
        "unit": "°C",
        "ymin": -20,
        "ymax": 40,
        "lines": [],
    },
    "rawir": {
        "title": "Raw Infrared",
        "unit": "°C",
        "ymin": -40,
        "ymax": 40,
        "lines": [],
    },
}

SETTINGS_DDL = """
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
"""

app = Flask(__name__, static_folder="static", static_url_path="/static")


def db_path():
    return os.environ.get("CLOUDWATCHER_DB", "/var/lib/cloudwatcher/data.db")


def utc_iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f+00:00")


def parse_utc(text):
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    return datetime.fromisoformat(text)


def open_db():
    path = db_path()
    if not os.path.exists(path):
        return None
    conn = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def open_rw():
    path = db_path()
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    conn = sqlite3.connect(path, timeout=5)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(SETTINGS_DDL)
    return conn


def _clean_number(value):
    if value is None or value == "":
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError("limit value must be a number")
    number = float(value)
    if not _finite(number):
        raise ValueError("limit value must be finite")
    return number


def merge_limits(saved):
    merged = copy.deepcopy(DEFAULT_LIMITS)
    if not isinstance(saved, dict):
        return merged
    for field, spec in saved.items():
        if not isinstance(field, str) or not isinstance(spec, dict):
            continue
        base = merged.setdefault(
            field, {"title": field, "unit": "", "ymin": None, "ymax": None, "lines": []}
        )
        if "ymin" in spec:
            base["ymin"] = _clean_number(spec.get("ymin"))
        if "ymax" in spec:
            base["ymax"] = _clean_number(spec.get("ymax"))
        incoming = spec.get("lines")
        if not isinstance(incoming, list):
            continue
        by_id = {}
        for line in incoming:
            if isinstance(line, dict) and isinstance(line.get("id"), str):
                by_id[line["id"]] = line
        if base.get("lines"):
            for line in base["lines"]:
                got = by_id.get(line["id"])
                if got and "value" in got:
                    line["value"] = _clean_number(got.get("value"))
        else:
            cleaned = []
            for line in incoming:
                if not isinstance(line, dict):
                    continue
                cleaned.append({
                    "id": str(line.get("id") or "limit"),
                    "label": str(line.get("label") or "Limit"),
                    "value": _clean_number(line.get("value")),
                    "color": str(line.get("color") or "#666666"),
                })
            base["lines"] = cleaned
    return merged


def read_raw_settings(conn):
    row = conn.execute("SELECT value FROM settings WHERE key = 'config'").fetchone()
    if not row:
        return {"order": [], "limits": {}}
    try:
        data = json.loads(row["value"])
    except (json.JSONDecodeError, TypeError):
        return {"order": [], "limits": {}}
    if not isinstance(data, dict):
        return {"order": [], "limits": {}}
    return data


def _name_list(value):
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def public_settings(raw):
    lang = raw.get("lang") if raw.get("lang") in ("de", "en") else ""
    return {
        "order": _name_list(raw.get("order")),
        "hidden": _name_list(raw.get("hidden")),
        "lang": lang,
        "limits": merge_limits(raw.get("limits")),
    }


def write_settings(conn, raw):
    conn.execute(
        "INSERT OR REPLACE INTO settings (key, value) VALUES ('config', ?)",
        (json.dumps(raw, ensure_ascii=False),),
    )


def apply_settings(conn, payload):
    if not isinstance(payload, dict):
        raise ValueError("JSON object required")
    raw = read_raw_settings(conn)
    if "order" in payload:
        order = payload["order"]
        if (
            not isinstance(order, list)
            or len(order) > 200
            or not all(isinstance(item, str) and len(item) <= 80 for item in order)
        ):
            raise ValueError("order must be a list of field names")
        raw["order"] = order
    if "limits" in payload:
        limits = payload["limits"]
        if not isinstance(limits, dict):
            raise ValueError("limits must be an object")
        # Validate numbers before storing. Unknown fields are kept.
        merge_limits(limits)
        raw["limits"] = limits
    if "hidden" in payload:
        hidden = payload["hidden"]
        if (
            not isinstance(hidden, list)
            or len(hidden) > 200
            or not all(isinstance(item, str) and len(item) <= 80 for item in hidden)
        ):
            raise ValueError("hidden must be a list of field names")
        raw["hidden"] = hidden
    if "lang" in payload:
        lang = payload["lang"]
        if lang not in ("de", "en", ""):
            raise ValueError("lang must be de or en")
        raw["lang"] = lang
    write_settings(conn, raw)
    return public_settings(raw)


def parse_day(value):
    if not value or not DATE_RE.match(value):
        return None
    try:
        day = datetime.strptime(value, "%Y-%m-%d")
    except ValueError:
        return None
    start = datetime(day.year, day.month, day.day, 12, tzinfo=TZ)
    return start, start + timedelta(days=1)


def is_number(value):
    if isinstance(value, bool) or value is None:
        return False
    if isinstance(value, (int, float)):
        return _finite(float(value))
    if isinstance(value, str) and value.strip():
        try:
            return _finite(float(value))
        except ValueError:
            return False
    return False


def _finite(number):
    return number == number and number not in (float("inf"), float("-inf"))


def flatten(value, prefix, out):
    if isinstance(value, dict):
        for key, item in value.items():
            name = "%s.%s" % (prefix, key) if prefix else str(key)
            flatten(item, name, out)
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            name = "%s.%d" % (prefix, index) if prefix else str(index)
            flatten(item, name, out)
        return
    if prefix and is_number(value):
        out.append((prefix, float(value)))


def local_hour(ts_utc, day_start):
    """Hours after noon. 0 is 12:00, 12 is midnight, 24 is the next 12:00."""
    del day_start
    moment = parse_utc(ts_utc).astimezone(TZ)
    minutes = (
        moment.hour * 60
        + moment.minute
        + moment.second / 60.0
        + moment.microsecond / 60000000.0
    )
    delta = minutes - 12 * 60
    if delta < 0:
        delta += 24 * 60
    return delta / 60.0


def chart_date(moment):
    local = moment.astimezone(TZ)
    day = local.date()
    if local.hour < 12:
        day -= timedelta(days=1)
    return day


def latest_message_iso(conn):
    row = conn.execute("SELECT MAX(ts_utc) FROM messages").fetchone()
    if not row or row[0] is None:
        return None
    return parse_utc(row[0]).astimezone(TZ).isoformat(timespec="seconds")


def list_days(conn):
    row = conn.execute("SELECT MIN(ts_utc), MAX(ts_utc) FROM messages").fetchone()
    if row[0] is None:
        return []
    first = chart_date(parse_utc(row[0]))
    last = chart_date(parse_utc(row[1]))
    found = []
    day = first
    while day <= last:
        start, end = parse_day(day.isoformat())
        hit = conn.execute(
            "SELECT 1 FROM messages WHERE ts_utc >= ? AND ts_utc < ? LIMIT 1",
            (utc_iso(start), utc_iso(end)),
        ).fetchone()
        if hit:
            found.append(day.isoformat())
        day += timedelta(days=1)
    return found


def series_for_day(conn, start, end):
    series = {}
    received = 0
    skipped = 0
    rows = conn.execute(
        """
        SELECT ts_utc, payload FROM messages
        WHERE ts_utc >= ? AND ts_utc < ?
        ORDER BY ts_utc
        """,
        (utc_iso(start), utc_iso(end)),
    )
    for row in rows:
        received += 1
        try:
            payload = json.loads(row["payload"])
        except (json.JSONDecodeError, TypeError, ValueError):
            skipped += 1
            continue
        points = []
        flatten(payload, "", points)
        hour = round(local_hour(row["ts_utc"], start), 4)
        for name, value in points:
            series.setdefault(name, []).append([hour, value])
    return series, received, skipped


@app.after_request
def no_cache_html(response):
    ctype = response.content_type or ""
    if ctype.startswith("text/html"):
        response.headers["Cache-Control"] = "no-cache"
    return response


@app.get("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.get("/config")
def config_page():
    return send_from_directory(app.static_folder, "config.html")


@app.get("/api/settings")
def get_settings():
    conn = open_rw()
    try:
        return jsonify(public_settings(read_raw_settings(conn)))
    finally:
        conn.close()


@app.put("/api/settings")
def put_settings():
    payload = request.get_json(silent=True)
    conn = open_rw()
    try:
        try:
            saved = apply_settings(conn, payload)
        except ValueError as exc:
            conn.rollback()
            return jsonify(error=str(exc)), 400
        conn.commit()
        return jsonify(saved)
    finally:
        conn.close()


@app.get("/api/days")
def days():
    conn = open_db()
    if conn is None:
        return jsonify(timezone="Europe/Berlin", days=[])
    try:
        return jsonify(timezone="Europe/Berlin", days=list_days(conn))
    finally:
        conn.close()


@app.get("/api/data")
def data():
    parsed = parse_day(request.args.get("date", ""))
    if parsed is None:
        return jsonify(error="date must be YYYY-MM-DD"), 400
    start, end = parsed
    body = {
        "date": start.date().isoformat(),
        "timezone": "Europe/Berlin",
        "received": 0,
        "skipped": 0,
        "series": {},
        "last_message": None,
    }
    conn = open_db()
    if conn is None:
        return jsonify(body)
    try:
        series, received, skipped = series_for_day(conn, start, end)
        body["received"] = received
        body["skipped"] = skipped
        body["series"] = series
        body["last_message"] = latest_message_iso(conn)
        return jsonify(body)
    finally:
        conn.close()


def main():
    host = os.environ.get("WEB_HOST", "127.0.0.1")
    port = int(os.environ.get("WEB_PORT", "8095"))
    app.run(host=host, port=port, threaded=True)


if __name__ == "__main__":
    main()
