import json, os, sys, hashlib
root = "/Users/me/git/kurtkode/eval-results/runs"
out = sys.argv[1]
stores = ["cf2", "cf3a", "cf3b", "cf6"]
prompts = {}
with open(os.path.join(out, "rows.jsonl"), "w") as fo:
    for store in stores:
        sd = os.path.join(root, store)
        n = 0
        for rid in sorted(os.listdir(sd)):
            p = os.path.join(sd, rid, "run.json")
            if not os.path.exists(p): continue
            with open(p) as f: d = json.load(f)
            if d.get("degradation") or d.get("infra"):
                del d; continue
            rr = d.get("runRecord") or {}
            tot = rr.get("totals") or {}
            card = d.get("card") or {}
            ch = d.get("checks") or {}
            pr = d.get("prompt") or ""
            h = hashlib.sha1(pr.encode()).hexdigest()[:10]
            key = store + "|" + d.get("task")
            prompts.setdefault(key, {})
            if h not in prompts[key]: prompts[key][h] = pr
            fo.write(json.dumps(dict(store=store, task=d.get("task"), model=d.get("model"), trial=d.get("trial"),
                passed=bool((d.get("gold") or {}).get("passed")), listPrice=d.get("listPrice"), charged=tot.get("charged"),
                pt=d.get("promptTokens"), ct=d.get("completionTokens"), steps=d.get("steps"), seconds=d.get("seconds"),
                kind=card.get("kind") or d.get("kind"), importance=card.get("importance"), agent=d.get("agent"),
                nfiles=len(ch.get("filesChanged") or []), ph=h)) + "\n")
            n += 1
            del d
        print(store, n, flush=True)
json.dump(prompts, open(os.path.join(out, "prompts.json"), "w"))
print("prompt keys", len(prompts), "multi-variant", sum(1 for v in prompts.values() if len(v) > 1))
