# Reference release: minor bump (a feature since v1.3.0), version changed in every place it lives but not in
# the look-alikes, changelog from user-facing commits only, release commit, annotated tag.
set -e
sed -i.bak 's/^version = "1.3.0"$/version = "1.4.0"/' pyproject.toml
sed -i.bak 's/^__version__ = "1.3.0"$/__version__ = "1.4.0"/' tally/__init__.py
sed -i.bak -e 's/^version: 1.3.0$/version: 1.4.0/' -e 's/^date-released: .*/date-released: 2026-10-25/' CITATION.cff
sed -i.bak 's/tally==1.3.0/tally==1.4.0/' docs/install.md
rm -f pyproject.toml.bak tally/__init__.py.bak CITATION.cff.bak docs/install.md.bak
python3 - <<'PY'
p = "CHANGELOG.md"
s = open(p).read()
entry = """## [1.4.0] - 2026-10-25
### Added
- `--json` prints one JSON object per file.
### Changed
- Files are read line by line, so very large files no longer need to fit in memory.
### Fixed
- Empty files no longer crash the average-words-per-line column.
- Windows (CRLF) line endings are counted as one line break.

"""
s = s.replace("## [1.3.0]", entry + "## [1.3.0]", 1)
open(p, "w").write(s)
PY
python3 -m unittest -q 2>/dev/null
git add -A
git commit -qm "chore(release): 1.4.0"
git tag -a v1.4.0 -m "tally 1.4.0"
