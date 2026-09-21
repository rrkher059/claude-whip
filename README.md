# claude-whip

Twelve hotkeys that fire pre-written, high-leverage slash commands into Claude Code running in a terminal. Each press plays a synthesized whip crack and draws a photoreal leather bullwhip lashing across the entire screen.

**It does not make the model think faster. Nothing can.** There is no prompt, no hotkey, and no tool that changes how quickly Claude reasons. What this does is make the prompts you never bother typing cost one keystroke.

That is the whole pitch. The prompts in this repo are ones most people know they *should* send — a hostile pre-merge review, a scaling and cost check, a decision record, a handoff note — and don't, because typing three hundred words of careful instruction at the moment you are tired and almost done is a tax nobody pays. Binding them to F1–F6 removes the tax. The whip is there so it feels like something happened.

---

## The twelve bindings

| Key | Command | What it actually buys you |
|---|---|---|
| `F1` | `/whip` | Hard stop on overbuilding. Sets standing rules — smallest change, no new files, no one-caller helpers, no speculative error handling — and deletes any excess already written. The single most useful key here. |
| `F2` | `/redteam` | Hostile senior-engineer review of the **live working tree**, grounded in a real `git diff`. Three sections: what breaks in production, security, the one thing to fix first. No praise. |
| `F3` | `/ship` | Detects your test and lint commands, runs them, and commits + pushes **only if they pass**. On failure it stops and shows you the output without "helpfully" fixing anything. Double-tap to confirm. |
| `F4` | `/decide` | Appends a dated entry to `DECISIONS.md` — decision, why, what you rejected, and the signal that should reopen it. Prompts for a title. Six months from now this is the only record of why. |
| `F5` | `/scale` | This code at 100x traffic: what breaks first and at what load, estimated cost per 1,000 users with assumptions stated, and the cheapest fix that buys the most headroom. |
| `F6` | `/unstuck` | Circuit breaker for debugging loops. Writes no code. Forces out the assumption you have both been treating as true without checking — which is usually the bug — then picks a five-minute experiment. |
| `Shift+F1` | `/orient` | Dropping into an unfamiliar or forgotten repo. What it does, the five files that matter, how data flows end to end, the one piece of architecture you will otherwise trip over, and what the last fifteen commits say you were mid-way through. |
| `Shift+F2` | `/secure` | Full-repo security sweep, not just the diff. Secrets, missing authorization, injection, CORS wildcards, missing rate limiting, PII in logs — ordered by what gets exploited first. |
| `Shift+F3` | `/test` | Writes the one regression test that would have caught the bug you just fixed, matching your existing conventions, then runs it. Must fail against the old behavior or it isn't a regression test. |
| `Shift+F4` | `/debt` | The three worst things in the repo ranked by **six-month cost, not ugliness**, with fix-now vs fix-later estimates. "Leave it" is an allowed and frequently correct verdict. Prompts for optional focus. |
| `Shift+F5` | `/user` | Walks your actual entry path as a first-time user. Where confusion starts, every step between arriving and value, what breaks on mobile / with no data / with a typo, and the one change that moves activation. |
| `Shift+F6` | `/handoff` | Overwrites `HANDOFF.md` so a zero-context session resumes exactly where you stopped: state, literal next action, traps, open questions. |

Every skill is marked `disable-model-invocation: true`. These are deliberate manual triggers — Claude will never decide on its own that now is a good time to run `/ship`.

## Why F2 has teeth

Most "review my code" prompts are answered from whatever the model remembers about your code, which drifts from what is actually on disk.

`/redteam` opens with a dynamic-context line:

```markdown
!`git diff HEAD`
```

Claude Code executes that **before** the model reads the rest of the prompt, so the real working tree is already in context when the instructions arrive. The review is grounded in the code you are about to commit, not a recollection of it. `/orient` uses the same mechanism for `git log` and `git ls-files`.

If the diff is empty, the skill is told to say so and stop, rather than inventing a review.

## Install

Requires Windows and [AutoHotkey v2](https://www.autohotkey.com/). `winget install AutoHotkey.AutoHotkey GitHub.cli Git.Git` covers the dependencies.

```powershell
git clone https://github.com/rrkher059/claude-whip
cd claude-whip
powershell -ExecutionPolicy Bypass -File .\gen-whip-wav.ps1   # synthesizes whip.wav
```

Install the twelve skills and start it:

```powershell
Copy-Item .\skills\* "$env:USERPROFILE\.claude\skills\" -Recurse -Force
.\whip.ahk
```

To start it with Windows, drop a shortcut to `whip.ahk` in `shell:startup`.

`whip.wav` is generated, not downloaded — see `gen-whip-wav.ps1`. Nothing is fetched from the network at any point.

## Config

`config.ini` is written with defaults on first run and is gitignored, so your local settings are yours.

```ini
[whip]
sound=              ; path to a custom wav; blank uses whip.wav next to the script
titles=claude       ; comma-separated fragments matched against the active window title
debug=0             ; 1 logs every non-matching window title to whip.log
hud=1               ; the bottom-right cheat sheet
volume=1            ; 0 mutes
animate=1           ; 0 skips the visuals entirely and just sends the command

[keys]
F1=whip
F2=redteam
...                 ; all twelve are freely remappable
```

Behavior follows the **command**, not the key: `ship` always double-taps to confirm and `decide` / `debt` always prompt for arguments, wherever you bind them.

Tray menu: reload config, open config, open log, toggle HUD, pause hotkeys, exit.

## Troubleshooting: the hotkeys do nothing

This is almost always title detection. Every hotkey is scoped with `#HotIf IsClaude()`, which matches the `titles=` fragments against the active window title. If your terminal does not put "claude" in its title, nothing fires — by design, so that F1 stays F1 everywhere else.

Fix it in four steps:

1. Set `debug=1` in `config.ini` and reload from the tray.
2. Focus your Claude Code window and press any bound key.
3. Open `whip.log`. It records every title that was checked and rejected:
   ```
   2026-09-20 21:09:30  no match: zsh — my-project
   ```
4. Paste a distinctive fragment of that real title into `titles=` (e.g. `titles=my-project,claude`) and reload.

`whip.log` also records how many hotkeys bound at startup (`bound 12/12 hotkeys`), which tells you immediately whether the problem is registration or detection.

Two more things worth knowing:

- If `config.ini` is saved by an editor that adds a UTF-8 BOM, Windows' INI functions silently return defaults for **every** setting. `whip.ahk` detects and strips the BOM at startup, but if you are editing config by hand and nothing takes effect, that is the classic cause.
- The overlay windows are `+E0x20 +Disabled`, so they are click-through and cannot take focus. If the whip ever appears to block you, it isn't — click straight through it.

---

## How the rendering works

This is the part worth stealing.

AutoHotkey cannot draw an anti-aliased curve onto the desktop. What it *can* do is set an arbitrary polygonal **region** on a borderless window, which clips that window to any shape you like:

```ahk
WinSetRegion(points " Polygon", "ahk_id " hwnd)
```

A shaped window is a single flat color, so one window gives you a silhouette, not leather. The trick is that you are not limited to one window. `whip.ahk` stacks several click-through shaped windows and recomputes every region each frame:

| Layer | Color | Role |
|---|---|---|
| 2 ghost windows | `#2A1A0F`, `#3A2415` | The whip's shape at `t-0.10` and `t-0.05`, at ~15% and ~30% opacity. Motion blur. |
| Body | `#4E3018` | The leather itself. |
| Grip bands | `#2E1B0D` | Three short offset shapes near the handle, so it reads as bound leather rather than a stick. |
| Highlight | `#8A6034` | The same centerline offset ~45% toward one edge and much thinner — light catching the top of the leather. |
| Flash + 4 sparks | white | An ellipse-region window at the tip plus thin radiating spikes at 30°, 75°, 200°, 250°, shown for two frames at the snap. |

Depth comes entirely from that layering. Collapse it to one window and it stops looking like leather.

### The traveling loop

The gross shape is a cubic bezier: handle anchored off the right edge, tip sweeping upper-right to lower-left on a cubic ease-out, with control points that **lag** the tip and then snap past it (they are driven off `lag = 1-t`).

But a moving bezier reads as a swinging rope, not a whip. What makes it a whip is the crack itself — a gaussian bump that *travels* from handle to tip. At each sample `s` along the curve, the point is offset perpendicular to its local tangent by:

```
offset = amp * exp(-((s - p) / 0.20)^2)
```

where `p = t*1.15 - 0.05` is the loop's position along the whip and `amp = 30*(1-t) + 7`, collapsing to ~25% once `t > 0.94`.

`p` walks from handle to tip as `t` advances, so the bump runs down the leather and the tip snaps past it right as the amplitude collapses. That is the entire illusion. Everything else — the taper (`7.6*(1-s)^1.45 + 0.8`, a fat grip and a 0.7px cracker), the ghosts, the highlight — is dressing on top of it.

Each polygon is built by walking forward along one perpendicular offset and back along the other, closing the shape. A frame whose region fails to apply is skipped rather than fatal, and the whole stack is hidden in a `finally` block, so an interrupted animation can never leave a window stranded on screen.

### The sound

`whip.wav` is synthesized by `gen-whip-wav.ps1` — 22050 Hz, 16-bit mono, 0.42s, written through a `BinaryWriter` with a hand-built RIFF/WAVE header.

- **Swish** (`t < 0.21s`): white noise through a one-pole lowpass `lp += k*(noise-lp)` whose cutoff opens from 0.04 to 0.59 while amplitude rises as `0.12*p³`. That is the leather accelerating.
- **Crack** (`t >= 0.21s`): full-band noise on an `exp(-34p)` decay, mixed 0.72 raw / 0.28 filtered so it stays bright, with `0.18*sin(2π*190*p)*exp(-60p)` underneath to give it body instead of hissing static.

If `whip.wav` is missing it falls back to `SoundBeep` and keeps working.

## License

MIT
