# History: the payments token was hardcoded in the first commit and moved to the environment in the third.
# The token is derived here so its value never appears in the fixture files.
set -e
git init -q -b main
TOKEN=$(python3 -c "import hashlib; print(hashlib.sha256(b'kk-fixture-payments').hexdigest()[:40])")
mkdir -p payments tests
: > payments/__init__.py
: > tests/__init__.py
cat > README.md <<'EOF'
# payments-client

Client for the payments API. Python 3, standard library only.

    python3 -m unittest discover -s tests -t .
EOF
cat > payments/client.py <<EOF
"""Payments API client."""

API_URL = "https://payments.internal.example/v1"
TOKEN = "$TOKEN"


def auth_headers():
    return {"Authorization": "Bearer " + TOKEN}
EOF
git add -A && git commit -qm "Add payments client"

cat > payments/verify.py <<'EOF'
"""Check downloaded release files against their published checksum."""
import hashlib

RELEASE_SHA256 = "5f2b9c8e41d07a6c3be92d1f04a8e7c6d39b51f2a0c47e88d16b3a9f72e0c4d1"


def verify(data):
    return hashlib.sha256(data).hexdigest() == RELEASE_SHA256
EOF
git add -A && git commit -qm "Verify release checksums"

cat > payments/client.py <<'EOF'
"""Payments API client."""
import os

API_URL = "https://payments.internal.example/v1"


def auth_headers():
    return {"Authorization": "Bearer " + os.environ["PAYMENTS_TOKEN"]}
EOF
cat > .env.example <<'EOF'
# Copy to .env and fill in.
PAYMENTS_TOKEN=changeme
EOF
printf '.env\n__pycache__/\n' > .gitignore
git add -A && git commit -qm "Read the payments token from the environment"

cat > tests/test_client.py <<'EOF'
import os
import unittest

from payments.client import auth_headers
from payments.verify import verify


class ClientTest(unittest.TestCase):
    def test_auth_header(self):
        os.environ["PAYMENTS_TOKEN"] = "test-token-not-real"
        self.assertEqual(auth_headers(), {"Authorization": "Bearer test-token-not-real"})

    def test_verify_rejects_other_data(self):
        self.assertFalse(verify(b"not the release"))
EOF
git add -A && git commit -qm "Add tests"
