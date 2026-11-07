# Reference upgrade: pin 2.0.0, then handle every breaking change in its CHANGELOG, including the two silent ones
# (slugify's default separator, truncate's width now counting the ellipsis).
sed -i.bak 's/^textkit 1.4.2$/textkit 2.0.0/' vendor.txt && rm vendor.txt.bak
python3 - <<'PY'
import re
p = "blog/posts.py"
s = open(p).read()
s = s.replace("from textkit import count_words, slugify, strip_tags, truncate",
              "from textkit import slugify, truncate, word_count\nfrom textkit.html import strip_tags")
s = s.replace("slugify(title)", 'slugify(title, sep="-")')
s = s.replace("truncate(strip_tags(html), width)", "truncate(strip_tags(html), width + 1)")
s = s.replace("count_words(", "word_count(")
open(p, "w").write(s)
p = "blog/feed.py"
s = open(p).read()
s = s.replace("slugify(tag)", 'slugify(tag, sep="-")')
s = s.replace('truncate(post["title"], 70)', 'truncate(post["title"], 71)')
open(p, "w").write(s)
PY
python3 -m unittest -q
