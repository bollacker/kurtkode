# numstat

Summary statistics for a file of numbers, one per line. Python 3, standard library only.

    python3 -m numstat.cli data.txt --mean

Options:

- `--mean`: print the arithmetic mean.

Before pushing, run the same checks as CI:

    python3 tools/check.py
