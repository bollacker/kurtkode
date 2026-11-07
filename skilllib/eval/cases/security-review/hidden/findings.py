"""Shared parser: the bullets under a '## Findings' heading of a markdown report, as (basename, line, text)."""
import os, re


def findings(path):
    if not os.path.exists(path):
        return None
    out, inside, cur = [], False, None
    for ln in open(path, encoding="utf-8", errors="replace").read().splitlines():
        if re.match(r"^\s*#+\s", ln):
            inside = bool(re.match(r"^\s*#+\s*findings\b", ln, re.I))
            cur = None
            continue
        if not inside:
            continue
        if re.match(r"^\s{0,3}[-*]\s+", ln):
            cur = [ln]
            out.append(cur)
        elif cur is not None and ln.strip():
            cur.append(ln)
        else:
            cur = None
    result = []
    for b in out:
        t = " ".join(s.strip() for s in b)
        m = re.search(r"([\w./-]+\.\w+):(\d+)", t)
        result.append((os.path.basename(m.group(1)) if m else None, int(m.group(2)) if m else None, t))
    return result
