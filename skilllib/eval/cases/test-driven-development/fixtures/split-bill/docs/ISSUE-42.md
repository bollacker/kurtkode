# ISSUE-42: split a bill between flatmates by weight

When one person pays a bill, the app needs each flatmate's share. Shares are weighted (someone with the big room
pays weight 2, the others weight 1).

Add `split_bill(total_cents, weights)` in `ledger/split.py`. It returns a list of integer cents, one per weight, in
the same order.

Rules:

1. The shares add up to `total_cents` exactly. No cent is lost or invented.
2. Each share is the exact proportional amount `total_cents * w / sum(weights)` rounded down, plus at most one
   extra cent.
3. The cents left over after rounding down go one each to the shares with the largest remainders (the largest
   fractional parts that were cut off). When remainders are equal, the earlier position in the list gets the cent.
4. A weight of 0 is allowed and always gets 0.
5. Raise `ValueError` when: `weights` is empty; any weight is negative; all weights are 0; `total_cents` is negative;
   `total_cents` is not an integer (e.g. 10.5).

Examples:

- `split_bill(100, [1, 1, 1])` -> `[34, 33, 33]`
- `split_bill(1000, [2, 1, 1])` -> `[500, 250, 250]`
- `split_bill(0, [1, 2])` -> `[0, 0]`
