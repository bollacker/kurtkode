#!/usr/bin/env python3
"""List the line ranges a change adds or modifies, in the NEW version of each file.

Usage: changed_lines.py [RANGE] [--staged] [--line PATH:N]

  RANGE        anything `git diff` accepts: main...HEAD, A..B, <sha>^!, a branch name.
               Omitted: uncommitted changes against HEAD (staged and unstaged).
  --staged     only staged changes (git diff --cached)
  --line P:N   instead of listing, say whether line N of file P (new version) is part of the change

Prints one line per changed hunk: "path:start-end" (or "path:start" for one line); deleted-only hunks print
"path:N (deleted lines after N)". Untracked files are not included (git diff does not show them).
With --line it prints "P:N changed" or "P:N unchanged".

Exit codes: 0 = changes listed / the line is changed, 1 = no changes in range / the line is unchanged,
2 = usage or git error.
"""
import argparse, re, subprocess, sys

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def hunks(args):
    cmd = ["git", "diff", "-U0", "--no-color", "--no-ext-diff"] + args
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.stderr.write(p.stderr or "git diff failed\n")
        sys.exit(2)
    path = None
    for line in p.stdout.splitlines():
        if line.startswith("+++ "):
            t = line[4:]
            path = None if t == "/dev/null" else (t[2:] if t.startswith("b/") else t)
        elif line.startswith("@@") and path:
            m = HUNK.match(line)
            if m:
                start, count = int(m.group(1)), int(m.group(2) or 1)
                yield path, start, count


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("range", nargs="?")
    ap.add_argument("--staged", action="store_true")
    ap.add_argument("--line")
    a = ap.parse_args()
    args = ["--cached"] if a.staged else []
    args += [a.range] if a.range else ([] if a.staged else ["HEAD"])
    if a.line:
        m = re.match(r"^(.+):(\d+)$", a.line)
        if not m:
            ap.print_usage(sys.stderr)
            return 2
        want, n = m.group(1), int(m.group(2))
        want = want[2:] if want.startswith("./") else want
        for path, start, count in hunks(args):
            if (path == want or path.endswith("/" + want)) and count and start <= n < start + count:
                print(f"{a.line} changed")
                return 0
        print(f"{a.line} unchanged")
        return 1
    found = 0
    for path, start, count in hunks(args):
        found += 1
        if count == 0:
            print(f"{path}:{start} (deleted lines after {start})")
        elif count == 1:
            print(f"{path}:{start}")
        else:
            print(f"{path}:{start}-{start + count - 1}")
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())
