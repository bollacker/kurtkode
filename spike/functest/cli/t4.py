from drive import *
import subprocess
# A real repository OUTSIDE the temp folders, or the sandbox would allow what it shouldn't and prove nothing.
R = os.path.expanduser("~/git/kurtkode-friction/AgentCore/.build/kk-t4")
subprocess.run(f"rm -rf {R}; mkdir -p {R}/proj && cd {R}/proj && git init -q -b main && git config user.email t@t && git config user.name t && echo one > a.txt && git add . && git commit -qm first && git init -q --bare ../remote.git && git remote add origin ../remote.git && git push -q -u origin main", shell=True, check=True)
HERE_PROJ = R + "/proj"
class Here(App):
    def __init__(s, args, cwd, rows=24, cols=120):
        s.term = Term(rows, cols); s.raw = b""
        s.pid, s.fd = pty.fork()
        if s.pid == 0:
            os.environ.update(CFFIXED_USER_HOME=HERE + "/home", TERM="xterm-256color", KURTKODE_NO_KEYCHAIN="1"); os.environ.pop("NO_COLOR", None)
            os.chdir(cwd); os.execv(BIN, [BIN] + args)
        fcntl.ioctl(s.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0)); s.status = None
env = dict(ISOLATED)
def kk(*a):
    return subprocess.run([BIN, *a], cwd=HERE_PROJ, env=env, capture_output=True, text=True, timeout=30)
check("no worktrees to start", "No worktrees" in kk("worktree", "list").stdout)
m, log = mock(18110, [
  {"tool": "write_file", "args": {"path": "b.txt", "content": "from the session\n"}},
  {"bash": "git add b.txt && git -c user.email=t@t -c user.name=t commit -qm 'sandboxed commit' && git log --oneline | wc -l"},
  {"text": "committed in the worktree"}, 
  {"calls": [["task", {"description": "Add c", "prompt": "Add c.txt", "agent": "general", "isolation": "worktree"}]]},
  {"tool": "write_file", "args": {"path": "c.txt", "content": "from a subagent\n"}},
  {"text": "Added c.txt."}, {"text": "all done"}])
a = Here([x for x in args(18110, "--mode", "auto", "--sandbox", "always", "-w", "feature one") if x != "--no-subagents"], HERE_PROJ)
check("session starts in the worktree", a.wait(r"feature-one", 8), a.term.screen())
a.wait(r"Full Auto")
a.send("write and commit" + ENTER)
check("sandboxed commit in a worktree works", a.wait(r"committed in the worktree", 15, "all"), a.term.all()[-500:])
ti = a.term.all(); check("no sandbox denial", "not permitted" not in ti and "sandbox blocked" not in ti, ti[-500:])
a.gone(r"esc to stop"); a.pump(0.3)
log_main = subprocess.run("git log --oneline main | wc -l; git log --oneline kk/feature-one | wc -l", shell=True, cwd=HERE_PROJ, capture_output=True, text=True).stdout.split()
check("the commit is on the worktree's branch only", log_main == ["1", "2"], log_main)
check("the main checkout is untouched", not os.path.exists(HERE_PROJ + "/b.txt"))
a.send("/status" + ENTER); check("/status says it's a worktree", a.wait(r"\(a worktree\)", 5, "all"), a.term.all()[-400:])
a.send("/worktrees" + ENTER); check("/worktrees lists it", a.wait(r"feature-one +kk/feature-one", 5, "all"), a.term.all()[-400:])
a.send("/diff branch main" + ENTER); check("/diff against the branch's start", a.wait(r"added b\.txt", 5, "all"), a.term.all()[-300:])
a.gone(r"esc to stop")
a.send("delegate to the side" + ENTER)
check("isolated subagent reports", a.wait(r"all done", 20, "all"), a.term.all()[-700:])
a.gone(r"esc to stop"); a.pump(0.5)
br = subprocess.run("git branch --list 'kk/task-*'", shell=True, cwd=HERE_PROJ, capture_output=True, text=True).stdout.strip()
check("its work is on a branch", br.startswith("kk/task-") or "kk/task-" in br, br)
show = subprocess.run(f"git show {br.strip(' *+')}:c.txt", shell=True, cwd=HERE_PROJ, capture_output=True, text=True).stdout
check("the branch has the file", show == "from a subagent\n", show)
check("its worktree is gone", "task-" not in subprocess.run("git worktree list", shell=True, cwd=HERE_PROJ, capture_output=True, text=True).stdout)
check("not in this session's checkout", not os.path.exists(HERE_PROJ + "/.worktrees/feature-one/c.txt"))
a.send(CTRLD); a.exit_code()
stop(m)
r = kk("worktree", "list"); check("worktree list from the CLI", "feature-one" in r.stdout, r.stdout + r.stderr)
# The subagent's branch started from this worktree's HEAD, so it holds the same commits: without it they're on no other branch.
subprocess.run(f"git branch -qD {br.strip(' *+')}", shell=True, cwd=HERE_PROJ)
r = kk("worktree", "remove", "feature-one", "--delete-branch"); check("won't delete a branch with unmerged commits", r.returncode == 1 and "on no other branch" in r.stdout, r.stdout)
r = kk("worktree", "remove", "feature-one"); check("removes the worktree", r.returncode == 0 and "stays" in r.stdout, r.stdout + r.stderr)
check("its branch stays", "kk/feature-one" in subprocess.run("git branch", shell=True, cwd=HERE_PROJ, capture_output=True, text=True).stdout)
st = subprocess.run("git status --short", shell=True, cwd=HERE_PROJ, capture_output=True, text=True).stdout
check("main checkout shows nothing", st == "", st)
subprocess.run(f"rm -rf {R}", shell=True)
summary()
