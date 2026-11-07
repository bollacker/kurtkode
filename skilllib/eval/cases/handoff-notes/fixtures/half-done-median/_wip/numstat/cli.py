"""Print statistics for the numbers in a file (one per line)."""
import argparse
import sys

from numstat.stats import mean, median


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("file")
    ap.add_argument("--mean", action="store_true", help="print the arithmetic mean")
    ap.add_argument("--median", action="store_true", help="print the median")
    a = ap.parse_args(argv)
    with open(a.file) as f:
        xs = [float(line) for line in f if line.strip()]
    if a.mean:
        print(f"mean {mean(xs):g}")
    if a.median:
        print(f"median {median(xs):g}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
