# Reference: the tests written first (one per rule of ISSUE-42), then the implementation that makes them pass.
cat > tests/test_split.py <<'PY'
import unittest

from ledger.split import split_bill


class SplitBill(unittest.TestCase):
    def test_issue_examples(self):
        self.assertEqual(split_bill(100, [1, 1, 1]), [34, 33, 33])
        self.assertEqual(split_bill(1000, [2, 1, 1]), [500, 250, 250])
        self.assertEqual(split_bill(0, [1, 2]), [0, 0])

    def test_shares_add_up(self):
        for total, weights in [(7, [3, 1, 1]), (101, [1, 2, 3, 4]), (1, [1, 1, 1])]:
            with self.subTest(total=total, weights=weights):
                self.assertEqual(sum(split_bill(total, weights)), total)

    def test_leftover_goes_to_largest_remainder_not_first_or_heaviest(self):
        # 7 * [3,1,1] / 5 = 4.2, 1.4, 1.4 -> remainders .2 .4 .4 -> the cent goes to position 1 (tie: earlier)
        self.assertEqual(split_bill(7, [3, 1, 1]), [4, 2, 1])
        # 100 * [1,2] / 3 = 33.3, 66.7 -> the larger remainder is the second share
        self.assertEqual(split_bill(100, [1, 2]), [33, 67])

    def test_tie_goes_to_earlier_position(self):
        self.assertEqual(split_bill(1, [1, 1]), [1, 0])

    def test_zero_weight_gets_zero_and_keeps_its_place(self):
        self.assertEqual(split_bill(5, [0, 1, 0, 1]), [0, 3, 0, 2])

    def test_errors(self):
        for total, weights in [(10, []), (10, [3, -1]), (10, [0, 0]), (-1, [1]), (10.5, [1, 1])]:
            with self.subTest(total=total, weights=weights), self.assertRaises(ValueError):
                split_bill(total, weights)


if __name__ == "__main__":
    unittest.main()
PY
cp "$CASE_DIR/hidden/split_ref.py" ledger/split.py
python3 -m unittest -q >/dev/null 2>&1
