---
name: why
description: Explain why a file or function is the way it is from its actual git history, not from reading it cold.
disable-model-invocation: true
background: false
allowed-tools: Bash(git *)
---

History for what I asked about:

!`git log -p --follow --max-count=25 -- "$ARGUMENTS"`

Target: $ARGUMENTS

If that is empty, ask me which file or function and stop. If the log above is empty, the path is wrong or untracked — say so and stop rather than guessing from the current contents.

Explain **why this code is the way it is**, using the history above as evidence. Reading the file as it stands today tells me what it does; I want to know why it does it that way, which is only recoverable from how it changed.

Cover:

**What it was originally.** The shape of the first version, and what it was solving then. This is the baseline everything since has been a reaction to.

**The turning points.** Not every commit — the three or four that actually changed the design. For each: what changed, and what the commit message, tests, or surrounding changes say forced it. A commit that adds a null check and a test called `test_empty_response` is telling you something broke in production.

**The scar tissue.** The parts that look arbitrary, over-defensive, or redundant, and which incident or bug each one is a response to. Special cases, retries, sleeps, seemingly pointless re-checks, oddly specific constants. Name the commit that introduced each. **This is the part I actually want** — it is the difference between "this looks like it could be deleted" and "this was added at 3am for a reason."

**What has been tried and reverted.** Anything that was added and later removed is a warning: someone already tried that. Call it out explicitly, because it is the most likely thing for me to propose again.

**What is safe to change now.** Given the above, which parts are genuinely incidental and which are load-bearing. Be specific about what would break.

Where the history is ambiguous, say it is ambiguous. Do not invent a narrative to make the story tidy — an honest "the commit message says only 'fix' and the change is not self-explanatory" is more useful than a confident guess.
