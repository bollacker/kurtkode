import unittest

from parcel.quote import quick_quote


class QuoteTest(unittest.TestCase):
    def test_both_options(self):
        self.assertEqual(quick_quote(0.5, "domestic"), {"standard": 5.6, "express": 9.3})
