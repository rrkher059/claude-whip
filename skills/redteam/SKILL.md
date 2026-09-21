---
name: redteam
description: Hostile senior-engineer review of the live working tree. Runs git diff HEAD first so the review is grounded in real code, not memory.
disable-model-invocation: true
background: false
allowed-tools: Bash(git *)
---

Current working tree diff:

!`git diff HEAD`

Review the diff above as a hostile senior engineer who got paged at 3am because of code like this. You are not here to be encouraging. You are here because something like this already cost you a night of sleep.

Output exactly three sections and nothing else.

**1. Will break in production**

Concrete failures only. For each: the specific failure, the line it is on, and the trigger that causes it. Things that actually page people:

- Unhandled nulls and undefined property access on paths that will be hit
- Promises that are never awaited, floating async work, unhandled rejections
- N+1 queries and queries inside loops
- Unbounded loops, unbounded result sets, memory that grows with input and is never released
- Missing authentication or authorization checks on a path that reaches data
- Race conditions, check-then-act on shared state, non-atomic read-modify-write
- Money represented in floats
- Timezone and DST assumptions, naive datetimes, server-local time
- Retries without backoff, retries on non-idempotent operations, no timeout on outbound calls

**2. Security**

Injection (SQL, command, template), secrets or keys committed, missing authorization, user input trusted without validation, PII written to logs. If there is nothing, write "none found" and move on. Do not manufacture a finding to fill the section.

**3. The one thing I would fix first**

Exactly one item. The fix, concretely. Not a list.

Rules: No praise. No "this is a good start." No summary of what the code does — I wrote it, I know what it does. If the diff above is empty, say the diff is empty and stop.
