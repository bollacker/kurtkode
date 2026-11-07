# shop

Order storage on SQLite. Schema changes are migrations in `migrations/`, applied with `python3 migrate.py up`
(see `python3 migrate.py --help`). `app.db` is a recent snapshot of the production database. Tests:
`python3 -m unittest`.
