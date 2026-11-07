import sys

from .summary import summarize

if len(sys.argv) != 2:
    sys.exit("usage: python3 -m logsum ACCESS.LOG")
with open(sys.argv[1]) as f:
    print(summarize(f))
