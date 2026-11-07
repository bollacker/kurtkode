#!/usr/bin/env python3
"""Show what a conflicted merge, rebase, cherry-pick or revert is combining, so both sides' intent can be kept.

Usage: conflict_context.py [--max-names N]     (run inside the repository while the operation is in progress)

Prints, in this order:
  OPERATION, HEAD / OTHER / BASE   which commit is "ours" (HEAD) and which is "theirs" (OTHER) for this operation
  SIDE COMMITS                     commits on each side since the base (read them with git show <sha>)
  FILE ... / HUNK ...              each conflicted file and hunk: its line range and the commits on each side
                                   that wrote the lines in it
  STALE NAMES                      identifiers one side removed or renamed everywhere that are still used in the
                                   working tree, including files that merged without a conflict
  RESULT conflicted=<n> stale=<n>

Exit codes: 0 = no conflicted files left, 1 = conflicted files remain, 2 = usage error, not a repository,
or no merge/rebase/cherry-pick/revert in progress. Read-only: it never changes files, the index or refs.
"""
import argparse, os, re, subprocess, sys

KEYWORDS = set("""and as assert async await break case catch class const continue def default del delete do elif else
enum except export extends false final finally for from func function if impl import in interface is let match mut
new nil none not null or pass private protected pub public raise return self static struct super switch this throw
true try type typeof undefined use var void while with yield""".split())


def git(*args, ok=False):
    p = subprocess.run(["git", *args], capture_output=True, text=True, errors="replace")
    if p.returncode != 0 and not ok:
        return ""
    return p.stdout


def ref(name):
    return git("rev-parse", "-q", "--verify", name, ok=True).strip()


def subject(sha):
    return git("log", "-1", "--format=%h %s", sha).strip()


def find_block(lines, block):
    """1-based start of block inside lines, or 0."""
    n = len(block)
    for i in range(len(lines) - n + 1):
        if lines[i:i + n] == block:
            return i + 1
    return 0


def writers(rev, path, block, base):
    """Commits after base that wrote the given lines of path at rev."""
    if not block:
        return ["(no lines on this side)"]
    text = git("show", f"{rev}:{path}", ok=True).splitlines()
    start = find_block(text, block)
    if not start:
        return ["(lines not found at this revision)"]
    out = git("blame", "--porcelain", "-L", f"{start},{start + len(block) - 1}", rev, "--", path, ok=True)
    shas = []
    for line in out.splitlines():
        m = re.match(r"^([0-9a-f]{40}) \d+ \d+", line)
        if m and m.group(1) not in shas:
            shas.append(m.group(1))
    after = [s for s in shas if not base or subprocess.run(
        ["git", "merge-base", "--is-ancestor", s, base], capture_output=True).returncode != 0]
    return [subject(s) for s in after] or ["(unchanged since base)"]


def hunks(path):
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return []
    found, cur, part = [], None, None
    for i, line in enumerate(lines, 1):
        if line.startswith("<<<<<<<"):
            cur, part = {"start": i, "ours": [], "base": [], "theirs": []}, "ours"
        elif cur and line.startswith("|||||||"):
            part = "base"
        elif cur and line == "=======":
            part = "theirs"
        elif cur and line.startswith(">>>>>>>"):
            cur["end"] = i
            found.append(cur)
            cur = None
        elif cur:
            cur[part].append(line)
    return found


def idents(text):
    return {w for w in re.findall(r"\b[A-Za-z_][A-Za-z0-9_]{2,}\b", text) if w.lower() not in KEYWORDS}


def stale_names(base, side, label, limit):
    diff = git("diff", "-U0", base, side)
    minus = idents("\n".join(l[1:] for l in diff.splitlines() if l.startswith("-") and not l.startswith("---")))
    plus = idents("\n".join(l[1:] for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")))
    rows = []
    for name in sorted(minus - plus):
        if subprocess.run(["git", "grep", "-q", "-w", name, side], capture_output=True).returncode == 0:
            continue  # still exists on that side: not removed
        uses = git("grep", "-n", "-w", name, "--", ".", ok=True).splitlines()
        uses = [":".join(u.split(":")[:2]) for u in uses]
        if uses:
            more = f" (+{len(uses) - 4} more)" if len(uses) > 4 else ""
            rows.append(f"  {name}  removed on {label} side; still used at {', '.join(uses[:4])}{more}")
    return rows[:limit]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--max-names", type=int, default=15, help="max stale names to list (default 15)")
    a = ap.parse_args()
    gitdir = git("rev-parse", "--git-dir").strip()
    if not gitdir:
        print("not a git repository", file=sys.stderr)
        return 2
    gitdir = os.path.abspath(gitdir)
    os.chdir(git("rev-parse", "--show-toplevel").strip() or ".")
    op = other = None
    rebasing = any(os.path.isdir(os.path.join(gitdir, d)) for d in ("rebase-merge", "rebase-apply"))
    for name, kind in (("MERGE_HEAD", "merge"), ("REBASE_HEAD", "rebase"), ("CHERRY_PICK_HEAD", "cherry-pick"),
                       ("REVERT_HEAD", "revert")):
        if ref(name) and (kind != "rebase" or rebasing):
            op, other = kind, ref(name)
            break
    conflicted = [f for f in git("diff", "--name-only", "--diff-filter=U").splitlines() if f]
    if not op:
        if conflicted:
            print(f"OPERATION unknown (stash pop or apply?) CONFLICTED {len(conflicted)}: {' '.join(conflicted)}")
            return 1
        print("no merge, rebase, cherry-pick or revert in progress", file=sys.stderr)
        return 2
    head = ref("HEAD")
    if op == "merge":
        base = git("merge-base", head, other).strip()
    elif op == "revert":
        base = other
    else:
        base = ref(other + "^")
    print(f"OPERATION {op}")
    if op == "rebase":
        print("  note: in a rebase HEAD/ours is the branch being rebased onto; OTHER/theirs is your commit being replayed")
    print(f"HEAD   {subject(head)}   (ours, --ours, stage 2)")
    print(f"OTHER  {subject(other)}   (theirs, --theirs, stage 3)")
    print(f"BASE   {subject(base) if base else '(none)'}")
    print("SIDE COMMITS")
    for label, tip in (("HEAD", head), ("OTHER", other)):
        rng = f"{base}..{tip}" if base else tip
        log = git("log", "--format=%h %s", "-n", "20", rng).splitlines()
        print(f"  {label}: " + ("; ".join(log) if log else "(none)"))
    print(f"CONFLICTS {len(conflicted)} files")
    stages = {}
    for line in git("ls-files", "-u").splitlines():
        meta, path = line.split("\t", 1)
        stages.setdefault(path, set()).add(meta.split()[2])
    for path in conflicted:
        st = stages.get(path, set())
        kind = ("deleted on HEAD side" if "2" not in st else "deleted on OTHER side" if "3" not in st
                else "added on both sides" if "1" not in st else "modified on both sides")
        hs = hunks(path)
        print(f"FILE {path}  {kind}, {len(hs)} hunk(s)")
        for n, h in enumerate(hs, 1):
            print(f"  HUNK {n} lines {h['start']}-{h['end']}: HEAD {len(h['ours'])} lines, OTHER {len(h['theirs'])} lines")
            print(f"    HEAD wrote:  {'; '.join(writers(head, path, h['ours'], base))}")
            print(f"    OTHER wrote: {'; '.join(writers(other, path, h['theirs'], base))}")
    rows = []
    if base:
        rows = stale_names(base, head, "HEAD", a.max_names) + stale_names(base, other, "OTHER", a.max_names)
    print("STALE NAMES" + ("" if rows else " (none found)"))
    for r in rows:
        print(r)
    print(f"RESULT conflicted={len(conflicted)} stale={len(rows)}")
    return 1 if conflicted else 0


if __name__ == "__main__":
    sys.exit(main())
