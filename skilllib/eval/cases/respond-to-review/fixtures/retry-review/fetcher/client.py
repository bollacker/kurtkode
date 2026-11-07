"""Fetch a URL with retries."""
import time


def parse_status(line):
    """'HTTP/1.1 200 OK' -> 200."""
    return int(line.split()[1])


def fetch(get, url, cfg, sleep=time.sleep):
    """Call get(url) until it succeeds, up to cfg["max_attempts"] times; return the status code.

    get(url) returns the response's status line.
    """
    attempts = max(1, cfg["max_attempts"])
    error = None
    for _ in range(attempts):
        try:
            return parse_status(get(url))
        except Exception as e:
            error = e
            sleep(cfg["backoff"])
    raise error
