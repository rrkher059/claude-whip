#Requires AutoHotkey v2.0
#SingleInstance Force
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
ConfirmAt  := Map()

; command name -> behaviour. Attached to the command rather than the key so a
; remapped binding keeps sane semantics.
NeedsArgs    := Map("decide", true, "debt", true)
NeedsConfirm := Map("ship", true)

DEFAULT_KEYS := [ ["F1","whip"],  ["F2","redteam"], ["F3","ship"]
                , ["F4","decide"],["F5","scale"],   ["F6","unstuck"]
                , ["+F1","orient"],["+F2","secure"],["+F3","test"]
                , ["+F4","debt"], ["+F5","user"],   ["+F6","handoff"] ]

HotIfFn := (*) => IsClaude()

LoadCfg()
BuildOverlays()
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
WhipSpine(t, W, H) {
    if (t < 0)
        t := 0
    if (t > 1)
        t := 1

    hx := W * 1.06, hy := H * 0.88          ; handle, anchored off the right edge

    e    := 1 - (1 - t) ** 3                ; cubic ease-out on the tip
    tipX := (W * 0.90) + ((W * -0.10) - (W * 0.90)) * e
    tipY := (H * 0.08) + ((H *  0.68) - (H *  0.08)) * e

    lag := 1 - t                            ; control points trail, then overshoot
    c1x := W * (0.80 + 0.24 * lag), c1y := H * (0.94 - 0.46 * t)
    c2x := W * (0.38 + 0.54 * lag), c2y := H * (0.16 + 0.70 * lag)

    p   := t * 1.15 - 0.05                  ; loop position along the whip
    amp := 30 * (1 - t) + 7                 ; loop amplitude, shrinking as it runs out
    if (t > 0.94)
        amp *= 0.25                         ; collapses as the tip snaps past

    N   := 60
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

        if (s < 0.06)
            wd := 8.5                       ; grip
        else if (s > 0.93)
            wd := 0.7                       ; cracker
        else
            wd := 7.6 * (1 - s) ** 1.45 + 0.8

        pts.Push({ x: cur.x + px * amp * g
                 , y: cur.y + py * amp * g
                 , px: px, py: py, tx: tx, ty: ty, w: wd, s: s })
    }
    return pts
}

; Walk forward along one perpendicular offset and back along the other, closing
; the shape. `lateral` shifts the centreline sideways (used for the highlight).
PolyFromSpine(pts, wmul := 1.0, lateral := 0.0) {
    fwd := "", back := ""
    for i, pt in pts {
        hw := pt.w * wmul
        if (hw < 0.5)
            hw := 0.5
        cx := pt.x + pt.px * lateral * pt.w
        cy := pt.y + pt.py * lateral * pt.w
        fwd  .= Round(cx + pt.px * hw) "-" Round(cy + pt.py * hw) " "
        back := Round(cx - pt.px * hw) "-" Round(cy - pt.py * hw) " " back
    }
    return fwd back "Polygon"
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
    return Round(ax + pt.px*hw) "-" Round(ay + pt.py*hw) " " Round(bx + pt.px*hw) "-" Round(by + pt.py*hw) " " Round(bx - pt.px*hw) "-" Round(by - pt.py*hw) " " Round(ax - pt.px*hw) "-" Round(ay - pt.py*hw) " Polygon"
}

SparkPoly(cx, cy, angleDeg, len, halfW) {
    a  := angleDeg * 3.14159265358979 / 180
    dx := Cos(a), dy := Sin(a)
    px := -dy,    py := dx
    ex := cx + dx * len, ey := cy + dy * len
    return Round(cx + px*halfW) "-" Round(cy + py*halfW) " " Round(ex + px*0.6) "-" Round(ey + py*0.6) " " Round(ex - px*0.6) "-" Round(ey - py*0.6) " " Round(cx - px*halfW) "-" Round(cy - py*halfW) " Polygon"
}

; ---------------------------------------------------------------------------
; overlay windows
; ---------------------------------------------------------------------------
MakeOverlay(colour) {
    ; -Caption +AlwaysOnTop +ToolWindow +E0x20 (WS_EX_TRANSPARENT) +Disabled
    ; makes it click-through, out of alt-tab, and incapable of taking focus.
    g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 +Disabled -DPIScale")
    g.BackColor := colour
    g.Show("NA x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    WinSetTransparent(0, "ahk_id " g.Hwnd)
    g.Hide()
    return g
}

BuildOverlays() {
    global Win
    Win["g1"]    := MakeOverlay("2A1A0F")     ; ghost at t-0.10
    Win["g2"]    := MakeOverlay("3A2415")     ; ghost at t-0.05
    Win["body"]  := MakeOverlay("4E3018")     ; the leather
    Win["b1"]    := MakeOverlay("2E1B0D")     ; grip bands
    Win["b2"]    := MakeOverlay("2E1B0D")
    Win["b3"]    := MakeOverlay("2E1B0D")
    Win["hi"]    := MakeOverlay("8A6034")     ; light along the top edge
    Win["flash"] := MakeOverlay("FFFFFF")
    Loop 4
        Win["s" A_Index] := MakeOverlay("FFF4D6")
}

SetRegion(key, spec) {
    global Win
    try WinSetRegion(spec, "ahk_id " Win[key].Hwnd)   ; a bad frame is skipped, not fatal
}

ShowWin(key, alpha) {
    global Win
    try {
        WinSetTransparent(alpha, "ahk_id " Win[key].Hwnd)
        Win[key].Show("NA x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
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
Crack() {
    global Win, Animating

    W := A_ScreenWidth, H := A_ScreenHeight
    FRAMES := 18
    ORDER  := ["g1","g2","body","b1","b2","b3","hi"]
    BASE   := Map("g1", 38, "g2", 77, "body", 255, "b1", 255, "b2", 255, "b3", 255, "hi", 235)

    try {
        Loop FRAMES {
            f := A_Index
            t := (f - 1) / (FRAMES - 1)

            spine := WhipSpine(t, W, H)
            SetRegion("g1", PolyFromSpine(WhipSpine(t - 0.10, W, H)))
            SetRegion("g2", PolyFromSpine(WhipSpine(t - 0.05, W, H)))
            SetRegion("body", PolyFromSpine(spine))
            SetRegion("hi",   PolyFromSpine(spine, 0.30, 0.45))
            SetRegion("b1",   BandPoly(spine, 0.014, 3.2, 1.35))
            SetRegion("b2",   BandPoly(spine, 0.038, 3.0, 1.30))
            SetRegion("b3",   BandPoly(spine, 0.066, 2.8, 1.25))

            fade := 1.0
            if (f > FRAMES - 4)
                fade := (FRAMES - f + 1) / 5.0

            if (f = 1) {
                for key in ORDER
                    ShowWin(key, BASE[key])
            } else if (fade < 1.0) {
                for key in ORDER
                    try WinSetTransparent(Round(BASE[key] * fade), "ahk_id " Win[key].Hwnd)
            }

            ; the snap: white flash at the tip plus four radiating sparks,
            ; two frames only
            if (f = 16 || f = 17) {
                tip := spine[spine.Length]
                d   := 54
                SetRegion("flash", Round(tip.x - d/2) "-" Round(tip.y - d/2) " W" d " H" d " E")
                ShowWin("flash", 200)
                for i, ang in [30, 75, 200, 250] {
                    SetRegion("s" i, SparkPoly(tip.x, tip.y, ang, 92, 2.6))
                    ShowWin("s" i, 170)
                }
            } else if (f = 18) {
                HideWin("flash")
                Loop 4
                    HideWin("s" A_Index)
            }

            Sleep(12)
        }
    }
    finally {
        HideAll()       ; never leave a window on screen, whatever went wrong
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
    HudEdge := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 +Disabled -DPIScale")
    HudEdge.BackColor := "332C24"

    Hud := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 +Disabled -DPIScale")
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
            return
        }
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
        last := ConfirmAt.Has(cmd) ? ConfirmAt[cmd] : 0
        if (A_TickCount - last > 900) {
            ConfirmAt[cmd] := A_TickCount
            ToolTip(KeyLabel(key) " again to ship")
            SetTimer(() => ToolTip(), -900)
            return
        }
        ConfirmAt[cmd] := 0
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
