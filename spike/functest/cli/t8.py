from drive import *
import subprocess
# Every way out leaves the terminal as it was: same stty, cursor shown, bracketed paste off.
m, log = mock(18160, [{"bash": "sleep 20"}, {"text": "done"}])
def run(name, leave, during_run=False):
    tag = name.replace(" ", "-"); before, after = f"{HERE}/stty-{tag}-before", f"{HERE}/stty-{tag}-after"
    cmd = " ".join(repr(x) for x in [BIN] + args(18160, "--mode", "auto"))
    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(CFFIXED_USER_HOME=HERE + "/home", TERM="xterm-256color", KURTKODE_NO_KEYCHAIN="1")
        os.chdir(HERE + "/proj")
        os.execv("/bin/bash", ["bash", "--norc", "-c", f"stty -a > {before}; {cmd}; echo exit-$?; stty -a > {after}; echo finished"])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
    raw = b""
    def pump(t):
        nonlocal raw
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: d = os.read(fd, 65536)
                except OSError: return
                if not d: return
                raw += d
    pump(1.5)
    if during_run: os.write(fd, b"go\r"); pump(2)
    kid = subprocess.run(["pgrep", "-P", str(pid), "-x", "kurtkode"], capture_output=True, text=True).stdout.split()
    leave(fd, int(kid[0]) if kid else None); pump(2.5)
    for _ in range(100):
        if b"finished" in raw: break
        pump(0.1)
    if b"finished" not in raw:
        os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0); check(name + ": ends", False, raw[-300:]); return
    os.waitpid(pid, 0)
    same = open(before).read() == open(after).read()
    tail = raw[raw.rfind(b"exit-") - 200:]
    check(name + ": stty as it was", same, subprocess.run(["diff", before, after], capture_output=True, text=True).stdout)
    if b"\x1b[?25l" in raw: check(name + ": cursor shown", raw.rfind(b"\x1b[?25h") > raw.rfind(b"\x1b[?25l"), tail)
    if b"\x1b[?2004h" in raw: check(name + ": bracketed paste off", raw.rfind(b"\x1b[?2004l") > raw.rfind(b"\x1b[?2004h"), tail)
    print("     ", re.search(rb"exit-\d+", raw)[0].decode())
def keys(*ks):
    def f(fd, kid):
        for k in ks: os.write(fd, k.encode()); time.sleep(0.2)
    return f
def sig(n):
    def f(fd, kid): os.kill(kid, n)
    return f
run("ctrl-d", keys(CTRLD)); run("exit", keys("/exit" + ENTER)); run("ctrl-c twice", keys(CTRLC, CTRLC))
def sig2(s):
    def go(fd, pid):
        os.kill(pid, s); time.sleep(0.3); os.kill(pid, s)
    return go
# One SIGINT at the prompt only says how to leave: two within 2 seconds leave.
run("sigterm idle", sig(signal.SIGTERM)); run("sigint twice idle", sig2(signal.SIGINT)); run("sighup idle", sig(signal.SIGHUP))
def stop_then_quit(fd, kid):
    # The first stops the run, and any more while it stops only ask the same: quitting takes two at the prompt.
    os.write(fd, CTRLC.encode()); time.sleep(6); os.write(fd, CTRLC.encode()); time.sleep(0.2); os.write(fd, CTRLC.encode())
run("sigterm in a run", sig(signal.SIGTERM), True)
stop(m); m, log = mock(18160, [{"bash": "sleep 20"}, {"text": "done"}])
run("ctrl-c to stop, then twice to quit", stop_then_quit, True)
# Crashes: atexit doesn't run, the signal handler does (T15).
run("sigquit", sig(signal.SIGQUIT)); run("sigabrt", sig(signal.SIGABRT)); run("sigsegv", sig(signal.SIGSEGV))
stop(m); summary()
