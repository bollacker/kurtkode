# Reference: strict mode with pipefail, every expansion quoted, usage and argument checks before touching
# anything, absolute paths before any cd, a private staging dir removed by a trap, tar -C so no glob or
# leading-dash names reach tar's options, and the archive moved into place only when complete.
cat > tools/package.sh <<'SH'
#!/usr/bin/env bash
# Render every note (*.md) in SRC_DIR to HTML and pack the pages into OUT_DIR/NAME.tar.gz.
set -euo pipefail

usage() { echo "usage: $(basename "$0") SRC_DIR OUT_DIR [NAME]   (NAME defaults to notes)"; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
if [ $# -lt 2 ] || [ $# -gt 3 ]; then usage >&2; exit 2; fi

src=$1 out=$2 name=${3:-notes}
here=$(cd "$(dirname "$0")" && pwd)
if [ ! -d "$src" ]; then echo "package.sh: not a directory: $src" >&2; exit 1; fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/package.XXXXXX")
partial=""
cleanup() { rm -rf "$stage"; if [ -n "$partial" ]; then rm -f "$partial"; fi; }
trap cleanup EXIT

count=0
for f in "$src"/*.md; do
  [ -e "$f" ] || { echo "package.sh: no .md files in $src" >&2; exit 1; }
  base=$(basename "$f" .md)
  python3 "$here/render.py" "$f" | sed 's/[[:space:]]*$//' > "$stage/$base.html"
  count=$((count + 1))
done

mkdir -p "$out"
partial="$out/.$name.tar.gz.partial"
tar -czf "$partial" -C "$stage" .
mv -f "$partial" "$out/$name.tar.gz"
partial=""
echo "packed $count notes into $out/$name.tar.gz"
SH
chmod +x tools/package.sh
