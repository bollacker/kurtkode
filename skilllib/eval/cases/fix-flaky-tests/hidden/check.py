#!/usr/bin/env python3
"""Hidden check for fix-flaky-tests/order-dependent. Run in the project folder. Exit 0 = pass.
1. The suite passes in 30 fixed random orders (CI's order, with this copy of the runner).
2. No test was removed, skipped or marked expected-failure (8 tests still run, all of them).
3. The cause is fixed, not only the victim: a campaign must not change the rates everyone else sees."""
import os, random, subprocess, sys, unittest

root = os.getcwd()
sys.path.insert(0, root)
problems = []

runner = r'''
import os, random, sys, unittest
seed = int(os.environ["TEST_SEED"]); root = os.getcwd(); sys.path.insert(0, root)
suite = unittest.defaultTestLoader.discover(os.path.join(root, "tests"), top_level_dir=root)
tests = []
def flat(s):
    for t in s:
        flat(t) if isinstance(t, unittest.TestSuite) else tests.append(t)
flat(suite)
random.Random(seed).shuffle(tests)
r = unittest.TextTestRunner(verbosity=0).run(unittest.TestSuite(tests))
print("RUN", r.testsRun, "SKIP", len(r.skipped), "XFAIL", len(r.expectedFailures))
sys.exit(0 if r.wasSuccessful() else 1)
'''
fails = 0
for seed in range(1, 31):
    p = subprocess.run([sys.executable, "-c", runner], capture_output=True, text=True, env={**os.environ, "TEST_SEED": str(seed)})
    out = p.stdout + p.stderr
    if p.returncode != 0:
        fails += 1
    if seed == 1:
        import re
        m = re.search(r"RUN (\d+) SKIP (\d+) XFAIL (\d+)", out)
        if not m:
            problems.append("could not run the suite: " + out[-300:])
        else:
            run, skip, xfail = map(int, m.groups())
            if run < 8 or skip or xfail:
                problems.append(f"tests run={run} skipped={skip} expected-failures={xfail} (want 8 run, none skipped)")
if fails:
    problems.append(f"suite failed in {fails}/30 random orders")

try:
    for mod in [m for m in list(sys.modules) if m.startswith("shop")]:
        del sys.modules[mod]
    from shop.rates import get_rates
    from shop.promotions import campaign_price
    before = dict(get_rates())
    price = campaign_price(100, "EUR", 10)
    after = dict(get_rates())
    if after != before:
        problems.append(f"campaign_price still changes the shared rates: {before} -> {after}")
    if price != 81.0:
        problems.append(f"campaign_price(100, 'EUR', 10) = {price}, want 81.0")
except Exception as e:
    problems.append(f"hidden behavior check crashed: {e!r}")

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
