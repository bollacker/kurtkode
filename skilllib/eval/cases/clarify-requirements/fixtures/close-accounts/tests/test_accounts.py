import unittest

from accounts import db, orders, users


class AccountsTest(unittest.TestCase):
    def setUp(self):
        self.conn = db.connect()
        db.init_db(self.conn)
        self.ana = users.create_user(self.conn, "Ana@Example.com", "Ana Diaz")
        self.bo = users.create_user(self.conn, "bo@example.com", "Bo Chen")
        orders.add_order(self.conn, self.ana, 1250, "2026-09-03")
        orders.add_order(self.conn, self.bo, 800, "2026-09-20")
        orders.add_order(self.conn, self.bo, 500, "2026-10-01")

    def test_find_is_case_insensitive(self):
        self.assertEqual(users.find_user(self.conn, "ana@example.COM")["id"], self.ana)

    def test_list_users(self):
        self.assertEqual([u["email"] for u in users.list_users(self.conn)], ["ana@example.com", "bo@example.com"])

    def test_revenue_by_month(self):
        self.assertEqual(orders.revenue(self.conn, "2026-09"), 2050)
        self.assertEqual(orders.revenue(self.conn, "2026-10"), 500)


if __name__ == "__main__":
    unittest.main()
