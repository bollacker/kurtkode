import unittest
from inventory.models import Inventory, Item


class TestInventory(unittest.TestCase):
    def test_receive_and_ship(self):
        inv = Inventory()
        inv.add(Item("A1", "bolt", 0.5))
        inv.receive("A1", 10)
        inv.ship("A1", 4)
        self.assertEqual(inv.items["A1"].stock, 6)

    def test_value(self):
        inv = Inventory()
        inv.add(Item("A1", "bolt", 0.5, stock=4))
        self.assertAlmostEqual(inv.value(), 2.0)


if __name__ == "__main__":
    unittest.main()
