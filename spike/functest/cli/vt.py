"""A small terminal: enough of VT100 to see what a screen shows, with scrollback."""
import re
class Term:
    def __init__(s, rows=24, cols=100):
        s.rows, s.cols = rows, cols; s.grid = [[" "]*cols for _ in range(rows)]; s.r = s.c = 0; s.back = []; s.wrap = False; s.modes = {}
    def scroll(s):
        s.back.append("".join(s.grid[0]).rstrip()); s.grid = s.grid[1:] + [[" "]*s.cols]
    def nl(s):
        if s.r == s.rows-1: s.scroll()
        else: s.r += 1
    def put(s, ch):
        if s.wrap: s.c = 0; s.nl(); s.wrap = False
        s.grid[s.r][s.c] = ch
        if s.c == s.cols-1: s.wrap = True
        else: s.c += 1
    def feed(s, data):
        i = 0
        while i < len(data):
            ch = data[i]
            if ch == "\x1b":
                m = re.match(r"\x1b\[([?0-9;]*)([A-Za-z~])", data[i:])
                if not m:
                    i += 2 if i+1 < len(data) else 1
                    continue
                p, f = m.groups(); i += m.end()
                n = int(p.split(";")[0]) if p and p[0].isdigit() else 1
                s.wrap = False if f in "ABCDGHJ" else s.wrap
                if f == "A": s.r = max(0, s.r-n)
                elif f == "B": s.r = min(s.rows-1, s.r+n)
                elif f == "C": s.c = min(s.cols-1, s.c+n)
                elif f == "D": s.c = max(0, s.c-n)
                elif f == "J":
                    for c in range(s.c, s.cols): s.grid[s.r][c] = " "
                    for r in range(s.r+1, s.rows): s.grid[r] = [" "]*s.cols
                elif f == "K":
                    for c in range(s.c, s.cols): s.grid[s.r][c] = " "
                elif f in "hl" and p.startswith("?"): s.modes[p] = f == "h"
                continue
            if ch == "\r": s.c = 0; s.wrap = False
            elif ch == "\n": s.nl()     # the pty turned \n into \r\n already
            elif ch == "\x07": pass
            elif ch == "\b": s.c = max(0, s.c-1)
            elif ord(ch) >= 32: s.put(ch)
            i += 1
    def screen(s): return "\n".join("".join(r).rstrip() for r in s.grid).rstrip()
    def all(s): return "\n".join(s.back) + "\n" + s.screen()
