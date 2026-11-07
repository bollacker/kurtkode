"""Run inside the project: prints the app's outputs on fixed inputs as JSON (and the textkit version in use)."""
import json, os, sys
sys.path.insert(0, os.getcwd())
import blog  # noqa
import textkit
from blog.feed import feed_item, tag_url
from blog.posts import excerpt, post_url, reading_minutes

long_html = ("<h1>Why we moved</h1><p>After <em>six years</em> on the old host we finally moved the whole site, "
             "images and all, to a static generator that we wrote ourselves over a long weekend.</p>")
post = {"title": "A Very Long Title About Moving A Blog To A Static Site Generator Over One Weekend",
        "date": "2024-11-30", "html": long_html, "tags": ["Static Sites", "Python 3", "meta"]}
out = {
    "version": textkit.__version__,
    "url": [post_url("Hello World: Part 2", "2024-05-01"), post_url("  C'est la vie!  ", "2019-02-03")],
    "tags": [tag_url("Machine Learning"), tag_url("web-dev"), tag_url("Python")],
    "excerpt": [excerpt(long_html), excerpt(long_html, 25), excerpt("<p>Short <b>post</b>.</p>")],
    "minutes": [reading_minutes("<p>" + "word " * 650 + "</p>"), reading_minutes(long_html)],
    "feed": feed_item(post),
}
print(json.dumps(out, sort_keys=True, ensure_ascii=False))
