"""Summary statistics for lists of numbers."""


def mean(xs):
    if not xs:
        raise ValueError("mean of an empty list")
    return sum(xs) / len(xs)


def median(xs):
    if not xs:
        raise ValueError("median of an empty list")
    s = sorted(xs)
    return s[(len(s) - 1) // 2]
