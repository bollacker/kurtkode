# Reference: profiling shows list.index in UserIndex.pseudonym dominates (O(distinct users) per line). A dict from
# name to number keeps first-appearance order, so the pseudonyms and the report stay identical.
cat > logsum/users.py <<'PY'
class UserIndex:
    """Stable pseudonyms (u1, u2, ...) for user names, numbered in order of first appearance."""

    def __init__(self):
        self._numbers = {}

    def pseudonym(self, name):
        i = self._numbers.setdefault(name, len(self._numbers))
        return f"u{i + 1}"

    def __len__(self):
        return len(self._numbers)
PY
