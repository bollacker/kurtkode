set -e
git init -q -b main
python3 - <<'PY'
import os, subprocess
ROWS = ("rent:1450.00 travel:32.64 rent:352.19 rent:240.65 office:39.01 office:141.70 rent:57.32 travel:275.05 "
        "rent:158.72 rent:362.13 travel:39.73 office:82.13 groceries:383.07 rent:379.21 office:260.96 rent:145.88 "
        "rent:365.81 groceries:190.79 travel:95.53 office:78.19 office:203.16 office:119.44 rent:382.15 office:124.12 "
        "utilities:64.85 office:42.14 office:40.06 office:135.97 travel:349.46 travel:206.87 travel:384.75")
MARCH = "date,category,amount\n" + "".join(
    f"2026-03-{i + 1:02d},{c},{a}\n" for i, (c, a) in enumerate(x.split(":") for x in ROWS.split()))
PARSE = '''"""Read ledger CSV files: date,category,amount (amounts have two decimals)."""
import csv
from decimal import Decimal


def read_entries(path):
    entries = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):%s
            entries.append({"date": row["date"], "category": row["category"], %s})
    return entries
'''
DEC = '"amount": Decimal(row["amount"])'
CENTS = '"cents": int(float(row["amount"]) * 100)'
REJECT = '\n            if not row["category"]:\n                raise ValueError(f"{path}: empty category on {row[\'date\']}")'
REPORT = '''from collections import defaultdict
%s


def totals(entries):
    by_cat = defaultdict(%s)
    for e in entries:
        by_cat[e["category"]] += e[%s]
    return dict(by_cat)


def summary(entries):
    t = totals(entries)
    lines = [f"{cat:<10} {money(v):>10}" for cat, v in sorted(t.items())]
    lines.append(f"Total: {money(sum(t.values()))}")%s
    return "\\n".join(lines)
'''
LOCAL = 'from decimal import Decimal\n\n\ndef money(x):\n    return f"{x:,.2f}"'
COUNT = '\n    lines.append(f"Entries: {len(entries)}")'
MAIN = '''import sys
from .parse import read_entries
from .report import summary


def main(argv):
    if len(argv) != 2 or argv[0] != "summary":
        print("usage: python3 -m ledger summary FILE.csv", file=sys.stderr)
        return 2
    print(summary(read_entries(argv[1])))
    return 0


sys.exit(main(sys.argv[1:]))
'''
FMT = 'def money(x):\n    """Format an amount for reports."""\n    return f"{x%s}"\n'
T = "import unittest\nfrom ledger.%s import %s\n\n\nclass T(unittest.TestCase):\n    def test_it(self):\n        self.assertEqual(%s)\n"
f = {"ledger/__init__.py": "", "ledger/__main__.py": MAIN, "data/march.csv": MARCH,
     "ledger/parse.py": PARSE % ("", DEC), "ledger/report.py": REPORT % (LOCAL, "Decimal", '"amount"', ""),
     "README.md": "# ledger\n\nMonthly expense sumaries from CSV exports.\n"}
n = [0]


def commit(msg, edits=None):
    f.update(edits or {})
    for k, v in f.items():
        os.makedirs(os.path.dirname(k) or ".", exist_ok=True)
        open(k, "w").write(v)
    n[0] += 1
    d = f"2026-0{1 + n[0] // 15}-{1 + n[0] % 15:02d}T10:00:00"
    env = {**os.environ, "GIT_AUTHOR_DATE": d, "GIT_COMMITTER_DATE": d}
    subprocess.run(["git", "add", "-A"], check=True)
    subprocess.run(["git", "commit", "-qm", msg], check=True, env=env)


def add(path, text):
    return {path: f.get(path, "") + text}


commit("ledger 1.0")
subprocess.run(["git", "tag", "v1.0"], check=True)
commit("Add README usage section", add("README.md", "\nUsage: `python3 -m ledger summary data/march.csv`\n"))
commit("Add February sample data", {"data/feb.csv": "date,category,amount\n2026-02-01,rent,1450.00\n"})
commit("Add .gitignore", {".gitignore": "__pycache__/\n*.pyc\n"})
commit("Mention the CSV columns in README", add("README.md", "\nColumns: date,category,amount.\n"))
commit("Add data/README", {"data/README.md": "Sample exports, one file per month.\n"})
commit("Add unit tests for totals", {"tests/test_report.py": "from decimal import Decimal\n" + T % (
    "report", "totals", "totals([{'category': 'a', 'amount': Decimal('1.50')}]), {'a': Decimal('1.50')}")})
commit("Document running the tests", add("README.md", "\nTests: `python3 -m unittest`\n"))
commit("Add Makefile with a test target", {"Makefile": "test:\n\tpython3 -m unittest\n"})
commit("Fix typo in README", {"README.md": f["README.md"].replace("sumaries", "summaries")})
commit("Show the number of entries in the summary",
       {"ledger/report.py": REPORT % (LOCAL, "Decimal", '"amount"', COUNT)})
commit("Add CONTRIBUTING.md", {"CONTRIBUTING.md": "Open a pull request; run `make test` first.\n"})
commit("Note the Python version", add("README.md", "\nNeeds Python 3.8+.\n"))
commit("Add test for empty input", {"tests/test_empty.py": T % ("report", "totals", "totals([]), {}")})
commit("Start moving number formatting into ledger/fmt.py",
       {"ledger/report.py": REPORT % ("from decimal import Decimal\nfrom .fmt import money", "Decimal", '"amount"', COUNT)})
commit("Add April sample data", {"data/april.csv": "date,category,amount\n2026-04-01,rent,1450.00\n"})
commit("Update README for April", add("README.md", "\nData for Feb-April is in data/.\n"))
commit("Tidy Makefile", {"Makefile": "test:\n\tpython3 -m unittest -v\n"})
commit("Add CHANGELOG", {"CHANGELOG.md": "# Changes\n\n## 1.0\n- First release.\n"})
commit("Explain the categories in data/README", add("data/README.md", "Categories are free text.\n"))
commit("Add lint target", add("Makefile", "lint:\n\tpython3 -m pyflakes ledger\n"))
commit("Add missing ledger/fmt.py", {"ledger/fmt.py": FMT % ":,.2f"})
commit("Use one formatter everywhere", add("CONTRIBUTING.md", "Format money with ledger.fmt.money.\n"))
commit("Add LICENSE", {"LICENSE": "MIT License\n"})
commit("Drop thousands separators (spreadsheet imports choke on them)", {"ledger/fmt.py": FMT % ":.2f"})
commit("README: describe the number format", add("README.md", "\nAmounts print without thousands separators.\n"))
commit("Add tests for fmt.money", {"tests/test_fmt.py": "from decimal import Decimal\n" + T % (
    "fmt", "money", "money(Decimal('1234.5')), '1234.50'")})
commit("Reject rows with an empty category", {"ledger/parse.py": PARSE % (REJECT, DEC)})
commit("Store amounts as integer cents", {
    "ledger/parse.py": (PARSE % (REJECT, CENTS)).replace("from decimal import Decimal\n", ""),
    "ledger/report.py": REPORT % ("from .fmt import money", "int", '"cents"', COUNT),
    "ledger/fmt.py": 'def money(cents):\n    """Format an amount in cents for reports."""\n    return f"{cents / 100:.2f}"\n'})
commit("Update tests for cents", {
    "tests/test_report.py": T % ("report", "totals", "totals([{'category': 'a', 'cents': 150}]), {'a': 150}"),
    "tests/test_fmt.py": T % ("fmt", "money", "money(123450), '1234.50'")})
commit("Add May sample data", {"data/may.csv": "date,category,amount\n2026-05-01,rent,1450.00\n"})
commit("README: list the data files", add("README.md", "\nSample files: feb, march, april, may.\n"))
commit("Fix rounding when printing totals", {"ledger/fmt.py": 'def money(cents):\n    """Format an amount in cents '
       'for reports, without float rounding."""\n    return f"{cents // 100}.{cents % 100:02d}"\n'})
commit("CHANGELOG for 1.1", add("CHANGELOG.md", "\n## 1.1\n- Integer cents, no separators.\n"))
commit("Allow comment lines in CSV files", {"ledger/parse.py": f["ledger/parse.py"].replace(
    "csv.DictReader(f)", "csv.DictReader(line for line in f if not line.startswith('#'))")})
commit("Bump version to 1.1.0", {"ledger/__init__.py": '__version__ = "1.1.0"\n'})
commit("Tidy imports in __main__", {"ledger/__main__.py": MAIN.replace("import sys\n", "import sys\n\n", 1)})
commit("Update CONTRIBUTING", add("CONTRIBUTING.md", "Keep commits small.\n"))
commit("Add make check target", add("Makefile", "check: lint test\n"))
commit("README: how to report bugs", add("README.md", "\nReport bugs with the CSV that shows them.\n"))
PY
