# Subagent management: design

Status: agreed 2026-10-12 (session 5); the open questions below were settled with the proposals. All five phases built (recording, Debug window, live control, parallel, background). Scope chosen by the user: recording and the Debug window, live
control, parallel and background subagents. Debug window: a summary on the task call and a drill-in to the
subagent's full Timeline and Journal. Storage: child session files.

## Today

- The main agent calls `task` (description, prompt, agent). `AgentLoop.runSubagent` runs a fresh loop on the
  agent's model; only the final report returns, with a "final report" note. Calls in one turn run in order.
- The task card streams one line per step; at the end the conversation is written as one JSON file in
  `<session>.outputs/subagent-<agent>-<id>.json` ("Open transcript").
- Stop cancels the whole run; there's no way to stop one subagent.
- **The subagent inherits the parent's config, including `wireLog`.** By the code (not yet checked with a
  test), its requests and context snapshots go into the main session's `.wire/` under reply IDs that no
  session message has. The Timeline and Journal look turns up by those IDs, so they'd drop them silently. The
  JSON transcript has the messages but no link to those requests.
- One approval at a time (`ChatController.pendingApproval`), one live progress stream per card.

## Model: a subagent run is a child session

A **run** is one execution of one `task` call. Each run is a child session, stored beside its parent:

```
sessions/<project>/<parent>.jsonl
sessions/<project>/<parent>.subagents/<run>.jsonl          # same record format as a session
sessions/<project>/<parent>.subagents/<run>.wire/          # its own wire log and context index
```

- **Header** (`SessionHeader`, new optional fields; older builds ignore them): `parent` (session id),
  `parentCallID` (the `task` call), `agent`, `title` (the task's description), endpoint and model as usual.
- **Records**, appended live as the run goes, so a running subagent can be followed: the prompt (user message),
  each assistant message and tool result, compactions, and a new `subagentEnd` record (stop reason, steps, tokens,
  duration, the report as returned).
- **The link back**: the `task` tool result gets `toolResult.subagentRun` (the run id). The old JSON transcript
  is no longer written; "Open transcript" opens the child in the Debug window. (Older sessions keep their JSON
  files and the link to them.)
- A child is never listed as a session of its own (sidebar, `--list-sessions`, `-r`): the store skips
  `.subagents` folders.
- Approvals, undo checkpoints, and "Always allow" rules stay the parent's (as today).

## Debug window

- **Timeline, a turn with `task` calls**: a "Subagent" section in the call's detail: agent, model, how it ended,
  steps, tool calls, tokens in/out, time, the report, and badges from its own turns (lost, error, bad
  arguments…). A button **Open subagent**.
- **Drill-in**: Open subagent shows the child in the same window, with Timeline and Journal working unchanged
  (it's a session), and a breadcrumb: `Session title › turn 7 · explore: Find the parser`. Back returns to the
  parent with the same turn selected. Nested runs can't happen (no subagents of subagents).
- **Journal**: each run is one entry in the parent's stream ("explore subagent: Find the parser · 9 steps ·
  31 s"), expandable to its tool uses and report, with Open subagent. The parent's lens doesn't apply inside a
  child (a separate context); the child's own Journal has its own lens.
- **Budget and totals**: the parent's per-turn budget chart stays the parent's context; a session total
  (tokens, cost, time) adds "including subagents: …".
- **Provenance**: "where did these values come from?" on a parent call can point into a child: a value first
  seen in the report is traced to the child's tool result that produced it.
- Debug hooks: `KURTKODE_DEBUG_SUBAGENT=<run id or N>` opens the Nth run.

## Live control

- **Events**: `AgentEvent.subagentStarted(SubagentInfo)`, `.subagentUpdated(id, steps, tokens)`,
  `.subagentFinished(id, stop, report)`, emitted by the parent loop. `SubagentInfo`: run id, call id, agent,
  model, title, started, background flag.
- **A registry** (actor, one per run of the main loop) holds each running subagent's `Task` handle, so one can
  be cancelled alone.
- **The app**: a "Subagents" section in the inspector (and a count badge on the toolbar while any run): each run's
  agent, title, model, state (running, waiting for approval, queued for a slot, done, stopped, failed), steps,
  tokens, elapsed; **Stop** for one; Open in Debug. The task card keeps its live step lines.
- **Stopping one**: its report becomes "[Stopped by the user.]"; the main agent goes on. Stop (the main one)
  still stops everything.
- **CLI**: a line when a subagent starts and finishes (already partly there); `/agents` lists runs; `/stop N`
  stops one. Ctrl-C keeps stopping everything.

## Parallel subagents

- Several `task` calls in one reply run at once (a task group); their results go back in call order.
- **Concurrency limit per endpoint**: LM Studio, the loaded instance's parallel slots (`lms ps` PARALLEL; one
  slot means requests queue at the server, and a long queue can trip the turn's time limit); other endpoints, a
  setting (default 4). A run waiting for a slot shows "queued".
- **Writers**: two subagents editing the same files at once can't both be right. Read-only runs (explore, or
  any agent whose tools don't write) run in parallel freely; runs that can write (edit, write, bash) run one at a
  time among themselves, alongside readers. (Option: per-file locks instead; more parallel, more ways to go
  wrong.)
- **Approvals**: `pendingApproval` becomes a queue; the card says which subagent asks; answering one shows the
  next.
- **Cost**: parallel runs on one local model share its compute and evict each other's prompt cache; the limit
  above keeps that in check.

## Background subagents

- `task` gets `background: true`. The call returns at once ("Started explore subagent 3 in the background; its
  report will arrive as a message."), and the main agent keeps working.
- **Delivery**: when a background run finishes, its report is injected as a message before the next request, the
  same way queued user input is (`takeInput`), marked as a subagent report, not the user's words.
- **The main loop doesn't finish while background runs are going**: before it would stop, it waits for the next
  one to finish and continues with its report (as with queued input). Stop ends everything.
- Lifetime: a background run belongs to the run of the main loop that started it (not across user turns), so
  every report has a reader.
- The prompt tells the model when to use it (long independent work while it does something else).

## Phases (each builds, passes tests, and is checked in the app; commit per phase when asked)

1. **Recording**: child session files, header fields, live records, `subagentRun` link, wire log and index per
   child, the store skipping children; a test that the parent's `.wire` gets no subagent records. Fixes the stray
   records described above.
2. **Debug window**: Subagent section, Open subagent with breadcrumb, Journal entries, totals, debug hooks.
3. **Live control**: events, registry, inspector section, stop one; CLI lines, `/agents`, `/stop`.
4. **Parallel**: task group, per-endpoint limits, writer rule, approval queue.
5. **Background**: the flag, delivery, waiting before finishing, prompt text.

## Decisions (2026-10-12, the user took the proposals)

1. Writers in parallel: one writing run at a time; read-only runs in parallel freely.
2. Background runs live only within the main loop's run that started them.
3. Remote concurrency: one setting for all non-LM-Studio endpoints, default 4.
4. The old JSON transcript is no longer written; older sessions keep theirs.
