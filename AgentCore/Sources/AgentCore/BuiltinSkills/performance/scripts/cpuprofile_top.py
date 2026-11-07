#!/usr/bin/env python3
"""Summarize a V8 .cpuprofile (from `node --cpu-prof`, or Chrome DevTools) as the functions with the most time.

Usage: cpuprofile_top.py [--top N] [--total] FILE.cpuprofile

Prints one line per function, most expensive first: "<ms> ms  <self%>%  <function> <file>:<line>".
Self time by default (time in the function's own code); --total adds time spent in everything it calls.
Exit codes: 0 = printed, 2 = usage error or unreadable profile.
"""
import argparse, collections, json, sys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--total", action="store_true", help="inclusive time (function plus its callees)")
    a = ap.parse_args()
    try:
        p = json.load(open(a.file))
        nodes = {n["id"]: n for n in p["nodes"]}
    except (OSError, ValueError, KeyError) as e:
        print(f"error: not a readable .cpuprofile: {e}", file=sys.stderr)
        return 2
    self_us = collections.Counter()
    for node_id, dt in zip(p["samples"], p.get("timeDeltas", [])):
        self_us[node_id] += max(dt, 0)
    parent = {c: n["id"] for n in p["nodes"] for c in n.get("children", [])}

    def key(n):
        f = n["callFrame"]
        return f"{f.get('functionName') or '(anonymous)'} {f.get('url', '').split('/')[-1]}:{f.get('lineNumber', -1) + 1}"

    per_fn = collections.Counter()
    for node_id, us in self_us.items():
        if not a.total:
            per_fn[key(nodes[node_id])] += us
            continue
        seen, cur = set(), node_id
        while cur is not None:  # charge every distinct function on the stack once
            k = key(nodes[cur])
            if k not in seen:
                per_fn[k] += us
                seen.add(k)
            cur = parent.get(cur)
    total = sum(self_us.values()) or 1
    for k, us in per_fn.most_common(a.top):
        print(f"{us / 1000:9.1f} ms  {100 * us / total:5.1f}%  {k}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
