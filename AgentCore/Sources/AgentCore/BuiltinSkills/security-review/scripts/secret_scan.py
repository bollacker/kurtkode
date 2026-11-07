#!/usr/bin/env python3
"""Find likely secrets (API keys, tokens, private keys, passwords) without ever printing their values.

Usage: secret_scan.py [--history] [--all-files] [PATH ...]

  PATH          files or directories to scan (default: the files git tracks plus untracked, non-ignored files;
                outside a git repo, everything under the current directory)
  --history     scan every line ever added in any commit on any branch (git log -p --all) instead
  --all-files   with no PATH in a git repo, also scan ignored files (e.g. .env)

Prints one line per hit:
  tree:     path:line kind=<kind> name=<variable or -> len=<n> fp=<8 hex>
  history:  <commit7> path:line kind=<kind> name=<variable or -> len=<n> fp=<8 hex> in_tree=yes|no
fp is the first 8 hex digits of the value's SHA-256, so the same secret can be matched across files and commits;
in_tree says whether that value is still in the current files. Values that look like placeholders (changeme,
example, dummy, test, xxx, <...>, ${...}, env lookups) are skipped. A summary line follows: "RESULT hits=N".

Exit codes: 0 = nothing found, 1 = possible secrets found, 2 = usage error (e.g. --history outside a git repo).
"""
import argparse, hashlib, math, os, re, subprocess, sys

PATTERNS = [
    ("private-key", re.compile(r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----")),
    ("aws-access-key", re.compile(r"\b((?:AKIA|ASIA)[0-9A-Z]{16})\b")),
    ("github-token", re.compile(r"\b((?:gh[pousr]_[A-Za-z0-9]{36,})|github_pat_[A-Za-z0-9_]{50,})\b")),
    ("slack-token", re.compile(r"\b(xox[abprs]-[A-Za-z0-9-]{10,})")),
    ("stripe-key", re.compile(r"\b([rs]k_live_[A-Za-z0-9]{16,})\b")),
    ("google-api-key", re.compile(r"\b(AIza[0-9A-Za-z_\-]{35})\b")),
    ("jwt", re.compile(r"\b(eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})")),
    ("url-password", re.compile(r"[a-zA-Z][a-zA-Z0-9+.-]*://[^/\s:@'\"]+:([^/\s@'\"]{4,})@")),
]
ASSIGN = re.compile(
    r"(?i)\b([A-Za-z0-9_.-]*(?:secret|token|passw(?:or)?d|pwd|api[_-]?key|access[_-]?key|private[_-]?key|"
    r"credential|auth[_-]?key)[A-Za-z0-9_]*)[\"']?\s*(?::=|=>|[:=])\s*[\"']?([^\s\"'`,;#)]{8,})")
PLACEHOLDER = re.compile(
    r"(?i)change.?me|example|placeholder|dummy|fake|sample|test|xxx|your|redacted|todo|none|null|true|false|"
    r"^<.*>$|\$\{|\$\(|\{\{|%\(|environ|getenv|process\.env|ENV\[|settings\.|config\.|\*{3}")
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".tox", "dist", "build", ".agents"}


def entropy(s):
    return -sum(s.count(c) / len(s) * math.log2(s.count(c) / len(s)) for c in set(s))


def hits_in_line(line):
    found = []
    for kind, rx in PATTERNS:
        for m in rx.finditer(line):
            found.append((kind, "-", m.group(m.lastindex or 0)))
    if not found:
        for m in ASSIGN.finditer(line):
            name, value = m.group(1), m.group(2)
            if PLACEHOLDER.search(value) or "(" in value or "[" in value or value.startswith("http"):
                continue
            if re.fullmatch(r"[A-Za-z_][A-Za-z_.]*", value):  # a variable or attribute name, not a value
                continue
            low = 2.5 if re.search(r"(?i)passw|pwd", name) else 3.0  # passwords are often low-entropy
            if len(set(value)) < 6 or entropy(value) < low:
                continue
            found.append(("assignment", name, value))
    return found


def fp(value):
    return hashlib.sha256(value.encode()).hexdigest()[:8]


def git(*args):
    p = subprocess.run(["git", *args], capture_output=True, text=True, errors="replace")
    return p.returncode, p.stdout


def tree_files(paths, all_files):
    if paths:
        for p in paths:
            if os.path.isdir(p):
                for d, dirs, files in os.walk(p):
                    dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
                    yield from (os.path.join(d, f) for f in files)
            else:
                yield p
        return
    rc, out = git("ls-files", "-co", "--exclude-standard")
    if rc != 0:
        yield from tree_files(["."], all_files)
        return
    names = set(out.splitlines())
    if all_files:
        names |= set(git("ls-files", "-o", "-i", "--exclude-standard")[1].splitlines())
    yield from sorted(n for n in names if not set(n.split("/")) & SKIP_DIRS)


def read_lines(path):
    try:
        if os.path.getsize(path) > 2_000_000:
            return []
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return []
    if b"\0" in data[:4096]:
        return []
    return data.decode("utf-8", "replace").splitlines()


def scan_tree(paths, all_files, quiet=False):
    seen, n = set(), 0
    for path in tree_files(paths, all_files):
        for i, line in enumerate(read_lines(path), 1):
            for kind, name, value in hits_in_line(line):
                seen.add(fp(value))
                n += 1
                if not quiet:
                    print(f"{path}:{i} kind={kind} name={name} len={len(value)} fp={fp(value)}")
    return n, seen


def scan_history():
    rc, out = git("log", "-p", "--all", "-U0", "--no-color", "--no-ext-diff", "--format=@@COMMIT %h")
    if rc != 0:
        sys.stderr.write("--history needs a git repository with commits\n")
        sys.exit(2)
    _, in_tree = scan_tree([], False, quiet=True)
    commit = path = None
    lineno, n, reported = 0, 0, set()
    for line in out.splitlines():
        if line.startswith("@@COMMIT "):
            commit = line.split()[1]
        elif line.startswith("+++ "):
            t = line[4:]
            path = t[2:] if t.startswith("b/") else t
        elif line.startswith("@@ "):
            m = re.match(r"@@ -\S+ \+(\d+)", line)
            lineno = int(m.group(1)) if m else 0
        elif line.startswith("+") and path and path != "/dev/null":
            for kind, name, value in hits_in_line(line[1:]):
                key = (fp(value), path)
                if key not in reported:
                    reported.add(key)
                    n += 1
                    print(f"{commit} {path}:{lineno} kind={kind} name={name} len={len(value)} fp={fp(value)} "
                          f"in_tree={'yes' if fp(value) in in_tree else 'no'}")
            lineno += 1
    return n


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--history", action="store_true")
    ap.add_argument("--all-files", action="store_true")
    ap.add_argument("paths", nargs="*")
    a = ap.parse_args()
    if a.history and a.paths:
        ap.error("--history scans the whole repository; don't pass paths")
    n = scan_history() if a.history else scan_tree(a.paths, a.all_files)[0]
    print(f"RESULT hits={n}")
    return 1 if n else 0


if __name__ == "__main__":
    sys.exit(main())
