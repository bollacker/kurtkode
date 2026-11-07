"""Correct the deepseek-v4-flash-0731 list prices that cf6 recorded at OpenRouter's 10x listing glitch.

On 2026-10-26 10:43-11:18 UTC OpenRouter listed deepseek/deepseek-v4-flash-0731 at $0.44/$1.32 per M (input/output)
instead of $0.0444/$0.1333 (COST_AUDIT.md F5). Runs recorded then carry list prices 10x too high. A run is affected
when its implied output rate (list output dollars over completion tokens) is near $1.32 per M; every list-price
number in it is then divided by 10. Charges (what OpenRouter actually billed) are untouched.

Usage: python3 -I fix_cf6_deepseek_listing.py STORE [--apply BACKUP_DIR]
Without --apply it only reports. With it, each changed run.json is first copied to BACKUP_DIR/<run>/run.json.
"""
import json, os, shutil, sys

def affected(r):
    t = (r.get('runRecord') or {}).get('totals') or {}
    out = (t.get('listPrice') or {}).get('output') or 0
    toks = t.get('completionTokens') or 0
    return toks > 0 and 1.0 < out / toks * 1e6 < 1.6, (out / toks * 1e6 if toks else None)

def scale(r, f):
    if isinstance(r.get('listPrice'), (int, float)): r['listPrice'] *= f
    lp = r['runRecord']['totals']['listPrice']
    for k, v in lp.items():
        if isinstance(v, (int, float)): lp[k] = v * f
    t = r['runRecord']['totals']
    # spent is the charge where OpenRouter gave one; only a spent made of list prices moves
    if t.get('charged') is None and isinstance(t.get('spent'), (int, float)): t['spent'] *= f

store = sys.argv[1]
backup = sys.argv[sys.argv.index('--apply') + 1] if '--apply' in sys.argv else None
n = changed = 0
for d in sorted(os.listdir(store)):
    if 'deepseek-v4-flash-0731' not in d: continue
    p = os.path.join(store, d, 'run.json')
    if not os.path.exists(p): continue
    n += 1
    r = json.load(open(p))
    hit, rate = affected(r)
    if not hit: continue
    changed += 1
    if backup:
        os.makedirs(os.path.join(backup, d), exist_ok=True)
        shutil.copy2(p, os.path.join(backup, d, 'run.json'))
        scale(r, 0.1)
        with open(p, 'w') as f: json.dump(r, f, indent=2, sort_keys=True, separators=(',', ' : '), ensure_ascii=False)
print(f"{n} deepseek runs, {changed} at the 10x listing" + (" (corrected)" if backup else " (dry run)"))
