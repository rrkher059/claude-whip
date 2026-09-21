#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Screen"

; ---------------------------------------------------------------- config --
CFG := A_ScriptDir "\config.ini"
if !FileExist(CFG) {
    FileAppend(
    "[whip]`n"
    . "sound=" A_ScriptDir "\whip.wav`n"
    . "; comma separated, matched anywhere in the active window title`n"
    . "titles=claude`n"
    . "; set debug=1 to log every window title to whip.log, then tune titles=`n"
    . "debug=0`n"
    . "hud=1`n`n"
    . "[keys]`n"
    . "F1=/whip`nF2=/redteam`nF3=/ship`nF4=/decide`nF5=/scale`nF6=/unstuck`n"
    , CFG)
}
SOUND  := IniRead(CFG, "whip", "sound",  A_ScriptDir "\whip.wav")
TITLES := IniRead(CFG, "whip", "titles", "claude")
DEBUG  := IniRead(CFG, "whip", "debug",  "0")
HUDON  := IniRead(CFG, "whip", "hud",    "1")

BIND := Map()
for k in ["F1","F2","F3","F4","F5","F6"]
    BIND[k] := IniRead(CFG, "keys", k, "")

LABEL := Map("F1","cut scope", "F2","red-team diff", "F3","ship it",
             "F4","log decision", "F5","cost at 100x", "F6","unstuck")

; ------------------------------------------------------------ the lash ----
; A shaped, click-through window. Its region is recomputed each frame into a
; tapered polygon tracing a cubic bezier, so what you see is a real whip.

Lash := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 +Disabled")
Lash.BackColor := "1A0F0A"
Lash.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " NoActivate Hide")
WinSetRegion("0-0 1-0 1-1 0-1 Polygon", Lash)

Flash := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 +Disabled")
Flash.BackColor := "FFF6E0"
Flash.Show("x0 y0 w220 h220 NoActivate Hide")

Bez(a, b, c, d, s) {
    u := 1 - s
    return u*u*u*a + 3*u*u*s*b + 3*u*s*s*c + s*s*s*d
}

WhipPolygon(t) {
    W := A_ScreenWidth, H := A_ScreenHeight
    ; handle sits off the right edge; tip sweeps left and down
    x0 := W * 1.02,                      y0 := H * 0.80
    ease := 1 - (1 - t) ** 3
    tipx := W * (0.86 - 0.92 * ease)
    tipy := H * (0.12 + 0.52 * ease)
    ; travelling loop: control points lag behind the tip, then snap past it
    lag  := 1 - t
    x1 := W * (0.72 + 0.20 * lag),  y1 := H * (0.86 - 0.34 * t)
    x2 := W * (0.34 + 0.52 * lag),  y2 := H * (0.10 + 0.74 * lag)

    N := 34, base := 15
    cx := [], cy := []
    Loop N + 1 {
        s := (A_Index - 1) / N
        cx.Push(Bez(x0, x1, x2, tipx, s))
        cy.Push(Bez(y0, y1, y2, tipy, s))
    }
    fwd := "", rev := ""
    Loop N + 1 {
        i := A_Index
        if (i < N + 1)
            dx := cx[i+1] - cx[i], dy := cy[i+1] - cy[i]
        else
            dx := cx[i] - cx[i-1], dy := cy[i] - cy[i-1]
        len := Sqrt(dx*dx + dy*dy)
        if (len = 0)
            len := 1
        nx := -dy / len, ny := dx / len
        w := base * (1 - (i - 1) / N) ** 1.7 + 1.1
        fwd .= " " Round(cx[i] + nx*w) "-" Round(cy[i] + ny*w)
        rev := " " Round(cx[i] - nx*w) "-" Round(cy[i] - ny*w) rev
    }
    return Trim(fwd rev) " Polygon"
}

Crack() {
    global Lash, Flash, SOUND
    try SoundPlay(SOUND)
    Lash.Show("NoActivate")
    WinSetTransparent(228, Lash)
    frames := 15
    Loop frames {
        t := A_Index / frames
        try WinSetRegion(WhipPolygon(t), Lash)
        if (A_Index = frames - 2) {
            W := A_ScreenWidth, H := A_ScreenHeight
            ease := 1 - (1 - t) ** 3
            fx := Round(W * (0.86 - 0.92 * ease)) - 60
            fy := Round(H * (0.12 + 0.52 * ease)) - 60
            Flash.Show("x" fx " y" fy " w120 h120 NoActivate")
            WinSetRegion("0-0 120-0 120-120 0-120 Ellipse", Flash)
            WinSetTransparent(200, Flash)
        }
        Sleep 11
    }
    Loop 5 {
        WinSetTransparent(228 - A_Index * 45, Lash)
        try WinSetTransparent(200 - A_Index * 40, Flash)
        Sleep 14
    }
    Lash.Hide()
    Flash.Hide()
}

; ------------------------------------------------------------------ HUD ----
Hud := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 +Disabled")
Hud.BackColor := "14100D"
Hud.SetFont("s9 cC9A227", "Consolas")
Hud.Add("Text", "x12 y9 w160", "~ CLAUDE WHIP ~")
Hud.SetFont("s8 c8A7F72", "Consolas")
y := 28
for k in ["F1","F2","F3","F4","F5","F6"] {
    Hud.Add("Text", "x12 y" y " w170", k "  " LABEL[k])
    y += 15
}
Hud.Show("w190 h" (y + 8) " NoActivate Hide")
WinSetTransparent(205, Hud)
HudVisible := false

IsClaude() {
    global TITLES, DEBUG
    try t := WinGetTitle("A")
    catch
        return false
    for pat in StrSplit(TITLES, ",") {
        pat := Trim(pat)
        if (pat != "" && InStr(t, pat))
            return true
    }
    if (DEBUG = "1" && t != "")
        FileAppend(A_Now " no-match: " t "`n", A_ScriptDir "\whip.log")
    return false
}

Watch(*) {
    global Hud, HudVisible, HUDON
    if (HUDON != "1")
        return
    if IsClaude() {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "A")
            Hud.GetPos(, , &hw, &hh)
            Hud.Show("x" (wx + ww - hw - 18) " y" (wy + wh - hh - 18) " NoActivate")
            HudVisible := true
        }
    } else if HudVisible {
        Hud.Hide()
        HudVisible := false
    }
}
SetTimer Watch, 400

; -------------------------------------------------------------- hotkeys ----
Fire(key) {
    global BIND
    cmd := BIND[key]
    if (cmd = "")
        return
    if (key = "F4") {
        ib := InputBox("What was decided?", "claude-whip", "w420 h130")
        if (ib.Result != "OK")
            return
        cmd .= " " ib.Value
    }
    Crack()
    SendText(cmd)
    Send "{Enter}"
}

ShipArmed := 0
#HotIf IsClaude()
F1:: Fire("F1")
F2:: Fire("F2")
F3:: {
    global ShipArmed
    if (A_TickCount - ShipArmed < 900) {
        ShipArmed := 0
        Fire("F3")
    } else {
        ShipArmed := A_TickCount
        ToolTip "F3 again to ship"
        SetTimer () => ToolTip(), -900
    }
}
F4:: Fire("F4")
F5:: Fire("F5")
F6:: Fire("F6")
#HotIf
