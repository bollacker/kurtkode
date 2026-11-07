import re
from datetime import datetime

LINE = r"^(?P<ts>\S+) (?P<level>[A-Z]+) user=(?P<user>\S+) path=(?P<path>\S+) ms=(?P<ms>\d+)$"


def parse_line(line):
    """One access-log line as a dict, or None if the line is malformed."""
    m = re.compile(LINE).match(line.rstrip("\n"))
    if not m:
        return None
    rec = m.groupdict()
    rec["ms"] = int(rec["ms"])
    rec["hour"] = datetime.strptime(rec["ts"], "%Y-%m-%dT%H:%M:%S").hour
    return rec
