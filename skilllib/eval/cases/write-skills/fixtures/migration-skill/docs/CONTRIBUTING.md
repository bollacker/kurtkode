# Contributing

## Adding a database migration

Every schema change is a new migration. We have been burned by both of these: someone edited a migration that was
already on main (production had run the old version, so the databases diverged), and someone forgot to regenerate
schema.sql (reviewers review schema.sql, so the change went in unreviewed).

1. Take the next number: the highest number in `migrations/` plus one, four digits (`0003`).
2. Create `migrations/<number>_<short_name>.up.sql` with the change, and `migrations/<number>_<short_name>.down.sql`
   that undoes exactly that change. SQLite can't drop columns on old versions: a down for an added column
   rebuilds the table (create new, copy, drop old, rename).
3. Run `python3 tools/migrate_check.py`. It applies every up, then every down in reverse, then every up again on a
   scratch database and fails if any step errors or the schema differs between the two up passes.
4. Regenerate the snapshot: `python3 tools/dump_schema.py > schema.sql`.
5. Commit the up file, the down file and schema.sql together, in one commit.

Never edit or renumber a migration that is already on main, even to fix a typo: add a new migration that fixes it.
