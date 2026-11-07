---
name: database-migrations
description: Use when changing a database schema (add, rename or drop a column or table, a constraint, index or type, a backfill) with Alembic, Django, Rails, Prisma or SQL. Keeps data, reversible. Not for slow queries (performance).
---

# Database migrations

Change the schema so that every existing row survives, the new rules hold, the migration runs on the database as
it is in production, and it can be rolled back.

## Fast path

A new table, or a new nullable column nothing depends on yet: write the migration with up and down, run
up → down → up on a copy of a populated database, run the tests, report. Never skip the run on real-shaped data.

## Steps

1. **Learn how migrations run here.** Find the tool (Alembic, Django, Rails, Prisma, Knex, Flyway, goose, a
   project script), the migrations folder, how applied migrations are recorded (a `schema_migrations`-style table,
   `alembic_version`), whether each one runs in a transaction, and the engine and version. Engine limits and
   locking rules are in `references/engines.md`; read the part for your engine before writing DDL.

2. **Add a new migration; never edit an applied one.** Anything merged, deployed, or listed in the database's
   migration table is history: databases that already ran it will never run your edit. Check with the tool's
   status command or by querying the table.

3. **Decide the data rule for every change to existing rows.** For a new required column: what value does each
   existing row get (copied, computed, a known constant)? For a type change: how each value converts and what
   happens to values that don't. Write the rule in the migration's header comment.

4. **Choose one-step or expand/contract.** If the app keeps running during the deploy, or the table is large, split
   the change so old and new code both work at every step:
   - required column: add it nullable → backfill in batches → add the NOT NULL/CHECK → app writes it;
   - rename: add the new column → write both and backfill → switch reads → drop the old one in a later release;
   - drop: stop using it first, drop it in a later release.
   Small apps deployed together with their schema, with a short pause acceptable, can do it in one migration.

5. **Write up and down.** Down restores the previous schema with the data that existed before. If part of it can't
   be undone (dropped data, lossy conversion), make down fail with a clear message and say so in the report.
   Recreate everything a table rebuild loses: indexes, triggers, views, foreign keys, CHECKs, defaults.

6. **Test on a copy of real data.** Copy the populated database (or load a dump or seed into a scratch database);
   never use the only copy. Record row counts (and a checksum or a few full rows) for every affected table and every
   table that references them. Run up, compare, and try to break the new rule (insert a row that should be
   rejected, and one that should be accepted). Run down, compare again; run up again. Then run the migrations from
   an empty database (the test suite's setup path) too.

7. **Change the app with the schema.** Models or ORM schema, queries, seeds, fixtures and tests in the same change;
   run the test suite.

## Rules

- **Don't edit a migration that has run anywhere.** "I'll just add the column to the CREATE TABLE" works on a
  fresh database and never reaches production.
- **Don't trust a run on an empty database.** Backfills, constraints on existing rows and cascades only show up
  with data in the tables.
- **Don't drop or rebuild a table with data before checking what references it.** With foreign keys enforced, a
  DROP TABLE fires ON DELETE CASCADE / SET NULL on the child rows (SQLite does exactly this mid-rebuild).
- **Don't meet NOT NULL with a placeholder** (`''`, `0`, `'unknown'`) unless that is the agreed data rule, and drop
  a default the request says must not exist once the backfill is done.
- **Don't run migrations against a production database** or a shared one unless the user asks; work on a copy.
- **Don't lock a large table for a long rewrite**: backfill in batches outside the DDL transaction and use the
  engine's online options (`references/engines.md`).

## When no one can answer

Pick the data rule the request implies; if none, the most conservative one (keep data, add the constraint only
when every row satisfies it) and record it in the migration header and the report. Prefer expand/contract when
unsure whether the app runs during deploys. Stop and report instead of migrating if the change destroys data with
no way back (dropping a populated column, a lossy type change) and the request didn't explicitly ask for that.

## Done means

- the new migration file(s) and the app, model and test changes;
- a short report: what the migration does, the data rule, one-step or expand/contract (and what the later steps
  are), whether down is lossless;
- **evidence**: the commands that ran up → down → up on a copy of populated data, with row counts before and after,
  the rejected and accepted test inserts, and the test-suite result from an empty database;
- deploy notes: order relative to the app deploy, and expected locking or duration on large tables.
