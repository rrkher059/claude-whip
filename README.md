# claude-whip

Six hotkeys for Claude Code in the terminal. F2 red-teams your uncommitted diff.
F5 tells you what the code costs at 100x traffic. A whip cracks across the screen
when you press one.

## What it is not

It does not make the model think faster. Nothing can. What it does is fire a
pre-written prompt instantly, so the high-leverage asks you never bother typing
become one keystroke.

| Key | Command | What it does |
|-----|---------|--------------|
| F1 | `/whip` | Cuts scope. Kills overbuilding, the main tax on AI-written code. |
| F2 | `/redteam` | Pulls your live `git diff` and reviews it as a hostile senior engineer. |
| F3 | `/ship` | Tests, lint, commit, push. Stops at the first failure. Double-tap to confirm. |
| F4 | `/decide` | Appends to `DECISIONS.md` so you stop re-litigating the same call. |
| F5 | `/scale` | What breaks at 100x, and cost per 1,000 users. |
| F6 | `/unstuck` | Breaks the loop where the same fix fails four times. Writes no code. |

F2 is the one with teeth: the skill runs `git diff HEAD` before Claude reads it,
so the review is grounded in your actual working tree.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File whip-install.ps1
```

Installs AutoHotkey v2 and the GitHub CLI, writes six skills to
`~/.claude/skills/`, synthesizes `whip.wav` from scratch, and starts the
overlay. Restart Claude Code afterwards so it picks up the skills.

## Config

`config.ini`, read at startup:

- `titles` - comma-separated fragments matched against the active window title.
  Defaults to `claude`. If the hotkeys do not fire, set `debug=1`, press a key,
  and read `whip.log` to see the real title.
- `keys` - remap any F-key to any slash command.
- `hud=0` - hide the on-screen key list.

Hotkeys are scoped with `#HotIf`, so F1-F6 behave normally in every other app.

## The whip

A borderless click-through window whose region is recomputed each frame into a
tapered polygon along a cubic bezier. The control points lag behind the tip and
then snap past it, which is what a real whip does and why it cracks.

MIT.
