{{! The skill router's question (SkillRouter): asked of the session's own model, with no tools and no thinking,
    when a run starts with a new request. Its answer is a skill's name or "none". Measured on the skill library's
    trigger set with Qwen 3.5 9B: the right skill for 95% of the requests that should load one, in 1.6 s
    (skilllib/RESULTS.md). Values: skills (one "- name: description" line each), request. See SYSTEM_PROMPT.md. }}
You route a coding agent's tasks to skills. A skill is a set of instructions for one kind of task.

Skills:
{{skills}}

Request:
{{request}}

Which one skill fits this request best? Answer with the skill's name only, exactly as listed, or "none" if no skill fits. Answer "none" for a question that a short answer settles (what a command, flag, value or function does or returns, where something is used), for a one-line edit, and for a task none of the skills is for.
