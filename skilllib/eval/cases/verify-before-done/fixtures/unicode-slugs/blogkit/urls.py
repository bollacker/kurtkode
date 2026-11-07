from .slug import slugify


def post_url(post):
    """/posts/2024/05/my-title/"""
    return f"/posts/{post['date'][:4]}/{post['date'][5:7]}/{slugify(post['title'])}/"
