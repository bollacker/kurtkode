#!/usr/bin/env python3
"""Run every shell command shown in a Markdown document, in order, in a fresh copy of the project.

Usage: check_doc_commands.py DOC.md [--root DIR] [--keep] [--timeout SECS]

  DOC.md      the document (README.md, docs/usage.md, ...)
  --root      the project folder to copy (default: the git top level, else the current directory)
  --keep      keep the scratch copy and print its path
  --timeout   seconds allowed for the whole run (default 120)

Which blocks run: fenced blocks tagged sh, bash, shell, zsh or console. In console blocks only lines starting with
"$ " are commands (the rest is output). Untagged and text blocks are not run, so put sample output there.
The copy holds the git-tracked files plus the document (or everything under --root outside git), so files you
created while testing don't hide a missing step. All blocks run in document order in ONE bash session started in
the copy's root (like pasting them into one terminal: cd and export carry over), with `set -e` and HOME set to a
scratch folder. The run stops at the first failing command.

Prints "ok", "FAIL" or "skip" (not reached) with "<doc>:<line> <first command>" per block, the output of the
failing block (last 15 lines), then "RESULT blocks=N failed=0|1".

Exit codes: 0 = every block ran with exit status 0, 1 = a block failed (or there were no runnable blocks),
2 = usage error.
"""
import argparse, os, re, shutil, subprocess, sys, tempfile

RUN_TAGS = {"sh", "bash", "shell", "zsh", "console", "shell-session"}


def blocks(text):
    out, lines, i = [], text.splitlines(), 0
    while i < len(lines):
        m = re.match(r"^(\s*)(`{3,}|~{3,})\s*([\w+-]*)", lines[i])
        if not m:
            i += 1
            continue
        fence, tag, start, body = m.group(2), m.group(3).lower(), i + 1, []
        i += 1
        while i < len(lines) and not lines[i].strip().startswith(fence):
            body.append(lines[i])
            i += 1
        i += 1
        if tag in RUN_TAGS:
            if tag in ("console", "shell-session"):
                body = [l.strip()[2:] for l in body if l.strip().startswith("$ ")]
            body = [re.sub(r"^\s*\$ ", "", l) for l in body]
            if any(l.strip() and not l.strip().startswith("#") for l in body):
                out.append((start, "\n".join(body)))
    return out


def copy_project(root, doc, dest):
    p = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True)
    if p.returncode == 0 and p.stdout:
        for rel in p.stdout.decode().split("\0"):
            if rel and os.path.lexists(os.path.join(root, rel)):
                os.makedirs(os.path.dirname(os.path.join(dest, rel)), exist_ok=True)
                shutil.copy2(os.path.join(root, rel), os.path.join(dest, rel), follow_symlinks=False)
    else:
        shutil.copytree(root, dest, dirs_exist_ok=True, symlinks=True,
                        ignore=shutil.ignore_patterns(".git", "node_modules", "__pycache__"))
    rel = os.path.relpath(os.path.abspath(doc), root)
    if not rel.startswith(".."):
        os.makedirs(os.path.dirname(os.path.join(dest, rel)) or dest, exist_ok=True)
        shutil.copy2(doc, os.path.join(dest, rel))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("doc")
    ap.add_argument("--root")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--timeout", type=float, default=120)
    a = ap.parse_args()
    if not os.path.isfile(a.doc):
        print(f"no such file: {a.doc}", file=sys.stderr)
        return 2
    root = a.root
    if not root:
        p = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        root = p.stdout.strip() if p.returncode == 0 else os.getcwd()
    root = os.path.abspath(root)
    found = blocks(open(a.doc, encoding="utf-8").read())
    scratch = tempfile.mkdtemp(prefix="doccheck-")
    work, home = os.path.join(scratch, "project"), os.path.join(scratch, "home")
    os.makedirs(work)
    os.makedirs(home)
    copy_project(root, a.doc, work)
    env = {k: v for k, v in os.environ.items() if k not in ("VIRTUAL_ENV",)}
    env["HOME"] = home
    marks = "".join(f"echo '@@BLOCK {i}' >&2\n{body}\n" for i, (line, body) in enumerate(found))
    try:
        script = "set -e\n" + marks + "echo '@@BLOCK END' >&2\n"
        p = subprocess.run(["bash", "-c", script], cwd=work, env=env, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=a.timeout)
        rc, err, out = p.returncode, p.stderr, p.stdout + p.stderr
    except subprocess.TimeoutExpired as e:
        err = e.stderr.decode(errors="replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        rc, out = 124, err + f"\ntimed out after {a.timeout}s"
    reached = [int(x) for x in re.findall(r"^@@BLOCK (\d+)$", err, re.M)]
    last = reached[-1] if reached else 0
    failed = 0 if "@@BLOCK END" in err and rc == 0 else 1
    for i, (line, body) in enumerate(found):
        first = next(l.strip() for l in body.splitlines() if l.strip() and not l.strip().startswith("#"))
        state = "ok  " if (not failed or i < last) else ("FAIL" if i == last else "skip")
        print(f"{state} {a.doc}:{line} {first[:70]}")
        if state == "FAIL":
            tail = [l for l in out.rstrip().splitlines() if not l.startswith("@@BLOCK")][-15:]
            print("\n".join("    " + l for l in tail))
    print(f"RESULT blocks={len(found)} failed={failed}")
    if a.keep:
        print(f"scratch copy: {work}")
    else:
        shutil.rmtree(scratch, ignore_errors=True)
    return 0 if found and not failed else 1


if __name__ == "__main__":
    sys.exit(main())
