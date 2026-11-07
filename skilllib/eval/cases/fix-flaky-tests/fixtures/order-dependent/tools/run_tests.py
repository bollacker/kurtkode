#!/usr/bin/env python3
"""CI's test runner: every test, in a random order (TEST_SEED=n repeats an order). Exit 0 if all pass."""
import os, random, sys, unittest

seed = int(os.environ.get("TEST_SEED", random.randrange(1_000_000)))
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, root)
suite = unittest.defaultTestLoader.discover(os.path.join(root, "tests"), top_level_dir=root)
tests = []
def flat(s):
    for t in s:
        flat(t) if isinstance(t, unittest.TestSuite) else tests.append(t)
flat(suite)
random.Random(seed).shuffle(tests)
print(f"TEST_SEED={seed}, {len(tests)} tests")
result = unittest.TextTestRunner(verbosity=1).run(unittest.TestSuite(tests))
sys.exit(0 if result.wasSuccessful() else 1)
