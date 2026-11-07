"""CI checks: the unit tests, then every command-line flag in numstat/cli.py must be documented in README.md."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
tests = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "."], cwd=root)
flags = re.findall(r'add_argument\("(--[a-z-]+)"', (root / "numstat" / "cli.py").read_text())
readme = (root / "README.md").read_text()
missing = [f for f in flags if f"`{f}`" not in readme]
for f in missing:
    print(f"docs: README.md does not document {f}")
ok = tests.returncode == 0 and not missing
print("CHECKS PASSED" if ok else "CHECKS FAILED")
sys.exit(0 if ok else 1)
