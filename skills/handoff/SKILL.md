---
name: handoff
description: Overwrite HANDOFF.md so a zero-context session can resume exactly where this one stopped — state, next action, traps, open questions.
disable-model-invocation: true
allowed-tools: Bash(git *)
---

Write `HANDOFF.md` at the repository root. Overwrite it completely — do not append, do not preserve the previous contents. This file describes right now, not history.

Write it for a fresh session with zero context: no memory of this conversation, no knowledge of what we tried, no idea what is half-done. Everything they need to continue must be in the file.

Use exactly these five sections:

```
**Working on:** The current task in one sentence. What outcome are we going for.

**State:** What works right now and is verified. What is half-finished, which file it is in, and what shape it is in — stubbed, written but untested, written and failing.

**Next step:** The literal next action. Specific enough to start immediately without deciding anything. "Add the retry wrapper around fetchInvoice in billing/client.ts, mirroring the one in payments/client.ts" — not "continue working on retries."

**Traps:** What will waste an hour if they do not know it. The test that fails for an unrelated reason. The env var that must be set. The cache that must be cleared. The thing that looks like a bug and is not. The approach that seems obvious and does not work — and why, so they do not retry it.

**Open questions:** Decisions not yet made, and what each one blocks. If nothing is open, write "none."
```

Under 250 words for the whole file. No history, no changelog, no summary of what we have accomplished — the next session does not care what we did, only what is true now and what to do next.

Then reply with only the next step. Nothing else.
