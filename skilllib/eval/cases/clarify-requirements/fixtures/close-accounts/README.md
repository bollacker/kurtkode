# accounts

User accounts and orders for the shop, on SQLite.

    python3 cli.py --db shop.db init
    python3 cli.py --db shop.db add-user ana@example.com "Ana Diaz"
    python3 cli.py --db shop.db list-users
    python3 cli.py --db shop.db revenue 2026-09

`revenue` is the number finance uses for the monthly close.

Tests: `python3 -m unittest discover -s tests`
