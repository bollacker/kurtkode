import os
import unittest

from store.customers import load_customers

DATA = os.path.join(os.path.dirname(__file__), "data")


class CustomersTest(unittest.TestCase):
    def test_loads_every_customer(self):
        customers = load_customers(os.path.join(DATA, "customers.csv"))
        self.assertEqual(sorted(customers), ["C001", "C002", "C003", "C004"])
        self.assertEqual(customers["C003"].email, "accounts@crane.example")
