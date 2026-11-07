"""Parse request lines from the service log (format: README.md)."""
import json
import re
import sys

REQUEST = re.compile(r"(GET|POST|PUT|DELETE) (\S+) user=(\S+) status=(\d+) took=(\d+)ms")


def parse_line(line):
    m = REQUEST.search(line)
    if not m:
        return None
    method, path, user, status, ms = m.groups()
    return {"method": method, "path": path, "user": None if user == "-" else user,
            "status": int(status), "ms": float(ms)}


def main(path):
    with open(path, encoding="utf-8", newline="") as f:
        for line in f:
            rec = parse_line(line)
            if rec:
                print(json.dumps(rec))


if __name__ == "__main__":
    main(sys.argv[1])
