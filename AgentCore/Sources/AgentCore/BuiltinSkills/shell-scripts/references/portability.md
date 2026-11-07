# Portability: bash versions, POSIX sh, GNU vs BSD tools

Read this in step 1 of SKILL.md when the script must run on macOS, in `sh`/dash/busybox (Docker images, Debian's
`/bin/sh`), or on both Linux and macOS.

## bash 3.2 (macOS /bin/bash) vs bash 4+/5

| Feature | bash 3.2 | Use instead |
|---|---|---|
| `declare -A` associative arrays | missing | two parallel arrays, or a temp file, or Python |
| `mapfile` / `readarray` | missing | `while IFS= read -r line; do arr+=("$line"); done < file` |
| `${x,,}` / `${x^^}` | missing | `tr '[:upper:]' '[:lower:]'` |
| `"${arr[@]}"` on an empty array with `set -u` | "unbound variable" (fixed in 4.4) | `${arr[@]+"${arr[@]}"}`, or check `${#arr[@]}` first |
| `&>>`, `|&` | missing | `>> f 2>&1`, `2>&1 |` |
| `read -t 0.5` fractional | missing | whole seconds |
| `wait -n`, `$EPOCHSECONDS`, `${var@Q}` | missing | — |

Homebrew installs a newer bash at `/opt/homebrew/bin/bash`; `#!/usr/bin/env bash` picks whichever is first on
PATH, so don't assume either.

## POSIX sh (dash, busybox ash)

Not available: arrays, `[[ ]]`, `(( ))` as a command, `function` keyword, `source` (use `.`), `$'...'` strings,
`{a,b}` brace expansion, `<<<` here-strings, `echo -e` (use `printf`), `local` (works in dash and busybox, not
POSIX), `set -o pipefail` (only recent dash releases; busybox has it). Use `[ ]` with quoted operands and `=` (not `==`).

## GNU (Linux) vs BSD (macOS) tools

| Task | GNU | BSD/macOS | Works on both |
|---|---|---|---|
| in-place edit | `sed -i 's/a/b/' f` | `sed -i '' 's/a/b/' f` | `sed -i.bak 's/a/b/' f && rm f.bak`, or write to a temp file and `mv` |
| absolute path | `readlink -f p` | `realpath` (macOS 13+), `readlink -f` (12.3+) | `(cd "$(dirname "$p")" && echo "$(pwd)/$(basename "$p")")` |
| date arithmetic | `date -d '1 day ago'` | `date -v-1d` | `python3 -c` or avoid |
| file size | `stat -c %s f` | `stat -f %z f` | `wc -c < f` |
| extended regex | `sed -E`/`-r`, `grep -E` | `sed -E`, `grep -E` | `-E` |
| `mktemp` | `mktemp -d` | `mktemp -d` (template needs `XXXXXX`) | `mktemp -d "${TMPDIR:-/tmp}/name.XXXXXX"` |
| `xargs` with no input | runs once (use `-r`) | doesn't run | `find ... -exec cmd {} +` |
| `tar` | GNU tar | bsdtar; adds `._*` AppleDouble files unless `COPYFILE_DISABLE=1` | `tar -czf out.tgz -C dir .` |
| `cp -r dir/ dest` | copies dir into dest | copies contents | `cp -R "dir/." "dest/"` |
| `base64 -d` | yes | `-d` (newer), `-D` (older) | `openssl base64 -d` |

## Argument parsing template (bash)

```bash
dry_run=0 verbose=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -n|--dry-run) dry_run=1 ;;
    -v|--verbose) verbose=1 ;;
    -o|--out) [ $# -ge 2 ] || { usage >&2; exit 2; }; out=$2; shift ;;
    --out=*) out=${1#*=} ;;
    --) shift; break ;;
    -*) echo "$(basename "$0"): unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
# "$@" now holds the positional arguments
```

`getopts` is POSIX and handles bundled short options (`-nv`) but no long options.

## Common shellcheck findings worth knowing

SC2086 unquoted variable · SC2046 unquoted `$(...)` · SC2155 `local x=$(...)` masks the status · SC2164 `cd`
without `|| exit` · SC2045 iterating over `ls` · SC2068 unquoted `$@` · SC2181 `if [ $? -ne 0 ]` instead of
`if ! cmd` · SC2115 `rm -rf "$dir/"` with a possibly empty `dir` · SC2002 useless `cat` (style only).
