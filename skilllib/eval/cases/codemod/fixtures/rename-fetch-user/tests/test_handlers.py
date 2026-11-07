import unittest
from unittest import mock

from app.handlers.partner_page import partner_page
from app.handlers.profile_page import profile_page
from app.handlers.show_user import show_user
from app.handlers.user_exists import user_exists
from app.handlers.user_list import user_list
from app.handlers.user_name import user_name


class Handlers(unittest.TestCase):
    def test_show_user_uses_lookup(self):
        with mock.patch("app.handlers.show_user.fetch_user", return_value={"id": 5}) as lookup:
            self.assertEqual(show_user(5), {"status": 200, "user": {"id": 5}})
        lookup.assert_called_once_with(5)

    def test_others(self):
        self.assertEqual(user_name(2), "Linus")
        self.assertTrue(user_exists(1))
        self.assertFalse(user_exists(3))
        self.assertEqual(len(user_list([1, 2])), 2)
        self.assertIn("Ada", profile_page(1))
        self.assertEqual(partner_page(7)["status"], 200)


if __name__ == "__main__":
    unittest.main()
