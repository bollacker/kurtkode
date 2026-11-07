# Reference: a valid project skill for adding a migration, plus its trigger tests.
set -e
mkdir -p agent/skills/add-migration eval/cases/add-migration
cat > agent/skills/add-migration/SKILL.md <<'MD'
---
name: add-migration
description: Use when changing the database schema in this repo, adding a table, column or index, or touching migrations/ or schema.sql. Gives a numbered up/down migration that passes the check. Not for queries or data fixes.
---

# Add a database migration

Make a schema change as a new, reversible, checked migration with the schema snapshot updated.

## Fast path

Even a one-column change follows every step below; the steps are short. Only a change that doesn't touch the
schema (a query, a data fix) skips this skill.

## Steps

1. Take the next number: the highest number in `migrations/` plus one, four digits (`0003`).
2. Write `migrations/<number>_<short_name>.up.sql` with the change and
   `migrations/<number>_<short_name>.down.sql` that undoes exactly that change. On SQLite, a down for an added
   column rebuilds the table: create the new table, copy the rows, drop the old one, rename.
3. Run `python3 tools/migrate_check.py`. It must print `migrations OK` (up, down, up on a scratch database).
4. Regenerate the snapshot: `python3 tools/dump_schema.py > schema.sql`, and look at its diff.
5. Commit the up file, the down file and schema.sql together in one commit.

## Rules

- Never edit or renumber a migration that is already on main, even for a typo: production ran the old one, so
  the databases would diverge. Add a new migration that fixes it.
- Don't hand-edit schema.sql; reviewers read it, so it must come from dump_schema.py.
- Don't skip the down file: migrate_check.py fails without it and rollbacks need it.

## When no one can answer

Pick a short snake_case name from the change ("add_entry_memo"), make the down exact, and note any choice
(types, defaults, NOT NULL with a default) in your report.

## Done means

New `.up.sql` and `.down.sql` with the next number, `python3 tools/migrate_check.py` printing `migrations OK`,
schema.sql regenerated, all three in one commit; the report names the command and its output.
MD
cat > eval/cases/add-migration/cases.json <<'JSON'
{
  "triggers": {
    "should": [
      "Add a memo column to entries.",
      "We need an index on entries.account_id, it's slow.",
      "Create a currencies table and link accounts to it.",
      "Rename the accounts.name column to display_name.",
      "Drop the unused column from entries, and make sure we can roll it back.",
      "The schema needs a created_at timestamp on accounts."
    ],
    "should_not": [
      "Write a query that sums amount_cents per account.",
      "Fix the three entries that were posted to the wrong account.",
      "Run the tests and tell me what fails.",
      "What does tools/dump_schema.py print?"
    ]
  },
  "tasks": []
}
JSON
python3 tools/migrate_check.py >/dev/null
