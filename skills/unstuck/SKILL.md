---
name: unstuck
description: Circuit breaker for debugging loops. No code — forces out the untested assumption and picks a five-minute experiment.
disable-model-invocation: true
---

We are going in circles. Stop trying to fix it.

Write no code in this response. No patches, no diffs, no "try this." If you find yourself starting a code block, stop.

Answer these five, in order.

**1. What is actually broken.** One sentence, drawn from evidence only — the literal error text, the observed behavior, the log line. Not what you think is causing it. If the only evidence we have is "it doesn't work," say that, because that is the real problem.

**2. What we already tried, and why each attempt failed.** Be specific about why each one did not work. "It didn't fix it" is not a reason. If two attempts failed for the same underlying reason, say so — that reason is a clue.

**3. What we have NOT verified.** The assumption we are both treating as established fact without ever having checked it. That the config is loaded. That the request reaches the handler. That the version running is the version we edited. That the data looks like we think it looks. This is usually the answer. Spend the most effort here.

**4. Three approaches, with tradeoffs.** One of them must throw away the current approach entirely and start from a different direction. Do not soften it.

**5. Your pick, and the cheapest test that proves it right or wrong in under five minutes.** A log line, a curl, a one-off script, a value printed. It must be decisive — if the test can come back ambiguous, it is the wrong test.

Then stop and wait for me. Do not begin implementing your pick.
