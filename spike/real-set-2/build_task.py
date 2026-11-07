#!/usr/bin/env python3
"""Builds one hidden-test task's files for a real set (REAL_TASKS_PLAN.md).

    build_task.py REPO SHA ID SETDIR [--tests PATH ...] [--exclude PATH ...] [--add SRC:DEST ...] [--patch DIFF ...]
                  [--mod-download]
                  [--write-tests [--src PATH]]

Writes into SETDIR:
  ID.tgz         the repository at SHA's parent (tracked files only), minus --exclude paths, plus --add files, with
                 each --patch applied to the files of it that the tree has (a later fix the harness needs, such as
                 a hang in the test suite; it must not touch the files the commit changes)
  ID-hidden.tgz  the commit's added or changed files under --tests, as they are at SHA
  ID.gold.diff   the commit's other changes (the solution), for validate_task.py
and prints the task's size as JSON. Deleted test files can't be expressed as an overlay and are reported.

--tests may repeat and may be a git pathspec with magic, for tests that sit beside the code (Go:
--tests ':(glob)**/*_test.go' --tests ':(glob)**/testdata/**'). --mod-download runs `go mod download` in the fixture
before packing it, into the GOMODCACHE of the environment: it fetches the modules the parent's go.mod pins, and runs
none of their code.

With --write-tests (group D: "add tests that would have caught this bug") the files are instead:
  ID.tgz           the repository at SHA (the fixed code) with the tests as they were at its parent
  ID-buggy.tgz     the commit's changed files under --src (default src/) as they were at the parent: the harness lays
                   them over the run's tree to see its tests fail; files the fix added stay, which the old code ignores
  ID-reference.tgz the commit's own tests, for validate_task.py to show the task can be done
"""
import argparse, json, os, shutil, subprocess, sys, tempfile

def git(repo, *args, text=True):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=text, check=True).stdout

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo"); ap.add_argument("sha"); ap.add_argument("id"); ap.add_argument("setdir")
    ap.add_argument("--tests", action="append")
    ap.add_argument("--mod-download", action="store_true")
    ap.add_argument("--exclude", action="append", default=[])
    ap.add_argument("--add", action="append", default=[], help="SRC:DEST, a file copied into the fixture")
    ap.add_argument("--patch", action="append", default=[], help="a diff applied to the fixture's files that exist")
    ap.add_argument("--write-tests", action="store_true", help="the fixed code with the old tests; see above")
    ap.add_argument("--src", default="src/", help="--write-tests: where the code the buggy overlay restores is")
    a = ap.parse_args()
    a.tests = a.tests or ["tests/"]
    os.makedirs(a.setdir, exist_ok=True)
    parent = git(a.repo, "rev-parse", a.sha + "^").strip()

    work = tempfile.mkdtemp(prefix="kk-build-")
    try:
        tree = os.path.join(work, "tree")
        os.makedirs(tree)
        base = a.sha if a.write_tests else parent
        archive = subprocess.run(["git", "-C", a.repo, "archive", base], capture_output=True, check=True).stdout
        subprocess.run(["tar", "-x", "-C", tree], input=archive, check=True)
        if a.write_tests:  # the tests back as they were before the fix
            restore(a.repo, parent, a.sha, a.tests, tree)
        for path in a.exclude:
            p = os.path.join(tree, path)
            shutil.rmtree(p) if os.path.isdir(p) else (os.path.exists(p) and os.remove(p))
        for spec in a.add:
            src, dest = spec.split(":", 1)
            os.makedirs(os.path.dirname(os.path.join(tree, dest)) or tree, exist_ok=True)
            shutil.copy(src, os.path.join(tree, dest))
        touched = set(git(a.repo, "diff", "--name-only", "--no-renames", parent, a.sha).split())
        for diff in a.patch:
            files = [l[6:] for l in open(diff).read().splitlines() if l.startswith("+++ b/")]
            if touched & set(files):
                sys.exit(f"{diff} touches files the commit changes: {sorted(touched & set(files))}")
            present = [f for f in files if os.path.exists(os.path.join(tree, f))]
            include = [f"--include={f}" for f in present]
            applied = subprocess.run(["git", "apply", "--reverse", "--check", *include, os.path.abspath(diff)],
                                     cwd=tree, capture_output=True).returncode == 0
            if present and not applied:
                subprocess.run(["git", "apply", *include, os.path.abspath(diff)], cwd=tree, check=True)
        if a.mod_download:
            subprocess.run(["go", "mod", "download"], cwd=tree, check=True)
        subprocess.run(["tar", "-czf", os.path.join(a.setdir, a.id + ".tgz"), "-C", tree, "."], check=True)
        if a.write_tests:
            return write_tests_overlays(a, parent, work)

        hidden = os.path.join(work, "hidden")
        os.makedirs(hidden)
        changed, deleted = [], []
        for line in git(a.repo, "diff", "--name-status", "--no-renames", parent, a.sha, "--", *a.tests).splitlines():
            status, path = line.split("\t", 1)
            if status == "D":
                deleted.append(path); continue
            changed.append(path)
            out = os.path.join(hidden, path)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "wb") as f:
                f.write(git(a.repo, "show", f"{a.sha}:{path}", text=False))
        subprocess.run(["tar", "-czf", os.path.join(a.setdir, a.id + "-hidden.tgz"), "-C", hidden, "."], check=True)

        excludes = [exclude(t) for t in a.tests] + [exclude(p) for p in a.exclude]
        diff = git(a.repo, "diff", "--no-renames", parent, a.sha, "--", ".", *excludes)
        with open(os.path.join(a.setdir, a.id + ".gold.diff"), "w") as f:
            f.write(diff)
        files = [l[6:] for l in diff.splitlines() if l.startswith("+++ b/")]
        lines = sum(1 for l in diff.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---")))
        print(json.dumps({"id": a.id, "sha": a.sha, "parent": parent[:9], "solution_files": files, "solution_lines": lines,
                          "hidden_tests": changed, "deleted_tests": deleted,
                          "fixture_bytes": os.path.getsize(os.path.join(a.setdir, a.id + ".tgz"))}))
    finally:
        shutil.rmtree(work, ignore_errors=True)

def exclude(spec):
    """The pathspec that leaves `spec` out; a magic one (":(glob)...") gets "exclude" added to its magic."""
    return ":(exclude," + spec[2:] if spec.startswith(":(") else ":(exclude)" + spec

def restore(repo, parent, sha, under, tree):
    """Puts the files under `under` back as they were at `parent`: added ones removed, the others rewritten."""
    for line in git(repo, "diff", "--name-status", "--no-renames", parent, sha, "--", *under).splitlines():
        status, path = line.split("\t", 1)
        out = os.path.join(tree, path)
        if status == "A":
            os.remove(out); continue
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "wb") as f:
            f.write(git(repo, "show", f"{parent}:{path}", text=False))

def pack(repo, rev, paths, setdir, name, work):
    d = os.path.join(work, name)
    os.makedirs(d)
    for path in paths:
        out = os.path.join(d, path)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "wb") as f:
            f.write(git(repo, "show", f"{rev}:{path}", text=False))
    subprocess.run(["tar", "-czf", os.path.join(setdir, name), "-C", d, "."], check=True)

def write_tests_overlays(a, parent, work):
    def changes(under):
        out = git(a.repo, "diff", "--name-status", "--no-renames", parent, a.sha, "--", *under)
        return [l.split("\t", 1) for l in out.splitlines()]
    src, tests = changes([a.src]), changes(a.tests)
    buggy = [p for s, p in src if s != "A"]
    pack(a.repo, parent, buggy, a.setdir, a.id + "-buggy.tgz", work)
    pack(a.repo, a.sha, [p for s, p in tests if s != "D"], a.setdir, a.id + "-reference.tgz", work)
    diff = git(a.repo, "diff", "--no-renames", parent, a.sha, "--", a.src)
    lines = sum(1 for l in diff.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---")))
    print(json.dumps({"id": a.id, "sha": a.sha, "parent": parent[:9], "kind": "write-tests", "fix_files": buggy,
                      "fix_lines": lines, "fix_added_files": [p for s, p in src if s == "A"],
                      "reference_tests": [p for s, p in tests if s != "D"],
                      "fixture_bytes": os.path.getsize(os.path.join(a.setdir, a.id + ".tgz"))}))

if __name__ == "__main__":
    main()
