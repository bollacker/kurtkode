import unittest

from shop.search import lookup, search


class SearchTest(unittest.TestCase):
    def test_search(self):
        self.assertEqual(search(" gad "), [("B200", "Gadget")])

    def test_empty_term(self):
        self.assertEqual(search("  "), [])

    def test_lookup_unknown(self):
        self.assertIsNone(lookup("Z999"))
