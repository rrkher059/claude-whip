---
name: decide
description: Append a dated architecture decision record to DECISIONS.md, newest first, including what was rejected and when to revisit.
disable-model-invocation: true
allowed-tools: Bash(git *)
---

Record a decision in `DECISIONS.md` at the repository root.

Subject: $ARGUMENTS

If that is empty, infer the decision from what we have been discussing in this conversation. If we have not actually decided anything, say so and stop rather than inventing one.

If `DECISIONS.md` does not exist, create it with a `# Decisions` heading on the first line. Insert the new entry immediately after that heading so the newest decision is always at the top. Never append to the bottom.

Use exactly this format:

```
## YYYY-MM-DD — <short title>

**Decision:** One sentence. What we are doing.
**Why:** Two sentences maximum. The actual reason, including the constraint that forced it — not the flattering reason.
**Rejected:** What we seriously considered and did not pick, and the specific reason it lost.
**Revisit when:** The concrete signal that should reopen this. A number, a threshold, an event. Not "when it becomes a problem."
```

Use today's real date. The whole entry stays under 100 words — this is a record, not an essay. If "Rejected" would be empty, then no real decision was made; say that instead of writing the entry.

Reply with only the title you added.
