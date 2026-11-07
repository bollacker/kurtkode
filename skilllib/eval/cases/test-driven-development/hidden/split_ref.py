"""Split a bill by weight (ISSUE-42)."""


def split_bill(total_cents, weights):
    if isinstance(total_cents, bool):
        raise ValueError(f"total_cents must be a non-negative integer: {total_cents!r}")
    if not isinstance(total_cents, int) or total_cents < 0:
        raise ValueError(f"total_cents must be a non-negative integer: {total_cents!r}")
    if not weights:
        raise ValueError("no weights")
    if any(w < 0 for w in weights):
        raise ValueError(f"negative weight in {weights!r}")
    whole = sum(weights)
    if whole == 0:
        raise ValueError("all weights are zero")
    base = [total_cents * w // whole for w in weights]
    rema = [total_cents * w % whole for w in weights]
    left = total_cents - sum(base)
    order = sorted(range(len(weights)), key=lambda i: (-rema[i], i))
    for i in order[:left]:
        base[i] += 1
    return base
