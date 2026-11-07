import unittest
from shop.promotions import campaign_price


class TestPromotions(unittest.TestCase):
    def test_eur_campaign(self):
        self.assertEqual(campaign_price(100, "EUR", 10), 81.0)

    def test_jpy_campaign(self):
        self.assertEqual(campaign_price(2, "JPY", 50), 150.0)
