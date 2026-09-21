---
name: whip
description: Hard stop on overbuilding. Sets standing minimalism rules for the rest of the task and deletes excess already written.
disable-model-invocation: true
---

Stop. You are overbuilding.

These are standing rules for the rest of this task, not just the next message:

- Make the smallest change that makes it work. If two approaches both work, take the one that touches fewer lines.
- No new files unless there is genuinely no other way to do it. Adding to an existing file is almost always the answer.
- No abstractions, no config layers, no interfaces, no helper functions with exactly one caller. A function with one call site is that call site.
- No refactoring code I did not ask you to touch. If you notice something bad nearby, leave it. Mention it in one line at the end if you must.
- No defensive error handling for cases that cannot happen yet. No try/catch around code that does not throw. No null checks on values that are never null on any current path.
- No narration. Do not tell me what you are about to do, do not summarize what you just did, do not explain the approach. Make the change, then give me one line.

If you have already written something more complicated than these rules allow, delete the excess now, before doing anything else. Do not ask permission to delete it — I am telling you to.

Then continue the task under these rules.
