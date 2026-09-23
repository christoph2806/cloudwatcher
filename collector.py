#!/usr/bin/env python3
"""Subscribe to CloudWatcher MQTT messages and store the raw payload."""

import logging
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

log = logging.getLogger("cloudwatcher.collector")

SCHEMA = """
CREATE TABLE IF NOT EXISTS messages (
  id        INTEGER PRIMARY KEY,
  ts_utc    TEXT NOT NULL,
  topic     TEXT NOT NULL,
  payload   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages(ts_utc);
"""


def db_path():
    return os.environ.get("CLOUDWATCHER_DB", "/var/lib/cloudwatcher/data.db")


def utc_now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f+00:00")


def payload_text(raw):
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("latin-1")


def connect_db(path):
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    conn = sqlite3.connect(path, isolation_level=None)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.executescript(SCHEMA)
    return conn


def store_message(conn, topic, payload, ts_utc=None):
    conn.execute(
        "INSERT INTO messages (ts_utc, topic, payload) VALUES (?, ?, ?)",
        (ts_utc or utc_now_iso(), topic, payload),
    )


def _failed(reason_code):
    if hasattr(reason_code, "is_failure"):
        return bool(reason_code.is_failure)
    try:
        return int(reason_code) != 0
    except (TypeError, ValueError):
        return True


def run():
    host = os.environ.get("MQTT_HOST", "localhost")
    port = int(os.environ.get("MQTT_PORT", "1883"))
    user = os.environ.get("MQTT_USER", "collector")
    password = os.environ.get("MQTT_PASSWORD", "")
    topic = os.environ.get("MQTT_TOPIC", "sternwarte/cloudwatcher/#")
    if not password:
        log.error("MQTT_PASSWORD is not set")
        return 1

    conn = connect_db(db_path())
    log.info("database %s", db_path())

    def on_connect(client, userdata, flags, reason_code, properties):
        if _failed(reason_code):
            log.error("broker refused connection: %s", reason_code)
            return
        log.info("connected to %s:%s", host, port)
        client.subscribe(topic, qos=1)
        log.info("subscribed to %s", topic)

    def on_disconnect(client, userdata, disconnect_flags, reason_code, properties):
        log.warning("disconnected from broker: %s", reason_code)

    def on_message(client, userdata, message):
        text = payload_text(message.payload)
        try:
            store_message(conn, message.topic, text)
        except sqlite3.Error:
            log.exception("failed to store message on %s", message.topic)
            return
        log.info("stored topic=%s bytes=%d", message.topic, len(message.payload))

    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id="cloudwatcher-collector",
        clean_session=False,
    )
    client.username_pw_set(user, password)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message
    client.reconnect_delay_set(min_delay=1, max_delay=60)
    while True:
        try:
            client.connect(host, port, keepalive=60)
            client.loop_forever(retry_first_connection=True)
            return 0
        except Exception:
            log.exception("broker connection failed, retrying in 5s")
            time.sleep(5)


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    try:
        sys.exit(run())
    except Exception:
        log.exception("collector stopped")
        sys.exit(1)


if __name__ == "__main__":
    main()
