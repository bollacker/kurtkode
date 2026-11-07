# kurtkode: functional test suite

Written 2026-10-12 at the end of session 5, to run in session 6. Unit tests (`make test`, 223) check the pieces;
this suite checks the **whole app and CLI working as a user would use them**, end to end, on real models. Read
`HANDOFF.md` first (conventions, debug hooks, data locations), then run this file top to bottom.

## How to run it

- **Record results** in `FUNCTIONAL_TEST_RESULTS.md` (new file): one row per test: ID, result (pass / fail / partial /
  skipped), evidence (screenshot path, session id, numbers), notes. Fix nothing during the run unless a failure blocks
  later tests; list failures, then propose fixes to the user as options.
- **Drivers.** Accessibility isn't granted, so tests are marked by who drives them:
  - **H** (hooks): a Debug build launched with `open -n --env KURTKODE_…` (HANDOFF "Driving the app without clicks"),
    checked through the session JSONL, wire records, and window screenshots (`screencapture -l`).
  - **C** (CLI): `AgentCore/.build/debug/kurtkode` (or release), checked by output and session files; a Python pty for
    interactive features.
  - **U** (user): needs clicks or eyes; write the steps as a short checklist for the user and record what they report.
    Batch U tests into one or two sittings (sections 14 and 15).
- **Models** (use as they are; never load or unload without asking; check `lms ps` and free RAM first, stop below 25%):
  - **Local**: google/gemma-4-26b-a4b-qat on This Mac's LM Studio (left loaded at 64k, 1 slot).
  - **LAN**: the user's LM Studio at `http://192.168.1.20:1234/v1`, saved endpoint **"bang"**, qwen/qwen3.5-9b loaded
    (68k). No key.
  - **Mock**: `spike/mock_stream_server.py` (fixed replies, tool calls via `--bash`), `spike/fault_proxy.py` (drops
    calls): launch-only endpoints (`KURTKODE_EXTRA_ENDPOINT`, CLI `--endpoint`).
  - **OpenRouter**: only the tests marked **$**, and only after asking the user (models, trials, estimate, cap).
- **Hygiene**: test projects in the scratchpad (git init; the 8-file `lib/partN.py` demo with a class and "keeps N
  records" docstring in each, plus a small calc project with tests: `EvalKit/Fixtures.swift` has both). Stop only
  `/build/` app instances. Read, set, and restore any shared defaults a test needs (`showInspector`, `inspectorTab`,
  `chatFolder`). Test builds must **never read a Keychain key** (a prompt lands on the user's screen): no **$** test
  from a test build without asking, and if a SecurityAgent window appears, tell the user to click Deny. Afterwards move
  test sessions (`sessions/<project>-*`) and folders to the Trash as `kurtkode-test-s6-*`.
- **Time**: about 3–4 hours with local models; run the long ones (compaction, evals) in the background.

## 0. Build and smoke

| ID | Test | Drv | Expected |
|---|---|---|---|
| 0.1 | `make test` | C | 223+ pass, no failures |
| 0.2 | `make build`, `make release`, `make cli` | C | no warnings or errors |
| 0.3 | Launch the Debug app beside the user's | H | window opens, sidebar lists sessions; no hang-log stalls ≥250 ms at idle (`log show … category hang`) |
| 0.4 | `kurtkode --help`, `--version`, `inspect --help` | C | usage text includes inspect/replay/export |

## 1. Chat basics (plain chat, no project)

| ID | Test | Drv | Expected |
|---|---|---|---|
| 1.1 | Plain chat on Gemma: a two-line question | H | reply streams, Markdown and a fenced code block render; title set from the first line |
| 1.2 | Reasoning shown as "Thought for N tokens", expandable | H/U | reasoning stored on the message; collapsed by default |
| 1.3 | Stop mid-reply | U | stops within ~1 s; partial reply kept, marked stopped |
| 1.4 | Retry the last reply (`/retry`) | H | new reply replaces the old (old retracted in the JSONL) |
| 1.5 | `/rename New title`, `/help`, `/context`, `/clear` | H | title record; help lists built-ins incl. /agents; context shows tokens; /clear opens a new chat |
| 1.6 | Tools in plain chats (Settings → Chats on): "list the files you can see" | H | uses the chat working folder (`~/kurtkode` or a scratch `chatFolder`, restored after) |
| 1.7 | Reopen a session after quitting the test app | H | messages, title, model, mode restored (`KURTKODE_OPEN_SESSION`) |

## 2. Models and endpoints

| ID | Test | Drv | Expected |
|---|---|---|---|
| 2.1 | Model picker lists This Mac's and bang's models; switch to bang:qwen for one turn | H | turn's meta has bang's endpoint; next turn can switch back; `model` record written |
| 2.2 | LM Studio silent substitution warning: ask for a model id that isn't loaded on a server that substitutes | H | the app warns (reported model ≠ requested) |
| 2.3 | Models window: memory, loaded models, load/unload buttons visible | H (`KURTKODE_OPEN_WINDOW=models`) | shows Gemma loaded (64k, 1 slot); **don't** press load/unload |
| 2.4 | Settings → Endpoints: test message to bang | U | answers; nothing saved twice |
| 2.5 | Model browser sheet (`KURTKODE_OPEN_SHEET=browser`) opens fast | H | no stall ≥500 ms (was 61 s once) |
| 2.6 | Per-model profile (`KURTKODE_OPEN_SHEET=profile`): temperature and history shape apply | H | the next request's body shows the temperature (wire log) |
| 2.7 **$** | OpenRouter: one short turn on a cheap model; provider recorded; cost in meta | H | `provider` and `cost` set; Debug Overview shows them |

## 3. Agent tools and permission modes (project: calc demo)

| ID | Test | Drv | Expected |
|---|---|---|---|
| 3.1 | Full Auto: "find where add() is defined, fix the failing test, run the tests" | H | grep/read/edit/bash used; tests pass; todo list in the inspector |
| 3.2 | Ask mode: an edit asks for approval; `KURTKODE_AUTOAPPROVE=2` allows it | H | approval record (user, waited ~2 s) in the tool result |
| 3.3 | Ask mode, deny with feedback | U | model gets the feedback and adjusts |
| 3.4 | Accept Edits: edits run without asking, bash still asks | H/U | as stated |
| 3.5 | Plan mode: write tools not offered; model only reads and proposes | H | request's tools list has no edit/write/bash |
| 3.6 | "Always allow" a bash rule, then the same command again | U | second runs without asking; rule listed |
| 3.7 | Sandbox in Full Auto: `touch /tmp/x` ok, `touch ~/x-kk-test` blocked and reported, network off | H | blocked write reported in the result; nothing created in ~ |
| 3.8 | Rewind (`KURTKODE_REWIND_AFTER`) restores edited files and the message | H | files back to the checkpoint; messages after it retracted |
| 3.9 | Long bash output saved in full (`Open full output`) | H | `.outputs/` file exists, model saw head and tail |
| 3.10 | Repeated identical read is "not run" with the note | H | note on the tool result |

## 4. Folders

| ID | Test | Drv | Expected |
|---|---|---|---|
| 4.1 | Extra folder read-only (`KURTKODE_FOLDERS=/path:ro`): read ok, write denied (also in the sandbox) | H | read result; write refused |
| 4.2 | Extra folder read-write: edit there in Accept Edits | H | edit applied without asking |
| 4.3 | CLI `--add-dir` / `--read-dir` kept with the session (`-c` shows them) | C | folders record; banner lists them |

## 5. Composer

| ID | Test | Drv | Expected |
|---|---|---|---|
| 5.1 | Custom slash command in `.kurtkode/commands/x.md` with `$ARGUMENTS` | H | expanded prompt sent |
| 5.2 | `@lib/part3.py` mention attaches the file | H | attachment entry; model answers from it without a read |
| 5.3 | `!ls lib` runs, output shown, sent as context | H | userCommand message |
| 5.4 | Queued input (`KURTKODE_QUEUE=…`, `KURTKODE_QUEUE_AFTER=2`) steers a running agent | H | injected message before the 3rd request |
| 5.5 | Image (`KURTKODE_IMAGE`) to Gemma (vision) | H | model describes it; image stored in `.images/`; wire record shows the size note |

## 6. Context management (project: 8-file demo)

| ID | Test | Drv | Expected |
|---|---|---|---|
| 6.1 | `KURTKODE_CONTEXT_LIMIT=9000`, Full Auto, "read each file… append to NOTES.md" | H | compactions happen; none grows the prompt (tokensAfter < tokensBefore); "Didn't compact" notes appear when declined |
| 6.2 | Compaction detail in the Debug window lists its summary request(s) | H | HTTP, time, output tokens |
| 6.3 | `/compact focus on X` | H | compaction record; summary mentions X; output room from the context size |
| 6.4 | Settings → Summaries thinking off, one compaction | H | the summary request body has `reasoning_effort: none`; restore the setting |
| 6.5 | Context meter in the toolbar matches the last prompt size | H | within ~10% |
| 6.6 | `long-doc` eval on Gemma, 1 trial (`--no-load`) | C | pass (13/14+), summaries recorded in the result JSON |

## 7. Reliability paths (mock servers)

| ID | Test | Drv | Expected |
|---|---|---|---|
| 7.1 | Lost reply (empty with output tokens) via `fault_proxy.py` with two imitated providers | C/H | retried on the other provider; notes on the turn; Debug badge "lost"/"recovered" |
| 7.2 | Fallback model after all providers lose the call | C | fallback turn noted; run continues |
| 7.3 | Empty reply nudge | C | nudge note; second reply used |
| 7.4 | HTTP 429 then 200 | C | statuses `429 → 200` in the wire record |
| 7.5 | Server down mid-run (stop the mock) | C | turn fails with a readable error; session intact |
| 7.6 | Streaming at 110 tok/s from `mock_stream_server.py` with a long Markdown reply | H | no stalls ≥250 ms (hang log) |

## 8. MCP and hooks

| ID | Test | Drv | Expected |
|---|---|---|---|
| 8.1 | Project `.mcp.json` stdio server (a tiny Python echo server): approval once, tools offered as `mcp__…` | H (`KURTKODE_MCP_APPROVE=1`) | call works; approval stored for that exact command |
| 8.2 | Streamable HTTP MCP server (local Python) without a token | H/C | tools listed and called |
| 8.3 | Hooks: PreToolUse deny on `bash rm`, PostToolUse context, UserPromptSubmit, Stop sending the agent back once | H/C | each effect visible (blocked call, feedback note, injected message) |
| 8.4 | A changed hook or MCP command needs approval again | H | asks again |

## 9. Subagents

| ID | Test | Drv | Expected |
|---|---|---|---|
| 9.1 | explore subagent on Gemma: child session in `.subagents/`, linked from the task result, own wire log | H/C | as stated; parent wire log has no child requests |
| 9.2 | Custom agent with `model: bang|qwen/qwen3.5-9b` | C | runs on the LAN Qwen; header model set |
| 9.3 | Agents tab: running → completed; stats; Open in Debug | H | screenshots at two moments |
| 9.4 | Stop one subagent (`KURTKODE_STOP_SUBAGENT_AFTER`) | H | "[The user stopped this subagent…]"; main agent continues |
| 9.5 | CLI Ctrl-C during a subagent (pty): first stops it, second stops all | C | as stated |
| 9.6 | Parallel: two task calls, explore on Gemma + scout on bang | C | overlapping start/finish times; results in call order |
| 9.7 | Parallel on one slot (two explore on Gemma) | H | "Waiting for a free slot" in the Agents tab |
| 9.8 | Writers one at a time (two general tasks) | C | second waits |
| 9.9 | Background scout on bang; main does its own work; report card; loop waits | H/C | as stated; status line |
| 9.10 | Background refused for a writer agent | C | error result |
| 9.11 | `/agents` in app and CLI | H/C | tab opens / list printed |

## 10. Debug window

| ID | Test | Drv | Expected |
|---|---|---|---|
| 10.1 | Timeline: turns, calls, badges, Problems only, tool filter | H | screenshot of a session with errors (e.g. repeated reads) |
| 10.2 | Turn tabs: Overview, Reasoning, Request, Response, Diff (cache prefix) | H (`KURTKODE_DEBUG_TAB`) | each shows real data |
| 10.3 | Journal: blended stream, lens on a turn, lifetimes, budget chart, search, filters, provenance links | H (`KURTKODE_DEBUG_MODE=journal`, `_LENS`, `_SELECT`, `_SEARCH`) | as stated |
| 10.4 | Subagent drill-in, breadcrumb, live following, totals | H (`KURTKODE_DEBUG_SUBAGENT`) | as stated |
| 10.5 | Replay turn N on bang with reasoning none; comparison; Replays tab | H (`KURTKODE_DEBUG_REPLAY`) | saved replay; differences listed |
| 10.6 | Replay sheet estimate for an OpenRouter model (nothing sent; no Keychain prompt) | H (`KURTKODE_DEBUG_REPLAY_SHEET`) | "$… in / $… out per million tokens" |
| 10.7 | Copy as cURL; run the command against This Mac | H (`KURTKODE_DEBUG_CURL`) + C | the curl streams a reply |
| 10.8 | Fork before and after a turn; the fork opens; its Timeline shows copied turns | H (`KURTKODE_DEBUG_FORK`) | message counts; wire and index copied |
| 10.9 | Follow the main window vs a chosen session; Reload | U | switches correctly |

## 11. Inspector and git

| ID | Test | Drv | Expected |
|---|---|---|---|
| 11.1 | Todos and Changes tabs after 3.1 | H | todo progress; changed files with diffs |
| 11.2 | Context tab | H | meter, compactions |
| 11.3 | Git tab: status, diff, stage, unstage, commit in the scratch repo; discard a change | U | git state matches (`git status`) |

## 12. Command line

| ID | Test | Drv | Expected |
|---|---|---|---|
| 12.1 | `-p` with text, json, stream-json; piped stdin appended | C | outputs as documented; exit 0 |
| 12.2 | `-p` with an action needing approval in Ask mode | C | refused with a note to the model |
| 12.3 | Interactive (pty): line editing, history, Tab completion of /commands and @paths, `\` continuation | C | as stated |
| 12.4 | `-c`, `-r ID`, `--list-sessions` | C | resumes the right session |
| 12.5 | `!command` and Ctrl-C stopping it | C | stopped, exit noted |
| 12.6 | `inspect` (table, `--turn`, `--json`), `replay -m bang:qwen/qwen3.5-9b`, `export -o x.md` and `--format json` | C | as stated; replay visible in the Debug window |
| 12.7 | A session made by the CLI opens in the app with its wire log | H | Timeline shows its turns |

## 13. Persistence and robustness

| ID | Test | Drv | Expected |
|---|---|---|---|
| 13.1 | Torn last line in a session file (append half a record) | C | session loads; the line is skipped |
| 13.2 | An old session (from before 264a9b7, no wire log) in the Debug window | H | "no wire record" states, no crash |
| 13.3 | Quit the test app during a subagent run; reopen | H | Agents tab shows the run "Cut off (no end recorded)" |
| 13.4 | Wire log cap: a session over the cap stops recording quietly | C (unit-level is enough if slow) | no crash |
| 13.5 | Release build launches and runs one turn (`build/DerivedData/…/Release/kurtkode.app`, `open -n`) | H | works; debug hooks absent |

## 14. User checklist A (one sitting, ~20 min)

Gather the **U** tests from sections 1–3 and 10 (1.3, 2.4, 3.3, 3.4, 3.6, 10.9) into a numbered checklist for the user
with exact steps and what to look for. Record their answers.

## 15. User checklist B (one sitting, ~15 min)

Section 11.3 (git), the task card's "Open in Debug" click, the Replay sheet's Replay button on This Mac (send), Fork from
the menu, and a look at the Agents tab and report cards in the user's own installed app after `make install` (theirs).

## 16. Round 2 (added 2026-10-13 from what round 1 found)

**Run in session 7 (2026-10-13)**: results, findings F8–F17 and the fixes in FUNCTIONAL_TEST_RESULTS.md ("Round 2" and
after). Run after the user's `make install` (their app then has every fix). Helpers: `spike/functest/` (README there). Record
results in FUNCTIONAL_TEST_RESULTS.md under "Round 2". Same hygiene as above: scratch projects, stop instances by pid,
restore shared defaults (`defaults export` first), trash test sessions as `kurtkode-test-s7-*`.

| ID | Test | Drv | Expected |
|---|---|---|---|
| 16.0 | Smoke in the installed app: one turn on Gemma | U or computer use | works; Release has no hooks |
| 16.1 | **Crash safety.** `kill -9` the CLI (a) mid tool call, (b) mid compaction (`KURTKODE_CONTEXT_LIMIT`-style small budget via an 8k-context model or many reads), (c) mid `!command`; same for a Debug app instance. Then `-c` / reopen | C + H | every record written before the kill is there; a torn last line is skipped and the next append starts a new line; `-c` continues; no duplicated or lost tool results |
| 16.2 | **Path spellings.** Project opened as `/tmp/x` and `/private/tmp/x`; a symlinked folder; a trailing slash; a folder name with spaces and Unicode (`Prüf ordner`). Check: one sidebar group, one MCP hub (approve once), hook approval once, extra folders, sandbox write rules, `--list-sessions` | H + C | one identity per folder everywhere; no second approval; sandbox allows the project under either spelling |
| 16.3 | **Approval cards by computer use:** Allow; Deny with feedback; Always allow (then the same command runs without asking; where the rule shows); a queue of approvals from two parallel writer subagents | computer use | as stated; approval records `decider: user` with waits |
| 16.4 | **Accessibility sweep:** `app_screenshot` + `app_ax_find` over the main window (chat, tool cards, approval card, composer), inspector tabs, Debug window, Settings, Models window; list controls that aren't reachable (buttons inside disclosure labels, actions only in context menus) | computer use | a list; fix what matters (as a151225 did for Git) |
| 16.5 | **Error display in the app** via `smock.py`: 401, 403 with a body (like OpenRouter's "Key limit exceeded"), 429 with Retry-After then 200, 500, connection dropped | H | a readable error on the turn (the server's message shown), retry where it should; the CLI equivalents print to stderr (F4) |
| 16.6 | **App and CLI on one session:** `kurtkode -c` while the app shows the session; the Debug window following a CLI run live; then a message in the app | H + C | no interleaved or lost records; the app picks up the CLI's records (or says it can't) |
| 16.7 | **Interrupted states:** quit the app during an approval wait, a `/compact`, a `!command`, a wait for a background report; reopen | H | readable state; nothing stuck "running"; the cut-off action is marked |
| 16.8 | **MCP server dies mid-session** (the mock server's `crash` tool), then Settings → MCP → Restart | H | the failed call is an error result; the status shows failed; restart brings the tools back |
| 16.9 | **F1 regression:** `kurtkode-eval --no-load --models lmstudio:google/gemma-4-26b-a4b-qat --scenarios long-doc --trials 4` | C (background) | passes; if a reply is only `<tool_call|>`, the note "only a tool-call marker" appears and the run continues |
| 16.10 | **Streaming soak** on `build/PerfDD` (rebuild from HEAD): 10 × 60 KB mock streams at 110 tok/s; on any hang-log stall ≥1 s run `sample` at once | H (background) | no stall ≥500 ms besides launch and first sheet; any long one sampled |

Suggested order: 16.9 and 16.10 in the background; meanwhile 16.1, 16.2, 16.5; then 16.6–16.8; 16.3, 16.4 with the
user at the machine (menus need full-screen approval).

## 17. Round 3 (added 2026-10-15: the features since round 2, and regressions)

**Scope**: everything since round 2 (ed3ed2a): native Anthropic/Gemini, caches and the kept system prompt, reasoning
views, trimming, declined replies, spending and output limits, switch costs, withheld files, rate limits, web search,
lean prompt, permission rules, destructive commands, notifications, skills, `ask_user`; plus a regression pass over
what rounds 1–2 covered. Two parts: **17A** adversarial unit tests (`AgentCore/Tests/AgentCoreTests/Round3Tests.swift`;
a test that exposes a bug stays as `withKnownIssue` until it's fixed) and **17B** end to end on local Gemma, mock
servers, and recorded sessions. **No keyed API calls** (Anthropic, Gemini, OpenRouter) in this round: native paths are
checked with MockServer and recordings. Don't write in the user's home folders (user-level skills are tested with a
scratch home in unit tests; the CLI ignores `$HOME`). Same hygiene as above; trash test sessions as `kurtkode-test-r3-*`.
Record results in FUNCTIONAL_TEST_RESULTS.md under "Round 3".

### 17A. Unit level (adversarial)

| ID | Test | Expected |
|---|---|---|
| 17A.1 | Front matter: CRLF line endings, a UTF-8 BOM, `description: >` with a blank line, a colon in the value, a quoted name with spaces, upper case | a skill/command loads with the right description in every case, or is skipped without crashing |
| 17A.2 | Skill names and places: a symlinked skill folder, a skill folder inside the project, a skill whose folder is the project, duplicate names across all six folders, a name with `/` or spaces, an empty description, a 5,000-file skill folder | precedence as documented; the listing is bounded and fast; no folder outside the skill becomes readable |
| 17A.3 | Skill folders and safety: write/edit/bash-redirect into a skill folder in each mode; a withheld pattern matching a skill file on a third-party model; the sandbox profile with skills outside the project | writes refused (or asked); withheld stays withheld; sandboxed commands can read skill scripts |
| 17A.4 | `ask_user`: two questions in one turn, the same question twice, Stop while pending (no double resume), a subagent calling it, plan mode, a deny rule `AskUserQuestion`, a PreToolUse hook on it, options as a string, 0/1/9 options | answers matched to calls; one resume each; tool absent where nobody can answer |
| 17A.5 | Permission rules: quoting, extra spaces, `bash -c '…'`, `$(…)`, backticks, newlines, `;` `&&` `||` `|`, `/bin/rm`, `command`/`env`/`nohup` prefixes, `git -C`, `Read(./x)` vs `x/` vs `../x`, `~`, `/private/tmp` vs `/tmp`, case | deny and ask can't be bypassed by spelling; allow never covers a chained command |
| 17A.6 | Destructive commands: the same spellings against `git reset --hard`, `rm -rf ~`, `git push -f`, `curl … | sh`; harmless look-alikes (`git reset --soft`, `rm -rf build`, `git checkout -b x`, `grep -- -f`) | dangerous caught; look-alikes pass |
| 17A.7 | Native wire edge cases from review (SSE split across chunks, error events mid-stream, partial tool JSON, parallel calls, unknown blocks, thinking signatures after trimming/compaction, Gemini call/response pairing) | requests stay valid; nothing dropped; no crash |
| 17A.8 | Withheld files on a third-party model through every path: read_file, grep, glob, list_dir, bash `cat`, `@` mentions, subagents, MCP, skills | contents never sent (or what leaks is listed as a known limit) |
| 17A.9 | Costs and limits: cache read/write pricing, thinking tokens, unknown prices, a run limit hit mid-turn, a session limit across a resume | the meter matches hand arithmetic; limits stop where they should |

### 17B. End to end

| ID | Test | Drv | Expected |
|---|---|---|---|
| 17B.0 | `make test`; `make build`, `make release`, `make cli` | C | all pass; no warnings |
| 17B.1 | **Regression, CLI on Gemma** (calc project, `-p --mode auto`): fix a failing test (read, edit, bash pytest), then `-c` a follow-up | C | tests pass; `-c` keeps the recorded system prompt (one `systemPrompt` record) and adds the context note |
| 17B.2 | **Regression, interactive CLI** (ptydrive, Ask mode): approve with y, deny with feedback, `a` always-allow then the same command unasked; `/context`, `/model`, `/mode plan` then a write refused | C | as stated |
| 17B.3 | **Regression, subagents**: explore in the foreground and in the background (CLI -p), a general subagent that edits | C | reports arrive; child sessions recorded; `--no-subagents` removes `task` |
| 17B.4 | **Regression, inspect/replay/export** on 17B.1's session; `inspect` on a recorded Claude and a recorded Gemini session from session 8 (no sending) | C | readable; Steps in server order; thinking shown vs billed lines |
| 17B.5 | **Regression, app** (Debug, hooks, Gemma, calc project, Full Auto): one edit-and-test task; Ask mode with `KURTKODE_AUTOAPPROVE`; `KURTKODE_CONTEXT_LIMIT=9000` on the parts demo forces trims/compaction | H | finishes; compaction record; no stuck state |
| 17B.6 | **Permission rules live**: project `.claude/settings.json` deny `Bash(cat secrets.txt)` and `Read(./secrets.txt)`, ask `Bash(git push:*)`, allow `Bash(python3 -m pytest:*)`; CLI -p (allow not yet approved), interactive (approve the project rules), app (banner state) | C + H | deny holds through every spelling the model tries; allow applies only after approval |
| 17B.7 | **Destructive commands live**: Full Auto, ask Gemma to `git reset --hard` / `rm -rf ..`; -p refuses with the reason; interactive asks and `n` keeps the files | C | as stated |
| 17B.8 | **Skills live**: project skill with a script and a template (`.claude/skills`), one in `.agents/skills`, one `disable-model-invocation`; `/skills`; `/name args`; the model runs the skill's script in Full Auto with the sandbox on | C + H | loads on request; script runs (sandbox allows reading it); hidden skill only by name |
| 17B.9 | **Skills edge files live**: a CRLF SKILL.md and a BOM SKILL.md | C | loaded (or a known issue from 17A.1) |
| 17B.10 | **ask_user CLI** (ptydrive): number, `1,3` with multiple, free text, empty line (asks again), Ctrl-D, Ctrl-C at the prompt | C | answers mapped; Ctrl-D = no answer and the model goes on; Ctrl-C stops the run |
| 17B.11 | **ask_user -p**: a prompt that asks the model to ask | C | tool not offered; the model decides and says what it assumed |
| 17B.12 | **ask_user app**: the card on screen (screenshot), then quit while it waits; reopen | H | card readable; after reopen nothing is stuck and the cut-off call is marked |
| 17B.13 | **Plan mode with skills and ask_user** (CLI): both offered, writes refused | C | as stated |
| 17B.14 | **Kept system prompt across app and CLI**: a session started in the app, continued with `kurtkode -c`, back in the app | H + C | one recorded prompt; context notes appended; no prompt rebuilt |

## 18. Round 4 (added 2026-10-17: everything, with cost tracking new since round 3)

**Scope**: the whole product, correctness and stability only (no UI polish). New since round 3: cost tracking (entries,
run records, reconciliation, `cost check`/`calibrate`, `runs`, displays and limits reading the records) and round 3's
fixes. Found by six code reviews (cost, safety layer, model wire layer, agent loop, persistence, tools/MCP/CLI), each
candidate then probed. Two parts: **18A** unit probes (`AgentCore/Tests/AgentCoreTests/Round4Tests.swift`, bugs as
`withKnownIssue`, as in round 3) and **18B** end to end. **No keyed API calls**: priced paths use `pmock.py` (below);
live model runs use the user's LM Studio model as loaded (meta/muse-glimmer, 131k, 4 slots: no load or unload).
Trash test sessions afterwards as `kurtkode-test-r4-*`. Results in FUNCTIONAL_TEST_RESULTS.md under "Round 4".

**Priced mock** (`spike/functest/pmock.py PORT SCRIPT.json LOG`): an OpenAI-compatible server whose `/models` lists
OpenRouter-style prices; reached as `http://0.0.0.0:PORT/v1` it counts as a remote server (`Endpoint.isThirdParty`), so
kurtkode prices its replies at list price with no key. Script steps: `text`, `bash`, `tool`+`args`, `calls`, `usage`,
`status`, `drop`, `sleep`.

### 18A. Unit probes

| ID | Area | Probes (each a candidate from the reviews) |
|---|---|---|
| 18A.1 | Command splitting, danger check, deny rules | CRLF and combining marks; `$'…'`; `<<` that isn't a heredoc, quoted heredoc delimiters; nesting past the depth limit; zsh precommands (`noglob`, `nocorrect`, `repeat`), `=rm`, globbed command paths, `$'rm'`; `bash -o opt -c`, `env -S`; commands inside arguments (`git -c alias.x='!…'`, `find -exec /bin/rm`, `-execdir`, `bash <<<`, `echo … | sh`); a 100 KB word's parse time |
| 18A.2 | Hooks | PreToolUse `{"decision":"block"}` and `{"continue":false}`; a timed-out pipeline hook |
| 18A.3 | Loop state | a subagent's edit vs the parent's duplicate-read check; a denied subagent's result; queued input after Stop |
| 18A.4 | Persistence | two stores appending to one session at once; a fork of a session with a subagent run (runs, costs) |
| 18A.5 | Costs | OpenRouter `-1` placeholder prices; an older run record without a later field |
| 18A.6 | Model layer | an `error` chunk inside an OpenAI-compatible stream; Gemini `MALFORMED_FUNCTION_CALL`; pings only past the wall-clock limit; merged user messages' images; a tool call quoted in a code fence |
| 18A.7 | Tools and commands | editing a Latin-1 file; refusing an ambiguous one-character edit in a 16 KB file; CRLF multi-line edits and line numbers; `$1` inside the user's text; a command started after Stop |
| 18A.8 | Debug views and undo | repeated call ids (`call_0` each turn) in the Timeline; two checkpoint stores on one session |
| 18A.9 | Git panel, cost check | Discard on an add/add conflict; `cost check --day` on the 25-hour DST day |

### 18B. End to end

| ID | Test | Drv | Expected |
|---|---|---|---|
| 18B.0 | `make test`; Debug app and CLI build | C | all pass (known issues listed) |
| 18B.1 | **Spending limit** at list price: pmock answers every request with a bash call and 400k prompt tokens; `-p --mode auto` | C | stops at the run limit ($2 default) |
| 18B.2 | **Retries priced**: 503, then a lost reply (output tokens, no text), then an answer | C | both billed attempts in the cost records and `cost_usd` |
| 18B.3 | **Subagent costs**: two parallel explore runs on pmock | C | `-p` JSON's cost covers (or shows) the children's spending |
| 18B.4 | **Two writers on one session**: two `kurtkode -r ID -p` at once (pmock, 2 s replies) | C | every record of both runs in the file |
| 18B.5 | **Regression, CLI on muse-glimmer**: calc project, `-p --mode auto`, fix the tests | C | tests pass |
| 18B.6 | **Danger check live**: pmock asks for `git reset --hard`, then `bash -o pipefail -c 'git reset --hard'`, Full Auto, uncommitted change | C | both refused; the change kept |
| 18B.7 | **Ambiguous resume**: `kurtkode -r 0` with several sessions starting with 0 | C | refused like `inspect 0` |
| 18B.8 | **Regression, app on muse-glimmer**: calc, Full Auto | H | tests pass; run record written |
| 18B.9 | **Regression, compaction in the app**: parts demo, `KURTKODE_CONTEXT_LIMIT=9000`, Full Auto | H | all eight classes and counts right; compactions recorded; nothing stuck |
| 18B.10 | **Regression, CLI Ctrl-C at an approval** (ptydrive, pmock) | C | denied, nothing run, next line goes to the main prompt |

## 19. Round 5 (added 2026-10-25, session 14: Phase 1 of GAP_ANALYSIS.md)

**Scope**: what Phase 1 added or changed: grep on ripgrep and glob order (B4); multi-edit, the loose second pass,
read before edit, `apply_patch` and the rules over its paths (B5); background commands and exported variables (B2);
the plan workflow and Plan mode's read-only commands and sandbox (B1); instruction files, nested files, imports and
memory (B6); the compaction template and tracked facts (B7). Correctness and safety only. Found by three code
reviews (tools; shell and Plan mode; instructions and compaction), each candidate then probed. Two parts: **19A**
unit probes (`AgentCore/Tests/AgentCoreTests/Round5Tests.swift`, bugs as `withKnownIssue` until fixed) and **19B** end
to end. Live model runs on Gemma 4 26B QAT (loaded at 32k, one slot, unloaded after); loop mechanics on `pmock.py`
(reached as `http://0.0.0.0:PORT/v1`, so it counts as remote: priced, and withheld files apply). No keyed calls.
Test sessions go to the Trash as `kurtkode-test-r5-*`. Results in FUNCTIONAL_TEST_RESULTS.md under "Round 5".

### 19A. Unit probes

`Round5Tests.swift`, one test per finding (`r5_1_…` to `r5_34_…`, `r5_c_…` for the minor ones). Areas: grep's file list
(folders, NUL bytes, the file limit, a file named `-`); apply_patch (crash, partial writes, moves, stacked anchors,
unified line numbers, `-- ` lines, blank lines); the `.git` guard's case; the read log (appends, deletes, failed reads,
seeding); Plan mode (sandbox after approval, withheld files, the allowlist's escapes, carried variables, the plan
fallback, approval words, calls after approval, subagents' mode); background jobs (forked groups, subagents'); the
environment snapshot; instruction files and imports (links, secrets, parents outside home); subfolder rules (as a
message, after a compaction, before a first write, dependencies); memory (risk, Plan mode, concurrent appends,
truncation); the tracked last check. Each finding and its fix: FUNCTIONAL_TEST_RESULTS.md "Round 5".

### 19B. End to end

| ID | Test | Drv | Expected |
|---|---|---|---|
| 19B.0 | `make test`; Debug app and CLI build | C | all pass (known issues listed) |
| 19B.1 | **Withheld files through grep on a remote model**: pmock (remote), Full Auto, a project with `.env` and a `secrets/` folder; the script greps for the secret in content, files and count modes, with `type`, and with `path: .env` | C | no secret in any result; the notes count what was withheld |
| 19B.2 | **Edit rules over every path**: settings deny `Edit(secrets/**)`; pmock sends edit_file with the path inside `edits`, `file_path`, and an `apply_patch` touching `secrets/` and `src/` | C | all refused; nothing written |
| 19B.3 | **Read before edit against a changed file**: pmock reads a file, sleeps while the test changes it, then edits it | C | refused ("changed since you last read it"); a read and the edit again go through |
| 19B.4 | **Exported variables across calls**: pmock runs `export KK_X=1` and, in a later call, `echo $KK_X`; then `source` of a script exporting a PATH; a `-r` resume in a new process | C | carried within the process; the resumed process starts without them (documented) |
| 19B.5 | **Background job lifetime**: pmock starts a ticker with `run_in_background`, reads it twice, then the CLI exits (and, in the app, the instance quits) | C, H | output read in pieces; no process of the job left after exit or quit |
| 19B.6 | **Plan: revise, then approve** (app, Gemma, `KURTKODE_AUTOPLAN`): the first plan sent back with feedback, the second approved as Accept Edits | H | two plans shown, the second reflects the feedback; mode saved; the change made |
| 19B.7 | **Plan: reject** in the CLI (pty, Gemma) | C | run stops as denied; no file changed; mode still Plan |
| 19B.8 | **Plan mode's commands**: pmock asks for read-only commands and for each bypass the reviews found (pagers, preprocessors, output options) | C | read-only ones run; the rest refused; nothing written in the project |
| 19B.9 | **Memory in the app**: `KURTKODE_AUTOSEND='# use tabs'`, then `/memory`, then a new session's prompt | H | saved, listed, in the next prompt |
| 19B.10 | **Nested instructions after a compaction**: parts demo with a `lib/AGENTS.md` rule, `KURTKODE_CONTEXT_LIMIT=9000`, Gemma | C | the rule sent once before the compaction and again after it, and followed |
| 19B.11 | **Regression, eval scenarios on Gemma**: `--scenarios all` and `--scenarios phase1`, 1 trial | C | no scenario worse than its last recorded result |

## 20. Round 6 (added 2026-10-26, session 15: Phase 2 of GAP_ANALYSIS.md)

**Scope**: what Phase 2 added or changed: model listings and capabilities, the reasoning setting and the model pool
(A1); automatic subagent models, the default grader and the retry ladder (A2); end-of-run signals, thumbs and implicit
judgments on main runs (A3); the spending report, what-if, daily budgets and the cache notice (A5). Correctness, privacy
and money figures. Found by three code reviews (pool and retry; signals and spending; regressions and integration),
plus a replay of the retry trigger over the cost-floor re-run's 1,439 stored runs (`kurtkode-eval --retry-sim`). Two
parts: **20A** unit probes (`AgentCore/Tests/AgentCoreTests/Round6Tests.swift`, `r6_n_…`) and **20B** end to end, on
the mock server, pmock and Gemma 4 26B; no keyed calls. Results in FUNCTIONAL_TEST_RESULTS.md under "Round 6".

### 20A. Unit probes

`Round6Tests.swift`: which servers count as hosted for routing; the undo inside the run's writer slot; retries only
for pool-routed runs and never down; pool.json read leniently or refused, never replaced; Ollama's served context; a
retried background run's report; rung matching under a profile's reasoning; `--reasoning` and Gemini Pro levels; the
grader never the run's own model; the citation checker and "no report" on runs that changed files; eval stores'
degraded copies and infrastructure failures; a run's spending over mixed requests; the request a retry answers and the
reply its thumbs go on; daily limits' message and local sessions; report keys and cache share.

### 20B. End to end

| ID | Test | Drv | Expected |
|---|---|---|---|
| 20B.0 | `make test`; Debug app and CLI build | C | all pass (known issues listed) |
| 20B.1 | **The retry trigger on real runs**: `kurtkode-eval --retry-sim cf6` before and after the checker fixes | C | how often it fires, and on how many gold failures |
| 20B.2 | **Pool routing and retry through the CLI** (`CLIPoolEndToEndTests`): a hosted-looking main endpoint, two pool rungs on mock servers | T | the subagent runs on rung 1, fails, its file undone, retried on rung 2 with that entry's reasoning |
| 20B.3 | **Reasoning setting on a local model**: Gemma, `--reasoning none` and default | C | `reasoning_effort: none` sent, no reasoning tokens; nothing sent by default |
| 20B.4 | **Thumbs and signals**: Gemma in the interactive CLI fixes a bug, then `/good`; the app shows the session | C, app | the run's signals name the check and its exit; the judgment is saved; a filled thumb on the run's last reply only |
| 20B.5 | **The cache notice**: pmock, a 90%-cached request then an uncached one | C | one notice naming the tokens and their price |
| 20B.6 | **Reports**: `kurtkode cost report` and `whatif` over the re-run store and this Mac's sessions; the Spending and Pool windows | C, app | the study's own figures; the windows render |

## 21. Round 7 (added 2026-10-26, session 16: Phase 3 of GAP_ANALYSIS.md)

**Scope**: what Phase 3 added: project snapshots in a shadow git repository, the Changes tab, `/diff` and revert by file
and hunk (C1); rewind from the snapshots with files-only and conversation-only choices, the checkpoint list and
`/rewind` (C3); cross-vendor review, `/review`, Fix These and the automatic review of important subagent changes (A6);
the advisory escalation card, `/escalate` and the recorded offers (A4); kurtkode-initiated delegation, forced or
written by kurtkode (A7); and the eval tools that measured them (`--review-sim`, `--trigger-sim`, `--ladder`,
`--kk-delegation`). Data safety, privacy and money first. Found by three independent code reviews (snapshots and
rewind; review and escalation; delegation and integration). Two parts: **21A** unit probes
(`AgentCore/Tests/AgentCoreTests/Round7Tests.swift`, `r7_n_…`) and **21B** end to end, on mock servers and the local
model; keyed calls only with the user's go-ahead. Results in FUNCTIONAL_TEST_RESULTS.md under "Round 7".

### 21A. Unit probes

`Round7Tests.swift`: one probe per real finding of the three reviews, written to fail before its fix.

### 21B. End to end

| ID | Test | Drv | Expected |
|---|---|---|---|
| 21B.0 | `make test`; Debug app and CLI build | C | all pass (known issues listed) |
| 21B.1 | **Snapshots on real repositories**: time a snapshot of this repository and of `~/git/sugar`, first and later | T | well under a second after the first; big untracked folders named, not stored |
| 21B.2 | **A command's change, shown and rewound**: the local model changes a file with `sed`; `/diff`; the Changes tab; a files-only rewind | C, app | the change listed and diffed; the file back as committed; the conversation kept, with the note to the model |
| 21B.3 | **Review**: `/review` in a local session (no remote reviewer chosen), `/review -m` naming one; `--review-sim` on bank1 | C | refuses to go remote on its own; a verdict kept as a `reviewer` judgment; catch and false-alarm rates |
| 21B.4 | **Escalation**: a run that stops at the step limit (CLI) and one whose test fails after a change (app) | C, app | an offer one tier up with a price; declined and accepted both recorded |
| 21B.5 | **Delegation**: the delegation scenarios with and without `--kk-delegation` on the local model | C | how often it delegates, pass rate, wall time |
| 21B.6 | **Triggers offline**: `--trigger-sim` and `--ladder` over the stored eval runs | C | the tables in `eval-results/trigger-sim/` |

## 22. Round 8 (added 2026-10-31: Phase 5 of GAP_ANALYSIS.md and `ask_user`)

**Scope**: what has shipped to main since Round 7 and never had a round: the app's everyday friction (7317319), the
CLI's live screen (40e1950), worktrees and review (1e61445), agent capabilities (1105592), and `ask_user` with several
questions (f4ae412). Security, data and money first. **Test builds of the app take their own bundle id** (HANDOFF.md), or their preferences are the user's, and `KURTKODE_MODEL` needs `Endpoint|model`, or it picks This Mac and loads there. Found by four independent code reviews, one per batch. Two parts:
**22A** unit probes (`AgentCore/Tests/AgentCoreTests/Round8Tests.swift`, `r8_n_…`) and **22B** end to end, on mock
servers. Local models only if the user has one loaded (never load one for a test); keyed calls only with the user's
go-ahead, batched into one build. Results in FUNCTIONAL_TEST_RESULTS.md under "Round 8".

### 22A. Unit probes

`Round8Tests.swift`: one probe per real finding of the four reviews, written to fail before its fix.

### 22B. End to end

| ID | Test | Drv | Expected |
|---|---|---|---|
| 22B.0 | Full suite; Debug app and CLI build | C | all pass (known issues listed) |
| 22B.1 | **CLI live screen** (`spike/functest/cli/t1.py`–`t3.py`, a real pty on a mock) | C | each scenario passes on this build |
| 22B.2 | **Worktrees** (`t4.py`): `-w`, a commit under `--sandbox always`, an isolated subagent, the removal guards | C | as stated |
| 22B.3 | **Capabilities** (`t5.py`): the fetch asked, a local address refused, hooks, an image in the request, `/btw` | C | as stated |
| 22B.4 | **ask_user picker** (`t6.py`): three questions in one call; ↑↓ and Enter, space for several, typed words, a typed number, the old flat form, Esc skips the rest | C | each answer reaches the model; the scrollback keeps what was asked |
| 22B.5 | **A real terminal**: the CLI on a mock in the app's Terminal panel, a terminal that isn't `vt.py` | C | the live block draws and clears; typing during a run; an exit leaves the shell usable |
| 22B.5b | **Ways out** (`t8.py`): Ctrl-D, `/exit`, Ctrl-C twice, signals, idle and in a run | C | stty as it was, cursor shown, bracketed paste off |
| 22B.6 | **Real files** (`t7.py`): a real PDF of 1 page and of many, a damaged one, a photo, a large PNG, through `read_file` to a mock | C | the text and the image bytes in the request are right; a long PDF is cut with a way on |
| 22B.7 | **App friction on a mock** (hooks): queue, paste, fork, find, the cut-off banner | H | as stated in GAP_ANALYSIS.md |
| 22B.8 | **Git panel operations in the app** (hooks where they exist): Uncommitted basis, comment, commit, publish to a local bare remote | H | as stated in GAP_ANALYSIS.md |
| 22B.9 | **ask_user on real models** (`live_ask.py`, paid, cents): told to ask three things in one call; then a decision left open, without naming the tool | C | nested `questions` on Claude, GPT and Gemini; answers come back; a plain-text question is acceptable only in the second |
| 22B.10 | **Phase 5 on a real model** (local if one is loaded; otherwise paid, with the user's go-ahead): a session in a worktree, a fetch, a queued message | C | as stated |
| 22B.11 | **ask_user app card** (U): several questions; radio, checkbox, words, Answer enabled once anything's given, Skip, ⌘1 on a single question | U | as stated |
| 22B.12 | **User checklist C** (U, one sitting, after an install): Terminal.app and iTerm2 (flicker, wide characters, resize, Ctrl-V, `/copy`, Ctrl-Z); the rewind dialog and checkpoint list; revert by file and hunk; ⌘F, ⌘G, hover buttons, real ⌘V; hover to comment, open at a line, Merge, branch menu, stashes, removal dialog; a real GitHub remote; the first-run sheet's buttons | U | as stated in GAP_ANALYSIS.md |

## Reporting

End with a summary table per section (pass / fail / partial / skipped), the failures with evidence, and fix options
with a recommendation. Commit the results file when the user says.
