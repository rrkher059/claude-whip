# The sixteen skills

These are the actual product. The hotkeys and the whip are delivery; this directory is the part worth forking.

Each skill is a Claude Code slash command: a folder containing one `SKILL.md`. They work on their own — copy them into `~/.claude/skills/` and type `/redteam` by hand, with no AutoHotkey involved anywhere.

```powershell
Copy-Item .\skills\* "$env:USERPROFILE\.claude\skills\" -Recurse -Force
```

---

## What each one is for

### Stopping yourself

| Skill | Use it when |
|---|---|
| **`/whip`** | Claude is three files into a refactor you didn't ask for. Sets standing rules — smallest change, no new files, no single-caller helpers, no speculative error handling — and tells it to delete what it already overbuilt. The most-used skill here by a wide margin. |
| **`/unstuck`** | The third failed fix for the same bug. Forbids writing any code and forces out the assumption you've both been treating as verified without checking. That assumption is usually the bug. |

### Before you commit

| Skill | Use it when |
|---|---|
| **`/redteam`** | About to merge. Reviews the **live working tree** as a hostile engineer who got paged at 3am. Three sections, no praise, and it stops if the diff is empty. |
| **`/secure`** | Periodically, and before anything ships publicly. Whole-repo sweep ordered by what gets exploited first, not by severity label. |
| **`/test`** | Right after fixing a bug. Writes the one regression test that would have caught it, matching your existing conventions, and must fail against the old behaviour. |
| **`/ship`** | Tests and lint, then commit and push **only if they pass**. Stops dead on failure and refuses to "helpfully" fix things. |

### Understanding code

| Skill | Use it when |
|---|---|
| **`/orient`** | New repo, or one you haven't touched in a month. Five files that matter, how data flows, and the one piece of architecture you'd otherwise trip over. |
| **`/why`** | Something looks wrong and you're about to "clean it up". Reads the file's git history and tells you which incident each odd line is a response to — and what was already tried and reverted. |
| **`/simplify`** | Code feels heavy. Three functions with the worst complexity-to-value ratio, each with a real diff and proof the complexity isn't earning its keep. |
| **`/debt`** | Planning. Ranks by six-month cost, not ugliness. "Leave it" is an allowed and frequently correct verdict. |

### Money and scale

| Skill | Use it when |
|---|---|
| **`/scale`** | Before a launch. What breaks first and at what load, specific to your code. |
| **`/cost`** | The bill surprised you. Every paid call, the monthly total with assumptions listed above the number, and the one call path responsible for most of it. |

### Writing things down

| Skill | Use it when |
|---|---|
| **`/decide`** | You just made a call you'll forget the reasoning for. Appends to `DECISIONS.md` including what you **rejected** and when to revisit. |
| **`/handoff`** | End of session. Overwrites `HANDOFF.md` so a zero-context session resumes exactly where you stopped. |
| **`/onboard`** | Someone else is about to clone this. Generates `CONTRIBUTING.md` from lockfiles, scripts and CI rather than boilerplate. |
| **`/user`** | Activation is bad and you don't know why. Walks your real entry path as a first-time user. |

---

## Customising one

A `SKILL.md` is YAML frontmatter followed by a prompt. That's the whole format.

```markdown
---
name: redteam
description: Hostile senior-engineer review of the live working tree.
disable-model-invocation: true
background: false
allowed-tools: Bash(git *)
---

Current working tree diff:

!`git diff HEAD`

Review the diff above as a hostile senior engineer who got paged at 3am...
```

**`description`** is what claude-whip shows in the palette and what Claude uses to understand the skill. The palette reads it live off disk, so editing it updates the UI with no restart beyond a config reload.

**`disable-model-invocation: true`** is on every skill here and should stay on. It means Claude will never decide by itself that now is a good moment to run `/ship`. These are manual triggers, deliberately.

**`allowed-tools`** narrows what the skill may run. `Bash(git *)` permits git and nothing else.

**``!`command` ``** is the part worth stealing. Claude Code executes it **before** the model reads the rest of the prompt, so the output is already in context when the instructions arrive. It's why `/redteam` reviews your actual working tree instead of a recollection of it, and why `/why` can reason about real history. Three skills use it: `/redteam` (`git diff HEAD`), `/orient` (`git log`, `git ls-files`), and `/why` (`git log -p --follow`).

**`$ARGUMENTS`** carries whatever you typed after the command. `/decide`, `/debt` and `/why` use it — claude-whip prompts you for it, and typing the command by hand works the same way.

## Writing a good one

What makes these different from "please review my code":

- **Name the output shape.** "Exactly three sections" beats "be thorough". A model given a structure fills it; a model given an adjective rambles.
- **Say what not to do.** "No praise. No summary of what the code does." Most of the quality here comes from the prohibitions, not the instructions.
- **Give it an out.** Every skill has a stop condition — "if the diff is empty, say so and stop". Without one you get invented findings, which is worse than none.
- **Ground it in real state.** A `!` command line is worth more than three paragraphs of instruction.
- **Let it say no.** `/debt` is explicitly told "leave it" is a valid verdict. `/secure` is told an empty report is a useful report. Removing the pressure to produce findings is what makes the findings trustworthy.
