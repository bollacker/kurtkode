#!/usr/bin/env python3
"""Hidden check for refactor-safely/tangled-invoice. Run in the project folder. Exit 0 = pass.
1. Behavior: shop.billing.compute_invoice gives the same result as the original (hidden/billing_orig.py) on targeted
   cases and 4000 seeded random orders (floats equal within 1e-9; exceptions compared by type), and doesn't
   mutate its input differently.
2. Structure: compute_invoice is at most 25 lines, no function under shop/ is longer than 30 lines, and at least 3
   new functions exist under shop/ (the refactor happened)."""
import ast, copy, glob, importlib.util, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
root = os.getcwd()
problems = []


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def outcome(fn, order):
    o = copy.deepcopy(order)
    try:
        return ("ok", fn(o), o)
    except Exception as e:
        return ("error", type(e).__name__, o)


def same(a, b):
    if isinstance(a, float) or isinstance(b, float):
        return isinstance(a, (int, float)) and isinstance(b, (int, float)) and abs(a - b) < 1e-9
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


def orders():
    I = lambda price, qty=1, cat=None, w=None: {k: v for k, v in
                                                 {"price": price, "qty": qty, "category": cat, "weight": w}.items() if v is not None}
    yield {}
    yield {"items": []}
    yield {"items": [I(10, 1, "fragile"), I(5, 1, "general")]}                    # fragile not last
    yield {"items": [I(5, 1, "general"), I(10, 1, "fragile")]}                    # fragile last
    yield {"items": [I(10, 1, "fragile"), I(5, 0, "general")]}                    # last line skipped
    yield {"items": [I(10), I(10, 0), I(10, 0)], "member": True}                  # 3 lines, one real
    yield {"items": [I(1), I(1), I(1), I(1), I(1, 0)]}                             # 5 lines, surcharge
    yield {"items": [I(20, 2)], "coupon": "SAVE10"}
    yield {"items": [I(60)], "coupon": "SAVE10"}
    yield {"items": [I(10)], "coupon": "VIP"}
    yield {"items": [I(3)], "coupon": "FLAT5"}
    yield {"items": [I(150)], "member": True}
    yield {"items": [I(150)], "member": True, "coupon": "BOGUS"}
    yield {"items": [I(10, 1, "food")], "member": True, "region": "NY"}
    yield {"items": [I(10, 3, "clearance", 6)], "region": "TX"}
    yield {"items": [I(10)], "region": "WA"}
    yield {"items": [{"qty": 1}]}
    yield {"items": [{"qty": 0}]}
    rnd = random.Random(7)
    for _ in range(4000):
        items = []
        for _ in range(rnd.randint(0, 7)):
            it = {"price": round(rnd.uniform(0.5, 60), 2)}
            if rnd.random() < 0.8:
                it["qty"] = rnd.choice([-1, 0, 1, 1, 1, 2, 3, 5])
            if rnd.random() < 0.8:
                it["category"] = rnd.choice(["general", "clearance", "food", "fragile", "fragile"])
            if rnd.random() < 0.7:
                it["weight"] = round(rnd.uniform(0, 6), 1)
            items.append(it)
        o = {"items": items}
        for key, choices in [("region", ["CA", "NY", "OR", "TX", "WA"]), ("coupon", [None, "SAVE10", "VIP", "FLAT5", "BOGUS"]),
                             ("member", [True, False])]:
            if rnd.random() < 0.8:
                o[key] = rnd.choice(choices)
        yield o


orig = load(os.path.join(HERE, "billing_orig.py"), "billing_orig")
sys.path.insert(0, root)
try:
    from shop.billing import compute_invoice
except Exception as e:
    print(f"FAIL: can't import compute_invoice from shop/billing.py: {e!r}"); sys.exit(1)

diffs = []
for order in orders():
    want, got = outcome(orig.compute_invoice, order), outcome(compute_invoice, order)
    if not same(want, got):
        diffs.append((order, want, got))
if diffs:
    order, want, got = diffs[0]
    problems.append(f"behavior changed on {len(diffs)} orders, e.g. {order}\n    before: {want[:2]}\n    after:  {got[:2]}")

new_funcs, long_funcs, ci_len = 0, [], None
orig_names = {"compute_invoice", "monthly_revenue"}
for path in glob.glob(os.path.join(root, "shop", "**", "*.py"), recursive=True):
    tree = ast.parse(open(path, encoding="utf-8").read())
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            n = node.end_lineno - node.lineno + 1
            if node.name not in orig_names:
                new_funcs += 1
            if n > 30:
                long_funcs.append(f"{os.path.relpath(path, root)}:{node.name} ({n} lines)")
            if node.name == "compute_invoice" and path.endswith(os.path.join("shop", "billing.py")):
                ci_len = n
if ci_len is None:
    problems.append("compute_invoice is no longer defined in shop/billing.py")
elif ci_len > 25:
    problems.append(f"compute_invoice is still {ci_len} lines (want at most 25)")
if long_funcs:
    problems.append("functions longer than 30 lines: " + ", ".join(long_funcs))
if new_funcs < 3:
    problems.append(f"only {new_funcs} new functions under shop/ (want at least 3)")

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
