#!/usr/bin/env python3
"""Re-run a case's check on the kept project folders of earlier runs (after a check was fixed), updating the
results files in place. Usage: rescore.py CASE_ID RESULTS.jsonl [...]"""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import skilleval as se
case, files = sys.argv[1], sys.argv[2:]
for f in files:
    rows = [json.loads(l) for l in open(f)]
    for r in rows:
        if r.get("case") != case or r.get("kind") != "task":
            continue
        cdir = se.CASES / r["skill"]
        task = next(t for t in json.loads((cdir / "cases.json").read_text())["tasks"] if t["id"] == case)
        if not Path(r["project"]).exists():
            print("missing", r["project"]); continue
        rc, out = se.sh(task["check"], r["project"], timeout=300, env={"CASE_DIR": str(cdir)})
        old = r["pass"]; r["pass"] = rc == 0; r["check_output"] = out[-600:]; r["rescored"] = True
        print(f"{r['arm']:9s} {old} -> {r['pass']}")
    with open(f, "w") as fh:
        fh.writelines(json.dumps(r) + "\n" for r in rows)
