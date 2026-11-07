# Upcoming enhancements

Agreed with the user but not scheduled. Bigger planned work is in HANDOFF.md ("Next steps") and
SUBAGENTS_DESIGN.md ("Phases").

## Debug window

- **Trace values into subagent runs** (deferred from subagents phase 2, 2026-10-12). "Where did these values come
  from?" stops at a `task` result ("from task result, turn 2"). When the origin is a task result, load that run and
  search its entries the same way, so the answer names the run and the entry ("from grep result, turn 1, in the
  explore subagent"). The link opens the run (the existing drill-in) and selects and scrolls to that entry, which
  needs a target entry passed into the child's Journal. If the subagent reworded the value, say the trail ends at
  its report. Core: extend `SessionJournal.origin(of:before:)` with the session's runs; test it. About an hour plus
  a check in the app.

## Subagents

- **Wake on queued input while waiting for a background report** (deferred from subagents phase 5, 2026-10-12).
  When the main loop would finish but background subagents still run, it waits for the next report
  (`BackgroundRuns.waitForReport`); a message the user queues meanwhile is delivered only with that report. Wake
  on either: let the wait also return when `config.takeInput` has something (it can't be peeked today, so add a
  way to check without taking), then go on with the user's message and keep waiting for the report afterwards.
  Test: queue input during the wait and check it reaches the model before the report.

## Default model picker (2026-11-02)

- **Built, not seen.** Settings → Generation → Models picks the server for new chats and a model from that server's
  list (`DefaultModelPicker`), so a default can't name a model only another server has; one typed in is kept only
  when the server can't be listed. It compiles; it hasn't been looked at on screen or clicked.
- **The Endpoints tab's "Default for new chats" toggle** changes the server without fitting the model to it; the
  Generation tab then shows the model as missing there. Fit it there too, or drop the toggle for the picker.
- **No server chosen yet:** the Endpoints toggle shows This Mac as the default, `AppModel.defaultEndpoint` takes
  `endpoints[0]`. The same while This Mac is first in the list, which `EndpointStore.load` ensures only when it's
  missing.

## Round 8 (2026-10-31)

- **A nested repository still acts on the user's own git.** kurtkode's git is safe (`GitRepo.safeConfig`), but `git status`
  in a terminal, or a shell prompt that runs it, runs a `core.fsmonitor` a sandboxed command left in a nested repository or
  in `.git/modules`. Stopping that means refusing nested `.git/config`, which takes `git clone` and `git init` out of the
  sandbox. The user's call.
- **Plan mode's unreadable patterns and links**: a command reading `.env` when that's a link to an ordinary name gets the
  file, because Seatbelt sees the target. `read_file` and the rest refuse it.
- **A worktree's commands can move `main`'s ref.** Refs are open as a group; it's data, not code.
- **Unconfirmed**: C10 assumed Return submits a vertical `TextField`. The guard costs nothing if it doesn't.

## Real local models (2026-10-31)

- **A vision model on an opaque image**: `t11.py vision` hasn't had a clean run. The image reached gemma-4-e4b-it, which invented
  its reply, but that page was 77% transparent, so it proves nothing about reading. Retest with `label.png` when memory allows.
- **Transparent PNGs**: flatten them onto white before sending? A model may see black on black. Only worth doing if the retest
  bears that out.
- **`rate_task` with no subagent run**: qwen3-coder called it again and again after finishing, inventing task names. The error
  now says there's nothing to rate; the next step, if it comes back, is not to offer it until a subagent has run.
- **Small models wander off `read_file`**: asked to read a PDF, qwen3-coder once tried `web_fetch` on a parser's website.
  The sandbox's network setting stopped it at the approval.
- **The shell-scripts skill** had qwen3-coder write a script for a one-line `sleep`.

## Agent capabilities (2026-10-30)

- **A prompt typed during startup isn't sent**: typed before the terminal goes raw, it lands in the composer and Enter is lost,
  so it needs Enter again. Three attempts didn't move it (a poll at the reader's start, `FIONREAD` before raw, mapping the first
  read's newlines); read what actually arrives before trying a fourth.

- **`/goal` and `/loop`**: decide what limits them first. Both keep spending with nobody watching.
- **Ctrl-B**, moving a running command to the background: `BashTool.run` waits on `Subprocess`; it needs to hand the process
  and its output to `BackgroundCommands` while it runs.
- **MCP**: prompts as slash commands; OAuth login; image results (still a placeholder).
- **`web_fetch`**: a host that changes its address between the check and the connection isn't covered.
- **MCP**: a server's exit can be noticed before its last stderr is read, so "Stopped." can lack the reason (seen once under
  load, `aServerThatExitsIsMarkedFailedUntilRestarted`; an old race in `MCPClient`, not from this batch).

## Worktrees and review (2026-10-30)

- **Files a worktree doesn't get**: ignored files (`.env`, a build) aren't in a new worktree. Codex has `.worktreeinclude`.
- **Chats of a removed worktree** stay in the sidebar with a blocker saying the folder is gone; there's no way to file them.
- **A review in the Git bases**: Review works on the snapshot scopes only.
- **Conflicts**: Merge undoes itself and shows git's message; there's no help resolving them.

## CLI live screen (2026-10-30)

- **Try it in Terminal.app and iTerm2**: only a small emulator has seen it. Flicker, `?2026`, wide characters and a resize
  while wrapped (the block's rows re-wrap, so a redraw can leave a row behind) need real eyes.
- **Images**: LM Studio models count as not taking images (the CLI doesn't read its model list for that); Ctrl-V is
  untested with a real clipboard.
- **Syntax highlighting** in code blocks; tables are left as typed.
- **A full-screen mode** on the same `Frame`, if the inline block turns out to flicker.

## App friction (2026-10-30)

- **No escalation card on a run the user stopped.** Esc on a run with an open todo list offers a stronger model ("it left
  2 todos unfinished"): the user stopped it, nothing went wrong. Seen on a mock; from before this batch.
- **A fork's permission mode.** `AppModel.forkSession(_:before:)` gets the session as it is in memory, where a mode set
  during the session isn't kept (`controller.permissionMode` is), so a fork starts on the default: the safer side, but
  a surprise. Pass the controller's.
- **Approvals of a cut-off run** come back only as the model's next request, not as the card that was waiting (U5's
  other half).
- **Next, in the comparison's order:** the CLI's interaction layer (C6), worktree sessions and write-capable background
  subagents (C2), inline review comments and a diff base in Changes, `web_fetch` and images in `read_file` (B8), hooks
  and MCP depth (D2, D3), onboarding (C8).

## Phase 3 (session 16, 2026-10-26)

- **Round 7's noted items** (FUNCTIONAL_TEST_RESULTS.md "Round 7"): R7-5 edits made by the user or another session
  during a run count as the run's (a rewind reverts them); R7-25 a `/review` the user asks for isn't checked against
  the spending limits; R7-32 older builds skip the new record kinds and read lower spending; R7-36 a call kurtkode
  writes counts as a step and a task call in run stats; R7-37 no total cap on a large git project's first snapshot.
- **A7's threshold** is a fifth of the context, which large-context hosted models never reach: try a token threshold,
  measured on the delegation scenarios (`kurtkode-eval --kk-delegation both`).
- **Open a changed file at its line** in the user's editor from the Changes tab (needs an editor setting).
- **Click through** the rewind dialog's three choices and the Changes tab's checkpoint list in the app (built and
  unit-tested; not tried by hand).
