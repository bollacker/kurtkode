#!/usr/bin/env python3
"""Check what is staged for the next commit: secrets, local config, debug leftovers, conflict markers, big files.

Usage: check_staged.py [--max-kb N]      (run inside the repository, after `git add`)

Prints "STAGED <n> files" and the staged paths, then one line per finding:
  "FLAG <path>[:line] <kind>: <detail>"
and a summary "RESULT clean" or "RESULT flagged=<n>".
Only added lines are scanned (the staged diff), so old content does not count.

Exit codes: 0 = nothing flagged, 1 = something flagged, 2 = usage error or not a git repository.
Read-only: it never stages, unstages or edits anything.
"""
import argparse, re, subprocess, sys

BAD_NAMES = [
    (r"(^|/)\.env(\..*)?$", "local env/secret file"),
    (r"\.(pem|key|p12|pfx|keystore|jks)$", "key or certificate"),
    (r"(^|/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$", "ssh key"),
    (r"(^|/)(credentials|secrets?|service[-_]account)[^/]*\.(json|ya?ml|txt|ini)$", "credentials file"),
    (r"(^|/)(debug|scratch|tmp|temp)[_\-.][^/]*$|(^|/)(scratch|tmp)/", "debug or scratch file"),
    (r"\.(log|sqlite3?|db|dump)$|(^|/)(\.DS_Store|Thumbs\.db)$", "log, database or OS file"),
]
SECRET_LINES = [
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "private key"),
    (r"\bAKIA[0-9A-Z]{16}\b", "AWS access key id"),
    (r"\b(ghp|gho|ghs|github_pat)_[A-Za-z0-9_]{20,}", "GitHub token"),
    (r"\bxox[abpr]-[A-Za-z0-9-]{10,}", "Slack token"),
    (r"\bsk-[A-Za-z0-9_-]{20,}", "API secret key"),
    (r"(?i)\b[\w-]*(secret|token|passw(or)?d|api[_-]?key|private[_-]?key)[\w-]*\s*[:=]\s*['\"]?[^\s'\"#]{8,}",
     "assignment of a secret-like value"),
]
DEBUG_LINES = [
    (r"\bbreakpoint\(\)|\bpdb\.set_trace\(\)|\bimport pdb\b", "debugger call"),
    (r"^\s*debugger;?\s*$", "debugger statement"),
    (r"\bconsole\.log\(", "console.log"),
    (r"print\(\s*f?['\"](DEBUG|XXX|HERE)", "debug print"),
    (r"^(<<<<<<<|>>>>>>>)( |$)|^=======$", "conflict marker"),
]


def git(*args):
    p = subprocess.run(["git", *args], capture_output=True, text=True)
    return p.returncode, p.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--max-kb", type=int, default=500, help="flag staged files larger than this (default 500)")
    a = ap.parse_args()
    rc, _ = git("rev-parse", "--git-dir")
    if rc != 0:
        print("not a git repository", file=sys.stderr)
        return 2
    _, names = git("diff", "--cached", "--name-only", "--diff-filter=ACMR")
    files = [f for f in names.splitlines() if f]
    print(f"STAGED {len(files)} files")
    for f in files:
        print("  " + f)
    flags = []
    for f in files:
        for pat, kind in BAD_NAMES:
            if re.search(pat, f) and not f.endswith((".example", ".sample", ".template")):
                flags.append(f"FLAG {f} name: {kind}")
        _, size = git("cat-file", "-s", f":{f}")
        if size.strip().isdigit() and int(size) > a.max_kb * 1024:
            flags.append(f"FLAG {f} size: {int(size) // 1024} KB staged")
        _, diff = git("diff", "--cached", "-U0", "--", f)
        line_no = 0
        for line in diff.splitlines():
            m = re.match(r"^@@ -\S+ \+(\d+)", line)
            if m:
                line_no = int(m.group(1))
                continue
            if not line.startswith("+") or line.startswith("+++"):
                continue
            text = line[1:]
            for pat, kind in SECRET_LINES:
                if re.search(pat, text):
                    flags.append(f"FLAG {f}:{line_no} secret: {kind}")
                    break
            for pat, kind in DEBUG_LINES:
                if re.search(pat, text):
                    flags.append(f"FLAG {f}:{line_no} leftover: {kind}")
                    break
            line_no += 1
    for fl in flags:
        print(fl)
    print("RESULT clean" if not flags else f"RESULT flagged={len(flags)}")
    return 1 if flags else 0


if __name__ == "__main__":
    sys.exit(main())
