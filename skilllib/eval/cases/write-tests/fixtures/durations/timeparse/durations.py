"""Parse and format durations such as "1h30m" or "2d 4h".

parse_duration(text) -> int seconds
  - text is one or more <number><unit> parts; units are d, h, m, s (days, hours, minutes, seconds)
  - parts may be separated by spaces; leading and trailing spaces are ignored
  - units must come in decreasing order (d, h, m, s) and each at most once
  - numbers are non-negative integers; "0s" is valid
  - the total must not exceed MAX_SECONDS (30 days); exactly 30 days is allowed
  - anything else raises ValueError: empty or blank text, unknown unit, missing number,
    repeated or out-of-order unit, too long

format_duration(seconds) -> str
  - the inverse: largest units first, zero parts left out: 5400 -> "1h30m", 90061 -> "1d1h1m1s"
  - 0 -> "0s"
  - negative values and values above MAX_SECONDS raise ValueError
"""
import re

MAX_SECONDS = 30 * 86400
UNITS = {"d": 86400, "h": 3600, "m": 60, "s": 1}
ORDER = "dhms"
_PART = re.compile(r"(\d+)([a-z])")


def parse_duration(text):
    s = text.strip()
    if not s:
        raise ValueError("empty duration")
    total = 0
    last = -1
    pos = 0
    while pos < len(s):
        if s[pos] == " ":
            pos += 1
            continue
        m = _PART.match(s, pos)
        if not m:
            raise ValueError(f"bad duration at position {pos}: {text!r}")
        number, unit = m.groups()
        if unit not in UNITS:
            raise ValueError(f"unknown unit {unit!r} in {text!r}")
        rank = ORDER.index(unit)
        if rank <= last:
            raise ValueError(f"unit {unit!r} repeated or out of order in {text!r}")
        last = rank
        total += int(number) * UNITS[unit]
        pos = m.end()
    if total > MAX_SECONDS:
        raise ValueError(f"duration too long: {text!r}")
    return total


def format_duration(seconds):
    if seconds < 0 or seconds > MAX_SECONDS:
        raise ValueError(f"duration out of range: {seconds}")
    if seconds == 0:
        return "0s"
    out = []
    for unit in ORDER:
        n, seconds = divmod(seconds, UNITS[unit])
        if n:
            out.append(f"{n}{unit}")
    return "".join(out)
