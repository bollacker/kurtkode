import unittest

from depot import audit
from depot.stock import OutOfStock, Warehouse, transfer


class StockTest(unittest.TestCase):
    def setUp(self):
        audit.clear()
        self.east = Warehouse("east", {"lamp": 5})
        self.west = Warehouse("west", {"lamp": 1})

    def test_reserve_takes_units(self):
        self.east.reserve("lamp", 2)
        self.assertEqual(self.east.available("lamp"), 3)

    def test_cannot_reserve_more_than_available(self):
        with self.assertRaises(OutOfStock):
            self.east.reserve("lamp", 6)
        self.assertEqual(self.east.available("lamp"), 5)

    def test_restock_adds_units(self):
        self.west.restock("lamp", 4)
        self.assertEqual(self.west.available("lamp"), 5)

    def test_transfer_moves_units(self):
        transfer(self.east, self.west, "lamp", 3)
        self.assertEqual((self.east.available("lamp"), self.west.available("lamp")), (2, 4))

    def test_every_movement_is_audited(self):
        transfer(self.east, self.west, "lamp", 1)
        self.assertEqual([e["event"] for e in audit.entries()], ["reserve", "restock"])
