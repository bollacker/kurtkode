import os
import unittest

from logparse import parse_line

SAMPLES = os.path.join(os.path.dirname(__file__), "..", "samples", "requests.log")


class ParseLineTest(unittest.TestCase):
    def setUp(self):
        with open(SAMPLES, encoding="utf-8") as f:
            self.lines = f.read().splitlines()

    def test_plain_request(self):
        self.assertEqual(parse_line(self.lines[0]),
                         {"method": "GET", "path": "/orders/42", "user": "alice", "status": 200, "ms": 34.0})

    def test_quoted_user_and_seconds(self):
        self.assertEqual(parse_line(self.lines[1]),
                         {"method": "POST", "path": "/orders", "user": "Bob Smith", "status": 503, "ms": 1200.0})

    def test_other_component_is_not_a_request(self):
        self.assertIsNone(parse_line(self.lines[2]))

    def test_anonymous_user(self):
        self.assertEqual(parse_line(self.lines[3])["user"], None)

    def test_patch_with_extra_field(self):
        self.assertEqual(parse_line(self.lines[4]),
                         {"method": "PATCH", "path": "/users/7", "user": "carol", "status": 204, "ms": 15.5})

    def test_not_a_request(self):
        self.assertIsNone(parse_line(self.lines[5]))
