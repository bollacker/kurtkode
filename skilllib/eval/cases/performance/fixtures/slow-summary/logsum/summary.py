import json
from collections import Counter

from .parse import parse_line
from .users import UserIndex


def percentile(values, pct):
    ordered = sorted(values)
    k = max(0, -(-len(ordered) * pct // 100) - 1)
    return ordered[k]


def summarize(lines):
    """Per-path report for an access log: requests, errors, p95 latency, busiest hour, top users (pseudonymized)."""
    users = UserIndex()
    paths = {}
    skipped = 0
    for line in lines:
        rec = parse_line(line)
        if rec is None:
            skipped += 1
            continue
        p = paths.setdefault(rec["path"], {"requests": 0, "errors": 0, "ms": [], "hours": Counter(), "users": Counter()})
        p["requests"] += 1
        p["errors"] += rec["level"] == "ERROR"
        p["ms"].append(rec["ms"])
        p["hours"][rec["hour"]] += 1
        p["users"][users.pseudonym(rec["user"])] += 1
    report = {"skipped_lines": skipped, "distinct_users": len(users), "paths": {}}
    for path, p in sorted(paths.items()):
        top = sorted(p["users"].items(), key=lambda kv: (-kv[1], int(kv[0][1:])))[:3]
        report["paths"][path] = {
            "requests": p["requests"],
            "errors": p["errors"],
            "p95_ms": percentile(p["ms"], 95),
            "busiest_hour": min(p["hours"], key=lambda h: (-p["hours"][h], h)),
            "top_users": [u for u, _ in top],
        }
    return json.dumps(report, indent=2)
