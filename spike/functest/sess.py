#!/usr/bin/env python3
"""sess.py PROJECTPREFIX|PATH [--wait SECS] [--after EPOCH] : summarize newest session (optionally wait for it to finish)"""
import json, os, sys, time, glob
D = os.path.expanduser("~/Library/Application Support/kurtkode/sessions")
arg = sys.argv[1]
wait = float(sys.argv[sys.argv.index("--wait")+1]) if "--wait" in sys.argv else 0
after = float(sys.argv[sys.argv.index("--after")+1]) if "--after" in sys.argv else 0
quiet = "--quiet" in sys.argv
def newest():
    if arg.endswith(".jsonl"): return arg
    fs = [f for d in glob.glob(os.path.join(D, arg + "*")) for f in glob.glob(os.path.join(d, "*.jsonl"))]
    fs = [f for f in fs if os.path.getmtime(f) >= after]
    return max(fs, key=os.path.getmtime) if fs else None
def load(f):
    recs = []
    for line in open(f):
        try: recs.append(json.loads(line))
        except Exception: pass
    return recs
def done(recs):
    msgs = [r["message"] for r in recs if r.get("type") == "message"]
    if not msgs: return False
    m = msgs[-1]
    return m["role"] == "assistant" and not m.get("toolCalls") and (m.get("meta") or {}).get("stopReason") is not None
t0 = time.time()
while True:
    f = newest()
    if f and (not wait or done(load(f))): break
    if time.time() - t0 > wait: print("TIMEOUT waiting", f); break
    time.sleep(3)
if not f: sys.exit("no session")
recs = load(f)
print("FILE", f)
for r in recs:
    t = r.get("type")
    if t == "message":
        m = r["message"]; meta = m.get("meta") or {}
        tc = ",".join(c["name"] + c["arguments"][:80] for c in m.get("toolCalls", []))
        extra = ""
        if meta: extra = f' [{meta.get("requestedModel")} pt={meta.get("usage",{}).get("promptTokens")} ct={meta.get("usage",{}).get("completionTokens")} stop={meta.get("stopReason")} notes={meta.get("notes")}]'
        tr = m.get("toolResult")
        if tr: extra = f' [{tr.get("toolName")} err={tr.get("isError")} notes={tr.get("notes")}]'
        c = m.get("content", "")
        if quiet: c = c[:150]
        print(f'{m["role"]:9} {c[:400]!r}{(" CALLS " + tc) if tc else ""}{extra}')
    else:
        s = json.dumps(r)
        print("REC", s[:300])
