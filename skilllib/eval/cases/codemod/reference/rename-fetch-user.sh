# Reference: inventory with the skill's tool, keep only the locations that refer to app.users.api.fetch_user
# (drop the partner client's method, legacy.crm's own fetch_user, metric names and log texts), dry run, apply, test.
TOOL="$CASE_DIR/../../../skills/codemod/scripts/codemod.py"
INV=$(mktemp) SEL=$(mktemp)
python3 "$TOOL" find fetch_user > $INV
grep -E '  code|  string' $INV \
  | grep -v -E 'attr\((client|CLIENT)\)|app/remote/client.py|legacy/crm.py|legacy/sync.py:(2|9):' \
  | grep -v -E '  string' > $SEL
grep -E '^(app/users/api.py:5:|tests/test_handlers.py:14:)' $INV >> $SEL
python3 "$TOOL" apply fetch_user load_user --from $SEL > /dev/null || exit 1
python3 "$TOOL" apply fetch_user load_user --from $SEL --write || exit 1
rm -f $INV $SEL
python3 -B -m unittest -q 2>/dev/null
