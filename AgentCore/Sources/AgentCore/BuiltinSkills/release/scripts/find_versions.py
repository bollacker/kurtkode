#!/usr/bin/env python3
"""Find every place a project's version lives, check they agree, and list other mentions of the version string.

Usage: find_versions.py [--root DIR] [--version V] [--expect V]
  --root DIR   project folder (default: current directory); tracked files only when it is a git repository
  --version V  the version string to search for (default: the most common declared version)
  --expect V   after a bump: every declaration and the top CHANGELOG heading must equal V, and mentions of the
               previous version (--version, or the latest tag) are listed for review

Prints:
  DECLARED <path>:<line>: <version>  <field>   version fields of known files (package.json, pyproject.toml,
                                               Cargo.toml, __version__, VERSION, CITATION.cff, pom.xml, ...)
  TAG <latest tag> commits-since=<n>
  CHANGELOG <path>:<line>: <top version heading>
  MENTION <path>:<line>: <text>  [hint]       any other line containing the searched version: READ EACH ONE.
                                               Some are this project's version (install commands, docs, constants
                                               the release must change); some are not (a dependency pin, a file
                                               format or API version that happens to match, sample data).
                                               Hints: [this project?] [version constant] [dependency or other?]
                                               [a different constant? read it] are guesses from the line's shape.
  RESULT ok <version> | RESULT mismatch: <details>
Exit codes: 0 = declarations agree (and match --expect), 1 = they disagree or differ from --expect,
2 = usage error or no version declaration found.
Changelog files and lockfiles are not searched for mentions (they hold history and other packages' versions).
"""
import argparse, collections, json, os, re, subprocess, sys

SKIP_DIRS = {".git", "node_modules", "vendor", ".venv", "venv", "dist", "build", "target", "__pycache__", ".build"}
LOCKS = {"package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Cargo.lock", "poetry.lock", "uv.lock", "go.sum",
         "Gemfile.lock", "composer.lock", "Package.resolved"}
CHANGELOG = re.compile(r"^(CHANGELOG|CHANGES|HISTORY|NEWS|RELEASES)(\.\w+)?$", re.I)
SEMVER = r"v?(\d+\.\d+(?:\.\d+)?(?:[-+][\w.]+)?)"
# file name pattern -> list of (line regex, section required or None, label)
LINE_RULES = [
    (r"pyproject\.toml", r'^version\s*=\s*["\']([^"\']+)', ("[project]", "[tool.poetry]"), "pyproject version"),
    (r"Cargo\.toml", r'^version\s*=\s*"([^"]+)', ("[package]", "[workspace.package]"), "Cargo.toml version"),
    (r"setup\.cfg", r"^version\s*=\s*(\S+)", ("[metadata]",), "setup.cfg version"),
    (r"setup\.cfg|\.bumpversion\.cfg", r"^current_version\s*=\s*(\S+)", None, "bumpversion current_version"),
    (r"setup\.py", r'\bversion\s*=\s*["\']([^"\']+)', None, "setup.py version"),
    (r"(__init__|_version|version|__about__)\.py", r'^__version__\s*=\s*["\']([^"\']+)', None, "__version__"),
    (r"(VERSION|version)(\.txt)?", r"^\s*" + SEMVER + r"\s*$", None, "version file"),
    (r"CITATION\.cff", r'^version:\s*["\']?([^"\'\s]+)', None, "CITATION.cff version"),
    (r"Chart\.yaml", r'^(?:app)?[vV]ersion:\s*["\']?([^"\'\s]+)', None, "Chart.yaml version"),
    (r"pubspec\.yaml", r"^version:\s*(\S+)", None, "pubspec version"),
    (r"build\.gradle(\.kts)?", r'^version\s*=\s*["\']([^"\']+)', None, "gradle version"),
    (r"gradle\.properties", r"^version\s*=\s*(\S+)", None, "gradle.properties version"),
    (r".*\.gemspec|.*\.podspec", r'\.version\s*=\s*["\']([^"\']+)', None, "spec version"),
    (r"conf\.py", r'^(?:release|version)\s*=\s*["\']([^"\']+)', None, "sphinx conf version"),
    (r"mix\.exs", r'\bversion:\s*"([^"]+)', None, "mix version"),
    (r".*\.csproj", r"<Version>([^<]+)</Version>", None, "csproj Version"),
    (r"CMakeLists\.txt", r"project\([^)]*VERSION\s+([\d.]+)", None, "cmake project VERSION"),
]


def files(root):
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, text=True, check=True).stdout
        paths = [p for p in out.split("\0") if p]
        if paths:
            return paths
    except (OSError, subprocess.CalledProcessError):
        pass
    found = []
    for d, dirs, fs in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        found += [os.path.relpath(os.path.join(d, f), root) for f in fs]
    return found


def read(root, path):
    try:
        with open(os.path.join(root, path), "rb") as f:
            data = f.read(1_000_000)
    except OSError:
        return None
    return None if b"\0" in data else data.decode("utf-8", "replace").splitlines()


def declarations(root, paths):
    found = []
    for path in paths:
        name = os.path.basename(path)
        if name in ("package.json", "manifest.json", "composer.json"):
            lines = read(root, path)
            try:
                v = json.loads("\n".join(lines or [])).get("version")
            except (ValueError, AttributeError):
                v = None
            if isinstance(v, str):
                n = next((i for i, l in enumerate(lines, 1) if re.search(r'"version"\s*:', l)), 1)
                found.append((path, n, v, f"{name} version"))
            continue
        if name == "pom.xml":
            text = "\n".join(read(root, path) or [])
            blocks = r"<(parent|dependencies|dependencyManagement|build|profiles|reporting)>.*?</\1>"
            masked = re.sub(blocks, lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
            m = re.search(r"<version>([^<$]+)</version>", masked)
            if m:
                found.append((path, masked[:m.start()].count("\n") + 1, m.group(1), "pom.xml project version"))
            continue
        for fpat, rx, sections, label in LINE_RULES:
            if not re.fullmatch(fpat, name):
                continue
            lines = read(root, path) or []
            section = None
            for i, l in enumerate(lines, 1):
                if l.startswith("["):
                    section = l.strip()
                m = re.search(rx, l)
                if m and (sections is None or section in sections):
                    found.append((path, i, m.group(1).lstrip("v") if label == "version file" else m.group(1), label))
                    if sections is None and label != "spec version":
                        break
    return found


def git(root, *args):
    p = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else ""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".")
    ap.add_argument("--version")
    ap.add_argument("--expect")
    a = ap.parse_args()
    if not os.path.isdir(a.root):
        print(f"not a directory: {a.root}", file=sys.stderr)
        return 2
    paths = sorted(files(a.root))
    decl = declarations(a.root, paths)
    for path, n, v, label in decl:
        print(f"DECLARED {path}:{n}: {v}  {label}")
    tag = git(a.root, "describe", "--tags", "--abbrev=0")
    if tag:
        print(f"TAG {tag} commits-since={git(a.root, 'rev-list', '--count', tag + '..HEAD') or '?'}")
    top = None
    for path in paths:
        if CHANGELOG.match(os.path.basename(path)) and os.path.dirname(path) == "":
            for i, l in enumerate(read(a.root, path) or [], 1):
                m = re.match(r"^#+\s*\[?(unreleased|" + SEMVER + r")\]?", l, re.I)
                if m:
                    top = m.group(2) or "Unreleased"
                    print(f"CHANGELOG {path}:{i}: {l.strip()}")
                    break
    if not decl:
        print("RESULT no version declaration found (look for a version constant by hand)")
        return 2
    counts = collections.Counter(v for _, _, v, _ in decl)
    current = a.version or (tag.lstrip("v") if a.expect and tag else counts.most_common(1)[0][0])
    project = ""
    for path, _, _, label in decl:
        lines = read(a.root, path) or []
        m = next((re.search(r'^\s*"?name"?\s*[=:]\s*["\']?([\w.-]+)', l) for l in lines
                  if re.search(r'^\s*"?name"?\s*[=:]', l)), None)
        if m:
            project = m.group(1)
            break
    seen = {(p, n) for p, n, _, _ in decl}
    token = re.compile(r"(?<![\w.])v?" + re.escape(current) + r"(?![\w]|\.\d)")
    for path in paths:
        base = os.path.basename(path)
        if base in LOCKS or CHANGELOG.match(base) or any(part in SKIP_DIRS for part in path.split("/")):
            continue
        for i, l in enumerate(read(a.root, path) or [], 1):
            if (path, i) in seen or not token.search(l):
                continue
            pre = l[:token.search(l).start()]
            hint = ""
            assign = re.search(r"([A-Za-z_][\w.]*)\s*:?=\s*[\"']?$", pre)
            dep = re.search(r"([\w.@/-]+)[\"']?\s*(==|>=|<=|~=|!=|>|<|@|:)\s*[\"']?[\^~=<>]*$", pre)
            if assign:
                own = assign.group(1).split(".")[-1].lower() in ("version", "__version__", "app_version")
                hint = "  [version constant]" if own else "  [a different constant? read it]"
            elif dep:
                hint = "  [this project?]" if project and dep.group(1).lower() == project.lower() else "  [dependency or other?]"
            print(f"MENTION {path}:{i}: {l.strip()[:160]}{hint}")
    problems = []
    if a.expect:
        problems += [f"{p}:{n} is {v}" for p, n, v, _ in decl if v != a.expect]
        if top != a.expect:
            problems.append(f"CHANGELOG top heading is {top}, not {a.expect}")
    elif len(counts) > 1:
        problems.append("declarations disagree: " + ", ".join(f"{v} x{c}" for v, c in counts.most_common()))
    if problems:
        print("RESULT mismatch: " + "; ".join(problems))
        return 1
    print(f"RESULT ok {a.expect or current}" + (f" (searched mentions of {current})" if a.expect else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
