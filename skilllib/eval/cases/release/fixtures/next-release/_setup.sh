# Builds the history: the files here are the current state; the edits below are undone to get the 1.3.0
# release (tagged v1.3.0), then replayed one commit at a time.
python3 - <<'PY'
import os, subprocess
ARGS_OLD = '    p.add_argument("files", nargs="+")\n    p.add_argument("--version"'
ARGS_NEW = ('    p.add_argument("files", nargs="+")\n'
            '    p.add_argument("--json", action="store_true", help="print one JSON object per file")\n'
            '    p.add_argument("--version"')
PRINT_OLD = '        print(f"{lines:8} {words:8} {chars:8} {avg:6} {path}")\n'
PRINT_NEW = ('        if args.json:\n            print(json.dumps({"file": path, "lines": lines, "words": words, '
             '"chars": chars, "per_line": avg}))\n        else:\n    ' + PRINT_OLD)
PARSER = ('    p = argparse.ArgumentParser(prog="tally", description="Count lines, words and characters.")\n'
          + ARGS_NEW + ', action="version", version=f"tally {__version__}")\n')
CORE_BASE = ('    """Return (lines, words, chars) for a text file."""\n    with open(path, newline="") as f:\n'
             '        text = f.read()\n    lines = text.count("\\n") + text.count("\\r")\n'
             '    return lines, len(text.split()), len(text)\n')
CORE_CRLF = CORE_BASE.replace('open(path, newline="") as f:', 'open(path) as f:  # universal newlines: "\\r\\n" is one line break').replace(' + text.count("\\r")', '')
CORE_FINAL = open("tally/core.py").read().split("def count(path):\n")[1]
TESTS_NEW = open("tests/test_core.py").read().split("\n    def test_empty_file")[1]
COMMITS = [
    ("feat: add --json output", [
        ("tally/cli.py", '"""Command line: tally FILE..."""', '"""Command line: tally FILE... [--json]"""'),
        ("tally/cli.py", "import argparse, sys", "import argparse, json, sys"),
        ("tally/cli.py", ARGS_OLD, ARGS_NEW), ("tally/cli.py", PRINT_OLD, PRINT_NEW),
        ("docs/install.md", "Then run `tally FILE...`.", "Then run `tally FILE...`, or `tally --json FILE...` for machine-readable output.")]),
    ("chore: bump dev dependencies", [("requirements-dev.txt", "black==24.3.0\nflake8==7.0.0\n", "black==24.8.0\nflake8==7.1.1\n")]),
    ("fix: don't crash on empty files", [("tally/cli.py", "avg = round(words / lines, 1)\n", "avg = round(words / lines, 1) if lines else 0\n")]),
    ("ci: cache pip downloads", [(".github/workflows/ci.yml", '"3.12"\n', '"3.12"\n          cache: pip\n')]),
    ("fix: count Windows (CRLF) line endings once", [("tally/core.py", CORE_BASE, CORE_CRLF)]),
    ("docs: fix typo in README", [("README.md", "words and charaters in", "words and characters in")]),
    ("Read files line by line so huge files don't have to fit in memory", [("tally/core.py", CORE_CRLF, CORE_FINAL)]),
    ("refactor: move argument parsing into build_parser()", [("tally/cli.py",
        "def main(argv=None):\n" + PARSER + "    args = p.parse_args(argv)\n",
        "def build_parser():\n" + PARSER + "    return p\n\n\ndef main(argv=None):\n    args = build_parser().parse_args(argv)\n")]),
    ("test: cover empty files and CRLF line endings",
     [("tests/test_core.py", "(2, 3, 14))\n", "(2, 3, 14))\n\n    def test_empty_file" + TESTS_NEW)]),
]


def edit(path, old, new):
    s = open(path).read()
    assert s.count(old) == 1, (path, old[:60])
    open(path, "w").write(s.replace(old, new))


def git(*args, day=None):
    env = dict(os.environ)
    if day is not None:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"2026-{6 + day // 28:02d}-{1 + day % 28:02d}T10:00:00"
    subprocess.run(["git", *args], check=True, env=env)


for _, edits in reversed(COMMITS):
    for path, old, new in reversed(edits):
        edit(path, new, old)
git("init", "-q", "-b", "main")
git("add", "-A")
git("commit", "-qm", "chore(release): 1.3.0", day=1)
git("tag", "-a", "v1.3.0", "-m", "tally 1.3.0", day=1)
for i, (msg, edits) in enumerate(COMMITS):
    for path, old, new in edits:
        edit(path, old, new)
    git("add", "-A")
    git("commit", "-qm", msg, day=5 + 4 * i)
PY
