# quick look at what slugify does with the titles from the bug report
from textutil import slugify

for t in ["  Hello, World! ", "C++ -- tips", "--draft--"]:
    print(repr(t), "->", repr(slugify(t)))
