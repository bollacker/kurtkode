# Builds the history: the page size was capped at 37 (reason only in that commit's message), then the file was
# moved into a package and restyled, so `git blame` and `git log <path>` no longer reach the reason.
set -e
git init -q -b main
c() { GIT_AUTHOR_DATE="$1T10:00:00" GIT_COMMITTER_DATE="$1T10:00:00" git commit -qm "$2" ${3:+-m "$3"}; }

mkdir -p ledger tests reports
cat > ledger/__init__.py <<'EOF'
EOF
cat > ledger/store.py <<'EOF'
"""In-memory ledger used by the sync jobs and the tests."""
_rows = {}


def upsert(invoice):
    _rows[invoice["id"]] = invoice


def all_rows():
    return list(_rows.values())


def clear():
    _rows.clear()
EOF
cat > README.md <<'EOF'
# ledger-sync

Nightly jobs that pull invoices from Paywise into our ledger and export reports.

    python3 -m unittest discover -s tests
EOF
cat > paywise_sync.py <<'EOF'
"""Pull invoices from Paywise into the local ledger."""
from ledger import store

PAGE = 100


def fetch_all(client):
    invoices, cursor = [], None
    while True:
        page = client.get("/invoices", limit=PAGE, cursor=cursor)
        invoices.extend(page["items"])
        if not page["has_more"]:
            return invoices
        cursor = page["next"]


def sync(client):
    for inv in fetch_all(client):
        store.upsert(inv)
EOF
cat > tests/__init__.py <<'EOF'
EOF
cat > tests/test_sync.py <<'EOF'
import unittest

import paywise_sync as sync
from ledger import store


class FakeClient:
    def __init__(self, n):
        self.items = [{"id": i, "amount": 10 * i} for i in range(n)]
        self.limits = []

    def get(self, path, limit, cursor=None):
        self.limits.append(limit)
        start = cursor or 0
        chunk = self.items[start:start + limit]
        more = start + limit < len(self.items)
        return {"items": chunk, "has_more": more, "next": start + limit if more else None}


class SyncTest(unittest.TestCase):
    def setUp(self):
        store.clear()

    def test_sync_copies_every_invoice(self):
        sync.sync(FakeClient(250))
        self.assertEqual(len(store.all_rows()), 250)


if __name__ == "__main__":
    unittest.main()
EOF
git add -A && c 2023-03-02 "Add Paywise invoice sync"

cat > reports/__init__.py <<'EOF'
EOF
cat > reports/export.py <<'EOF'
"""CSV export of ledger rows for the finance team."""
import csv
import io

from ledger import store

PAGE_SIZE = 50


def export_csv():
    rows = store.all_rows()
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["id", "amount"])
    for start in range(0, len(rows), PAGE_SIZE):
        for r in rows[start:start + PAGE_SIZE]:
            w.writerow([r["id"], r["amount"]])
    return buf.getvalue()
EOF
git add -A && c 2023-03-20 "Add CSV report export"

cat > paywise_sync.py <<'EOF'
"""Pull invoices from Paywise into the local ledger."""
from ledger import store

PAGE = 37


def fetch_all(client):
    invoices, cursor = [], None
    while True:
        page = client.get("/invoices", limit=PAGE, cursor=cursor)
        invoices.extend(page["items"])
        if not page["has_more"]:
            return invoices
        cursor = page["next"]


def sync(client):
    for inv in fetch_all(client):
        store.upsert(inv)
EOF
python3 - <<'EOF'
p = "tests/test_sync.py"
s = open(p).read()
s = s.replace('''        self.assertEqual(len(store.all_rows()), 250)
''', '''        self.assertEqual(len(store.all_rows()), 250)

    def test_page_size_within_limit(self):
        client = FakeClient(100)
        sync.sync(client)
        self.assertTrue(all(limit <= 37 for limit in client.limits))
''')
open(p, "w").write(s)
EOF
git add -A && c 2023-05-11 "Cap Paywise page size at 37" "Paywise's /invoices endpoint silently drops every record after the 37th on a
page when limit > 37, and still returns has_more=false for the last page, so
the missing invoices never show up on a later page. We lost 212 invoices from
the April close this way (INC-2291). Paywise support confirmed the bug
(ticket PW-88412) and has no fix date.

Keep the page size at 37 or below until Paywise confirms a fix. The new test
guards the limit."

python3 - <<'EOF'
p = "reports/export.py"
s = open(p).read().replace("PAGE_SIZE = 50", "PAGE_SIZE = 200")
open(p, "w").write(s)
EOF
git add -A && c 2023-08-04 "Bump report page size for faster exports"

mkdir -p billing
cat > billing/__init__.py <<'EOF'
EOF
git mv paywise_sync.py billing/sync.py
python3 - <<'EOF'
p = "tests/test_sync.py"
s = open(p).read().replace("import paywise_sync as sync", "from billing import sync")
open(p, "w").write(s)
EOF
git add -A && c 2024-01-15 "Move sync into billing package"

cat > billing/sync.py <<'EOF'
"""Pull invoices from Paywise into the local ledger."""
from typing import Any

from ledger import store

PAGE_SIZE: int = 37  # keep requests small


def fetch_all(client: Any) -> list:
    invoices: list = []
    cursor = None
    while True:
        page = client.get("/invoices", limit=PAGE_SIZE, cursor=cursor)
        invoices.extend(page["items"])
        if not page["has_more"]:
            return invoices
        cursor = page["next"]


def sync(client: Any) -> None:
    for inv in fetch_all(client):
        store.upsert(inv)
EOF
git add -A && c 2024-02-02 "Style: upper-case constants, add type hints"

cat > billing/sync.py <<'EOF'
"""Pull invoices from Paywise into the local ledger."""
import time
from typing import Any

from ledger import store

PAGE_SIZE: int = 37  # keep requests small
RETRIES: int = 3


class TransientError(Exception):
    """Paywise answered 503; worth retrying."""


def _get(client: Any, cursor: Any) -> dict:
    for attempt in range(RETRIES):
        try:
            return client.get("/invoices", limit=PAGE_SIZE, cursor=cursor)
        except TransientError:
            time.sleep(0.1 * (attempt + 1))
    return client.get("/invoices", limit=PAGE_SIZE, cursor=cursor)


def fetch_all(client: Any) -> list:
    invoices: list = []
    cursor = None
    while True:
        page = _get(client, cursor)
        invoices.extend(page["items"])
        if not page["has_more"]:
            return invoices
        cursor = page["next"]


def sync(client: Any) -> None:
    for inv in fetch_all(client):
        store.upsert(inv)
EOF
git add -A && c 2024-06-10 "Retry Paywise requests on 503"
