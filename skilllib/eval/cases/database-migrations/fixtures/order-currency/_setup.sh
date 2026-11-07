# Repo with one commit; app.db (untracked, ignored) is the production snapshot at migration 0002.
git init -q -b main && git add -A && git commit -qm "Add order items"
python3 migrate.py --db app.db up > /dev/null
python3 -c "import sqlite3; c = sqlite3.connect('app.db'); c.executescript(open('seed.sql').read()); c.commit()"
