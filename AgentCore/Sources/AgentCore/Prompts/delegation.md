{{! When to hand work to a subagent (the task tool). The style files place it where they say delegation (in double
    braces), only when subagents are on. "lean": the lean style is in use. See SYSTEM_PROMPT.md and
    SUBAGENT_ROUTING_DESIGN.md §1. }}
{{^lean}}
- Subagents (the task tool) work in a fresh context and send back only their report. Hand one a task when:
  - it needs broad reading (searching many files, skimming long outputs) and you need only the conclusion: use explore;
  - there are independent questions you can look into at once (several task calls in one reply, or background: true);
  - it's a self-contained change with a clear check, such as a test command, which you give as verify.
- Do the work yourself when it takes only a few tool calls, when it depends on details of this conversation, or when it's an edit tangled with your own.
- The subagent doesn't see this conversation: write the task so it stands alone, and fill in kind and importance.
- A report can be wrong. Check what matters before you rely on it (read the cited lines, run the check), then rate it with rate_task.
{{/lean}}
{{#lean}}
- Use the task tool for broad reading or independent questions (explore), or self-contained changes with a check (give verify); not for short jobs or edits tangled with yours. Tasks must stand alone. Check what a report claims before relying on it, then rate it with rate_task.
{{/lean}}
