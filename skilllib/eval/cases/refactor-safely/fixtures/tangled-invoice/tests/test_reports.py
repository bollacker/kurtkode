import unittest

from shop.reports import monthly_revenue


class Reports(unittest.TestCase):
    def test_empty_month(self):
        self.assertEqual(monthly_revenue([]), 0)


if __name__ == "__main__":
    unittest.main()
