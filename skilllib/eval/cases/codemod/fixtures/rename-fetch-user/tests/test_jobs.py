import unittest

from app import log
from app.cache import prefetch_users
from app.jobs.import_job import import_partner_users
from app.jobs.nightly import nightly_check
from app.remote.client import RemoteClient
from legacy.sync import stale_names


class Jobs(unittest.TestCase):
    def test_import(self):
        client = RemoteClient({1: {"name": "Ada"}, 2: {"name": "L. T."}})
        self.assertEqual(import_partner_users(client, [1, 2]), [2])
        self.assertIn("fetch_user mismatch for 2", log.LINES)

    def test_nightly(self):
        self.assertEqual(nightly_check([1, 9]), 1)
        self.assertIn("fetch_user failed for 9", log.LINES)

    def test_cache_and_legacy(self):
        self.assertEqual(prefetch_users([1, 2]), 2)
        self.assertEqual(stale_names(), ["c-1"])


if __name__ == "__main__":
    unittest.main()
