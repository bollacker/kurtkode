class UserIndex:
    """Stable pseudonyms (u1, u2, ...) for user names, numbered in order of first appearance."""

    def __init__(self):
        self._names = []

    def pseudonym(self, name):
        try:
            i = self._names.index(name)
        except ValueError:
            self._names.append(name)
            i = len(self._names) - 1
        return f"u{i + 1}"

    def __len__(self):
        return len(self._names)
