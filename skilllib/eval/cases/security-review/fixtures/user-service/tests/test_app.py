import unittest

from app import db, files


class AppTest(unittest.TestCase):
    def setUp(self):
        self.conn = db.connect()
        db.add_user(self.conn, "alice", "alice@example.com", "2026-01-02")
        db.add_user(self.conn, "bob", "bob@example.com", "2026-03-04")
        db.add_user(self.conn, "root", "root@example.com", "2025-01-01", is_admin=True)

    def test_list_sorted_by_join_date(self):
        self.assertEqual([n for _, n in db.list_users(self.conn, "joined")], ["alice", "bob"])

    def test_search(self):
        self.assertEqual(db.search_users(self.conn, "li"), [(1, "alice")])

    def test_report(self):
        self.assertIn(b"signups", files.read_report("2026-09.txt"))

    def test_bad_report_name(self):
        with self.assertRaises(ValueError):
            files.read_report("../secrets.txt")
