# Reference README: facts taken from the code, every command run.
cat > README.md <<'MD'
# tally

A small command-line expense tracker with monthly budgets. Python 3 standard library only; nothing to install.

## Quick start

```sh
python3 tally.py add 12.50 groceries --note "milk and bread"
python3 tally.py add 40 transport
python3 tally.py budget groceries 200
python3 tally.py report
python3 tally.py check
```

```text
groceries         12.50
transport         40.00
total             52.50
```

## Commands

| Command | Arguments | What it does |
|---|---|---|
| `add AMOUNT CATEGORY [--note TEXT] [--date YYYY-MM-DD]` | amount first | records an expense (date defaults to today) |
| `report [--month YYYY-MM]` | | totals per category for a month (default: this month) |
| `budget CATEGORY AMOUNT` | category first | sets the monthly budget for a category |
| `check` | | compares this month's spending with every budget |

Amounts are written like `12` or `12.50` (no currency sign). Note the argument order: `add` takes the amount
first, `budget` takes the category first.

```sh
python3 tally.py add 8.20 groceries --date 2026-01-15
python3 tally.py report --month 2026-01
```

## Where data is stored

In `tally.db` in the current directory. Set `TALLY_DB` to use another file:

```sh
TALLY_DB=household.db python3 tally.py add 3 coffee
TALLY_DB=household.db python3 tally.py report
```

## Exit codes

- `0`: success.
- `1`: `report` found no expenses for the month (it prints "no expenses in YYYY-MM").
- `2`: bad arguments (for example an amount like `$12`).
- `3`: `check` found at least one category over its budget (it prints `OVER` lines).

```sh
python3 tally.py budget transport 10
python3 tally.py check || echo "check exited with $?"
```
MD
