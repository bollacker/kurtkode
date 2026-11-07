# Shared similarity scores and PR utilities (stdlib only)
import re
STOP = set("""a about above after again against all am an and any are as at be because been before being below between both but by
can could did do does doing down during each few for from further had has have having he her here hers him his how i if in into is it
its itself just me more most my no nor not now of off on once only or other our out over own same she should so some such than that the
their them then there these they this those through to too under until up very was we were what when where which while who whom why will
with would you your yours also let lets now ok okay here's it's i'm i've don't doesn't done""".split())
WORD = re.compile(r"[a-z0-9_]+")
def words(t):
    return {w for w in WORD.findall(t.lower()) if w not in STOP}
NUM = re.compile(r"(?<![\w.])-?\d+(?:\.\d+)?(?![\w])")
PATH = re.compile(r"[\w./-]*[\w-]+\.(?:py|js|ts|md|txt|json|toml|yaml|yml|cfg|ini|sh|diff|csv|html|go|rs|swift|c|h)\b|(?:[\w-]+/)+[\w.-]+")
SNAKE = re.compile(r"\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b")
CAMEL = re.compile(r"\b[a-z]+[A-Z][A-Za-z0-9]*\b|\b[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*\b")
QUOTE = re.compile(r"`([^`\n]{1,80})`|\"([^\"\n]{1,80})\"|'([^'\n]{2,80})'")
def idents(t):
    s = set()
    s.update(NUM.findall(t))
    s.update(p.strip("./") for p in PATH.findall(t))
    s.update(SNAKE.findall(t)); s.update(CAMEL.findall(t))
    for m in QUOTE.findall(t):
        q = next(x for x in m if x).strip()
        if q: s.add(q.lower())
    return s
SENT = re.compile(r"(?<=[.!?])\s+")
def last_sentence(t):
    lines = [l.strip() for l in t.strip().splitlines() if l.strip() and not l.strip().startswith("```")]
    if not lines: return ""
    sents = [s for s in SENT.split(lines[-1]) if s.strip()]
    return sents[-1] if sents else lines[-1]
def jac(a, b):
    if not a and not b: return 1.0
    return len(a & b) / len(a | b)
class Feat:
    __slots__ = ("w", "i", "l", "p", "empty")
    def __init__(self, report):
        r = report or ""
        self.empty = not r.strip()
        self.w = words(r); self.i = idents(r); self.l = words(last_sentence(r))
        self.p = {x.strip("./").lower() for x in PATH.findall(r)}
def scores(fa, fb):
    if fa.empty or fb.empty:
        # an empty report agrees with nothing (a non-empty pair of empties is still a failure signal)
        return dict(words=0.0, idents=0.0, paths=0.0, last=0.0, mean=0.0)
    s = dict(words=jac(fa.w, fb.w), idents=jac(fa.i, fb.i), paths=jac(fa.p, fb.p), last=jac(fa.l, fb.l))
    s["mean"] = (s["words"] + s["idents"] + s["last"]) / 3
    return s
SCORES = ("words", "idents", "paths", "last", "mean")

def pr_curve(items):
    """items: list of (score, is_failure, weight). Fire when score < t. Returns rows per unique threshold and AP."""
    P = sum(w for s, f, w in items if f)
    tot = sum(w for s, f, w in items)
    xs = sorted(set(s for s, f, w in items))
    rows = []
    for k, s in enumerate(xs):
        # threshold just above s: fire on score <= s
        tp = sum(w for x, f, w in items if f and x <= s)
        fp = sum(w for x, f, w in items if not f and x <= s)
        rows.append(dict(t=s, tp=tp, fp=fp, fire=(tp + fp) / tot, recall=tp / P if P else 0, precision=tp / (tp + fp) if tp + fp else 0))
    ap = 0.0; prev_r = 0.0
    for r in rows:
        ap += (r["recall"] - prev_r) * r["precision"]; prev_r = r["recall"]
    return rows, ap, P / tot if tot else 0, P, tot
def best_f1(rows):
    best = None
    for r in rows:
        if r["tp"] == 0: continue
        f1 = 2 * r["precision"] * r["recall"] / (r["precision"] + r["recall"])
        if best is None or f1 > best[0] + 1e-12: best = (f1, r)
    return best
def at_recall(rows, target):
    for r in rows:
        if r["recall"] >= target - 1e-9: return r
    return None
