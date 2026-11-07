import os
import unittest

from store.customers import load_customers
from store.invoice import invoice_total
from store.products import load_products

DATA = os.path.join(os.path.dirname(__file__), "data")


class InvoiceTest(unittest.TestCase):
    def setUp(self):
        self.customers = load_customers(os.path.join(DATA, "customers.csv"))
        self.prices = load_products(os.path.join(DATA, "products.csv"))

    def test_us_customer_pays_no_tax(self):
        self.assertEqual(invoice_total(self.customers["C002"], [(2, self.prices["P-1"])]), 50.0)

    def test_eu_customer_gets_vat(self):
        self.assertEqual(invoice_total(self.customers["C001"], [(4, self.prices["P-1"])]), 121.0)
