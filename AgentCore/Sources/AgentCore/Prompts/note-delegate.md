{{! The note added to a tool result when the agent has been reading broadly itself (Settings → Subagents → Suggest
    delegating). "reads": calls in a row; "tokens": about how much they put into the context. }}
{{! "force": the next reply must be a task call (A7); "delegated": kurtkode writes that call itself (a server that can't be
    made to call a tool). }}
[kurtkode: that's {{reads}} reads in a row, about {{tokens}} tokens of your context. For broad reading like this, the explore subagent can do the searching in its own context and report back only what matters.{{#force}} Hand the rest of the reading to it now: your next step is a task call (agent: explore) saying what to find and report back.{{/force}}{{#delegated}} kurtkode is handing the rest of the reading to it now; its report comes back as the result of the task call that follows.{{/delegated}}]
