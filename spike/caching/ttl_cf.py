"""Counterfactual for Claude Code main-thread requests: actual (1h TTL) vs 5-minute TTL, priced at list."""
import json, glob, os, datetime, collections
P = {"claude-fable-5-1": (10, 50, 0.25), "claude-fable-5": (10, 50, 1.0), "claude-opus-5-5": (4, 20, 0.20),
     "claude-opus-5": (5, 25, 0.5), "claude-opus-4-8": (5, 25, 0.5), "claude-sonnet-5-5": (2, 10, 0.2),
     "claude-sonnet-5": (2, 10, 0.2), "claude-haiku-5-5": (0.1, 0.5, 0.01), "claude-haiku-4-5-20251001": (1, 5, 0.1)}
files = [f for f in glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True) if "/subagents/" not in f]
cost = collections.Counter(); seen = set(); n_cold = 0
for f in files:
    last = None
    for line in open(f, errors="replace"):
        if '"usage"' not in line: continue
        try: d = json.loads(line)
        except Exception: continue
        m = d.get("message") or {}; u = m.get("usage")
        if d.get("type") != "assistant" or not isinstance(u, dict) or m.get("id") in seen: continue
        seen.add(m.get("id")); p = P.get(m.get("model"))
        t = datetime.datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
        if not p: last = t; continue
        i, o, r = p
        read, write, inp = u.get("cache_read_input_tokens", 0), u.get("cache_creation_input_tokens", 0), u.get("input_tokens", 0)
        cost["actual_1h"] += (inp * i + read * r + write * 2 * i) / 1e6
        gap = (t - last).total_seconds() if last else 0
        if read and 300 <= gap < 3600:  # with a 5-minute cache this prefix would have expired
            n_cold += 1; cost["5m"] += (inp * i + (read + write) * 1.25 * i) / 1e6
            # keepalive: pings every 270 s during the gap, each reading the prefix
            pings = int(gap // 270); cost["5m+keepalive"] += (inp * i + read * r + write * 1.25 * i + pings * read * r) / 1e6
        else:
            cost["5m"] += (inp * i + read * r + write * 1.25 * i) / 1e6
            wasted = 13 * (read + write) * r if gap >= 3600 else 0   # an hour of pings that the user never came back for
            cost["5m+keepalive"] += (inp * i + read * r + write * 1.25 * i + wasted) / 1e6
        last = t
print({k: round(v) for k, v in cost.items()}, "requests that would go cold:", n_cold)
