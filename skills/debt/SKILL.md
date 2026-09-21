---
name: debt
description: The three worst things in the repo ranked by six-month cost, not ugliness — with fix-now vs fix-later estimates and permission to leave it alone.
disable-model-invocation: true
background: false
---

Rank the three worst things in this repository by what they will cost me over the next six months. Cost, not ugliness. Something genuinely unpleasant to look at that never changes and never breaks costs nothing, and I do not want to hear about it.

For each of the three:

**Where it is** — the file, the module, the pattern. Be concrete enough that I could open it right now.

**What it actually costs** — what breaks because of it, what gets slower because of it, what I cannot do until it is fixed, or how much longer every change in that area takes. Tie it to something real: a class of bug that keeps recurring, a feature that keeps getting harder, an onboarding cost, a test suite that takes ten minutes.

**Cost to fix now versus in six months** — roughly how long it takes today, and roughly how long after another six months of features have been built on top of it. If the gap is small, that is a strong argument for leaving it. If the thing is load-bearing and everything new will sit on top of it, the gap is enormous and that is the real argument for doing it now.

**Verdict: fix it or leave it.** "Leave it" is a valid answer and is often the correct one. I want your actual recommendation, not three items each ending in "should probably be addressed at some point." If all three are worth leaving, tell me that and tell me what I should worry about instead.

Skip entirely: style nits, naming, formatting, comment quality, import ordering, missing type annotations that do not cause bugs, anything a linter could fix. If your top three are things a linter would flag, you have not looked hard enough — look at the architecture and the data model instead.
