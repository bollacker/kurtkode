#!/usr/bin/env python3
"""Hidden check for shell-scripts/fragile-packager. Run in the project folder. Exit 0 = pass.
Runs tools/package.sh with bash (macOS ships bash 3.2) in scratch folders:
1. paths with spaces, a relative OUT_DIR, note names with spaces and a leading dash: exit 0, archive has
   exactly the right pages with the right content, nothing else left in OUT_DIR, script callable from elsewhere;
   a second run over the same output works;
2. a note that fails to render (in the middle of a pipeline): non-zero exit, render.py's message shown, no
   archive and no staging leftovers in OUT_DIR, no 'packed' success line;
3. missing arguments: non-zero exit, a usage message, nothing created; a missing SRC_DIR: non-zero, no archive.
4. The project's own notes still package: tools/package.sh notes dist."""
import os, shutil, subprocess, tarfile, tempfile

script = os.path.abspath("tools/package.sh")
problems = []
GOOD = {"welcome.md": "# Welcome\n\nHello   \n", "second note.md": "# Second\n\n```\nx = 1\n```\n",
        "-draft ideas.md": "Ideas here.\n"}


def run(args, cwd):
    return subprocess.run(["bash", script, *args], cwd=cwd, capture_output=True, text=True, timeout=60)


def make(root, files):
    os.makedirs(root, exist_ok=True)
    for name, text in files.items():
        with open(os.path.join(root, name), "w") as f:
            f.write(text)


def members(path):
    with tarfile.open(path) as t:
        out = {}
        for m in t.getmembers():
            if m.isfile() and not os.path.basename(m.name).startswith("._"):  # skip macOS tar metadata
                out[os.path.normpath(m.name)] = t.extractfile(m).read().decode()
        return out


work = tempfile.mkdtemp(prefix="pkg check ")
try:
    # 1. spaces, relative OUT, odd names, run from another directory
    make(os.path.join(work, "my notes"), GOOD)
    os.makedirs(os.path.join(work, "out dir"))
    open(os.path.join(work, "out dir", "keep.txt"), "w").write("not ours\n")
    for attempt in (1, 2):
        p = run(["my notes", "out dir", "site pages"], work)
        archive = os.path.join(work, "out dir", "site pages.tar.gz")
        if p.returncode != 0 or not os.path.isfile(archive):
            problems.append(f"spaces/relative OUT run {attempt}: exit {p.returncode}, no archive; {p.stderr[-300:]}")
            break
        got = members(archive)
        want = {"welcome.html", "second note.html", "-draft ideas.html"}
        if set(got) != want:
            problems.append(f"archive has {sorted(got)}, want {sorted(want)}")
        elif "<h1>Second</h1>" not in got["second note.html"] or "x = 1" not in got["second note.html"] \
                or "Ideas here." not in got["-draft ideas.html"] or "Hello   " in got["welcome.html"]:
            problems.append("archive pages are not the rendered notes")
        left = sorted(set(os.listdir(os.path.join(work, "out dir"))) - {"keep.txt", "site pages.tar.gz"})
        if left or not os.path.exists(os.path.join(work, "out dir", "keep.txt")):
            problems.append(f"OUT_DIR after a successful run has extra files {left} or lost keep.txt")
    # 2. failure inside the render pipeline
    make(os.path.join(work, "broken notes"), {"a first.md": "# A\n", "b bad.md": "```\nnever closed\n",
                                               "c last.md": "# C\n"})
    p = run(["broken notes", "out2"], work)
    out2 = os.path.join(work, "out2")
    if p.returncode == 0:
        problems.append("a note that fails to render still exits 0")
    if "unclosed code block" not in p.stderr:
        problems.append("render.py's error message is not shown on stderr")
    if "packed" in p.stdout:
        problems.append("prints the success line although rendering failed")
    if os.path.isdir(out2) and os.listdir(out2):
        problems.append(f"failed run left files in OUT_DIR: {os.listdir(out2)}")
    # 3. missing arguments, missing source
    for args in ([], ["my notes"]):
        empty = tempfile.mkdtemp(prefix="pkg args ")
        p = run(args, empty)
        if p.returncode == 0 or "usage" not in (p.stdout + p.stderr).lower():
            problems.append(f"with arguments {args}: exit {p.returncode}, want non-zero and a usage message")
        if os.listdir(empty):
            problems.append(f"with arguments {args}: created {os.listdir(empty)}")
        shutil.rmtree(empty)
    p = run(["no such dir", "out3"], work)
    if p.returncode == 0 or os.path.exists(os.path.join(work, "out3", "notes.tar.gz")):
        problems.append("a missing SRC_DIR does not fail cleanly")
    # 4. the real job
    shutil.rmtree("dist", ignore_errors=True)
    p = subprocess.run(["bash", "tools/package.sh", "notes", "dist"], capture_output=True, text=True, timeout=60)
    if p.returncode != 0 or set(members("dist/notes.tar.gz")) != {"welcome.html", "setup.html"}:
        problems.append(f"tools/package.sh notes dist no longer works: {p.stderr[-300:]}")
    shutil.rmtree("dist", ignore_errors=True)
except Exception as e:
    problems.append(f"check crashed: {e!r}")
finally:
    shutil.rmtree(work, ignore_errors=True)

for x in problems:
    print("FAIL:", x)
print("PASS" if not problems else "")
raise SystemExit(1 if problems else 0)
