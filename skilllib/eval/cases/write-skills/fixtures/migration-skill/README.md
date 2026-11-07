# ledger

A tiny double-entry ledger on SQLite. Python 3, standard library only.

- `migrations/`: numbered schema migrations, each an `.up.sql` and a `.down.sql`
- `schema.sql`: the full schema after all migrations (generated, committed)
- `tools/`: migration checks and the schema dump
- `agent/skills/`: our coding-agent skills (linked into each agent's own skills folder on dev machines)

See docs/CONTRIBUTING.md for how we work.
