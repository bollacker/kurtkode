"""Summary statistics for lists of numbers."""


def mean(xs):
    if not xs:
        raise ValueError("mean of an empty list")
    return sum(xs) / len(xs)
