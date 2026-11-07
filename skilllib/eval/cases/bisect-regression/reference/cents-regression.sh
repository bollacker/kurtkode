# Reference: bisect with a test that skips commits where the program can't run (exit 125) and compares the total
# without thousands separators (their removal was intended), then record the first bad commit.
set -e
python3 "$CASE_DIR/../../../skills/bisect-regression/scripts/bisect_run.py" --good v1.0 -- \
  'out=$(python3 -m ledger summary data/march.csv) || exit 125; echo "$out" | tr -d , | grep -q "^Total: 7183.68$"' \
  | tee /dev/stderr | awk '/^FIRST_BAD/ {print $2}' > CULPRIT.txt
test -s CULPRIT.txt
