"""Hidden behavior tests for respond-to-review/retry-review (run from the project folder)."""
import unittest

from fetcher import config
from fetcher.client import fetch, parse_status


def scripted(*replies):
    calls = []
    replies = list(replies)

    def get(url):
        calls.append(url)
        r = replies.pop(0) if len(replies) > 1 else replies[0]
        if isinstance(r, Exception):
            raise r
        return r
    return get, calls


class Sleeps(list):
    def __call__(self, s):
        self.append(s)


class Comment1ParseStatus(unittest.TestCase):
    def test_good_line(self):
        self.assertEqual(parse_status("HTTP/1.1 200 OK"), 200)

    def test_bad_lines_return_none(self):
        for line in ["", "HTTP/1.1", "HTTP/1.1 abc", "   "]:
            self.assertIsNone(parse_status(line), line)


class Comment2KeepZeroAttempts(unittest.TestCase):
    def test_config_still_accepts_zero(self):
        self.assertEqual(config.load({"max_attempts": 0})["max_attempts"], 0)

    def test_zero_means_one_attempt(self):
        get, calls = scripted("HTTP/1.1 204 No Content")
        self.assertEqual(fetch(get, "u", config.load({"max_attempts": 0}), sleep=Sleeps()), 204)
        self.assertEqual(len(calls), 1)

    def test_zero_failing_tries_once(self):
        get, calls = scripted(ConnectionError("down"))
        with self.assertRaises(ConnectionError):
            fetch(get, "u", config.load({"max_attempts": 0}), sleep=Sleeps())
        self.assertEqual(len(calls), 1)


class Comment3OnlyRetryNetworkErrors(unittest.TestCase):
    def test_value_error_not_retried(self):
        get, calls = scripted(ValueError("bad url"))
        with self.assertRaises(ValueError):
            fetch(get, "u", config.load({}), sleep=Sleeps())
        self.assertEqual(len(calls), 1)

    def test_timeout_retried(self):
        get, calls = scripted(TimeoutError(), TimeoutError(), "HTTP/1.1 200 OK")
        self.assertEqual(fetch(get, "u", config.load({}), sleep=Sleeps()), 200)
        self.assertEqual(len(calls), 3)


class Comment4NoSleepAfterLast(unittest.TestCase):
    def test_sleeps_between_attempts_only(self):
        get, calls = scripted(ConnectionError("down"))
        sleeps = Sleeps()
        with self.assertRaises(ConnectionError):
            fetch(get, "u", config.load({"max_attempts": 3, "backoff": 0.25}), sleep=sleeps)
        self.assertEqual(len(calls), 3)
        self.assertEqual(sleeps, [0.25, 0.25])

    def test_success_after_retry_sleeps_once(self):
        get, calls = scripted(ConnectionError("down"), "HTTP/1.1 200 OK")
        sleeps = Sleeps()
        self.assertEqual(fetch(get, "u", config.load({"backoff": 0.1}), sleep=sleeps), 200)
        self.assertEqual(sleeps, [0.1])


if __name__ == "__main__":
    unittest.main()
