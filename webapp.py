#!/usr/bin/env python3
"""Read-only day charts for stored CloudWatcher MQTT messages."""

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


def parse_day(value):
    if not value or not DATE_RE.match(value):
        return None
    try:
        day = datetime.strptime(value, "%Y-%m-%d")
    except ValueError:
        return None
    start = datetime(day.year, day.month, day.day, tzinfo=TZ)
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
    moment = parse_utc(ts_utc).astimezone(TZ)
    return (moment - day_start).total_seconds() / 3600.0


def list_days(conn):
    row = conn.execute("SELECT MIN(ts_utc), MAX(ts_utc) FROM messages").fetchone()
    if row[0] is None:
        return []
    first = parse_utc(row[0]).astimezone(TZ).date()
    last = parse_utc(row[1]).astimezone(TZ).date()
    found = []
    day = first
    while day <= last:
        start = datetime(day.year, day.month, day.day, tzinfo=TZ)
        hit = conn.execute(
            "SELECT 1 FROM messages WHERE ts_utc >= ? AND ts_utc < ? LIMIT 1",
            (utc_iso(start), utc_iso(start + timedelta(days=1))),
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
    }
    conn = open_db()
    if conn is None:
        return jsonify(body)
    try:
        series, received, skipped = series_for_day(conn, start, end)
        body["received"] = received
        body["skipped"] = skipped
        body["series"] = series
        return jsonify(body)
    finally:
        conn.close()


def main():
    host = os.environ.get("WEB_HOST", "127.0.0.1")
    port = int(os.environ.get("WEB_PORT", "8095"))
    app.run(host=host, port=port, threaded=True)


if __name__ == "__main__":
    main()
