import unittest

from fetcher import config
from fetcher.client import fetch, parse_status


class ClientTest(unittest.TestCase):
    def test_parse_status(self):
        self.assertEqual(parse_status("HTTP/1.1 404 Not Found"), 404)

    def test_retries_until_success(self):
        replies = [ConnectionError("down"), "HTTP/1.1 200 OK"]

        def get(url):
            r = replies.pop(0)
            if isinstance(r, Exception):
                raise r
            return r

        self.assertEqual(fetch(get, "http://x", config.load({}), sleep=lambda s: None), 200)

    def test_load_defaults(self):
        self.assertEqual(config.load({})["max_attempts"], 3)
