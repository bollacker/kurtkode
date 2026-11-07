import json
import os

from .slug import slugify


def export_archive(posts, outdir):
    """Write one <name>.md file per post plus index.json into outdir. Returns the file names, in post order.
    The print shop's upload server rejects file names that aren't plain ASCII."""
    os.makedirs(outdir, exist_ok=True)
    names = []
    for post in posts:
        base = slugify(post["title"]) or "untitled"
        name = f"{post['date']}-{base}.md"
        n = 2
        while name in names:
            name = f"{post['date']}-{base}-{n}.md"
            n += 1
        with open(os.path.join(outdir, name), "w", encoding="utf-8") as f:
            f.write(f"# {post['title']}\n\n{post['body']}\n")
        names.append(name)
    with open(os.path.join(outdir, "index.json"), "w", encoding="utf-8") as f:
        json.dump([{"file": n, "title": p["title"]} for n, p in zip(names, posts)], f, ensure_ascii=False, indent=1)
    return names
