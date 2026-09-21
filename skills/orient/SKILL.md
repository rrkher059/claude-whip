---
name: orient
description: Fast orientation in an unfamiliar or forgotten repo — what it does, which files matter, how data flows, the non-obvious trap, and what we were mid-way through.
disable-model-invocation: true
background: false
allowed-tools: Bash(git *)
---

Recent history:

!`git log --oneline -15`

Tracked files:

!`git ls-files | head -60`

I am either new to this repository or returning to it after several weeks away. Orient me. Read the actual code before answering — the file list above tells you where to look, not what is in it.

Under 400 words total. Cover, in this order:

**What this project does** — one sentence, in plain language, describing what it does for whoever uses it. Not the tech stack.

**The four or five files that matter** — the ones where the real logic lives and where I will spend my time. For each, one line on why it matters. Not the config files, not the entry point unless the entry point genuinely matters.

**How data flows end to end** — follow one real request or one real operation from the outside edge to persistence and back. Name the functions it passes through. This is the part that saves me an hour.

**The one surprising thing** — the piece of non-obvious architecture I will otherwise trip over and waste time on. A custom convention, an inverted dependency, a magic file, a thing that looks dead but is not, a thing that looks live but is. There is always one. Find it.

**What we were in the middle of** — read the last fifteen commits as a narrative and tell me what was underway and whether it looks finished.

No file tree dumps — I can run `ls` myself. No setup or install instructions unless there is no README, in which case give me the three commands to get it running.
