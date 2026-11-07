import pickle, collections, sys
rows = pickle.load(open(sys.argv[1], "rb"))
by = collections.defaultdict(list)
for r in rows: by[r["store"]].append(r)
print("| store | runs | real (no degradation/infra) | degraded | infra | models | tasks | judged runs | judgments |")
print("|---|---|---|---|---|---|---|---|---|")
for s, rs in sorted(by.items()):
    real = [r for r in rs if not r["degradation"] and not r["infra"]]
    print(f"| {s} | {len(rs)} | {len(real)} | {sum(1 for r in rs if r['degradation'])} | {sum(1 for r in rs if r['infra'])} | {len({r['model'] for r in rs})} | {len({r['task'] for r in rs})} | {sum(1 for r in rs if r['judgments'])} | {sum(len(r['judgments']) for r in rs)} |")
print(f"\nTotal runs: {len(rows)}\n")
for s, rs in sorted(by.items()):
    c = collections.Counter(r["model"] for r in rs)
    print(f"### {s}: {len(c)} models\n")
    print("| model | runs | real | gold pass (real) |"); print("|---|---|---|---|")
    for m, n in sorted(c.items(), key=lambda x: (-x[1], x[0])):
        real = [r for r in rs if r["model"] == m and not r["degradation"] and not r["infra"]]
        p = sum(1 for r in real if r["passed"])
        print(f"| {m} | {n} | {len(real)} | {p}/{len(real)} |")
    print()
