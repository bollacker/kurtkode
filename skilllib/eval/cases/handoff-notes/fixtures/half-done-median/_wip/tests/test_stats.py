import unittest

from numstat.stats import mean, median


class MeanTest(unittest.TestCase):
    def test_mean(self):
        self.assertEqual(mean([1, 2, 3, 4]), 2.5)

    def test_mean_empty(self):
        with self.assertRaises(ValueError):
            mean([])


class MedianTest(unittest.TestCase):
    def test_median_odd_count(self):
        self.assertEqual(median([3, 1, 2]), 2)

    def test_median_even_count(self):
        self.assertEqual(median([4, 1, 3, 2]), 2.5)

    def test_median_empty(self):
        with self.assertRaises(ValueError):
            median([])
