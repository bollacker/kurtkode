# Reference: gather the state by running things, then write HANDOFF.md. No code changes.
set -e
git status --short >/dev/null
python3 tools/check.py >/dev/null 2>&1 || true
cat > HANDOFF.md <<'MD'
# Handoff: median for numstat (issue #12)

Branch `median-12`, based on the "mean" commit; nothing committed yet.

## State
- Done (uncommitted): `stats.median()` in numstat/stats.py, `--median` flag in numstat/cli.py, median tests in
  tests/test_stats.py. Scratch notes in NOTES.md (untracked).
- Verify: `python3 tools/check.py` (what CI runs). Now: CHECKS FAILED.
  - `test_median_even_count` fails: `median([4, 1, 3, 2])` returns 2, expected 2.5.
  - docs: README.md does not document `--median`.

## Decisions
- Even count returns the mean of the two middle values (matches the spreadsheet export ops compare with,
  reported on #12). This replaced the earlier median_low choice; don't go back to it.

## Next steps
1. In numstat/stats.py `median()`, return the average of the two middle values for an even count.
2. Add `--median` to the Options list in README.md.
3. Run `python3 tools/check.py` until it prints CHECKS PASSED, then commit.
MD
