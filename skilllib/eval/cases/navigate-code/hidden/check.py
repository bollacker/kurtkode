#!/usr/bin/env python3
"""Hidden check for navigate-code/export-timeout. Run in the project folder. Exit 0 = pass.
The export's configured 45 s (settings.ini) is clamped to 40 s in transport.send by limits.GATEWAY_MAX_MS.
Decoys: DEFAULT_TIMEOUT = 30 (config.py, and the README), EXPORT_TIMEOUT = 60 (unused legacy_export.py),
the import section's 90.
1. ANSWER.md says timeout_seconds: 40.
2. files_to_change names settings.ini and exporter/limits.py, and not legacy_export.py.
3. No tracked file was changed (a question, not a change)."""
import re, subprocess, sys

problems = []
if subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "."]).returncode != 0:
    problems.append("tracked files were changed: " + subprocess.run(
        ["git", "diff", "--stat", "HEAD"], capture_output=True, text=True).stdout.strip())
try:
    text = open("ANSWER.md", encoding="utf-8").read()
except OSError:
    text = ""
    problems.append("ANSWER.md missing")

def field(name):
    m = re.search(rf"^\W*{name}\W*[:=]\s*(.+)$", text, re.I | re.M)
    return m.group(1).strip() if m else ""

t = re.findall(r"\d+(?:\.\d+)?", field("timeout_seconds"))
if not t:
    problems.append("no 'timeout_seconds:' line with a number")
elif float(t[0]) != 40:
    problems.append(f"timeout_seconds is {t[0]}, want 40")
files = field("files_to_change")
if "settings.ini" not in files:
    problems.append(f"files_to_change ({files!r}) misses settings.ini")
if "limits.py" not in files:
    problems.append(f"files_to_change ({files!r}) misses exporter/limits.py (the gateway clamp)")
if "legacy_export" in files:
    problems.append("files_to_change names legacy_export.py, which the CLI never calls")

for p in problems:
    print("FAIL:", p)
print("PASS" if not problems else "")
sys.exit(1 if problems else 0)
