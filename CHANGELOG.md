# Changelog

All notable changes to claude-whip.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/). Versions are [semver](https://semver.org/).

---

## [2.0.0] — 2026-09-21

The version where the whip actually renders, the sound is a crack rather than a beep, and the thing is usable by someone who is not its author.

### Added

**Visuals**
- Wind-up: five frames that pull back and right with the tip lagging, so the stroke has a load-up to release.
- Non-uniform frame timing across 26 frames — slow wind-up, fast loop travel, a held snap, then fade. A uniform frame time reads as a swinging rope.
- A shadowed underside layer offset from the body, and a highlight with its own taper that peaks mid-arc and dies before the tip.
- The cracker is its own window and colour, trailing the body by a beat that peaks mid-stroke.
- Snap built from a bright core, an expanding arc, and six shards at irregular angles and lengths.
- One-frame screen shake on the snap (`shake=`).
- Four themes — `leather`, `midnight`, `ember`, `bone` — defined in one table at the top of the file.
- A performance guard that drops the sample count if a frame genuinely overruns, rather than stuttering.

**Interface**
- The whip now plays across the focused terminal only, not the whole desktop.
- First-run welcome window, re-openable with `--welcome`.
- Terminal auto-detection with a one-time prompt and a window picker that writes `titles=` for you (`--pick`, or the tray).
- HUD reworked: a corner tab that expands on hover or Shift-held, fades when idle, toasts each fire, and is draggable to any corner with the position saved.
- Command palette on `Ctrl+Alt+P`, listing every command with its hotkey and its description read live from that skill's frontmatter.
- `Ctrl+Z` within 2s of a fire interrupts Claude and toasts `cancelled`.
- Styled multi-line argument prompt with history, replacing `InputBox`.

**Functionality**
- Four new skills: `/cost`, `/why`, `/simplify`, `/onboard`, on `Ctrl+F1`–`Ctrl+F4`.
- Chains: `F7=redteam | wait 45 | test`. The whole `[keys]` section is read, so any key can be bound.
- Usage stats to `stats.csv` with a tray viewer, including which commands have never been fired.
- `--doctor`, printing a full health report to stdout.
- Once-a-day update check. Never auto-updates, never blocks startup, silent offline.
- `install.ps1` — idempotent one-command install.
- Configurable `confirm=` list for commands that write.

### Fixed

- **The whip never rendered.** Every `WinSetRegion` call was rejected because of a trailing `Polygon` keyword, which AutoHotkey v2 does not accept — three or more bare points already form a polygon. Negative coordinates and 400-point polygons were both proven fine, so neither was the cause.
- **The overlays were never shown.** `DetectHiddenWindows` defaults to off, so `ahk_id` could not match a hidden window; `ShowWin` called `WinSetTransparent` first, threw, was swallowed by a bare `try`, and `Show()` never ran.
- **Keystrokes were being swallowed.** The overlays took activation, and hiding an activated window left focus unsettled while `SendText` was already typing. Fixed with `WS_EX_NOACTIVATE`.
- **The snap was drawn off-screen.** The tip finished at `W*-0.10`, so by the time the travelling loop reached it, the core, arc and shards were all outside the display.
- **The whip was a hairline.** Taper constants were tuned as if for a small window; they are half-widths now and scale with display height.
- **The crack sounded like a beep.** `p` was normalised 0–1 instead of seconds, making `exp(-34p)` a 6ms decay and turning `sin(2π·190·p)` into 905 Hz. The loud portion went from 8.1ms to 38.7ms and 180ms of trailing silence disappeared.
- **Hotkeys were live over the tool's own dialogs**, because they are titled "claude whip" and matched the default `titles=claude`.
- **The performance guard cried wolf** on frame 1 of every animation, permanently degrading quality for a cost that is just the first `Show()`.
- **A UTF-8 BOM in `config.ini`** made Windows' INI functions return defaults for every setting. The BOM is now detected and stripped at startup.
- Sorting the stats day buckets with `<` made AHK compare `"2026-09-16"` as a number and throw.

### Changed

- **Palette moved off `Ctrl+Shift+Space`.** Windows Terminal binds that to `OpenNewTabDropdown` in its package defaults. AutoHotkey's hook wins the race, so the palette worked — but the terminal's own dropdown would have silently stopped working. Now `Ctrl+Alt+P`, configurable.
- Region and sound failures log with frame and layer instead of being swallowed.

### Not implemented, deliberately

- **`wait-idle` in chains.** There is no reliable way to detect that Claude Code has stopped producing output from outside the terminal: the title does not change, there is no exit code, and pixel-diffing is defeated by a blinking cursor and a ticking token counter. The token stops the chain with an explicit message rather than guessing.
- **Per-project `.whip.ini` from the terminal's working directory.** The window belongs to the terminal host, not the shell inside it, and with tabs there is no reliable way to know which shell is in front.
- **`cwd` in `stats.csv`.** Same reason; the window title is recorded instead, because `A_WorkingDir` would have been whip's own directory under a misleading column name.

---

## [1.0.0] — 2026-09-20

Initial version.

- Twelve hotkeys (`F1`–`F6`, `Shift+F1`–`Shift+F6`) firing pre-written slash commands into Claude Code.
- Twelve skills with `disable-model-invocation: true`.
- Layered shaped-window whip renderer.
- Synthesized `whip.wav`, generated locally with no download.
- Static bottom-right HUD, tray menu, `config.ini` with remappable keys.
- Title-based detection scoping every hotkey, so the function keys behave normally everywhere else.

Shipped with the whip invisible and the crack inaudible. Both fixed in 2.0.0.
