from drive import *
import glob, subprocess
# Real files through read_file. cupsfilter makes real PDFs (Quartz) from text; a real photo comes from macOS.
P = HERE + "/proj"
def pdf(name, lines):
    open(f"{HERE}/{name}.txt", "w").write("\n".join(f"{name} line {i} of the document" for i in range(1, lines + 1)))
    with open(f"{P}/{name}.pdf", "wb") as f:
        subprocess.run(["cupsfilter", f"{HERE}/{name}.txt"], stdout=f, stderr=subprocess.DEVNULL, check=True)
pdf("small", 5); pdf("many", 6000)
open(P + "/locked.pdf", "wb").write(b"%PDF-1.4\nthis is not really a PDF\n")
photo = sorted(glob.glob("/System/Library/Desktop Pictures/*.heic") + glob.glob("/System/Library/CoreServices/*.heic"))
if photo: subprocess.run(["cp", photo[0], P + "/photo.heic"], check=True)
big_png = P + "/big.png"
if photo: subprocess.run(["sips", "-s", "format", "png", "-Z", "3000", P + "/photo.heic", "--out", big_png], capture_output=True)
read = lambda path, **more: {"tool": "read_file", "args": dict(path=path, **more)}
steps = [read("small.pdf"), read("many.pdf"), read("many.pdf", pages="2-3"), read("many.pdf", pages="9999"),
         read("locked.pdf"), read("photo.heic"), read("big.png"), {"text": "all read"}]
m, log = mock(18140, steps)
a = App(args(18140, "--mode", "auto"))
a.wait(r"Full Auto"); a.send("read them" + ENTER)
check("the run finishes", a.wait(r"all read", 40, "all"), a.term.all()[-500:])
a.gone(r"esc to stop"); a.send(CTRLD); a.exit_code(); stop(m)
reqs = [json.loads(l) for l in open(log)]
last = [r["last"] for r in reqs]
check("a one-page PDF's text", "--- page 1 of 1 ---" in last[1] and "small line 5" in last[1], last[1])
check("a long PDF is cut with a way on", "use pages to read on" in last[2] and "many line 1 " in last[2], last[2][-300:])
check("a range reads those pages", "--- page 2 of" in last[3] and "--- page 3 of" in last[3] and "--- page 1 of" not in last[3], last[3][:200])
check("past the end is said", "past the end" in last[4], last[4])
check("a damaged PDF is an error, not bytes", "can't be read" in last[5], last[5])
sizes = [(r["i"], len(r["last"])) for r in reqs]
print("request sizes", sizes)
if photo:
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "format", log + ".image"], capture_output=True, text=True).stdout
    w = int(re.search(r"pixelWidth: (\d+)", out)[1]); h = int(re.search(r"pixelHeight: (\d+)", out)[1])
    check("a big image goes out at most 1568 on its long side", max(w, h) <= 1568, out)
    check("the image sent is under 2 MB", os.path.getsize(log + ".image") < 2_000_000, os.path.getsize(log + ".image"))
    print("image sent", w, h, os.path.getsize(log + ".image"), "from", os.path.getsize(big_png))
summary()
