import unittest

from app import metrics
from app.users import api


class Api(unittest.TestCase):
    def test_lookup(self):
        self.assertEqual(api.load_user(1)["name"], "Ada")

    def test_missing(self):
        with self.assertRaises(KeyError):
            api.load_user(99)

    def test_metric_name_is_stable(self):
        before = metrics.COUNTS.get("fetch_user", 0)
        api.load_user(2)
        self.assertEqual(metrics.COUNTS["fetch_user"], before + 1)

    def test_list(self):
        self.assertEqual([u["id"] for u in api.list_users()], [1, 2])


if __name__ == "__main__":
    unittest.main()
