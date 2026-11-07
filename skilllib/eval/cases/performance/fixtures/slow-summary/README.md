# logsum

Nightly per-endpoint summary of our access logs: `python3 -m logsum access.log > summary.json`.
Python 3, standard library only.

`python3 tools/make_log.py 20000 8000 > big.log` writes a synthetic log (20k lines, 8k users) for trying changes;
production logs are about ten times bigger.
