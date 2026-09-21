#Requires AutoHotkey v2.0

; "Force" would be simpler, but it makes every launch kill whatever is already
; running - including `whip.ahk --doctor`, whose whole job is to report on the
; live instance, and `--pick`, which exists to fix a broken one. With Off, the
; direct-call flags run alongside the resident whip and the normal launch takes
; over explicitly via ReplaceResident().
#SingleInstance Off

; Regions are computed and applied to the overlays while they are still
; hidden, so the first frame appears already shaped instead of flashing a
; full-screen rectangle. Without this, "ahk_id" cannot match a hidden window
; and every WinSetRegion/WinSetTransparent fails with "Target window not found".
DetectHiddenWindows(true)
;
; claude-whip - twelve hotkeys that fire pre-written slash commands into
; Claude Code, each with a synthesized whip crack and a full-screen bullwhip.
;
; It does not make the model think faster. Nothing does. It makes the prompts
; you never bother typing cost one keystroke.
;
; RENDERING NOTE
; AHK cannot draw an anti-aliased curve onto the desktop. What it can do is
; set an arbitrary polygonal *region* on a borderless window, which clips that
; window to any shape you like. A shaped window is one flat colour, so a single
; window gives you a silhouette, not leather. Stacking several shaped windows -
; two motion-blur ghosts behind, the body, a thin offset highlight on top -
; is what produces depth. That layering is the whole trick.
;

; ---------------------------------------------------------------------------
; paths and state
; ---------------------------------------------------------------------------
IniPath := A_ScriptDir "\config.ini"
LogPath := A_ScriptDir "\whip.log"
WavPath := A_ScriptDir "\whip.wav"
StatsPath := A_ScriptDir "\stats.csv"

WHIP_VERSION := "2.0.0"
WHIP_REPO    := "rrkher059/claude-whip"

; The terminals whose *process* counts as a Claude Code window regardless of
; what the title currently says. See ActiveIsClaude() for why this exists.
DEFAULT_TERMINALS := "WindowsTerminal.exe,powershell.exe,pwsh.exe,cmd.exe,wezterm-gui.exe,alacritty.exe"

; Everything at script scope is already global in v2.
Cfg        := Map()
Titles     := []
Terminals  := []
CfgStamp   := ""
Standalone := false
ConOut     := ""
Keys       := []
Animating  := false
Paused     := false
LastMiss   := ""
Win        := Map()
Hud        := ""
HudEdge    := ""
HudShown   := false
HudX       := -99999
HudY       := -99999
Registered := []
ConfirmAt  := 0

; --- v2 UI state ---
FirstRun      := false
HudTab        := ""      ; the small always-visible tab (clickable)
HudPanel      := ""      ; the expanded binding list (click-through)
HudEdge       := ""      ; hairline border behind the panel
HudTabEdge    := ""
ToastWin      := ""
ToastEdge     := ""
HudExpanded   := false
HudTabShown   := false
HudPanelShown := false
HudDragging   := false
LastFireAt    := 0
ShiftSince    := 0
ToastUntil    := 0
Descs         := Map()
NoMatchMs     := 0
DetectNagged  := false
UndoUntil     := 0
UndoTarget    := 0
ArgHist       := []
WelcomeWin    := ""
StatsWin      := ""
ChainAbort    := false
NagWin        := ""
PickWin       := ""
PickList      := ""
PickEdit      := ""
PickProcs     := []
PalWin        := ""
PalEdit       := ""
PalList       := ""
PalRows       := []
PalTarget     := 0
ArgWin        := ""
ArgEdit       := ""
ArgResult     := ""
ArgDone       := false
ArgHistIdx    := 0

HUD_TAB_W := 92
HUD_TAB_H := 26
HUD_PAN_W := 246
HUD_PAN_H := 158

; command name -> behaviour. Attached to the command rather than the key so a
; remapped binding keeps sane semantics.
NeedsArgs    := Map("decide", true, "debt", true, "why", true)
NeedsConfirm := Map("ship", true)

DEFAULT_KEYS := [ ["F1","whip"],  ["F2","redteam"], ["F3","ship"]
                , ["F4","decide"],["F5","scale"],   ["F6","unstuck"]
                , ["+F1","orient"],["+F2","secure"],["+F3","test"]
                , ["+F4","debt"], ["+F5","user"],   ["+F6","handoff"]
                , ["^F1","cost"], ["^F2","why"],    ["^F3","simplify"]
                , ["^F4","onboard"] ]

; ---------------------------------------------------------------------------
; themes - add one in four lines: pick ten colours, give it a name, done.
;   g1/g2  motion-blur ghosts      under  shadowed underside of the leather
;   body   the leather itself      band   the three grip wraps
;   crk    the cracker (last 7%)   hi     light along the top edge
;   core/ring/spark                the snap
; ---------------------------------------------------------------------------
THEMES := Map(
    "leather", Map("g1","2A1A0F", "g2","3A2415", "under","1F1208", "body","4E3018", "band","2E1B0D"
                 , "crk","5A3A1C", "hi","8A6034", "core","FFFFFF", "ring","FFE9B0", "spark","FFF4D6"),

    "midnight", Map("g1","070910", "g2","0E131F", "under","04060A", "body","161C2B", "band","0F1420"
                 , "crk","1E2639", "hi","5B87C7", "core","E8F2FF", "ring","A8C8F0", "spark","D6E8FF"),

    "ember",    Map("g1","1A0A04", "g2","2A1006", "under","120703", "body","3A1508", "band","240D05"
                 , "crk","6B2A0A", "hi","E2761F", "core","FFF2D0", "ring","FFB259", "spark","FFD9A0"),

    ; deliberately the darkest body of the four - a pale whip is invisible on a
    ; light terminal. "bone" is the ivory highlight, not the leather.
    "bone",     Map("g1","8C8377", "g2","6E6558", "under","332E27", "body","6B6257", "band","4A443B"
                 , "crk","7E7568", "hi","D8CFBD", "core","3A342C", "ring","7E7568", "spark","4A443B"))

Theme := THEMES["leather"]

HotIfFn := (*) => IsClaude()

FirstRun := !FileExist(IniPath)
LoadCfg()
LoadDescs()

; --- direct-call flags -------------------------------------------------
; These do one thing and exit, and they run *alongside* a resident whip
; rather than replacing it. Reporting on a live instance, or fixing its
; detection, is useless if invoking it is what takes the HUD away.
for arg in A_Args {
    if (arg = "--doctor") {
        Standalone := true
        EnsureConsole()
        Doctor()
        ExitApp()
    }
    if (arg = "--pick") {
        Standalone := true
        EnsureConsole()
        ShowPicker()
        ; GUI callbacks run during Sleep, so this is the message pump. The
        ; resident instance picks the new terminals= up via WatchCfg().
        while (IsObject(PickWin))
            Sleep(100)
        ExitApp()
    }
}

BuildOverlays()

; --test: one slow, loud crack on demand, then quit. No hotkeys, no HUD, so
; it can be verified without switching windows or focusing Claude. Like the
; other direct-call flags it leaves a resident whip running.
for i, arg in A_Args {
    if (arg = "--test") {
        Standalone := true
        ; --test [speed]   speed 1 = real time, default 12 = slow enough to watch
        spd := (A_Args.Has(i + 1) && IsNumber(A_Args[i + 1])) ? A_Args[i + 1] + 0 : 12
        Cfg["debug"] := 1
        LogLine("--test: screen " A_ScreenWidth "x" A_ScreenHeight ", DPI " A_ScreenDPI
              . ", theme " Cfg["theme"] ", speed " spd ", wav " WavPath)
        PlayCrackSound()
        ; demo over whatever window is in front, so confinement is visible
        Crack(spd, TargetRect(WinExist("A")))
        LogLine("--test: finished")
        Sleep(400)
        ExitApp()
    }
}

; Past this point we are the resident whip, so take over from any older one.
ReplaceResident()

BuildHud()
BindKeys()
BuildTray()
SetTimer(UpdateHud, 150)
SetTimer(DetectTick, 2000)
SetTimer(WatchCfg, 3000)
SetTimer(CheckUpdate, -6000)      ; once, well after startup; never blocks

wantWelcome := FirstRun
for arg in A_Args {
    if (arg = "--welcome")
        wantWelcome := true
    ; calls ShowPalette directly, so the palette can be exercised without
    ; depending on a synthetic keystroke reaching the hook
    if (arg = "--palette")
        SetTimer(ShowPalette, -300)
    if (arg = "--stats")
        SetTimer(ShowStats, -300)
}
if (wantWelcome)
    ShowWelcome()

; ---------------------------------------------------------------------------
; config
; ---------------------------------------------------------------------------
WriteDefaultCfg() {
    global IniPath, DEFAULT_KEYS, DEFAULT_TERMINALS
    IniWrite("",       IniPath, "whip", "sound")
    IniWrite("claude", IniPath, "whip", "titles")
    IniWrite(DEFAULT_TERMINALS, IniPath, "whip", "terminals")
    IniWrite("0",      IniPath, "whip", "debug")
    IniWrite("1",      IniPath, "whip", "hud")
    IniWrite("1",      IniPath, "whip", "volume")
    IniWrite("1",      IniPath, "whip", "animate")
    IniWrite("leather",IniPath, "whip", "theme")
    IniWrite("1",      IniPath, "whip", "shake")
    IniWrite("br",     IniPath, "whip", "hudcorner")
    IniWrite("^!p",    IniPath, "whip", "palette")
    IniWrite("ship",   IniPath, "whip", "confirm")
    for pair in DEFAULT_KEYS
        IniWrite(pair[2], IniPath, "keys", pair[1])

    ; Two example chains, commented out. A binding whose value contains "|"
    ; runs its steps in order.
    try FileAppend("`n; --- chains -------------------------------------------------------`n"
                 . "; A binding whose value contains | runs its steps in order. Between`n"
                 . "; steps you can put 'wait <seconds>'. Uncomment to use:`n"
                 . ";`n"
                 . "; F7=redteam | wait 45 | test`n"
                 . "; F8=secure | wait 60 | handoff`n"
                 , IniPath, "UTF-8")
}

; Windows' INI functions do not skip a UTF-8 BOM, so a config saved by an
; editor that adds one silently reads back as all-defaults. Rewrite it clean.
StripBom(path) {
    if (!FileExist(path))
        return
    try {
        raw := FileRead(path, "RAW")
        if (raw.Size < 3)
            return
        if (NumGet(raw, 0, "UChar") != 0xEF || NumGet(raw, 1, "UChar") != 0xBB || NumGet(raw, 2, "UChar") != 0xBF)
            return
        txt := FileRead(path, "UTF-8")          ; reading as UTF-8 drops the BOM
        f := FileOpen(path, "w", "UTF-8-RAW")   ; write it back without one
        f.Write(txt)
        f.Close()
    }
}

LoadCfg() {
    global Cfg, Titles, Terminals, Keys, IniPath, WavPath, DEFAULT_KEYS, DEFAULT_TERMINALS
    if (!FileExist(IniPath))
        WriteDefaultCfg()
    StripBom(IniPath)

    Cfg := Map()
    Cfg["sound"]   := Trim(IniRead(IniPath, "whip", "sound", ""))
    Cfg["titles"]  := Trim(IniRead(IniPath, "whip", "titles", "claude"))
    ; Absent key -> the default list. Present but empty -> genuinely empty,
    ; which is how you turn process matching off on purpose.
    Cfg["terminals"] := Trim(IniRead(IniPath, "whip", "terminals", DEFAULT_TERMINALS))
    Cfg["debug"]   := IniRead(IniPath, "whip", "debug",   "0") + 0
    Cfg["hud"]     := IniRead(IniPath, "whip", "hud",     "1") + 0
    Cfg["volume"]  := IniRead(IniPath, "whip", "volume",  "1") + 0
    Cfg["animate"] := IniRead(IniPath, "whip", "animate", "1") + 0
    Cfg["shake"]   := IniRead(IniPath, "whip", "shake",   "1") + 0
    Cfg["theme"]   := Trim(IniRead(IniPath, "whip", "theme", "leather"))
    Cfg["palette"]   := Trim(IniRead(IniPath, "whip", "palette", "^!p"))

    ; Which commands need a double-tap. Keyed on the command, not the key, so
    ; remapping a binding keeps its safety. Default is ship alone - the other
    ; writers only touch a file in the repo, which git can undo.
    Cfg["confirm"]   := Trim(IniRead(IniPath, "whip", "confirm", "ship"))
    global NeedsConfirm
    NeedsConfirm := Map()
    for c in StrSplit(Cfg["confirm"], ",") {
        c := Trim(c)
        if (c != "")
            NeedsConfirm[c] := true
    }
    Cfg["hudcorner"] := Trim(IniRead(IniPath, "whip", "hudcorner", "br"))
    if (!InStr("tl tr bl br", Cfg["hudcorner"]))
        Cfg["hudcorner"] := "br"

    global THEMES, Theme
    if (!THEMES.Has(Cfg["theme"])) {
        LogLine("unknown theme '" Cfg["theme"] "', falling back to leather")
        Cfg["theme"] := "leather"
    }
    Theme := THEMES[Cfg["theme"]]

    if (Cfg["sound"] != "")
        WavPath := Cfg["sound"]
    else
        WavPath := A_ScriptDir "\whip.wav"

    Titles := []
    for frag in StrSplit(Cfg["titles"], ",") {
        f := Trim(frag)
        if (f != "")
            Titles.Push(f)
    }
    Terminals := []
    for frag in StrSplit(Cfg["terminals"], ",") {
        f := Trim(frag)
        if (f != "")
            Terminals.Push(f)
    }
    ; Emptying one list is a choice; emptying both leaves the whip inert
    ; everywhere, which is never what anyone meant.
    if (Titles.Length = 0 && Terminals.Length = 0)
        Titles.Push("claude")

    global ArgHist
    ArgHist := []
    Loop 5 {
        h := Trim(IniRead(IniPath, "history", "h" A_Index, ""))
        if (h != "")
            ArgHist.Push(h)
    }

    ; Read the whole [keys] section rather than only the known defaults, so a
    ; user can add F7, F8 and so on - which is what makes chains useful.
    Keys := []
    raw := ""
    try raw := IniRead(IniPath, "keys")
    for line in StrSplit(raw, "`n") {
        line := Trim(line, " `t`r")
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        eq := InStr(line, "=")
        if (!eq)
            continue
        k := Trim(SubStr(line, 1, eq - 1))
        v := Trim(SubStr(line, eq + 1))
        if (k != "" && v != "")
            Keys.Push([k, v])
    }
    if (Keys.Length = 0) {
        for pair in DEFAULT_KEYS
            Keys.Push([pair[1], pair[2]])
    }
}

ReloadCfg(*) {
    global IniPath, CfgStamp
    LoadCfg()
    BuildHud()
    BindKeys()
    try CfgStamp := FileGetTime(IniPath, "M")
    Notify("config reloaded")
}

; Every write we make to config.ini goes through here, so WatchCfg() can tell
; our own writes apart from somebody else's and not reload on each one.
IniPut(val, section, key) {
    global IniPath, CfgStamp
    IniWrite(val, IniPath, section, key)
    try CfgStamp := FileGetTime(IniPath, "M")
}

; Picks up config.ini changing underneath us - a hand edit, or a standalone
; `whip.ahk --pick` that just saved terminals= from another process. Without
; this, --pick would only take effect on the next restart, which is exactly
; the restart we stopped forcing.
WatchCfg(*) {
    global IniPath, CfgStamp
    try stamp := FileGetTime(IniPath, "M")
    catch
        return
    if (CfgStamp = "") {
        CfgStamp := stamp
        return
    }
    if (stamp != CfgStamp)
        ReloadCfg()
}

; ---------------------------------------------------------------------------
; detection
; ---------------------------------------------------------------------------
MatchTitle(title) {
    global Titles
    if (title = "")
        return false
    for frag in Titles {
        if (InStr(title, frag))          ; v2 InStr is case-insensitive by default
            return true
    }
    return false
}

MatchProc(name) {
    global Terminals
    if (name = "")
        return false
    for p in Terminals {
        if (p = name)                    ; "=" is case-insensitive in v2
            return true
    }
    return false
}

; Used as the #HotIf criterion for every binding, so F1-F6 and Shift+F1-F6
; behave completely normally in every other application.
; Our own dialogs are titled "claude whip", which matches the default
; titles=claude. Without this, the hotkeys would be live over the welcome
; window, the picker and the palette.
ActiveIsOurs() {
    try return WinGetPID("A") = DllCall("GetCurrentProcessId", "UInt")
    return false
}

; Why this is not just a title check.
;
; Claude Code rewrites the terminal title continuously while it works - the
; spinner, the current tool, a token counter - so a titles= fragment that
; matched at the shell prompt stops matching a second after you press Enter.
; The symptom is the HUD disappearing the moment Claude Code starts and the
; hotkeys going inert exactly when you want them. Title matching cannot be
; made reliable; the window's *process* never changes.
;
; So: a known terminal binary is a match on its own, and titles= still works
; on top of it for anything not in terminals= (a browser tab, an editor, a
; terminal nobody has heard of).
;
; Returns "" for no match, otherwise the rule that matched - Doctor() and the
; debug log both want to say which one it was.
ActiveIsClaude() {
    if (ActiveIsOurs())
        return ""
    proc := "", title := ""
    try proc  := WinGetProcessName("A")
    try title := WinGetTitle("A")
    if (proc = "" && title = "")
        return ""
    if (MatchProc(proc))
        return "process " proc
    if (MatchTitle(title))
        return "title " title
    LogMiss(title " [" proc "]")
    return ""
}

IsClaude() {
    global Paused
    if (Paused)
        return false
    return ActiveIsClaude() != ""
}

LogLine(text) {
    global Cfg, LogPath
    if (!Cfg["debug"])
        return
    try FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "  " text "`n", LogPath, "UTF-8")
}

LogMiss(title) {
    global Cfg, LastMiss
    if (!Cfg["debug"] || title = "" || title = LastMiss)
        return
    LastMiss := title
    LogLine("no match: " title)
}

; ---------------------------------------------------------------------------
; geometry - the whip itself
; ---------------------------------------------------------------------------
; Returns ~60 sample points along the whip at time t (0..1), each carrying its
; position, unit tangent, unit perpendicular and half-width.
;
; Gross shape is a cubic bezier whose control points LAG the tip and then snap
; past it. On top of that rides the part that actually sells it: a gaussian
; bump travelling from handle to tip. Offsetting each sample perpendicular to
; its own tangent by amp * exp(-((s-p)/0.20)^2), with p walking from 0 to 1 as
; t advances, is a loop running down the leather. Without it this is a rope
; being swung. With it, it is a whip.
WhipSpine(t, W, H, N := 60) {
    if (t < -1)
        t := -1
    if (t > 1)
        t := 1

    hx := W * 1.06, hy := H * 0.88          ; handle, anchored off the right edge

    if (t < 0) {
        ; --- wind-up: the load-up. Pulls back and to the right while the tip
        ; lags behind the body, so the stroke has something to release.
        u    := t + 1                       ; 0 -> 1 across the wind-up
        ease := u * u * (3 - 2 * u)         ; smoothstep, no hard start
        tipX := W * (0.70 + 0.20 * ease)
        tipY := H * (0.46 - 0.38 * ease)
        lag  := 1 - ease
        c1x  := W * (0.88 + 0.14 * lag), c1y := H * (0.93 - 0.05 * ease)
        c2x  := W * (0.72 + 0.22 * lag), c2y := H * (0.68 - 0.36 * ease)
        p    := 0.32 * ease - 0.06          ; a small coil near the handle
        amp  := 5 + 13 * ease
        tipLag := -7 * ease                 ; tip trails the wind-up direction
    } else {
        ; The tip finishes just inside the left edge, not past it. Ending at
        ; W*-0.10 put the tip off-screen before the loop reached it, so the
        ; entire snap - core, ring, shards - was drawn outside the display.
        e    := 1 - (1 - t) ** 3            ; cubic ease-out on the tip
        tipX := (W * 0.90) + ((W * 0.035) - (W * 0.90)) * e
        tipY := (H * 0.08) + ((H * 0.72)  - (H * 0.08)) * e

        lag := 1 - t                        ; control points trail, then overshoot
        c1x := W * (0.80 + 0.24 * lag), c1y := H * (0.94 - 0.46 * t)
        c2x := W * (0.38 + 0.54 * lag), c2y := H * (0.16 + 0.70 * lag)

        p   := t * 1.15 - 0.05              ; loop position along the whip
        amp := 30 * (1 - t) + 7             ; loop amplitude, shrinking as it runs out
        if (t > 0.94)
            amp *= 0.25                     ; collapses as the tip snaps past

        ; The cracker does not follow the body rigidly - it trails, peaking
        ; mid-stroke and releasing at the end. This is the beat of delay that
        ; makes the last 7% read as the part breaking the sound barrier.
        tipLag := 26 * Sin(3.14159265358979 * t) * (1 - 0.55 * t)
    }

    raw := []
    Loop N + 1 {
        s := (A_Index - 1) / N
        u := 1 - s
        bx := u*u*u*hx + 3*u*u*s*c1x + 3*u*s*s*c2x + s*s*s*tipX
        by := u*u*u*hy + 3*u*u*s*c1y + 3*u*s*s*c2y + s*s*s*tipY
        raw.Push({x: bx, y: by, s: s})
    }

    pts := []
    Loop raw.Length {
        i    := A_Index
        cur  := raw[i]
        prev := raw[Max(i - 1, 1)]
        nxt  := raw[Min(i + 1, raw.Length)]

        dx  := nxt.x - prev.x
        dy  := nxt.y - prev.y
        len := Sqrt(dx*dx + dy*dy)
        if (len < 0.0001)
            len := 0.0001
        tx := dx / len, ty := dy / len      ; unit tangent
        px := -ty,      py := tx            ; unit perpendicular

        s := cur.s
        q := (s - p) / 0.20
        g := Exp(-(q * q))                  ; the travelling crack

        ; cracker lag, ramping in over the last tenth so it stays attached
        extra := 0
        if (s > 0.90) {
            k := (s - 0.90) / 0.10
            extra := tipLag * k * k
        }

        ; Widths are half-widths and scale with the display: the original
        ; fixed values were tuned as if for a small window and read as a
        ; hairline across a 1440p screen.
        ws := H / 560.0
        if (s < 0.06)
            wd := 8.5 * ws                  ; grip
        else if (s > 0.93)
            wd := 0.7 * ws                  ; cracker
        else
            wd := (7.6 * (1 - s) ** 1.45 + 0.8) * ws

        pts.Push({ x: cur.x + px * (amp * g + extra)
                 , y: cur.y + py * (amp * g + extra)
                 , px: px, py: py, tx: tx, ty: ty, w: wd, s: s })
    }
    return pts
}

; Walk forward along one perpendicular offset and back along the other, closing
; the shape. `lateral` shifts the centreline sideways (used for the highlight).
; dx/dy shift the whole shape - used for the shadowed underside layer and for
; the one-frame screen shake. sFrom/sTo draw only part of the whip, so the
; cracker can be its own window in its own colour.
PolyFromSpine(pts, wmul := 1.0, lateral := 0.0, dx := 0, dy := 0, sFrom := 0.0, sTo := 1.0) {
    fwd := "", back := "", n := 0
    for i, pt in pts {
        if (pt.s < sFrom || pt.s > sTo)
            continue
        hw := pt.w * wmul
        if (hw < 0.5)
            hw := 0.5
        cx := pt.x + pt.px * lateral * pt.w + dx
        cy := pt.y + pt.py * lateral * pt.w + dy
        fwd  .= Round(cx + pt.px * hw) "-" Round(cy + pt.py * hw) " "
        back := Round(cx - pt.px * hw) "-" Round(cy - pt.py * hw) " " back
        n += 1
    }
    if (n < 2)
        return ""
    ; No "Polygon" keyword: AHK v2 rejects it outright. Three or more bare
    ; points already produce a polygonal region.
    return RTrim(fwd back)
}

; The highlight is not a scaled copy of the body. Light catches the leather
; across the middle of the arc and dies before the tip, so it has its own
; taper that peaks mid-whip and closes to nothing at both ends.
HighlightPoly(pts, dx := 0, dy := 0) {
    fwd := "", back := "", n := 0, sEnd := 0.80
    for i, pt in pts {
        if (pt.s < 0.04 || pt.s > sEnd)
            continue
        k  := (pt.s - 0.04) / (sEnd - 0.04)
        hw := pt.w * 0.52 * Sin(3.14159265358979 * k)
        if (hw < 0.5)
            hw := 0.5
        cx := pt.x + pt.px * 0.45 * pt.w + dx
        cy := pt.y + pt.py * 0.45 * pt.w + dy
        fwd  .= Round(cx + pt.px * hw) "-" Round(cy + pt.py * hw) " "
        back := Round(cx - pt.px * hw) "-" Round(cy - pt.py * hw) " " back
        n += 1
    }
    if (n < 2)
        return ""
    return RTrim(fwd back)
}

; An ARC, not a full ring, built like the whip ribbon: trace the outer radius
; forward and the inner radius back. A complete circle with shards coming off
; it reads unavoidably as a wagon wheel; a partial arc on the leading side
; reads as a shockwave.
ArcPoly(cx, cy, r, thickness, aStartDeg, aEndDeg) {
    rIn := r - thickness
    if (rIn < 1)
        rIn := 1
    a0 := aStartDeg * 3.14159265358979 / 180
    a1 := aEndDeg   * 3.14159265358979 / 180
    fwd := "", back := ""
    Loop 25 {
        a  := a0 + (a1 - a0) * (A_Index - 1) / 24
        co := Cos(a), si := Sin(a)
        fwd  .= Round(cx + co * r)   "-" Round(cy + si * r)   " "
        back := Round(cx + co * rIn) "-" Round(cy + si * rIn) " " back
    }
    return RTrim(fwd back)
}

; AHK v2 has no ATan2.
Atan2Deg(y, x) {
    PI := 3.14159265358979
    if (x > 0)
        a := ATan(y / x)
    else if (x < 0)
        a := ATan(y / x) + (y >= 0 ? PI : -PI)
    else
        a := (y > 0 ? PI/2 : -PI/2)
    return a * 180 / PI
}

; A short band across the grip, so the handle reads as bound leather.
BandPoly(pts, sCenter, halfLen, hwMul) {
    best := 1
    for i, pt in pts {
        if (Abs(pt.s - sCenter) < Abs(pts[best].s - sCenter))
            best := i
    }
    pt := pts[best]
    hw := pt.w * hwMul
    ax := pt.x + pt.tx * halfLen, ay := pt.y + pt.ty * halfLen
    bx := pt.x - pt.tx * halfLen, by := pt.y - pt.ty * halfLen
    return Round(ax + pt.px*hw) "-" Round(ay + pt.py*hw) " " Round(bx + pt.px*hw) "-" Round(by + pt.py*hw) " " Round(bx - pt.px*hw) "-" Round(by - pt.py*hw) " " Round(ax - pt.px*hw) "-" Round(ay - pt.py*hw)
}

; Shards start at innerR, not at the tip itself. Radiating every shard from a
; single point reads as a spoked wheel; starting them clear of the core reads
; as debris thrown off the crack.
SparkPoly(cx, cy, angleDeg, innerR, len, halfW) {
    a  := angleDeg * 3.14159265358979 / 180
    dx := Cos(a), dy := Sin(a)
    px := -dy,    py := dx
    sx := cx + dx * innerR,         sy := cy + dy * innerR
    ex := cx + dx * (innerR + len), ey := cy + dy * (innerR + len)
    return Round(sx + px*halfW) "-" Round(sy + py*halfW) " " Round(ex + px*0.4) "-" Round(ey + py*0.4) " " Round(ex - px*0.4) "-" Round(ey - py*0.4) " " Round(sx - px*halfW) "-" Round(sy - py*halfW)
}

; ---------------------------------------------------------------------------
; overlay windows
; ---------------------------------------------------------------------------
MakeOverlay(colour) {
    ; E0x08000020 = WS_EX_NOACTIVATE | WS_EX_TRANSPARENT.
    ; TRANSPARENT alone only makes it click-through - the window can still be
    ; activated, and hiding an activated window leaves focus unsettled long
    ; enough to swallow the keystrokes we send immediately afterwards.
    ; NOACTIVATE means it never takes focus in the first place.
    g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000020 +Disabled -DPIScale")
    g.BackColor := colour
    g.Show("NA x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    WinSetTransparent(0, "ahk_id " g.Hwnd)
    g.Hide()
    return g
}

BuildOverlays() {
    global Win, Theme
    Win["g1"]    := MakeOverlay(Theme["g1"])      ; ghost, t-0.10
    Win["g2"]    := MakeOverlay(Theme["g2"])      ; ghost, t-0.05
    Win["under"] := MakeOverlay(Theme["under"])   ; shadowed underside
    Win["body"]  := MakeOverlay(Theme["body"])    ; the leather
    Win["b1"]    := MakeOverlay(Theme["band"])    ; grip wraps
    Win["b2"]    := MakeOverlay(Theme["band"])
    Win["b3"]    := MakeOverlay(Theme["band"])
    Win["crk"]   := MakeOverlay(Theme["crk"])     ; the cracker, last 7%
    Win["hi"]    := MakeOverlay(Theme["hi"])      ; light along the top edge
    Win["core"]  := MakeOverlay(Theme["core"])    ; snap: bright core
    Win["ring"]  := MakeOverlay(Theme["ring"])    ; snap: expanding ring
    Loop 6
        Win["s" A_Index] := MakeOverlay(Theme["spark"])
}

; High-resolution clock. A_TickCount only moves in ~15ms steps, which cannot
; measure an 8ms frame budget.
NowMs() {
    static freq := 0
    if (!freq)
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
    return c * 1000.0 / freq
}

SetRegion(key, spec, frame := 0) {
    global Win
    if (spec = "") {            ; segment produced no points this frame
        HideWin(key)
        return
    }
    ; A bad frame is skipped rather than fatal, but it is never silent:
    ; swallowing these is what hid the Polygon-keyword bug.
    try {
        WinSetRegion(spec, "ahk_id " Win[key].Hwnd)
    } catch as e {
        LogLine("WinSetRegion FAILED frame " frame " layer " key ": " e.Message " | " SubStr(spec, 1, 120))
    }
}

ShowWin(key, alpha, rect) {
    global Win
    try {
        WinSetTransparent(alpha, "ahk_id " Win[key].Hwnd)
        Win[key].Show("NA x" rect.x " y" rect.y " w" rect.w " h" rect.h)
    } catch as e {
        LogLine("ShowWin FAILED layer " key ": " e.Message)
    }
}

; The whip plays across the terminal, not the whole desktop. Each overlay is
; sized to the target window, and because regions are window-relative the
; geometry is simply computed in that window's coordinate space - anything
; outside it is clipped for free.
TargetRect(hwnd := 0) {
    if (hwnd) {
        try {
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            if (w > 240 && h > 160)
                return {x: x, y: y, w: w, h: h}
        }
    }
    return {x: 0, y: 0, w: A_ScreenWidth, h: A_ScreenHeight}
}

HideWin(key) {
    global Win
    try Win[key].Hide()
}

HideAll() {
    global Win
    for key, g in Win
        HideWin(key)
}

; ---------------------------------------------------------------------------
; the animation
; ---------------------------------------------------------------------------
; Frame budget in ms. A whip crack is anticipation, then violence, then
; stillness - a uniform frame time reads as a swinging rope.
;   1-5   wind-up          6-8   early stroke, still slow
;   9-20  the loop running down the leather, fast
;   21    the snap, held
;   22-26 fade out
; Nominal total is ~292ms. Real elapsed lands ~360ms because each frame also
; pays for nine full-screen SetWindowRgn repaints, which no amount of sample
; reduction removes.
FrameMs(f) {
    if (f <= 8)
        return 16
    if (f <= 20)
        return 8
    if (f = 21)
        return 28
    return 8
}

Crack(speed := 1.0, rect := 0) {
    global Win, Cfg

    if (!IsObject(rect))
        rect := TargetRect()
    W := rect.w, H := rect.h
    FRAMES  := 26
    WINDUP  := 5                ; frames 1..5 are the load-up
    STROKE  := FRAMES - 5 - 5   ; frames 6..21 carry t from 0 to 1
    SNAP    := 21
    ORDER   := ["g1","g2","under","body","b1","b2","b3","crk","hi"]
    BASE    := Map("g1",38, "g2",77, "under",205, "body",255, "b1",255, "b2",255
                 , "b3",255, "crk",255, "hi",235)
    ; Offset from the tip's direction of travel, length, half-width - irregular
    ; in all three. Clustered ahead of the tip rather than spread over 360
    ; degrees, because debris goes where the tip was going.
    SPARKS  := [[-61,21,1.9],[-27,35,1.4],[-8,17,2.2],[13,40,1.3],[36,25,1.7],[69,30,1.5]]
    N       := 60               ; sample count, dropped under load by the perf guard
    degraded := false
    sc      := H / 560.0        ; everything scales with the display
    tStart  := NowMs()

    ; Windows' default timer granularity is ~15ms, so Sleep(8) sleeps 15 and
    ; the whole animation runs ~100ms long. Ask for 1ms for the ~350ms we need
    ; it, and always give it back.
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    try {
        Loop FRAMES {
            f      := A_Index
            budget := FrameMs(f) * speed
            t0     := NowMs()

            if (f <= WINDUP)
                t := -1 + (f - 1) / WINDUP
            else if (f <= SNAP)
                t := (f - WINDUP - 1) / STROKE
            else
                t := 1.0

            ; one-frame screen shake on the snap
            shx := 0, shy := 0
            if (Cfg["shake"] && f = SNAP)
                shx := Round(-3 * sc), shy := Round(2 * sc)

            ; Past the snap the whip is frozen at t=1 and only its opacity
            ; changes, so re-applying nine identical regions would be pure
            ; cost. Each WinSetRegion forces a full repaint of a full-screen
            ; window - that, not the sample maths, dominates the frame time.
            spine := WhipSpine(t, W, H, N)
            if (f <= SNAP) {
                SetRegion("g1",    PolyFromSpine(WhipSpine(t - 0.10, W, H, N), 1.0, 0, shx, shy), f)
                SetRegion("g2",    PolyFromSpine(WhipSpine(t - 0.05, W, H, N), 1.0, 0, shx, shy), f)
                SetRegion("under", PolyFromSpine(spine, 1.0, 0, shx + Round(3*sc), shy + Round(2*sc)), f)
                SetRegion("body",  PolyFromSpine(spine, 1.0, 0, shx, shy, 0.0, 0.935), f)
                SetRegion("crk",   PolyFromSpine(spine, 1.0, 0, shx, shy, 0.90, 1.0), f)
                SetRegion("hi",    HighlightPoly(spine, shx, shy), f)
                SetRegion("b1",    BandPoly(spine, 0.014, 3.2, 1.35), f)
                SetRegion("b2",    BandPoly(spine, 0.038, 3.0, 1.25), f)
                SetRegion("b3",    BandPoly(spine, 0.066, 2.8, 1.25), f)
            }

            fade := 1.0
            if (f > SNAP)
                fade := (FRAMES - f + 1) / (FRAMES - SNAP + 1.0)

            if (f = 1) {
                for key in ORDER
                    ShowWin(key, BASE[key], rect)
            } else if (fade < 1.0) {
                for key in ORDER
                    try WinSetTransparent(Round(BASE[key] * fade), "ahk_id " Win[key].Hwnd)
            }

            ; --- the snap: core, a ring expanding over three frames, shards
            if (f >= SNAP - 1 && f <= SNAP + 1) {
                k   := f - (SNAP - 1)               ; 0, 1, 2
                tip := spine[spine.Length]
                ; core shrinks and dims fast; the arc expands and thins as it
                ; goes, so it dissipates instead of sitting there
                ang := Atan2Deg(tip.ty, tip.tx)
                d   := Round((22 - k * 6) * sc)
                SetRegion("core", Round(tip.x - d/2) "-" Round(tip.y - d/2) " W" d " H" d " E", f)
                ShowWin("core", 230 - k * 85, rect)

                SetRegion("ring", ArcPoly(tip.x, tip.y, (18 + k * 40) * sc, (3.6 - k * 1.1) * sc
                        , ang - 74, ang + 74), f)
                ShowWin("ring", 88 - k * 32, rect)

                inner := d / 2 + 6 * sc
                for i, sp in SPARKS {
                    SetRegion("s" i, SparkPoly(tip.x, tip.y, ang + sp[1], inner
                            , sp[2] * sc * (0.55 + 0.40 * k), sp[3] * sc), f)
                    ShowWin("s" i, 140 - k * 52, rect)
                }
            } else if (f = SNAP + 2) {
                HideWin("core"), HideWin("ring")
                Loop 6
                    HideWin("s" A_Index)
            }

            ; --- performance guard: never make the machine feel slow.
            ; The three snap frames are exempt - they legitimately drive eight
            ; extra windows, and degrading the whip because of them would be
            ; punishing the one frame that matters most.
            ; The absolute floor matters more than the ratio: a 20ms frame is
            ; not making the machine feel slow, and degrading the whip for it
            ; would be crying wolf on every single crack.
            spent := NowMs() - t0
            ; frame 1 shows nine windows for the first time and the three snap
            ; frames drive eight more - both are legitimately expensive and
            ; neither means the machine is struggling
            isSnap := (f >= SNAP - 1 && f <= SNAP + 1)
            if (!degraded && f > 1 && !isSnap && spent > Max(budget * 2, 34) && N > 24) {
                N := 24
                degraded := true
                LogLine("perf: frame " f " took " Round(spent, 1) "ms against a "
                      . Round(budget, 1) "ms budget; dropped samples 60 -> 24")
            }
            rest := budget - (NowMs() - t0)
            if (rest >= 1)
                Sleep(Round(rest))
        }
    }
    finally {
        DllCall("winmm\timeEndPeriod", "UInt", 1)
        HideAll()       ; never leave a window on screen, whatever went wrong
        LogLine("crack: " FRAMES " frames in " Round(NowMs() - tStart) "ms"
              . " (speed " speed ", samples " N ")")
    }
}

; ---------------------------------------------------------------------------
; HUD
; ---------------------------------------------------------------------------
KeyLabel(k) {
    k := StrReplace(k, "+", "S+")
    k := StrReplace(k, "^", "C+")
    return k
}

; Descriptions come from each skill's own frontmatter, so editing a SKILL.md
; updates the palette and the HUD without touching this file.
LoadDescs() {
    global Descs, Keys
    Descs := Map()
    for pair in Keys {
        cmd := pair[2], d := ""
        if (InStr(cmd, "|")) {
            Descs[cmd] := "chain: " cmd
            continue
        }
        f := EnvGet("USERPROFILE") "\.claude\skills\" cmd "\SKILL.md"
        if (FileExist(f)) {
            try {
                txt := FileRead(f, "UTF-8")
                if (RegExMatch(txt, "m)^description:[ \t]*(.+)$", &m))
                    d := Trim(m[1])
            }
        }
        Descs[cmd] := (d != "") ? d : "no description found on disk"
    }
}

ShortDesc(cmd, maxLen := 88) {
    global Descs
    d := Descs.Has(cmd) ? Descs[cmd] : ""
    if (StrLen(d) > maxLen)
        d := SubStr(d, 1, maxLen - 1) "..."
    return d
}

; ---------------------------------------------------------------------------
; HUD - a small tab by default, expanding to the full list on hover or Shift
; ---------------------------------------------------------------------------
; "^+j" -> "Ctrl+Shift+J", for anything shown to a human.
PrettyChord(c) {
    out := ""
    while (c != "" && InStr("^+!#", SubStr(c, 1, 1))) {
        ch := SubStr(c, 1, 1)
        out .= (ch = "^") ? "Ctrl+" : (ch = "+") ? "Shift+" : (ch = "!") ? "Alt+" : "Win+"
        c := SubStr(c, 2)
    }
    return out . (StrLen(c) = 1 ? StrUpper(c) : c)
}

BuildHud() {
    global HudTab, HudTabEdge, HudPanel, HudEdge, Keys, Cfg
    global HudTabShown, HudPanelShown, HudExpanded
    global HUD_TAB_W, HUD_TAB_H, HUD_PAN_W, HUD_PAN_H

    for g in [HudTab, HudTabEdge, HudPanel, HudEdge] {
        if (IsObject(g))
            try g.Destroy()
    }
    HudTabShown := false, HudPanelShown := false, HudExpanded := false

    ; --- the tab. NOT click-through: it has to receive hover and drags.
    ; NOACTIVATE still keeps it from ever stealing focus from the terminal.
    HudTabEdge := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000 -DPIScale")
    HudTabEdge.BackColor := "332C24"
    HudTab := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000 -DPIScale")
    HudTab.BackColor := "181410"
    HudTab.MarginX := 0, HudTab.MarginY := 0
    HudTab.SetFont("s9 Bold", "Segoe UI")
    tx := HudTab.Add("Text", "x0 y4 w" (HUD_TAB_W - 2) " h18 Center BackgroundTrans cC9A227", Chr(0x26A1) " whip")
    tx.OnEvent("Click", (*) => DragHud())

    ; --- the expanded panel, click-through like the overlays
    HudEdge := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000020 +Disabled -DPIScale")
    HudEdge.BackColor := "332C24"
    HudPanel := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000020 +Disabled -DPIScale")
    HudPanel.BackColor := "181410"
    HudPanel.MarginX := 0, HudPanel.MarginY := 0

    col1 := "", col2 := ""
    half := Ceil(Keys.Length / 2)
    for i, pair in Keys {
        shown := IsChain(pair[2]) ? ChainLabel(pair[2]) : pair[2]
        line := Format("{:-5}", KeyLabel(pair[1])) " " shown
        if (i <= half)
            col1 .= (col1 = "" ? "" : "`n") line
        else
            col2 .= (col2 = "" ? "" : "`n") line
    }
    HudPanel.SetFont("s8 Bold", "Consolas")
    HudPanel.Add("Text", "x0 y5 w" (HUD_PAN_W - 2) " h15 Center BackgroundTrans cC9A227", "~ claude whip ~")
    HudPanel.SetFont("s8 Norm", "Consolas")
    HudPanel.Add("Text", "x10 y24 w112 h124 BackgroundTrans c8A7F72", col1)
    HudPanel.Add("Text", "x126 y24 w112 h124 BackgroundTrans c8A7F72", col2)
    HudPanel.SetFont("s7 Norm", "Consolas")
    HudPanel.Add("Text", "x0 y" (HUD_PAN_H - 16) " w" (HUD_PAN_W - 2) " h12 Center BackgroundTrans c6A6056"
               , PrettyChord(Cfg["palette"]) " for all commands")
}

; Where the tab sits inside the terminal, per the saved corner.
HudAnchor(rect) {
    global Cfg, HUD_TAB_W, HUD_TAB_H
    pad := 18
    c := Cfg["hudcorner"]
    x := InStr(c, "l") ? rect.x + pad : rect.x + rect.w - HUD_TAB_W - pad
    y := InStr(c, "t") ? rect.y + pad : rect.y + rect.h - HUD_TAB_H - pad
    return {x: x, y: y}
}

UpdateHud(*) {
    global Cfg, Paused, HudTab, HudTabEdge, HudPanel, HudEdge
    global HudTabShown, HudPanelShown, HudDragging
    global LastFireAt, ShiftSince, ToastUntil
    global HUD_TAB_W, HUD_TAB_H, HUD_PAN_W, HUD_PAN_H

    if (ToastUntil && A_TickCount > ToastUntil)
        HideToast()

    if (HudDragging)
        return
    if (!Cfg["hud"] || Paused) {
        HideHud()
        return
    }
    try {
        hwnd := WinGetID("A")
    } catch {
        HideHud()
        return
    }
    if (ActiveIsClaude() = "") {
        HideHud()
        return
    }
    rect := TargetRect(hwnd)
    if (rect.w < HUD_PAN_W + 60 || rect.h < HUD_PAN_H + 60) {
        HideHud()
        return
    }
    a := HudAnchor(rect)

    ; idle fade: stop being visual noise 10s after the last fire
    alpha := (A_TickCount - LastFireAt > 10000) ? 89 : 255

    if (!HudTabShown) {
        try {
            WinSetTransparent(alpha, "ahk_id " HudTabEdge.Hwnd)
            WinSetTransparent(alpha, "ahk_id " HudTab.Hwnd)
            HudTabEdge.Show("NA x" (a.x - 1) " y" (a.y - 1) " w" (HUD_TAB_W + 2) " h" (HUD_TAB_H + 2))
            HudTab.Show("NA x" a.x " y" a.y " w" HUD_TAB_W " h" HUD_TAB_H)
            HudTabShown := true
        }
    } else {
        try {
            WinGetPos(&cx, &cy, , , "ahk_id " HudTab.Hwnd)
            if (cx != a.x || cy != a.y) {
                HudTabEdge.Move(a.x - 1, a.y - 1)
                HudTab.Move(a.x, a.y)
            }
            WinSetTransparent(alpha, "ahk_id " HudTabEdge.Hwnd)
            WinSetTransparent(alpha, "ahk_id " HudTab.Hwnd)
        }
    }

    ; --- expand on hover, or on Shift held for 400ms
    want := false
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    if (mx >= a.x - 4 && mx <= a.x + HUD_TAB_W + 4 && my >= a.y - 4 && my <= a.y + HUD_TAB_H + 4)
        want := true
    if (GetKeyState("Shift", "P")) {
        if (!ShiftSince)
            ShiftSince := A_TickCount
        else if (A_TickCount - ShiftSince >= 400)
            want := true
    } else {
        ShiftSince := 0
    }


    if (want && !HudPanelShown) {
        px := InStr(Cfg["hudcorner"], "l") ? a.x : a.x + HUD_TAB_W - HUD_PAN_W
        py := InStr(Cfg["hudcorner"], "t") ? a.y + HUD_TAB_H + 6 : a.y - HUD_PAN_H - 6
        try {
            WinSetTransparent(248, "ahk_id " HudEdge.Hwnd)
            WinSetTransparent(248, "ahk_id " HudPanel.Hwnd)
            HudEdge.Show("NA x" (px - 1) " y" (py - 1) " w" (HUD_PAN_W + 2) " h" (HUD_PAN_H + 2))
            HudPanel.Show("NA x" px " y" py " w" HUD_PAN_W " h" HUD_PAN_H)
            HudPanelShown := true
            LogLine("hud: expanded at " px "," py " " HUD_PAN_W "x" HUD_PAN_H)
        } catch as e {
            LogLine("hud: expand FAILED: " e.Message)
        }
    } else if (!want && HudPanelShown) {
        try HudPanel.Hide()
        try HudEdge.Hide()
        HudPanelShown := false
    }
}

HideHud() {
    global HudTab, HudTabEdge, HudPanel, HudEdge, HudTabShown, HudPanelShown
    if (HudPanelShown) {
        try HudPanel.Hide()
        try HudEdge.Hide()
        HudPanelShown := false
    }
    if (HudTabShown) {
        try HudTab.Hide()
        try HudTabEdge.Hide()
        HudTabShown := false
    }
}

; Drag the tab anywhere, then snap to the nearest corner of the terminal and
; remember it. Polled rather than message-based because the tab is a
; NOACTIVATE window and must never take focus from the terminal.
DragHud() {
    global HudTab, HudTabEdge, HudDragging, Cfg, IniPath, HUD_TAB_W, HUD_TAB_H
    try hwnd := WinGetID("A")
    catch
        return
    rect := TargetRect(hwnd)
    HudDragging := true
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    WinGetPos(&wx, &wy, , , "ahk_id " HudTab.Hwnd)
    ox := mx - wx, oy := my - wy
    while (GetKeyState("LButton", "P")) {
        MouseGetPos(&cx, &cy)
        try {
            HudTab.Move(cx - ox, cy - oy)
            HudTabEdge.Move(cx - ox - 1, cy - oy - 1)
        }
        Sleep(10)
    }
    WinGetPos(&fx, &fy, , , "ahk_id " HudTab.Hwnd)
    midX := rect.x + rect.w / 2, midY := rect.y + rect.h / 2
    corner := ((fy + HUD_TAB_H / 2) < midY ? "t" : "b") . ((fx + HUD_TAB_W / 2) < midX ? "l" : "r")
    Cfg["hudcorner"] := corner
    IniPut(corner, "whip", "hudcorner")
    HudDragging := false
    Toast("HUD -> " corner)
}

; ---------------------------------------------------------------------------
; toast
; ---------------------------------------------------------------------------
Toast(msg, ms := 1500) {
    global ToastWin, ToastEdge, ToastUntil, Cfg, HUD_TAB_H, HUD_TAB_W
    try {
        hwnd := WinGetID("A")
        rect := TargetRect(hwnd)
    } catch
        return
    HideToast()
    w := 30 + StrLen(msg) * 8, h := 26
    ToastEdge := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000020 +Disabled -DPIScale")
    ToastEdge.BackColor := "3A3226"
    ToastWin := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000020 +Disabled -DPIScale")
    ToastWin.BackColor := "1E1A14"
    ToastWin.MarginX := 0, ToastWin.MarginY := 0
    ToastWin.SetFont("s9 Bold", "Consolas")
    ToastWin.Add("Text", "x0 y5 w" w " h16 Center BackgroundTrans cD8C68A", msg)
    a := HudAnchor(rect)
    x := InStr(Cfg["hudcorner"], "l") ? a.x : a.x + HUD_TAB_W - w
    y := InStr(Cfg["hudcorner"], "t") ? a.y + HUD_TAB_H + 6 : a.y - h - 6
    try {
        ToastEdge.Show("NA x" (x - 1) " y" (y - 1) " w" (w + 2) " h" (h + 2))
        ToastWin.Show("NA x" x " y" y " w" w " h" h)
    }
    ToastUntil := A_TickCount + ms
}

HideToast() {
    global ToastWin, ToastEdge, ToastUntil
    ToastUntil := 0
    if (IsObject(ToastWin))
        try ToastWin.Destroy()
    if (IsObject(ToastEdge))
        try ToastEdge.Destroy()
    ToastWin := "", ToastEdge := ""
}

; ---------------------------------------------------------------------------
; firing
; ---------------------------------------------------------------------------
PlayCrackSound() {
    global WavPath, Cfg
    if (Cfg["volume"] = 0)
        return
    if (FileExist(WavPath)) {
        try {
            SoundPlay(WavPath)
            LogLine("sound: SoundPlay ok -> " WavPath)
            return
        } catch as e {
            LogLine("sound: SoundPlay THREW (" e.Message ") for " WavPath)
        }
    } else {
        LogLine("sound: file not found -> " WavPath)
    }
    SoundBeep(1100, 45)             ; fall back, keep working
    SoundBeep(1700, 35)
}

Notify(msg) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -1200)
}

IsChain(spec) {
    return InStr(spec, "|") != 0
}

; "redteam | wait 45 | test" -> "redteam +2"
ChainLabel(spec) {
    steps := StrSplit(spec, "|")
    return Trim(LTrim(Trim(steps[1]), "/")) " +" (steps.Length - 1)
}

Fire(key, cmd, *) {
    global Animating, Cfg, NeedsArgs, NeedsConfirm, ConfirmAt
    global LastFireAt, UndoUntil, UndoTarget

    if (Animating)                  ; ignore keys pressed mid-animation
        return

    if (IsChain(cmd)) {
        FireChain(key, cmd)
        return
    }

    if (NeedsConfirm.Has(cmd)) {
        if (A_TickCount - ConfirmAt > 900) {
            ConfirmAt := A_TickCount
            Toast("press again to " cmd, 900)
            return
        }
        ConfirmAt := 0
    }

    try target := WinGetID("A")
    catch
        return

    args := ""
    if (NeedsArgs.Has(cmd)) {
        r := ArgPrompt(cmd)
        if (!r.ok)
            return
        args := r.text
        try {                       ; the prompt took focus; give it back
            WinActivate("ahk_id " target)
            WinWaitActive("ahk_id " target, , 1)
        }
    }

    LastFireAt := A_TickCount
    PlayCrackSound()
    Animating := true
    try {
        if (Cfg["animate"])
            Crack(1.0, TargetRect(target))   ; whip plays across the terminal only
    }
    finally {
        Animating := false
    }

    payload := "/" cmd (args != "" ? " " args : "")
    SendText(payload)
    Sleep(30)
    Send("{Enter}")

    UndoUntil  := A_TickCount + 2000    ; Ctrl+Z interrupts for the next 2s
    UndoTarget := target
    RecordFire(cmd, target)
    Toast("/" cmd)
}

; ---------------------------------------------------------------------------
; undo affordance - Ctrl+Z within 2s of a fire interrupts Claude
; ---------------------------------------------------------------------------
UndoArmed() {
    global UndoUntil
    return (A_TickCount < UndoUntil)
}

DoUndo(*) {
    global UndoUntil, UndoTarget
    UndoUntil := 0
    try {
        if (UndoTarget)
            WinActivate("ahk_id " UndoTarget)
    }
    Send("{Esc}")
    Toast("cancelled")
}

; ---------------------------------------------------------------------------
; argument prompt - replaces InputBox
; ---------------------------------------------------------------------------
ArgPrompt(cmd) {
    global ArgHist, ArgWin, ArgResult, ArgDone, ArgEdit, ArgHistIdx

    ArgResult := {ok: false, text: ""}
    ArgDone   := false
    ArgHistIdx := 0

    ArgWin := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "/" cmd)
    ArgWin.BackColor := "181410"
    ArgWin.MarginX := 18, ArgWin.MarginY := 16
    ArgWin.SetFont("s11 Bold", "Consolas")
    ArgWin.Add("Text", "cC9A227", "/" cmd)
    ArgWin.SetFont("s9 Norm", "Consolas")
    ArgWin.Add("Text", "c8A7F72 w540", ShortDesc(cmd, 190))
    ArgEdit := ArgWin.Add("Edit", "w540 r5 Background201A14 cE8DCC8 -WantReturn")
    ArgWin.SetFont("s8 Norm", "Consolas")
    ArgWin.Add("Text", "c6A6056", "Ctrl+Enter  submit        Esc  cancel        Up  recall last 5")
    ArgWin.OnEvent("Escape", (*) => ArgCancel())
    ArgWin.OnEvent("Close",  (*) => ArgCancel())
    ArgWin.Show("AutoSize Center")
    ArgEdit.Focus()

    HotIf((*) => ArgActive())
    Hotkey("^Enter", (*) => ArgSubmit(), "On")
    Hotkey("Up",     (*) => ArgRecall(), "On")
    HotIf()

    while (!ArgDone)
        Sleep(20)

    HotIf((*) => ArgActive())
    try Hotkey("^Enter", "Off")
    try Hotkey("Up", "Off")
    HotIf()

    try ArgWin.Destroy()
    ArgWin := ""
    return ArgResult
}

ArgActive() {
    global ArgWin
    if (!IsObject(ArgWin))
        return false
    try return WinActive("ahk_id " ArgWin.Hwnd) != 0
    return false
}

ArgSubmit() {
    global ArgResult, ArgDone, ArgEdit, ArgHist, IniPath
    txt := Trim(ArgEdit.Value)
    txt := StrReplace(StrReplace(txt, "`r`n", " "), "`n", " ")
    ArgResult := {ok: true, text: txt}
    if (txt != "") {
        ArgHist.InsertAt(1, txt)
        while (ArgHist.Length > 5)
            ArgHist.Pop()
        Loop 5
            IniPut(ArgHist.Has(A_Index) ? ArgHist[A_Index] : "", "history", "h" A_Index)
    }
    ArgDone := true
}

ArgCancel() {
    global ArgResult, ArgDone
    ArgResult := {ok: false, text: ""}
    ArgDone := true
}

; Up only recalls when the box is empty, so it never fights the caret.
ArgRecall() {
    global ArgEdit, ArgHist, ArgHistIdx
    if (ArgHist.Length = 0)
        return
    if (Trim(ArgEdit.Value) != "" && ArgHistIdx = 0)
        return
    ArgHistIdx += 1
    if (ArgHistIdx > ArgHist.Length)
        ArgHistIdx := 1
    ArgEdit.Value := ArgHist[ArgHistIdx]
}

; ---------------------------------------------------------------------------
; command palette - Ctrl+Shift+Space
; ---------------------------------------------------------------------------
ShowPalette(*) {
    global Keys, PalWin, PalEdit, PalList, PalTarget, PalRows

    LogLine("palette: opened")
    if (IsObject(PalWin)) {
        try PalWin.Destroy()
        PalWin := ""
    }
    try PalTarget := WinGetID("A")
    catch
        return

    PalWin := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "claude whip")
    PalWin.BackColor := "181410"
    PalWin.MarginX := 14, PalWin.MarginY := 12
    PalWin.SetFont("s10 Norm", "Consolas")
    PalEdit := PalWin.Add("Edit", "w680 Background201A14 cE8DCC8")
    PalEdit.OnEvent("Change", (*) => PalFilter())
    PalWin.SetFont("s9 Norm", "Consolas")
    PalList := PalWin.Add("ListBox", "w680 r18 Background181410 cBFB3A4")
    PalList.OnEvent("DoubleClick", (*) => PalFire())
    go := PalWin.Add("Button", "x-200 y-200 w1 h1 Default", "go")
    go.OnEvent("Click", (*) => PalFire())
    PalWin.OnEvent("Escape", (*) => PalClose())
    PalWin.OnEvent("Close",  (*) => PalClose())

    PalFilter()
    PalWin.Show("AutoSize Center")
    PalEdit.Focus()

    HotIf((*) => PalActive())
    Hotkey("Down", (*) => PalMove(1), "On")
    Hotkey("Up",   (*) => PalMove(-1), "On")
    HotIf()
}

PalActive() {
    global PalWin
    if (!IsObject(PalWin))
        return false
    try return WinActive("ahk_id " PalWin.Hwnd) != 0
    return false
}

PalFilter() {
    global Keys, PalEdit, PalList, PalRows
    q := Trim(PalEdit.Value)
    items := [], PalRows := []
    for pair in Keys {
        label := KeyLabel(pair[1]), cmd := pair[2]
        if (IsChain(cmd))
            line := Format("{:-7}", label) Format("{:-12}", ChainLabel(cmd)) "chain: " SubStr(cmd, 1, 58)
        else
            line := Format("{:-7}", label) Format("{:-10}", "/" cmd) ShortDesc(cmd, 74)
        if (q = "" || InStr(line, q)) {
            items.Push(line)
            PalRows.Push(cmd)
        }
    }
    PalList.Delete()
    if (items.Length) {
        PalList.Add(items)
        PalList.Choose(1)
    }
}

PalMove(d) {
    global PalList, PalRows
    if (!PalRows.Length)
        return
    cur := PalList.Value
    if (!cur)
        cur := 1
    n := cur + d
    if (n < 1)
        n := PalRows.Length
    if (n > PalRows.Length)
        n := 1
    PalList.Choose(n)
}

PalFire() {
    global PalList, PalRows, PalTarget, Keys
    idx := PalList.Value
    if (!idx || !PalRows.Has(idx)) {
        PalClose()
        return
    }
    cmd := PalRows[idx]
    key := ""
    for pair in Keys {
        if (pair[2] = cmd) {
            key := pair[1]
            break
        }
    }
    PalClose()
    try {
        WinActivate("ahk_id " PalTarget)
        WinWaitActive("ahk_id " PalTarget, , 1)
    }
    Fire(key, cmd)
}

PalClose() {
    global PalWin
    HotIf((*) => PalActive())
    try Hotkey("Down", "Off")
    try Hotkey("Up", "Off")
    HotIf()
    if (IsObject(PalWin))
        try PalWin.Destroy()
    PalWin := ""
}

; ---------------------------------------------------------------------------
; first-run welcome
; ---------------------------------------------------------------------------
ShowWelcome() {
    global WelcomeWin, Keys

    if (IsObject(WelcomeWin))
        try WelcomeWin.Destroy()

    WelcomeWin := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "claude whip")
    WelcomeWin.BackColor := "181410"
    WelcomeWin.MarginX := 24, WelcomeWin.MarginY := 20
    WelcomeWin.SetFont("s14 Bold", "Consolas")
    WelcomeWin.Add("Text", "cC9A227", Chr(0x26A1) " claude whip")
    WelcomeWin.SetFont("s10 Norm", "Consolas")
    WelcomeWin.Add("Text", "cBFB3A4 w560"
        , "Twelve hotkeys that fire pre-written, high-leverage prompts into Claude Code.")
    WelcomeWin.SetFont("s9 Italic", "Consolas")
    WelcomeWin.Add("Text", "c8A7F72 w560"
        , "It does not make the model think faster. Nothing can. It makes the prompts you never bother typing cost one keystroke.")

    col1 := "", col2 := ""
    half := Ceil(Keys.Length / 2)
    for i, pair in Keys {
        line := Format("{:-7}", KeyLabel(pair[1])) "/" pair[2]
        if (i <= half)
            col1 .= (col1 = "" ? "" : "`n") line
        else
            col2 .= (col2 = "" ? "" : "`n") line
    }
    WelcomeWin.SetFont("s9 Norm", "Consolas")
    WelcomeWin.Add("Text", "xm y+14 w270 c8A7F72", col1)
    WelcomeWin.Add("Text", "x+20 yp w270 c8A7F72", col2)

    WelcomeWin.SetFont("s10 Bold", "Consolas")
    WelcomeWin.Add("Text", "xm y+18 cC9A227", "Press F1 now to try it - nothing is sent.")
    WelcomeWin.SetFont("s9 Norm", "Consolas")
    b := WelcomeWin.Add("Button", "xm y+12 w120", "Got it")
    b.OnEvent("Click", (*) => CloseWelcome())
    WelcomeWin.OnEvent("Close", (*) => CloseWelcome())
    WelcomeWin.Show("AutoSize Center")

    HotIf((*) => WelcomeActive())
    Hotkey("F1", (*) => WelcomeDemo(), "On")
    HotIf()
}

WelcomeActive() {
    global WelcomeWin
    if (!IsObject(WelcomeWin))
        return false
    try return WinActive("ahk_id " WelcomeWin.Hwnd) != 0
    return false
}

WelcomeDemo() {
    global WelcomeWin, Animating
    if (Animating || !IsObject(WelcomeWin))
        return
    Animating := true
    try {
        PlayCrackSound()
        Crack(1.0, TargetRect(WelcomeWin.Hwnd))
    }
    finally {
        Animating := false
    }
}

CloseWelcome() {
    global WelcomeWin
    HotIf((*) => WelcomeActive())
    try Hotkey("F1", "Off")
    HotIf()
    if (IsObject(WelcomeWin))
        try WelcomeWin.Destroy()
    WelcomeWin := ""
}

; ---------------------------------------------------------------------------
; terminal auto-detection - titles=claude is the number one failure mode
; ---------------------------------------------------------------------------
IsTerminalProc(name) {
    static list := "WindowsTerminal.exe|pwsh.exe|powershell.exe|cmd.exe|wezterm-gui.exe"
                 . "|alacritty.exe|OpenConsole.exe|conhost.exe|Hyper.exe|kitty.exe"
    return InStr(list, name) != 0
}

DetectTick(*) {
    global NoMatchMs, DetectNagged
    if (DetectNagged)
        return
    try proc := WinGetProcessName("A")
    catch
        return
    if (ActiveIsClaude() != "") {           ; detection works, stop watching
        SetTimer(DetectTick, 0)
        return
    }
    if (IsTerminalProc(proc)) {
        NoMatchMs += 2000
        if (NoMatchMs >= 60000) {
            DetectNagged := true
            SetTimer(DetectTick, 0)
            ShowDetectNag()
        }
    }
}

ShowDetectNag() {
    global NagWin
    if (IsObject(NagWin))
        try NagWin.Destroy()
    NagWin := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "claude whip")
    NagWin.BackColor := "181410"
    NagWin.MarginX := 18, NagWin.MarginY := 14
    NagWin.SetFont("s10 Bold", "Consolas")
    NagWin.Add("Text", "cC9A227", "claude whip can't find your Claude Code window")
    NagWin.SetFont("s9 Norm", "Consolas")
    NagWin.Add("Text", "c8A7F72 w460"
        , "Your terminal has been focused for a while, and it is neither in terminals= "
          "nor matched by titles=, so the hotkeys stay inert there. Pick it below and "
          "its process name gets added to terminals= for good.")
    b := NagWin.Add("Button", "w150", "Pick window")
    b.OnEvent("Click", (*) => (CloseNag(), ShowPicker()))
    b2 := NagWin.Add("Button", "x+10 yp w110", "Ignore")
    b2.OnEvent("Click", (*) => CloseNag())
    NagWin.OnEvent("Close", (*) => CloseNag())
    NagWin.Show("AutoSize Center")
}

CloseNag() {
    global NagWin
    if (IsObject(NagWin))
        try NagWin.Destroy()
    NagWin := ""
}

; The picker saves the *process name*, not the title - a title picked here
; would stop matching the moment Claude Code started rewriting it, which is
; the bug this whole path exists to work around.
ShowPicker(*) {
    global PickWin, PickList, PickEdit, PickProcs, Cfg

    if (IsObject(PickWin))
        try PickWin.Destroy()

    ; DetectHiddenWindows is on globally for the overlays, so turn it off for
    ; this enumeration or the list fills with invisible windows.
    DetectHiddenWindows(false)
    ids := WinGetList()
    DetectHiddenWindows(true)

    PickProcs := [], items := []
    for hwnd in ids {
        try {
            t := WinGetTitle(hwnd)
            p := WinGetProcessName(hwnd)
        } catch
            continue
        if (Trim(t) = "" || StrLen(t) < 3)
            continue
        if (InStr(t, "claude whip"))
            continue
        PickProcs.Push(p)
        items.Push(Format("{:-24}", p) . t)
    }

    PickWin := Gui("+AlwaysOnTop -MaximizeBox", "claude whip - pick your Claude Code window")
    PickWin.BackColor := "181410"
    PickWin.MarginX := 14, PickWin.MarginY := 12
    PickWin.SetFont("s9 Norm", "Consolas")
    PickWin.Add("Text", "cBFB3A4 w620"
        , "Pick the window you run Claude Code in. Its process name gets added to the`n"
          "list below - process, not title, because Claude Code rewrites the title as`n"
          "it works. Edit the list freely; it is saved verbatim as terminals=.")
    PickList := PickWin.Add("ListBox", "w620 r12 Background181410 cBFB3A4")
    if (items.Length)
        PickList.Add(items)
    PickList.OnEvent("Change", (*) => PickSel())
    PickEdit := PickWin.Add("Edit", "w620 Background201A14 cE8DCC8", Cfg["terminals"])
    b := PickWin.Add("Button", "w120 Default", "Save")
    b.OnEvent("Click", (*) => PickSave())
    b2 := PickWin.Add("Button", "x+10 yp w120", "Cancel")
    b2.OnEvent("Click", (*) => PickClose())
    PickWin.OnEvent("Escape", (*) => PickClose())
    PickWin.OnEvent("Close",  (*) => PickClose())
    PickWin.Show("AutoSize Center")
}

PickSel() {
    global PickList, PickEdit, PickProcs
    i := PickList.Value
    if (!i || !PickProcs.Has(i))
        return
    proc := PickProcs[i]
    cur  := Trim(PickEdit.Value)
    for frag in StrSplit(cur, ",") {
        if (Trim(frag) = proc)              ; already covered, leave the list alone
            return
    }
    PickEdit.Value := (cur = "") ? proc : cur "," proc
}

PickSave() {
    global PickEdit, IniPath, Standalone
    list := Trim(PickEdit.Value)
    if (list = "") {
        Notify("nothing selected")
        return
    }
    IniPut(list, "whip", "terminals")
    PickClose()
    ; Standalone --pick has no HUD or hotkeys to rebuild, and the resident
    ; instance reloads itself when it sees config.ini change.
    if (Standalone) {
        Say("terminals set to: " list)
        return
    }
    ReloadCfg()
    Notify("terminals set to: " list)
}

PickClose() {
    global PickWin
    if (IsObject(PickWin))
        try PickWin.Destroy()
    PickWin := ""
}

BindKeys() {
    global Keys, Registered, HotIfFn, Cfg

    HotIf(HotIfFn)
    for k in Registered {
        try Hotkey(k, "Off")
    }
    Registered := []
    ok := 0, bad := ""
    for pair in Keys {
        try {
            Hotkey(pair[1], Fire.Bind(pair[1], pair[2]), "On")
            Registered.Push(pair[1])
            ok += 1
        } catch as err {
            bad .= pair[1] " (" err.Message ") "
            Notify("could not bind " pair[1] ": " err.Message)
        }
    }
    HotIf()

    ; palette is scoped like every other binding; undo is additionally gated on
    ; having just fired, so Ctrl+Z is untouched the rest of the time
    HotIf(HotIfFn)
    try {
        Hotkey(Cfg["palette"], ShowPalette, "On")
        LogLine("bound " Cfg["palette"] " (palette)")
    } catch as e2 {
        LogLine("FAILED to bind " Cfg["palette"] ": " e2.Message)
    }
    HotIf()
    HotIf((*) => IsClaude() && UndoArmed())
    try {
        Hotkey("^z", DoUndo, "On")
        LogLine("bound ^z (undo, armed 2s after a fire)")
    } catch as e3 {
        LogLine("FAILED to bind ^z: " e3.Message)
    }
    HotIf()

    LogLine("bound " ok "/" Keys.Length " hotkeys; terminals=" Cfg["terminals"]
          . "; titles=" Cfg["titles"] (bad != "" ? "; FAILED: " bad : ""))
}

; ---------------------------------------------------------------------------
; instances and console
; ---------------------------------------------------------------------------
; What #SingleInstance Force used to do, but only on the path that actually
; means it. Every AHK script owns a hidden main window of class AutoHotkey
; whose title starts with the script's full path, which is enough to find our
; older selves without touching other people's scripts.
; PID of another instance of this same script, or 0.
ResidentPid() {
    me := DllCall("GetCurrentProcessId", "UInt")
    for hwnd in WinGetList("ahk_class AutoHotkey") {
        try {
            pid := WinGetPID(hwnd)
            if (pid != me && InStr(WinGetTitle(hwnd), A_ScriptFullPath))
                return pid
        }
    }
    return 0
}

ReplaceResident() {
    me    := DllCall("GetCurrentProcessId", "UInt")
    found := 0
    for hwnd in WinGetList("ahk_class AutoHotkey") {
        try {
            if (WinGetPID(hwnd) = me)
                continue
            if (!InStr(WinGetTitle(hwnd), A_ScriptFullPath))
                continue
            PostMessage(0x111, 65405, , , hwnd)   ; WM_COMMAND, ID_FILE_EXIT
            found += 1
        }
    }
    if (!found)
        return
    ; Give the old instance a moment to drop its hotkeys and overlays, or the
    ; two briefly fight over the same bindings.
    Loop 20 {
        Sleep(50)
        if (!ResidentPid())
            break
    }
}

; AHK is a GUI-subsystem app, so it starts with no console and FileAppend to
; "*" goes nowhere - which is why --doctor used to look like it printed
; nothing. Borrow the calling terminal's console if there is one.
; If stdout is already a pipe or a file, leave it alone: a redirected
; --doctor must keep going to the redirect.
EnsureConsole() {
    global ConOut
    h := DllCall("GetStdHandle", "Int", -11, "Ptr")
    if (h && h != -1)
        return
    if (!DllCall("AttachConsole", "UInt", 0xFFFFFFFF))
        DllCall("AllocConsole")
    try ConOut := FileOpen("CONOUT$", "w")
}

; ---------------------------------------------------------------------------
; --doctor
; ---------------------------------------------------------------------------
Say(t := "") {
    global ConOut
    if (IsObject(ConOut)) {
        try {
            ConOut.Write(t "`n")
            ConOut.Read(0)              ; flush
            return
        }
    }
    try FileAppend(t "`n", "*", "UTF-8")
}

Rule() {
    Say("--------------------------------------------------------------------")
}

Doctor() {
    global Cfg, IniPath, LogPath, WavPath, DEFAULT_KEYS
    problems := 0

    Say("claude-whip doctor")
    Rule()

    ; --- AutoHotkey -------------------------------------------------------
    Say("AutoHotkey")
    Say("  version      : " A_AhkVersion)
    Say("  exe          : " A_AhkPath)
    Say("  script       : " A_ScriptFullPath)
    Say("  screen       : " A_ScreenWidth "x" A_ScreenHeight " @ " A_ScreenDPI " dpi"
        . (A_ScreenDPI = 96 ? " (100% scaling)" : " (scaled - report this if the whip looks wrong)"))
    pid := ResidentPid()
    Say("  resident whip: " (pid ? "running, pid " pid " (this report did not disturb it)"
                                 : "not running - start whip.ahk with no flags"))
    Say()

    ; --- sound ------------------------------------------------------------
    Say("sound")
    Say("  wav          : " WavPath)
    if (!FileExist(WavPath)) {
        problems += 1
        Say("  status       : MISSING - falls back to SoundBeep")
        Say("  fix          : powershell -ExecutionPolicy Bypass -File gen-whip-wav.ps1")
    } else {
        try {
            buf  := FileRead(WavPath, "RAW")
            tag  := StrGet(buf.Ptr, 4, "CP0")
            fmt  := StrGet(buf.Ptr + 8, 4, "CP0")
            ch   := NumGet(buf,  22, "UShort")
            rate := NumGet(buf,  24, "UInt")
            bits := NumGet(buf,  34, "UShort")
            peak := 0, i := 44
            while (i + 1 < buf.Size) {
                v := NumGet(buf, i, "Short")
                if (v < 0)
                    v := -v
                if (v > peak)
                    peak := v
                i += 2
            }
            secs := Round((buf.Size - 44) / (rate * ch * (bits / 8)), 3)
            Say("  header       : " tag "/" fmt "  " rate " Hz, " ch " ch, " bits "-bit")
            Say("  size         : " buf.Size " bytes (" secs " s)")
            Say("  peak amp     : " peak " of 32767 (" Round(peak / 327.67) "% of full scale)")
            if (tag != "RIFF" || fmt != "WAVE") {
                problems += 1
                Say("  status       : BAD HEADER - not a RIFF/WAVE file")
            } else if (peak < 3000) {
                problems += 1
                Say("  status       : TOO QUIET - regenerate with gen-whip-wav.ps1")
            } else {
                Say("  status       : ok")
            }
        } catch as e {
            problems += 1
            Say("  status       : UNREADABLE (" e.Message ")")
        }
    }
    Say()

    ; --- skills -----------------------------------------------------------
    root := EnvGet("USERPROFILE") "\.claude\skills"
    Say("skills  (" root ")")
    missing := 0
    for pair in DEFAULT_KEYS {
        cmd := pair[2]
        f   := root "\" cmd "\SKILL.md"
        if (FileExist(f)) {
            Say("  " Format("{:-8}", KeyLabel(pair[1])) Format("{:-10}", "/" cmd) "ok")
        } else {
            missing += 1
            Say("  " Format("{:-8}", KeyLabel(pair[1])) Format("{:-10}", "/" cmd) "MISSING")
        }
    }
    if (missing) {
        problems += 1
        Say("  " missing " of " DEFAULT_KEYS.Length " missing")
        Say("  fix          : Copy-Item .\skills\* `"$env:USERPROFILE\.claude\skills\`" -Recurse -Force")
    } else {
        Say("  all " DEFAULT_KEYS.Length " present")
    }
    Say()

    ; --- detection --------------------------------------------------------
    Say("detection")
    Say("  terminals=   : " (Cfg["terminals"] = "" ? "(empty - process matching off)" : Cfg["terminals"]))
    Say("  titles=      : " (Cfg["titles"] = "" ? "(empty - title matching off)" : Cfg["titles"]))
    t := "", p := ""
    try t := WinGetTitle("A")
    try p := WinGetProcessName("A")
    Say("  active window: " (t = "" ? "(none)" : t))
    Say("  active proc  : " (p = "" ? "(unknown)" : p))
    if (ActiveIsOurs())
        Say("  matches      : n/a (that window belongs to claude-whip itself)")
    else if (rule := ActiveIsClaude())
        Say("  matches      : YES by " rule " - hotkeys are live there")
    else {
        problems += 1
        Say("  matches      : NO - hotkeys stay inert in that window")
        Say("  fix          : run with --pick to add " (p = "" ? "its process" : p) " to terminals=")
    }
    Say()

    ; --- config -----------------------------------------------------------
    Say("config")
    Say("  path         : " IniPath)
    if (!FileExist(IniPath)) {
        Say("  status       : missing - defaults will be written on next start")
    } else {
        bom := "none"
        try {
            raw := FileRead(IniPath, "RAW")
            if (raw.Size >= 3 && NumGet(raw, 0, "UChar") = 0xEF
                && NumGet(raw, 1, "UChar") = 0xBB && NumGet(raw, 2, "UChar") = 0xBF)
                bom := "PRESENT - stripped automatically at startup"
        }
        Say("  utf-8 bom    : " bom)
        Say("  theme        : " Cfg["theme"])
        Say("  palette      : " Cfg["palette"] "  (" PrettyChord(Cfg["palette"]) ")")
        Say("  animate/hud  : " Cfg["animate"] " / " Cfg["hud"])
        Say("  shake/volume : " Cfg["shake"] " / " Cfg["volume"])
        Say("  debug        : " Cfg["debug"] (Cfg["debug"] ? "" : "  (set to 1 to log why detection fails)"))
    }
    Say()

    ; --- recent trouble ---------------------------------------------------
    Say("last log errors  (" LogPath ")")
    if (!FileExist(LogPath)) {
        Say("  (no log yet - set debug=1 in config.ini to create one)")
    } else {
        hits := []
        try {
            for ln in StrSplit(FileRead(LogPath, "UTF-8"), "`n") {
                if (InStr(ln, "FAILED") || InStr(ln, "THREW") || InStr(ln, "no match")
                    || InStr(ln, "perf:") || InStr(ln, "unknown theme"))
                    hits.Push(Trim(ln, " `t`r"))
            }
        }
        if (!hits.Length)
            Say("  none")
        else {
            from := Max(1, hits.Length - 4)
            Loop hits.Length - from + 1
                Say("  " hits[from + A_Index - 1])
        }
    }
    Say()

    Rule()
    Say(problems = 0 ? "VERDICT: healthy" : "VERDICT: " problems " problem(s) above")
}

; ---------------------------------------------------------------------------
; chains
; ---------------------------------------------------------------------------
; A binding whose value contains "|" runs its steps in order, with optional
; "wait <seconds>" between them.
;
; Only "wait" is supported. "wait-idle" - waiting until Claude Code stops
; producing output - is deliberately NOT implemented: there is no reliable
; signal for it from outside the terminal. The window title does not change,
; there is no exit code to wait on, and the only remaining approach is
; screen-diffing the terminal, which a blinking cursor and a ticking token
; counter both defeat. A chain step that silently guessed wrong would fire
; the next command into a half-finished answer, so the token is rejected
; loudly instead.
FireChain(key, spec) {
    global ChainAbort
    steps := []
    for part in StrSplit(spec, "|") {
        t := Trim(part)
        if (t != "")
            steps.Push(t)
    }
    if (!steps.Length)
        return

    ChainAbort := false
    for i, st in steps {
        if (ChainAbort)
            return
        if (RegExMatch(st, "i)^wait[ \t]+([0-9]+)$", &m)) {
            ms := Integer(m[1]) * 1000, waited := 0
            while (waited < ms) {
                if (ChainAbort || GetKeyState("Escape", "P")) {
                    ChainAbort := true
                    Toast("chain cancelled", 1200)
                    return
                }
                if (Mod(waited, 1000) = 0)
                    Toast("chain: waiting " Ceil((ms - waited) / 1000) "s  (Esc cancels)", 1200)
                Sleep(100)
                waited += 100
            }
        } else if (RegExMatch(st, "i)^wait-idle\b")) {
            LogLine("chain: 'wait-idle' is not supported (no reliable idle signal); chain stopped")
            Toast("wait-idle unsupported - chain stopped", 2600)
            return
        } else if (RegExMatch(st, "i)^wait\b")) {
            LogLine("chain: malformed step '" st "' - expected 'wait <seconds>'")
            Toast("bad chain step: " st, 2600)
            return
        } else {
            cmd := LTrim(st, "/ `t")
            Toast("chain " i "/" steps.Length ": /" cmd, 1200)
            Fire(key, cmd)
        }
    }
}

; ---------------------------------------------------------------------------
; usage stats
; ---------------------------------------------------------------------------
; The third column is the window title, not the working directory. A terminal
; window belongs to the terminal host rather than the shell inside it, and
; with tabs there is no reliable way to know which shell is in front, so a
; "cwd" column would be whip's own directory dressed up as yours.
RecordFire(cmd, hwnd) {
    global StatsPath
    try {
        title := hwnd ? WinGetTitle("ahk_id " hwnd) : ""
    } catch
        title := ""
    try {
        if (!FileExist(StatsPath))
            FileAppend("timestamp,command,window`n", StatsPath, "UTF-8")
        title := StrReplace(title, "`"", "`"`"")
        FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "," cmd ",`"" title "`"`n"
                 , StatsPath, "UTF-8")
    }
}

ShowStats(*) {
    global StatsPath, StatsWin, Keys

    if (IsObject(StatsWin))
        try StatsWin.Destroy()

    if (!FileExist(StatsPath)) {
        Notify("no stats yet - fire a command first")
        return
    }

    perCmd := Map(), perDay := Map(), total := 0, first := ""
    try {
        for i, ln in StrSplit(FileRead(StatsPath, "UTF-8"), "`n") {
            ln := Trim(ln, " `t`r")
            if (ln = "" || i = 1)
                continue
            parts := StrSplit(ln, ",", , 3)
            if (parts.Length < 2)
                continue
            ts := parts[1], cmd := parts[2]
            day := SubStr(ts, 1, 10)
            perCmd[cmd] := perCmd.Has(cmd) ? perCmd[cmd] + 1 : 1
            perDay[day] := perDay.Has(day) ? perDay[day] + 1 : 1
            if (first = "")
                first := day
            total += 1
        }
    }
    if (!total) {
        Notify("stats.csv has no entries yet")
        return
    }

    ; commands, most used first
    cmds := []
    for c, n in perCmd
        cmds.Push({cmd: c, n: n})
    Loop cmds.Length - 1 {
        i := A_Index
        Loop cmds.Length - i {
            j := A_Index
            if (cmds[j].n < cmds[j + 1].n) {
                tmp := cmds[j], cmds[j] := cmds[j + 1], cmds[j + 1] := tmp
            }
        }
    }

    body := "", top := cmds[1].cmd
    for c in cmds {
        bar := ""
        w := Round(28.0 * c.n / cmds[1].n)
        Loop Max(w, 1)
            bar .= Chr(0x2588)
        body .= Format("{:-10}", "/" c.cmd) Format("{:5}", c.n) "  " bar "`n"
    }

    ; last 7 days present in the file
    days := []
    for d, n in perDay
        days.Push(d)
    Loop days.Length - 1 {
        i := A_Index
        Loop days.Length - i {
            j := A_Index
            ; StrCompare, not "<": AHK v2 tries to compare "2026-09-16"
            ; numerically and throws "Expected a Number but got a String"
            if (StrCompare(days[j], days[j + 1]) < 0) {
                tmp := days[j], days[j] := days[j + 1], days[j + 1] := tmp
            }
        }
    }
    dayBody := ""
    Loop Min(7, days.Length) {
        d := days[A_Index]
        dayBody .= d "   " Format("{:4}", perDay[d]) "`n"
    }

    unused := ""
    for pair in Keys {
        if (!perCmd.Has(pair[2]))
            unused .= (unused = "" ? "" : ", ") "/" pair[2]
    }

    StatsWin := Gui("+AlwaysOnTop -MaximizeBox", "claude whip - stats")
    StatsWin.BackColor := "181410"
    StatsWin.MarginX := 20, StatsWin.MarginY := 16
    StatsWin.SetFont("s11 Bold", "Consolas")
    StatsWin.Add("Text", "cC9A227", total " fires since " first)
    StatsWin.SetFont("s9 Norm", "Consolas")
    StatsWin.Add("Text", "c8A7F72 y+10", "most used: /" top)
    StatsWin.SetFont("s9 Bold", "Consolas")
    StatsWin.Add("Text", "cC9A227 y+14", "by command")
    StatsWin.SetFont("s9 Norm", "Consolas")
    StatsWin.Add("Text", "cBFB3A4 w420", RTrim(body, "`n"))
    StatsWin.SetFont("s9 Bold", "Consolas")
    StatsWin.Add("Text", "cC9A227 y+14", "by day")
    StatsWin.SetFont("s9 Norm", "Consolas")
    StatsWin.Add("Text", "cBFB3A4 w420", RTrim(dayBody, "`n"))
    if (unused != "") {
        StatsWin.SetFont("s8 Norm", "Consolas")
        StatsWin.Add("Text", "c6A6056 w420 y+14", "never fired: " unused)
    }
    b := StatsWin.Add("Button", "y+14 w130", "Open stats.csv")
    b.OnEvent("Click", (*) => RunSafe(StatsPath))
    StatsWin.OnEvent("Close", (*) => StatsWin.Destroy())
    StatsWin.OnEvent("Escape", (*) => StatsWin.Destroy())
    StatsWin.Show("AutoSize Center")
}

; ---------------------------------------------------------------------------
; update check - once a day, never blocking, never automatic
; ---------------------------------------------------------------------------
CheckUpdate(*) {
    global IniPath, WHIP_VERSION, WHIP_REPO
    today := FormatTime(A_Now, "yyyy-MM-dd")
    if (Trim(IniRead(IniPath, "whip", "lastcheck", "")) = today)
        return
    try IniPut(today, "whip", "lastcheck")
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 4000)
        req.Open("GET", "https://api.github.com/repos/" WHIP_REPO "/releases/latest", true)
        req.SetRequestHeader("User-Agent", "claude-whip/" WHIP_VERSION)
        req.Send()
        req.WaitForResponse(5)
        if (req.Status != 200)
            return
        if (!RegExMatch(req.ResponseText, '"tag_name"\s*:\s*"([^"]+)"', &m))
            return
        latest := m[1]
        pa := StrSplit(StrReplace(latest, "v", ""), ".")
        pb := StrSplit(StrReplace(WHIP_VERSION, "v", ""), ".")
        newer := false
        Loop 3 {
            x := pa.Has(A_Index) ? Integer(pa[A_Index]) : 0
            y := pb.Has(A_Index) ? Integer(pb[A_Index]) : 0
            if (x != y) {
                newer := x > y
                break
            }
        }
        if (newer) {
            LogLine("update available: " latest " (running " WHIP_VERSION ")")
            TrayTip("claude whip " latest " is available"
                  , "You are running " WHIP_VERSION ". github.com/" WHIP_REPO "/releases")
        }
    }
    ; offline, rate-limited or no releases yet: silently do nothing
}

; ---------------------------------------------------------------------------
; tray
; ---------------------------------------------------------------------------
BuildTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Reload config", ReloadCfg)
    A_TrayMenu.Add("Open config", OpenConfig)
    A_TrayMenu.Add("Open log", OpenLog)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Show stats", ShowStats)
    A_TrayMenu.Add("Pick Claude window", ShowPicker)
    A_TrayMenu.Add("Show welcome", (*) => ShowWelcome())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Toggle HUD", ToggleHud)
    A_TrayMenu.Add("Pause hotkeys", TogglePause)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Toggle HUD"
    A_IconTip := "claude whip"
}

RunSafe(path) {
    try Run(path)
    catch
        Notify("could not open " path)
}

OpenConfig(*) {
    global IniPath
    RunSafe(IniPath)
}

OpenLog(*) {
    global LogPath
    if (!FileExist(LogPath)) {
        Notify("no log yet - set debug=1 in config.ini")
        return
    }
    RunSafe(LogPath)
}

ToggleHud(*) {
    global Cfg, IniPath
    Cfg["hud"] := Cfg["hud"] ? 0 : 1
    IniPut(Cfg["hud"], "whip", "hud")
    if (!Cfg["hud"])
        HideHud()
    Notify("HUD " (Cfg["hud"] ? "on" : "off"))
}

TogglePause(*) {
    global Paused
    Paused := !Paused
    A_TrayMenu.ToggleCheck("Pause hotkeys")
    if (Paused)
        HideHud()
    Notify(Paused ? "hotkeys paused" : "hotkeys live")
}
