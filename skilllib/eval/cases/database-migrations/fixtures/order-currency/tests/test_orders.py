import os, subprocess, sys, tempfile, unittest

from app.orders import connect, create_order, customer_orders

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class TestOrders(unittest.TestCase):
    def setUp(self):
        self.db = os.path.join(tempfile.mkdtemp(), "test.db")
        subprocess.run([sys.executable, os.path.join(ROOT, "migrate.py"), "--db", self.db, "up"], check=True,
                       capture_output=True)
        self.conn = connect(self.db)
        self.conn.execute("INSERT INTO customers (id, email, name) VALUES (1, 'a@x.org', 'A')")

    def test_create_order_totals_items(self):
        oid = create_order(self.conn, 1, [("MUG", 2, 1500), ("TEA", 1, 500)])
        self.assertEqual(customer_orders(self.conn, 1), [(oid, 3500)])

    def test_unknown_customer_rejected(self):
        with self.assertRaises(Exception):
            create_order(self.conn, 99, [("MUG", 1, 1500)])
