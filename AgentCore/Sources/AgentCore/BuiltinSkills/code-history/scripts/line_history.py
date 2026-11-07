#!/usr/bin/env python3
"""Show the git history of one line of code, through renames and reformatting, to find where it came from.

Usage: line_history.py FILE (--line N | --match REGEX) [--max N]

Prints, in this order:
  LINE     the file:line and its current text
  RENAMES  earlier paths of the file ("old -> new  in <commit>")
  COMMITS  every commit that changed the line, newest first: hash, date, author, subject, a tag
           [values unchanged] when only formatting or names changed (the literals stayed the same),
           the before/after text of the line, the full message body and the files the commit touched
  ORIGIN   the oldest commit that introduced the line's current literal values (numbers, strings)
  PICKAXE  other commits anywhere in the repo that added or removed those literals (git log -S)

Exit codes: 0 = history printed, 1 = the line has no committed history (new or uncommitted file/line),
            2 = usage error (not a git repo, file missing, no line matches).
Read-only: runs only git log/show/ls-files; never changes the working tree.
"""
import argparse, os, re, subprocess, sys

LIT = re.compile(r"""("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\b\d[\d_.]*\b)""")


def git(*args):
    p = subprocess.run(["git", *args], capture_output=True, text=True)
    return p.returncode, p.stdout


def literals(text):
    return sorted(set(m.replace("_", "") if m[0].isdigit() else m for m in LIT.findall(text)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--line", type=int)
    g.add_argument("--match", help="regex; the first matching line is used")
    ap.add_argument("--max", type=int, default=12, help="most commits to show (default 12)")
    a = ap.parse_args()

    rc, top = git("rev-parse", "--show-toplevel")
    if rc != 0:
        print("error: not inside a git repository", file=sys.stderr); return 2
    if not os.path.isfile(a.file):
        print(f"error: no such file: {a.file}", file=sys.stderr); return 2
    lines = open(a.file, encoding="utf-8", errors="replace").read().splitlines()
    if a.match:
        hits = [i + 1 for i, s in enumerate(lines) if re.search(a.match, s)]
        if not hits:
            print(f"error: no line in {a.file} matches {a.match!r}", file=sys.stderr); return 2
        n = hits[0]
        if len(hits) > 1:
            print(f"NOTE {len(hits)} lines match; using the first. Others: {hits[1:10]}")
    else:
        n = a.line
        if not 1 <= n <= len(lines):
            print(f"error: {a.file} has {len(lines)} lines", file=sys.stderr); return 2
    current = lines[n - 1]
    print(f"LINE {a.file}:{n}: {current.strip()}")

    rc, tracked = git("ls-files", "--error-unmatch", a.file)
    if rc != 0:
        print("RESULT no committed history: the file is not tracked"); return 1

    _, ren = git("log", "--follow", "--name-status", "--format=@%h", "--", a.file)
    renames, cur = [], None
    for s in ren.splitlines():
        if s.startswith("@"):
            cur = s[1:]
        elif s.startswith("R"):
            parts = s.split("\t")
            if len(parts) == 3:
                renames.append(f"{parts[1]} -> {parts[2]}  in {cur}")
    print("RENAMES" + ("" if renames else " none"))
    for r in renames:
        print("  " + r)

    fmt = "--format=@@C %H%n%h %ad %an%n%s%n%b@@E"
    rc, out = git("log", f"-L{n},{n}:{a.file}", "--date=short", fmt)
    if rc != 0 or "@@C" not in out:
        print("RESULT no committed history for this line (it may be uncommitted)"); return 1
    commits = []
    for chunk in out.split("@@C ")[1:]:
        head, _, diff = chunk.partition("@@E")
        hl = head.split("\n")
        full, meta, subject, body = hl[0], hl[1], hl[2], "\n".join(hl[3:]).strip()
        minus = [d[1:] for d in diff.splitlines() if d.startswith("-") and not d.startswith("---")]
        plus = [d[1:] for d in diff.splitlines() if d.startswith("+") and not d.startswith("+++")]
        commits.append(dict(full=full, meta=meta, subject=subject, body=body, minus=minus, plus=plus))

    want = literals(current)
    origin = None
    for c in commits:  # newest first; keep overwriting so the oldest introducer wins
        before, after = literals(" ".join(c["minus"])), literals(" ".join(c["plus"]))
        c["cosmetic"] = bool(c["minus"]) and before == after
        if want and set(want) <= set(after) and not set(want) <= set(before):
            origin = c
    print(f"COMMITS ({len(commits)} changed this line; newest first)")
    for c in commits[: a.max]:
        tag = " [values unchanged]" if c["cosmetic"] else ""
        print(f"* {c['meta']}  {c['subject']}{tag}")
        for s in c["minus"][:3]:
            print(f"    - {s.strip()}")
        for s in c["plus"][:3]:
            print(f"    + {s.strip()}")
        if c["body"]:
            for s in c["body"].splitlines()[:15]:
                print(f"    | {s}")
        _, files = git("show", "--name-status", "--format=", c["full"])
        print("    files: " + ", ".join(" ".join(f.split("\t")) for f in files.split("\n") if f.strip())[:400])
    if len(commits) > a.max:
        print(f"  ... {len(commits) - a.max} older commits not shown (raise --max)")
    if origin:
        print(f"ORIGIN {origin['meta']}  {origin['subject']}  (introduced {', '.join(want)}); "
              f"read it: git show {origin['full'][:10]}")
    else:
        print("ORIGIN unknown (no single commit introduced the current literals); read the oldest commits above")

    print("PICKAXE")
    for lit in want[:4]:
        if len(lit) < 2:
            continue
        _, pk = git("log", "--all", f"-S{lit}", "--date=short", "--format=%h %ad %s")
        for s in pk.splitlines()[:6]:
            print(f"  {lit}: {s}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
