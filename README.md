# claude-whip

Sixteen hotkeys that fire pre-written, high-leverage slash commands into Claude Code running in a terminal. Each press plays a synthesized whip crack and draws a photoreal leather bullwhip lashing across the entire screen.

**It does not make the model think faster. Nothing can.** There is no prompt, no hotkey, and no tool that changes how quickly Claude reasons. What this does is make the prompts you never bother typing cost one keystroke.

That is the whole pitch. The prompts in this repo are ones most people know they *should* send — a hostile pre-merge review, a scaling and cost check, a decision record, a handoff note — and don't, because typing three hundred words of careful instruction at the moment you are tired and almost done is a tax nobody pays. Binding them to a function key removes the tax. The whip is there so it feels like something happened.

---

## The sixteen bindings

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
| `Ctrl+F1` | `/cost` | Finds every paid model call in the repo and estimates the monthly bill at stated usage, naming the single call path responsible for most of it. |
| `Ctrl+F2` | `/why` | Takes a file or function, runs `git log -p --follow` on it, and explains why the code is that way from its real history — including the scar tissue and what was already tried and reverted. Prompts for the target. |
| `Ctrl+F3` | `/simplify` | The three functions with the worst complexity-to-value ratio, each with the actual diff it could become and proof the complexity isn't earning its keep. |
| `Ctrl+F4` | `/onboard` | Generates `CONTRIBUTING.md` from what the repo actually does — setup commands verified against lockfiles and CI, not boilerplate. |

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

Install the sixteen skills and start it:

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
hud=1               ; the corner tab and its expanding binding list
volume=1            ; 0 mutes
animate=1           ; 0 skips the visuals entirely and just sends the command
theme=leather       ; leather | midnight | ember | bone
shake=1             ; one-frame screen shake on the snap
hudcorner=br        ; tl | tr | bl | br - set by dragging the tab, saved here
palette=^!p         ; command palette chord: ^ Ctrl, + Shift, ! Alt, # Win
confirm=ship        ; comma-separated commands that need a double-tap first

[keys]
F1=whip
F2=redteam
...                 ; all sixteen are freely remappable
```

Behavior follows the **command**, not the key: `ship` always double-taps to confirm and `decide` / `debt` / `why` always prompt for arguments, wherever you bind them. Remapping a binding therefore keeps its safety.

### Which commands write something

Five of the sixteen change state rather than just producing a reply:

| command | what it writes |
|---|---|
| `/ship` | commits **and pushes** to the current branch |
| `/decide` | appends to `DECISIONS.md` |
| `/test` | adds a test file, then runs it |
| `/handoff` | overwrites `HANDOFF.md` |
| `/onboard` | overwrites `CONTRIBUTING.md` |

Only `/ship` requires a double-tap by default, because it is the only one that leaves your machine. The other four write a single file inside the repo, which `git checkout` undoes. If you want more of them guarded, list them:

```ini
confirm=ship,handoff,onboard
```

A guarded command shows `press again to <command>` on the first tap and arms for 900ms. Anything not in the list fires immediately. Separately, **Ctrl+Z within 2 seconds of any fire** sends Escape to interrupt Claude and toasts `cancelled`; outside that window Ctrl+Z is not intercepted at all.

Tray menu: reload config, open config, open log, pick Claude window, show welcome, toggle HUD, pause hotkeys, exit.

### Chains

A binding whose value contains `|` runs its steps in order. Between steps you can put `wait <seconds>`:

```ini
[keys]
F7=redteam | wait 45 | test
F8=secure | wait 60 | handoff
```

Both are shipped commented out in the generated config. Keys outside the default sixteen work too — the whole `[keys]` section is read, so `F7`, `F8`, `Ctrl+F5` and so on are all available.

While a chain waits it toasts a countdown, and **Escape cancels it**. The HUD and the palette show a chain as `redteam +2` rather than the full string.

**`wait-idle` is deliberately not implemented.** It was specified, and there is no reliable way to do it from outside the terminal: the window title does not change while Claude is working, there is no exit code to wait on, and the only remaining approach — diffing the terminal's pixels — is defeated by both a blinking cursor and a ticking token counter. A chain step that guessed wrong would fire the next command into a half-finished answer, which is worse than not having the feature. If you put `wait-idle` in a chain it stops with an explicit message rather than silently doing something unpredictable. Use `wait <seconds>` with a generous number.

### Why the palette is `Ctrl+Alt+P`, and how to pick your own

`Ctrl+Shift+Space` is the obvious chord for a command palette, and it is the wrong one on Windows. Windows Terminal binds it by default:

```json
{ "keys": "ctrl+shift+space", "id": "Terminal.OpenNewTabDropdown" }
```

That binding lives in the app package's `defaults.json`, not in your `settings.json`, so it applies even when your own `keybindings` array is empty — which is to say, to almost everyone.

It does not actually break the palette: AutoHotkey's low-level keyboard hook sees the chord before Windows Terminal does, so the palette wins. The problem is the other direction. While claude-whip is running and your Claude window is focused, you would silently lose Windows Terminal's new-tab dropdown and never be told why. Shadowing a documented default of the host terminal is not a trade worth making for one keystroke.

**Before binding anything, check it against both Windows Terminal's package defaults and your own `settings.json`.** Two chords that look free and are not:

| chord | what it really does in Windows Terminal |
|---|---|
| `Ctrl+Shift+Space` | `Terminal.OpenNewTabDropdown` |
| `Ctrl+Shift+W` | `Terminal.ClosePane` — **closes your tab** |

These ctrl+shift letters are unclaimed in Windows Terminal's defaults if you prefer one: **b e g h i j l o q r s u x y z**.

One caveat on the default: on international keyboard layouts AltGr sends Ctrl+Alt, so `Ctrl+Alt+P` can fire while you are typing. If you use such a layout, rebind `palette=` to one of the ctrl+shift letters above.

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
