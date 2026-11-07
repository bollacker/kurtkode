---
name: shell-scripts
description: Use when writing, fixing or reviewing a shell script or small CLI (bash, sh, cron or deploy scripts) with unquoted paths, ignored failures, arguments or --help. Strict, quoted, safe scripts. Not for CI failures (fix-build-and-ci).
---

# Shell scripts

Scripts that work with any path, stop at the first failure with a non-zero exit, check their arguments before
doing anything, and never leave a half-done result behind.

## Fast path

A few commands for the user's own one-off use: quote every expansion, add `set -euo pipefail`, run it once. A
script that others or machines run (cron, CI, deploy, release) gets all the steps.

## Steps

1. **Know where it runs.** `#!/usr/bin/env bash` if you use bash features; plain `sh` (dash, busybox) has no
   arrays, `[[ ]]` or `local` guarantees. macOS ships bash 3.2 and BSD tools: see `references/portability.md`
   before using arrays, `sed -i`, `readlink -f`, `date -d`, `mapfile` or `${x,,}`. Past ~150 lines or when you need
   data structures, suggest Python instead.

2. **Reproduce first** (when fixing). Run the script with the inputs that broke it, with a path containing spaces,
   with missing arguments, and with one step made to fail; `bash -x script ...` traces each command. Keep these
   cases; step 7 runs them again.

3. **Header and arguments.** Start with
   ```bash
   #!/usr/bin/env bash
   # <what it does, one line>
   set -euo pipefail
   usage() { echo "usage: $(basename "$0") [-n] INPUT_DIR [OUTPUT]"; }
   ```
   `-h`/`--help` prints usage to stdout and exits 0. A wrong argument count or unknown option prints usage to
   stderr and exits 2. Validate inputs (directory exists, number is a number) before creating, changing or deleting
   anything. Test optional arguments with `"${1:-}"` (plain `$1` is an error under `set -u`). For options, loop
   `while [ $# -gt 0 ]; do case "$1" in ... esac; shift; done`.

4. **Write the body by these patterns.**
   - Quote every expansion: `"$var"`, `"$(cmd)"`, `"${arr[@]}"`.
   - Loop over files with a glob, `for f in "$dir"/*.md; do [ -e "$f" ] || continue; ...`, or
     `find ... -print0 | while IFS= read -r -d '' f`. Never `for f in $(ls ...)` or `$(find ...)`.
   - Make paths absolute before any `cd` (`out=$(cd "$out" && pwd)`), find the script's own files with
     `here=$(cd "$(dirname "$0")" && pwd)`, and prefer a tool's `-C dir` or a subshell `(cd "$d" && ...)`.
   - Put `--` before file arguments, or use `./*` globs, so names starting with `-` are not read as options.
   - Temporary files: `tmp=$(mktemp -d)` and `trap 'rm -rf "$tmp"' EXIT` right after.
   - Results: write to a temporary name next to the target, then `mv` into place, so a failure leaves the old
     result or nothing, never a partial one.
   - Deletes: only paths you built and checked; `rm -rf "${dir:?}/build"` aborts if `dir` is empty.
   - Messages to stderr, prefixed with the script name. Exit 0 = success, 1 = failure, 2 = usage.
   - Re-runnable: `mkdir -p`, overwrite outputs, no step that fails because a previous run got halfway.

5. **Close the holes `set -e` leaves.** It does not stop the script when the failure is:
   - inside a pipeline without `pipefail` (`cmd | sed > out` takes `sed`'s status);
   - in `local x=$(cmd)`, `export x=$(cmd)` or `readonly x=$(cmd)` (the status is that of `local`): declare
     first, assign on the next line;
   - in a condition (`if`, `while`, `&&`, `||`), including everything inside a function called from one;
   - inside `$(...)` used as an argument (`echo "$(cmd)"`).
   Also: `((i++))` returns 1 when `i` was 0 and stops a `set -e` script; use `i=$((i + 1))`.

6. **Check statically.** `bash -n script` (syntax), and `shellcheck script` if installed: fix each warning or
   say why it doesn't apply.

7. **Run the cases.** Step 2's cases plus: spaces in every path argument, a relative output path, a file name
   starting with `-`, missing arguments (usage, non-zero, nothing created), a failing step (non-zero, error
   message shown, no partial output, no leftovers), and running it twice.

## Rules

- **Don't stop at adding `set -e`.** Pipelines, `local x=$(...)` and conditions still hide failures; step 5 is the
  part that fixes "it said done but it failed".
- **Don't silence errors you haven't analyzed** with `|| true` or `2>/dev/null`.
- **Don't parse `ls`** or loop over unquoted `$(...)` output; names with spaces and newlines break it.
- **Don't build commands in strings for `eval`.** Use an array: `args=(-v "$file"); cmd "${args[@]}"`.
- **Don't change the interface** (arguments, output paths, what is printed on success) when asked to make a
  script robust, unless the user asked for that too.
- **Don't test a destructive script against real targets.** Use temporary directories and stub commands.

## When no one can answer

Keep the interface. Write for bash 3.2 plus BSD and GNU tools unless the script already depends on something
newer. Record assumptions (target shell, platforms tested) in the report. Don't run the script against real
servers, production paths or other people's data to test it; if it can only be tested that way, stop and report.

## Done means

The script, and a short report with:
- **problems fixed**: each one as what broke → what changed;
- **evidence**: each case from step 7 with its command and exit status, and the `bash -n`/`shellcheck` result;
- **limits**: platforms or shells not tested.
