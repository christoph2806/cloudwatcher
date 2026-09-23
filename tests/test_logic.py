import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import collector
import webapp


class LogicTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "data.db")
        os.environ["CLOUDWATCHER_DB"] = self.db
        self.conn = collector.connect_db(self.db)
        self.client = webapp.app.test_client()

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def test_flatten_nested_numbers_and_ignore_bools(self):
        out = []
        webapp.flatten(
            {"temp": "12.5", "ok": True, "sky": {"ir": -8}, "note": "x"},
            "",
            out,
        )
        self.assertEqual(dict(out), {"temp": 12.5, "sky.ir": -8.0})

    def test_berlin_day_boundary(self):
        # 2026-09-23 22:30 UTC is 2026-09-24 00:30 in Berlin (CEST).
        collector.store_message(
            self.conn,
            "sternwarte/cloudwatcher",
            json.dumps({"temp": 1}),
            "2026-09-23T22:30:00.000000+00:00",
        )
        collector.store_message(
            self.conn,
            "sternwarte/cloudwatcher",
            "not-json",
            "2026-09-24T12:00:00.000000+00:00",
        )
        collector.store_message(
            self.conn,
            "sternwarte/cloudwatcher",
            json.dumps({"temp": 2}),
            "2026-09-24T22:00:00.000000+00:00",
        )

        response = self.client.get("/api/data?date=2026-09-24")
        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertEqual(body["received"], 2)
        self.assertEqual(body["skipped"], 1)
        self.assertEqual(body["series"]["temp"], [[0.5, 1.0]])

        days = self.client.get("/api/days").get_json()["days"]
        self.assertEqual(days, ["2026-09-24", "2026-09-25"])

    def test_winter_boundary_and_missing_day(self):
        collector.store_message(
            self.conn,
            "sternwarte/cloudwatcher",
            json.dumps({"wind": 3}),
            "2026-01-14T23:30:00.000000+00:00",
        )
        body = self.client.get("/api/data?date=2026-01-15").get_json()
        self.assertEqual(body["series"]["wind"], [[0.5, 3.0]])
        empty = self.client.get("/api/data?date=2026-01-16").get_json()
        self.assertEqual(empty["received"], 0)
        self.assertEqual(empty["series"], {})

    def test_bad_date(self):
        self.assertEqual(self.client.get("/api/data?date=yesterday").status_code, 400)

    def test_hour_uses_berlin_offset(self):
        start, _end = webapp.parse_day("2026-01-15")
        hour = webapp.local_hour("2026-01-14T23:30:00.000000+00:00", start)
        self.assertAlmostEqual(hour, 0.5)
        self.assertIsNotNone(start.tzinfo)
        self.assertEqual(start + timedelta(days=1), webapp.parse_day("2026-01-15")[1])
        self.assertEqual(datetime(2026, 1, 15, tzinfo=webapp.TZ).utcoffset(), start.utcoffset())


if __name__ == "__main__":
    unittest.main()
