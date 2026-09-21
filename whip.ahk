#Requires AutoHotkey v2.0
#SingleInstance Force

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

; Everything at script scope is already global in v2.
Cfg        := Map()
Titles     := []
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

; command name -> behaviour. Attached to the command rather than the key so a
; remapped binding keeps sane semantics.
NeedsArgs    := Map("decide", true, "debt", true)
NeedsConfirm := Map("ship", true)

DEFAULT_KEYS := [ ["F1","whip"],  ["F2","redteam"], ["F3","ship"]
                , ["F4","decide"],["F5","scale"],   ["F6","unstuck"]
                , ["+F1","orient"],["+F2","secure"],["+F3","test"]
                , ["+F4","debt"], ["+F5","user"],   ["+F6","handoff"] ]

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

LoadCfg()
BuildOverlays()

; --test: one slow, loud crack on demand, then quit. No hotkeys, no HUD, so
; it can be verified without switching windows or focusing Claude.
for i, arg in A_Args {
    if (arg = "--test") {
        ; --test [speed]   speed 1 = real time, default 12 = slow enough to watch
        spd := (A_Args.Has(i + 1) && IsNumber(A_Args[i + 1])) ? A_Args[i + 1] + 0 : 12
        Cfg["debug"] := 1
        LogLine("--test: screen " A_ScreenWidth "x" A_ScreenHeight ", DPI " A_ScreenDPI
              . ", theme " Cfg["theme"] ", speed " spd ", wav " WavPath)
        PlayCrackSound()
        Crack(spd)
        LogLine("--test: finished")
        Sleep(400)
        ExitApp()
    }
}

BuildHud()
BindKeys()
BuildTray()
SetTimer(UpdateHud, 400)

; ---------------------------------------------------------------------------
; config
; ---------------------------------------------------------------------------
WriteDefaultCfg() {
    global IniPath, DEFAULT_KEYS
    IniWrite("",       IniPath, "whip", "sound")
    IniWrite("claude", IniPath, "whip", "titles")
    IniWrite("0",      IniPath, "whip", "debug")
    IniWrite("1",      IniPath, "whip", "hud")
    IniWrite("1",      IniPath, "whip", "volume")
    IniWrite("1",      IniPath, "whip", "animate")
    IniWrite("leather",IniPath, "whip", "theme")
    IniWrite("1",      IniPath, "whip", "shake")
    for pair in DEFAULT_KEYS
        IniWrite(pair[2], IniPath, "keys", pair[1])
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
    global Cfg, Titles, Keys, IniPath, WavPath, DEFAULT_KEYS
    if (!FileExist(IniPath))
        WriteDefaultCfg()
    StripBom(IniPath)

    Cfg := Map()
    Cfg["sound"]   := Trim(IniRead(IniPath, "whip", "sound", ""))
    Cfg["titles"]  := Trim(IniRead(IniPath, "whip", "titles", "claude"))
    Cfg["debug"]   := IniRead(IniPath, "whip", "debug",   "0") + 0
    Cfg["hud"]     := IniRead(IniPath, "whip", "hud",     "1") + 0
    Cfg["volume"]  := IniRead(IniPath, "whip", "volume",  "1") + 0
    Cfg["animate"] := IniRead(IniPath, "whip", "animate", "1") + 0
    Cfg["shake"]   := IniRead(IniPath, "whip", "shake",   "1") + 0
    Cfg["theme"]   := Trim(IniRead(IniPath, "whip", "theme", "leather"))

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
    if (Titles.Length = 0)
        Titles.Push("claude")

    Keys := []
    for pair in DEFAULT_KEYS {
        cmd := Trim(IniRead(IniPath, "keys", pair[1], pair[2]))
        if (cmd != "")
            Keys.Push([pair[1], cmd])
    }
}

ReloadCfg(*) {
    LoadCfg()
    BuildHud()
    BindKeys()
    Notify("config reloaded")
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

; Used as the #HotIf criterion for every binding, so F1-F6 and Shift+F1-F6
; behave completely normally in every other application.
IsClaude() {
    global Paused
    if (Paused)
        return false
    try
        title := WinGetTitle("A")
    catch
        return false
    if (MatchTitle(title))
        return true
    LogMiss(title)
    return false
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

ShowWin(key, alpha) {
    global Win
    try {
        WinSetTransparent(alpha, "ahk_id " Win[key].Hwnd)
        Win[key].Show("NA x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    } catch as e {
        LogLine("ShowWin FAILED layer " key ": " e.Message)
    }
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

Crack(speed := 1.0) {
    global Win, Cfg

    W := A_ScreenWidth, H := A_ScreenHeight
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
                    ShowWin(key, BASE[key])
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
                ShowWin("core", 230 - k * 85)

                SetRegion("ring", ArcPoly(tip.x, tip.y, (18 + k * 40) * sc, (3.6 - k * 1.1) * sc
                        , ang - 74, ang + 74), f)
                ShowWin("ring", 88 - k * 32)

                inner := d / 2 + 6 * sc
                for i, sp in SPARKS {
                    SetRegion("s" i, SparkPoly(tip.x, tip.y, ang + sp[1], inner
                            , sp[2] * sc * (0.55 + 0.40 * k), sp[3] * sc), f)
                    ShowWin("s" i, 140 - k * 52)
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
            isSnap := (f >= SNAP - 1 && f <= SNAP + 1)
            if (!degraded && !isSnap && spent > Max(budget * 2, 34) && N > 24) {
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
    return StrReplace(k, "+", "S+")
}

BuildHud() {
    global Hud, HudEdge, Keys, HudShown, HudX, HudY
    if (IsObject(Hud))
        try Hud.Destroy()
    if (IsObject(HudEdge))
        try HudEdge.Destroy()
    HudShown := false, HudX := -99999, HudY := -99999

    col1 := "", col2 := ""
    for i, pair in Keys {
        line := Format("{:-5}", KeyLabel(pair[1])) " " pair[2]
        if (i <= 6)
            col1 .= (col1 = "" ? "" : "`n") line
        else
            col2 .= (col2 = "" ? "" : "`n") line
    }

    ; hairline border is a second window one pixel larger behind the panel -
    ; cheaper and more reliable than fighting control background colours.
    HudEdge := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000020 +Disabled -DPIScale")
    HudEdge.BackColor := "332C24"

    Hud := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000020 +Disabled -DPIScale")
    Hud.BackColor := "181410"
    Hud.MarginX := 0, Hud.MarginY := 0

    Hud.SetFont("s8 Bold", "Consolas")
    Hud.Add("Text", "x0 y5 w236 h15 Center BackgroundTrans cC9A227", "~ claude whip ~")
    Hud.SetFont("s8 Norm", "Consolas")
    Hud.Add("Text", "x10 y24 w110 h86 BackgroundTrans c8A7F72", col1)
    Hud.Add("Text", "x122 y24 w110 h86 BackgroundTrans c8A7F72", col2)
}

UpdateHud(*) {
    global Hud, HudEdge, Cfg, Paused, HudShown, HudX, HudY
    HW := 236, HH := 114

    if (!Cfg["hud"] || Paused) {
        HideHud()
        return
    }
    try {
        hwnd  := WinGetID("A")
        title := WinGetTitle("A")
    } catch {
        HideHud()
        return
    }
    if (!MatchTitle(title)) {
        HideHud()
        return
    }
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    catch {
        HideHud()
        return
    }
    if (ww < HW + 40 || wh < HH + 40) {
        HideHud()
        return
    }

    x := wx + ww - HW - 22          ; anchored bottom-right INSIDE the window
    y := wy + wh - HH - 22
    if (HudShown && x = HudX && y = HudY)
        return                      ; nothing moved, do not repaint

    HudX := x, HudY := y
    try {
        HudEdge.Show("NA x" (x - 1) " y" (y - 1) " w" (HW + 2) " h" (HH + 2))
        Hud.Show("NA x" x " y" y " w" HW " h" HH)
        HudShown := true
    }
}

HideHud() {
    global Hud, HudEdge, HudShown, HudX, HudY
    if (!HudShown)
        return
    try Hud.Hide()
    try HudEdge.Hide()
    HudShown := false
    HudX := -99999, HudY := -99999
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

Fire(key, cmd, *) {
    global Animating, Cfg, NeedsArgs, NeedsConfirm, ConfirmAt

    if (Animating)                  ; ignore keys pressed mid-animation
        return

    if (NeedsConfirm.Has(cmd)) {
        if (A_TickCount - ConfirmAt > 900) {
            ConfirmAt := A_TickCount
            ToolTip(KeyLabel(key) " again to ship")
            SetTimer(() => ToolTip(), -900)
            return
        }
        ConfirmAt := 0
    }

    try target := WinGetID("A")
    catch
        return

    args := ""
    if (NeedsArgs.Has(cmd)) {
        ib := InputBox("Arguments for /" cmd " (blank to let Claude infer it)", "claude whip", "w460 h132")
        if (ib.Result != "OK")
            return
        args := Trim(ib.Value)
        try {                       ; InputBox took focus; give it back
            WinActivate("ahk_id " target)
            WinWaitActive("ahk_id " target, , 1)
        }
    }

    PlayCrackSound()
    Animating := true
    try {
        if (Cfg["animate"])
            Crack()
    }
    finally {
        Animating := false
    }

    payload := "/" cmd (args != "" ? " " args : "")
    SendText(payload)
    Sleep(30)
    Send("{Enter}")
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
    LogLine("bound " ok "/" Keys.Length " hotkeys; titles=" Cfg["titles"] (bad != "" ? "; FAILED: " bad : ""))
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
    IniWrite(Cfg["hud"], IniPath, "whip", "hud")
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
