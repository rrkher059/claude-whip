---
name: simplify
description: The three functions with the worst complexity-to-value ratio, and the concrete diff each one could become.
disable-model-invocation: true
background: false
---

Find the three functions in this repository with the worst ratio of complexity to value delivered, and show me what each could become.

**Complexity-to-value, not complexity.** A genuinely hard function that does something genuinely hard is fine — leave it alone. I am looking for the ones where the complexity is not paying for anything: a state machine with three states that are never both reachable, a configurable strategy with one strategy, a cache that is always cold, five parameters where two are always passed the same value, a retry wrapper around something that cannot fail, defensive branches for inputs that no caller can produce.

Rank by how much the complexity costs against what it buys. Say the ratio out loud for each — "180 lines and four branches to do what two lines of filter would do."

For each of the three:

**Where it is.** File, function, line count, and the specific thing that makes it complex — nesting depth, branch count, number of parameters, mutable state threaded through, whatever is actually doing the damage.

**Why the complexity is not earning its keep.** Prove it from the code. If you claim a branch is dead, show that no caller can reach it. If you claim a parameter is always the same, list the call sites. This is the part that makes the recommendation trustworthy rather than an opinion about style.

**The diff.** Show the actual before and after, as a unified diff, not a description of one. Keep it to the function and anything that must change at its call sites. If the simplification changes behaviour in any edge case, say exactly which and stop calling it a simplification — that is a rewrite and I need to know.

**What it costs to do.** Roughly how long, how many call sites move, and what test coverage exists to catch a mistake. If there are no tests over it, say so — that changes whether this is worth doing at all.

Rules: do not touch anything you cannot show is safe. Do not propose renaming things. Do not propose splitting a function purely because it is long — length is not complexity. If fewer than three functions genuinely qualify, give me the ones that do and say the rest of the repo is fine, rather than padding the list.
