import json, os, sys, collections, pickle
root = "/Users/me/git/kurtkode/eval-results/runs"
out = sys.argv[1]
rows = []
keys = collections.defaultdict(collections.Counter)
for store in sorted(os.listdir(root)):
    sd = os.path.join(root, store)
    if not os.path.isdir(sd): continue
    for rid in os.listdir(sd):
        p = os.path.join(sd, rid, "run.json")
        if not os.path.exists(p): continue
        d = json.load(open(p))
        keys[store].update(d.keys())
        rr = d.get("runRecord") or {}
        tot = rr.get("totals") or {}
        jp = os.path.join(sd, rid, "judgments.jsonl")
        js = []
        if os.path.exists(jp):
            js = [json.loads(l) for l in open(jp) if l.strip()]
        rows.append(dict(store=store, id=d.get("id"), model=d.get("model"), task=d.get("task"), kind=d.get("kind"), trial=d.get("trial"),
            passed=(d.get("gold") or {}).get("passed"), listPrice=d.get("listPrice"), charged=tot.get("charged"),
            prompt=d.get("promptTokens"), completion=d.get("completionTokens"), cacheRead=tot.get("cacheReadTokens"),
            steps=d.get("steps"), stop=d.get("stop"), degradation=d.get("degradation"), infra=d.get("infra"),
            agent=d.get("agent"), checks=d.get("checks"), judgments=js, signals=d.get("signals"),
            setup_model=(rr.get("setup") or {}).get("model"), host=(rr.get("setup") or {}).get("host")))
pickle.dump(rows, open(out, "wb"))
for s, c in keys.items():
    print(s, dict(c))
