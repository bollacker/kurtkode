# Review: fetcher retry change (Sam)

1. client.py:7 `parse_status` crashes with IndexError on an empty or truncated status line ("" or "HTTP/1.1"),
   and with ValueError on "HTTP/1.1 abc". It should return None for any line it can't parse.

2. client.py:15 `max(1, ...)` is dead code: config.load() already rejects max_attempts below 1. Please use
   cfg["max_attempts"] directly.

3. client.py:20 `except Exception` retries everything, including a ValueError for a malformed URL that will never
   succeed. Only retry ConnectionError and TimeoutError; let anything else propagate right away.

4. client.py:22 we also sleep after the final failed attempt, so the caller waits `backoff` seconds for nothing
   before getting the error. Don't sleep after the last attempt.
