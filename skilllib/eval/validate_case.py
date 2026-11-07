#!/usr/bin/env python3
"""Check a skill's task cases without a model: each check must FAIL on the untouched fixture ("idle") and PASS once
the reference solution is applied. A reference is eval/cases/<skill>/reference/<case id>.sh, a script run in the
project folder (it may write files, apply a patch from $CASE_DIR, run git). Usage: validate_case.py SKILL [SKILL...]
or --all. Exit 0 when every case behaves."""
import json, os, shutil, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import skilleval as se

def validate(skill):
    cdir = se.CASES / skill
    cases = json.loads((cdir / "cases.json").read_text())
    ok = True
    work = Path(tempfile.mkdtemp(prefix="kkvalidate-"))
    t = cases.get("triggers", {})
    if len(t.get("should", [])) < 5 or len(t.get("should_not", [])) < 3:
        print(f"  {skill}: needs ≥5 should and ≥3 should_not triggers"); ok = False
    for task in cases.get("tasks", []):
        env = {"CASE_DIR": str(cdir)}
        for state in ("idle", "reference"):
            proj = se.make_project((cdir / task["fixture"]).resolve(), work, f"val-{task['id']}", None)
            if state == "reference":
                ref = cdir / "reference" / f"{task['id']}.sh"
                if not ref.exists():
                    print(f"  {skill}/{task['id']}: no reference/{task['id']}.sh"); ok = False; break
                rc, out = se.sh(f"bash {ref}", proj, timeout=300, env=env)
                if rc != 0:
                    print(f"  {skill}/{task['id']}: reference script failed: {out[-400:]}"); ok = False; continue
            rc, out = se.sh(task["check"], proj, timeout=300, env=env)
            want = 0 if state == "reference" else 1
            good = (rc == 0) == (want == 0)
            print(f"  {skill}/{task['id']} {state}: check exit {rc} {'ok' if good else 'WRONG'}"
                  + ("" if good else f"\n    {out[-600:]}"))
            ok &= good
    shutil.rmtree(work, ignore_errors=True)
    return ok

if __name__ == "__main__":
    names = sorted(p.name for p in se.CASES.iterdir() if (p / "cases.json").exists()) if sys.argv[1:] == ["--all"] else sys.argv[1:]
    results = [validate(n) for n in names]
    sys.exit(0 if all(results) else 1)
