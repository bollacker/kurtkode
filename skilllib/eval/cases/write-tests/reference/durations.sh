# Reference: tests aimed at each rule in the docstring, including both sides of every boundary.
cat > tests/test_durations.py <<'PY'
import unittest

from timeparse.durations import MAX_SECONDS, format_duration, parse_duration


class ParseDuration(unittest.TestCase):
    def test_single_units(self):
        self.assertEqual(parse_duration("2d"), 2 * 86400)
        self.assertEqual(parse_duration("3h"), 3 * 3600)
        self.assertEqual(parse_duration("4m"), 240)
        self.assertEqual(parse_duration("5s"), 5)

    def test_parts_add_up(self):
        self.assertEqual(parse_duration("1h30m"), 5400)
        self.assertEqual(parse_duration("1d1h1m1s"), 90061)

    def test_spaces_between_and_around(self):
        self.assertEqual(parse_duration("2d 4h"), 2 * 86400 + 4 * 3600)
        self.assertEqual(parse_duration("  5m  "), 300)

    def test_zero_is_valid(self):
        self.assertEqual(parse_duration("0s"), 0)

    def test_max_boundary(self):
        self.assertEqual(parse_duration("30d"), MAX_SECONDS)
        with self.assertRaises(ValueError):
            parse_duration("30d1s")

    def test_invalid(self):
        for text in ["", "   ", "h", "5", "5x", "1H", "-5m", "1.5h", "1h 2h", "30m1h", "1s1m"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_duration(text)


class FormatDuration(unittest.TestCase):
    def test_examples(self):
        self.assertEqual(format_duration(5400), "1h30m")
        self.assertEqual(format_duration(90061), "1d1h1m1s")
        self.assertEqual(format_duration(1), "1s")
        self.assertEqual(format_duration(86400), "1d")

    def test_zero(self):
        self.assertEqual(format_duration(0), "0s")

    def test_range(self):
        self.assertEqual(format_duration(MAX_SECONDS), "30d")
        for bad in (-1, MAX_SECONDS + 1):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                format_duration(bad)

    def test_round_trip(self):
        for s in (0, 1, 59, 60, 61, 3599, 3600, 86399, 86401, MAX_SECONDS - 1, MAX_SECONDS):
            with self.subTest(s=s):
                self.assertEqual(parse_duration(format_duration(s)), s)


if __name__ == "__main__":
    unittest.main()
PY
python3 -m unittest discover -s tests -t . >/dev/null 2>&1
