#!/usr/bin/env python3
"""List the commands that make up a project's full check, so "the tests pass" means the same thing CI means.

Usage: find_checks.py [ROOT]          (default: the current folder)

Reads CI configs (GitHub Actions, GitLab, CircleCI, Azure, Jenkinsfile), Makefile/justfile targets, package.json
scripts, and build files (pyproject/tox/nox, Cargo, Go, Swift, Maven, Gradle, pre-commit), then lists test folders
and flags Python test folders that plain `python -m unittest` discovery skips (no __init__.py).

Prints one line per finding, e.g.
  CI      .github/workflows/ci.yml: make check
  MAKE    Makefile: check -> unit integration
  NPM     package.json: test = jest
  BUILD   go.mod: go test ./... ; go vet ./...
  TESTDIR tests/integration: 3 test files, no __init__.py (python -m unittest discovery skips it)

Exit codes: 0 = at least one check command found, 1 = none found (ask or read the README), 2 = usage error.
Reads files only; runs nothing.
"""
import glob, json, os, re, sys

SKIP = {".git", "node_modules", ".venv", "venv", "env", "__pycache__", "dist", "build", "target", ".tox", ".build",
        "vendor", "Pods", ".next", "coverage"}
WORDS = re.compile(r"test|check|lint|verify|ci|type|e2e|integration|spec|vet|clippy|fmt|format", re.I)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def yaml_commands(text, keys):
    """Values of `key: cmd`, `key: |` blocks and `key:` lists, for the given keys. Good enough for CI files."""
    out, lines, i = [], text.splitlines(), 0
    while i < len(lines):
        m = re.match(r"^(\s*)(?:-\s+)?(%s):\s*(.*)$" % "|".join(keys), lines[i])
        if not m:
            i += 1; continue
        indent, val = len(m.group(1)), m.group(3).strip()
        i += 1
        if val and val[0] not in "|>":
            out.append(val.strip("'\""))
            continue
        while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > indent):
            s = lines[i].strip()
            if s and not s.startswith("#"):
                out.append(s[2:].strip("'\"") if s.startswith("- ") else s)
            i += 1
    return out


def main():
    args = sys.argv[1:]
    if args and args[0] in ("-h", "--help"):
        print(__doc__); return 0
    if len(args) > 1 or (args and not os.path.isdir(args[0])):
        print("usage: find_checks.py [ROOT]", file=sys.stderr); return 2
    root = os.path.abspath(args[0] if args else ".")
    rel = lambda p: os.path.relpath(p, root)
    found = []

    for f in sorted(glob.glob(os.path.join(root, ".github/workflows/*.y*ml"))):
        found += [("CI", f"{rel(f)}: {c}") for c in yaml_commands(read(f), ["run"])]
    for name, keys in [(".gitlab-ci.yml", ["script"]), (".circleci/config.yml", ["command", "run"]),
                       ("azure-pipelines.yml", ["script", "bash"]), ("bitbucket-pipelines.yml", ["script"])]:
        f = os.path.join(root, name)
        if os.path.isfile(f):
            found += [("CI", f"{name}: {c}") for c in yaml_commands(read(f), keys)]
    jf = os.path.join(root, "Jenkinsfile")
    for c in re.findall(r"""\bsh\s*\(?\s*['"]([^'"]+)['"]""", read(jf)):
        found.append(("CI", f"Jenkinsfile: {c}"))

    present = set(os.listdir(root))  # exact names: macOS file systems ignore case
    for name in [n for n in ("Makefile", "makefile", "GNUmakefile") if n in present][:1]:
        targets = {}
        for m in re.finditer(r"^([A-Za-z0-9_.-]+)[ \t]*:(?!=)[ \t]*([^\n#]*)\n?((?:\t[^\n]*\n?)*)", read(os.path.join(root, name)), re.M):
            recipe = m.group(3).strip().splitlines()
            targets[m.group(1)] = (m.group(2).split(), recipe[0].strip() if recipe else "")
        todo = [t for t in targets if WORDS.search(t) or t == "all"]
        shown = []
        while todo:
            t = todo.pop(0)
            if t in shown or t not in targets:
                continue
            shown.append(t)
            todo += targets[t][0]
        for t in shown:
            deps, cmd = targets[t]
            found.append(("MAKE", f"make {t}" + (f" -> {' '.join(deps)}" if deps else "") + (f" | {cmd}" if cmd else "")))
    for m in re.finditer(r"^([A-Za-z0-9_-]+)\s*[^:\n]*:(?!=)", read(os.path.join(root, "justfile")), re.M):
        if WORDS.search(m.group(1)):
            found.append(("JUST", f"justfile: just {m.group(1)}"))

    pkg = os.path.join(root, "package.json")
    if os.path.isfile(pkg):
        try:
            scripts = json.loads(read(pkg)).get("scripts", {})
        except ValueError:
            scripts = {}
        for k, v in scripts.items():
            if WORDS.search(k) or k == "build":
                found.append(("NPM", f"package.json: {k} = {v}"))

    build = [("pyproject.toml", r"\[tool\.pytest", "pytest"), ("pytest.ini", "", "pytest"), ("setup.cfg", r"\[tool:pytest",
             "pytest"), ("tox.ini", "", "tox"), ("noxfile.py", "", "nox"), ("Cargo.toml", "", "cargo test ; cargo clippy"),
             ("go.mod", "", "go test ./... ; go vet ./..."), ("Package.swift", "", "swift build ; swift test"),
             ("pom.xml", "", "mvn verify"), ("build.gradle", "", "./gradlew check"), ("build.gradle.kts", "", "./gradlew check"),
             (".pre-commit-config.yaml", "", "pre-commit run --all-files"), ("tsconfig.json", "", "npx tsc --noEmit")]
    for name, pat, cmd in build:
        f = os.path.join(root, name)
        if os.path.isfile(f) and (not pat or re.search(pat, read(f))):
            found.append(("BUILD", f"{name}: {cmd}"))
    for d in ("scripts", "tools", "bin", "ci"):
        for f in sorted(glob.glob(os.path.join(root, d, "*"))):
            if os.path.isfile(f) and WORDS.search(os.path.basename(f)):
                found.append(("SCRIPT", rel(f)))

    commands = len(found)
    for dirpath, dirnames, files in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP and not d.startswith("."))
        tests = [f for f in files if re.match(r"(test_.*|.*_test|.*\.(test|spec))\.(py|js|ts|jsx|tsx|mjs|go|rb)$", f)]
        if not tests and not re.search(r"(^|/)(tests?|spec|__tests__)$", dirpath):
            continue
        note = ""
        py = [f for f in tests if f.endswith(".py")]
        if py and "__init__.py" not in files and dirpath != root:
            note = ", no __init__.py (python -m unittest discovery skips it)"
        if tests:
            found.append(("TESTDIR", f"{rel(dirpath)}: {len(tests)} test file{'s' * (len(tests) != 1)}{note}"))

    for kind, text in found[:60]:
        print(f"{kind:<8}{text}")
    if len(found) > 60:
        print(f"... {len(found) - 60} more")
    if not commands:
        print("no check commands found: read README/CONTRIBUTING, or run each TESTDIR with the language's runner")
    return 0 if commands else 1


if __name__ == "__main__":
    sys.exit(main())
