# Reference: unicode slugs, the archive keeps ASCII names by transliterating, both test folders run, DONE.md written.
cat > blogkit/slug.py <<'PY'
import re
import unicodedata


def slugify(title):
    """'Hello, World!' -> 'hello-world', 'Café crème' -> 'café-crème'. Letters and digits from any language are kept
    (lowercased); runs of anything else become one dash; no dashes at the ends."""
    s = title.lower()
    s = "".join(c if c.isalnum() and c != "_" else " " for c in s)
    return re.sub(r"\s+", "-", s.strip())


def ascii_slugify(title):
    """Like slugify, but plain ASCII: accents dropped ('Café' -> 'cafe'), other non-ASCII letters removed."""
    plain = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode("ascii")
    return slugify(plain)
PY
python3 - <<'PY'
p = "blogkit/export.py"
s = open(p).read()
s = s.replace("from .slug import slugify", "from .slug import ascii_slugify")
s = s.replace('base = slugify(post["title"])', 'base = ascii_slugify(post["title"])')
open(p, "w").write(s)
p = "tests/unit/test_slug.py"
s = open(p).read()
s = s.replace("    def test_nothing_left(self):", """    def test_unicode_letters_kept(self):
        self.assertEqual(slugify("Café crème"), "café-crème")

    def test_nothing_left(self):""")
open(p, "w").write(s)
PY
make check >/dev/null 2>&1 || exit 1
cat > DONE.md <<'MD'
slugify keeps letters and digits from any language. The print archive needs ASCII file names (tests/integration),
so export.py now uses a new ascii_slugify (accents dropped). Checked with `make check` (unit and integration): all pass.
MD
