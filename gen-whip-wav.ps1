# gen-whip-wav.ps1 - synthesizes whip.wav from scratch. Downloads nothing.
#
# Two stages, back to back:
#   swish  (t < 0.21s) white noise pushed through a one-pole lowpass whose
#          cutoff opens up as the leather accelerates. Quiet, rising, airy.
#   crack  (t >= 0.21s) full-band noise on a steep exponential decay, mixed
#          mostly raw so it stays bright, with a 190 Hz thump underneath so it
#          has body instead of sounding like hissing static.

$ErrorActionPreference = 'Stop'

$outPath  = Join-Path $PSScriptRoot 'whip.wav'
$rate     = 22050
$duration = 0.42
$total    = [int]($rate * $duration)
$split    = 0.21
$splitN   = [int]($rate * $split)

$rand    = New-Object System.Random 20240917
$samples = New-Object 'System.Int16[]' $total

# one-pole lowpass state, carried across both stages
$lp = 0.0

for ($i = 0; $i -lt $total; $i++) {
    $t     = $i / $rate
    $noise = ($rand.NextDouble() * 2.0) - 1.0
    $v     = 0.0

    if ($t -lt $split) {
        # --- swish: leather accelerating ---
        $p  = $i / [double]$splitN          # 0 -> 1 across the swish
        $k  = 0.04 + (0.55 * $p)            # cutoff opens 0.04 -> 0.59
        $lp = $lp + ($k * ($noise - $lp))
        $v  = 0.12 * [Math]::Pow($p, 3) * $lp
    }
    else {
        # --- crack: the supersonic snap ---
        $p    = ($i - $splitN) / [double]($total - $splitN)   # 0 -> 1 across the crack
        $env  = [Math]::Exp(-34.0 * $p)
        $k    = 0.59
        $lp   = $lp + ($k * ($noise - $lp))
        $body = 0.18 * [Math]::Sin(2.0 * [Math]::PI * 190.0 * $p) * [Math]::Exp(-60.0 * $p)
        $v    = (($noise * 0.72) + ($lp * 0.28)) * $env + $body
    }

    if ($v -gt 1.0)  { $v = 1.0 }
    if ($v -lt -1.0) { $v = -1.0 }
    $samples[$i] = [int16]([Math]::Round($v * 30000.0))
}

# --- RIFF/WAVE container ---
$dataBytes = $total * 2
$fs = [System.IO.File]::Create($outPath)
$bw = New-Object System.IO.BinaryWriter($fs)
try {
    $bw.Write([char[]]'RIFF')
    $bw.Write([uint32](36 + $dataBytes))   # chunk size = 36 + data
    $bw.Write([char[]]'WAVE')

    $bw.Write([char[]]'fmt ')
    $bw.Write([uint32]16)                  # fmt chunk size
    $bw.Write([uint16]1)                   # PCM
    $bw.Write([uint16]1)                   # mono
    $bw.Write([uint32]$rate)               # sample rate
    $bw.Write([uint32]($rate * 2))         # byte rate = rate * blockAlign
    $bw.Write([uint16]2)                   # block align
    $bw.Write([uint16]16)                  # bits per sample

    $bw.Write([char[]]'data')
    $bw.Write([uint32]$dataBytes)
    foreach ($s in $samples) { $bw.Write([int16]$s) }
}
finally {
    $bw.Dispose()
    $fs.Dispose()
}

$len = (Get-Item $outPath).Length
$expected = 44 + $dataBytes
if ($len -ne $expected) { throw "whip.wav is $len bytes, expected $expected" }
if ($len -lt 10000)     { throw "whip.wav is implausibly small: $len bytes" }
Write-Output "whip.wav written: $len bytes, $total samples, ${duration}s @ ${rate}Hz"
