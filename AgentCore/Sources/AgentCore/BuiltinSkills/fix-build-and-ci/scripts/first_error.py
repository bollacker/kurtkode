#!/usr/bin/env python3
"""Find the first real error in a long build or CI log, skipping noise and wrapper messages.

Usage: first_error.py [LOGFILE | -] [--context N] [--all]
  LOGFILE   a saved log (default: stdin). Timestamps (GitHub Actions style) and ANSI colors are stripped.
  --context lines of context to show before and after the first error (default 4)
  --all     list every primary error line, not just the first and up to 5 more

Prints:
  FIRST <line>: <text>          the earliest line that looks like a cause (compiler, lint, test, exception, missing
                                file or command), then the surrounding lines (the error line marked '>'); for a Python
                                traceback, the whole traceback up to the exception line
  ALSO <line>: <text>           later primary errors (up to 5), so you can see whether they are separate causes
  WRAPPER <line>: <text>        the first "step failed / exit code N / Error 2" style line: a consequence, not a cause
  SUMMARY primary=P wrapper=W lines=N
Exit codes: 0 = no error line found, 1 = an error was found and printed, 2 = usage error (file unreadable).
Heuristics, not a parser: always read the context it prints and confirm by reproducing the failure.
"""
import argparse, re, sys

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
STAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z?\s")

# Lines that say a step failed because something earlier failed.
WRAPPER = re.compile(
    r"Process completed with exit code|exited with (exit )?code [1-9]|returned non-zero exit status|"
    r"make(\[\d+\])?: \*\*\* .*Error \d+|npm ERR! code ELIFECYCLE|npm ERR! (errno|Lifecycle|A complete log)|"
    r"Command failed with exit code|BUILD FAIL(ED|URE)|ERROR: Job failed|step \S+ failed|"
    r"error: Recipe for target|Error: Process completed|^FAILED \(|^Tests?: .*failed|^FAIL$|"
    r"script returned exit code|Failed to execute goal|due to \d+ previous errors?|^npm ERR! \S+@\S+ \w+:", re.I)

# Lines that state a cause.
PRIMARY = re.compile(
    r"\berror(\[\w+\])?:|\berror (TS|CS|C)\d+\b|\bfatal( error)?:|^\s*\S+:\d+(:\d+)?:? [EF]\d{2,4}\b|"
    r"^\s*[\w.]*(Error|Exception)\b(:|$)|^Traceback \(most recent call last\)|^(ERROR|FAIL):? \w|"
    r"^--- FAIL|^FAIL\s+\S|^\s*E\s{2,}\S|\bpanic:|undefined reference|cannot find (symbol|module)|"
    r"No such file or directory|command not found|Permission denied|Segmentation fault|\bKilled\b|"
    r"\[ERROR\]|^npm ERR!|##\[error\]|ModuleNotFoundError|ImportError|SyntaxError|Cannot find module|"
    r"\bAssertionError\b|unresolved import|is not defined|could not (resolve|find)|Unable to", re.I)

# Lines that match the patterns above but are not errors.
NOISE = re.compile(
    r"\b0 (errors?|failures?|failed)\b|\b(errors?|failures?|failed)[:=] ?0\b|\bno errors?\b|without errors|"
    r"\.\.\. ok$|\bpassed\b.*\b0 failed|\bwarn(ing)?s?\b[:\]]|DeprecationWarning|-Werror|\bretry(ing)?\b|"
    r"will be retried|\(ignored\)|continue-on-error|^\s*#|\berror[-_]?(handling|handler|message|page)\b", re.I)


def clean(line):
    return STAMP.sub("", ANSI.sub("", line.rstrip("\n")))


def traceback_end(lines, i):
    """Index of the exception line that ends the traceback starting at i."""
    for j in range(i + 1, min(len(lines), i + 200)):
        s = lines[j]
        if s and not s[0].isspace() and not s.startswith(("Traceback", "During handling", "The above exception")):
            return j
    return i


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log", nargs="?", default="-")
    ap.add_argument("--context", type=int, default=4)
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()
    try:
        raw = sys.stdin.readlines() if a.log == "-" else open(a.log, errors="replace").readlines()
    except OSError as e:
        print(f"cannot read {a.log}: {e}", file=sys.stderr)
        return 2
    lines = [clean(l) for l in raw]
    primary, wrapper = [], []
    for i, s in enumerate(lines):
        if not s.strip():
            continue
        if WRAPPER.search(s):
            wrapper.append(i)
        elif PRIMARY.search(s) and not NOISE.search(s):
            primary.append(i)
    if not primary and not wrapper:
        print(f"NO ERROR FOUND lines={len(lines)} (look for the step's exit status, or search the log by hand)")
        return 0
    if primary:
        i = primary[0]
        print(f"FIRST {i + 1}: {lines[i]}")
        end = traceback_end(lines, i) if lines[i].startswith("Traceback") else i
        lo, hi = max(0, i - a.context), min(len(lines), end + a.context + 1)
        span = list(range(lo, hi))
        if len(span) > 40:
            span = span[:20] + [None] + span[-15:]
        for k in span:
            print("   ..." if k is None else f"{'>' if k in (i, end) else ' '}{k + 1:6}: {lines[k]}")
        later, seen = [], {lines[i].strip()}
        for k in primary[1:]:
            key = re.sub(r"\d+", "N", lines[k].strip())
            if key not in seen:
                seen.add(key)
                later.append(k)
        for k in later if a.all else later[:5]:
            print(f"ALSO {k + 1}: {lines[k]}")
        if not a.all and len(later) > 5:
            print(f"ALSO ... {len(later) - 5} more (use --all)")
    else:
        print("FIRST none: only wrapper lines found; the cause is probably printed just above the first one")
    if wrapper:
        print(f"WRAPPER {wrapper[0] + 1}: {lines[wrapper[0]]}")
    print(f"SUMMARY primary={len(primary)} wrapper={len(wrapper)} lines={len(lines)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
