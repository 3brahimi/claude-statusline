# Claude Code StatusLine — Windows 11 / pwsh
# Line 1: model [effort]      │ ctx   bar pct [empty]   │ cache bar pct ↻reset
# Line 2: ⎇ branch  $cost     │ 5h    bar pct ↻reset    │ 7d    bar pct ↻reset
#         Both columns padded to COL1_MIN so │ separators align vertically
#         COL1_MIN = max(line1 col1 plain width, line2 col1 plain width)

param()
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ── stdin ─────────────────────────────────────────────────────────────────────
$jsonInput = "{}"
try {
    $r = [System.IO.StreamReader]::new([System.Console]::OpenStandardInput())
    $jsonInput = $r.ReadToEnd()
    $r.Close()
} catch {}

# ── ANSI ──────────────────────────────────────────────────────────────────────
$esc    = [char]27
$R      = "$esc[0m"
$bold   = "$esc[1m"
$white  = "$esc[97m"
$lbl_c  = "$esc[38;5;245m"   # dim label color
$sep_c  = "$esc[38;5;245m"   # separator color
$yellow = "$esc[38;5;220m"
$green  = "$esc[38;5;83m"
$orange = "$esc[38;5;208m"
$red    = "$esc[38;5;203m"
$cyan   = "$esc[38;5;117m"   # branch
$gold   = "$esc[38;5;178m"   # cost

$SEP    = " ${sep_c}│${R} "

# ── Bar constants ─────────────────────────────────────────────────────────────
$BAR_W   = 8     # chars
$LABEL_W = 5     # "ctx  " "5h   " "cache" "7d   "
$PCT_W   = 4     # " 63%"

$FULL  = [char]0x2588   # █
$EMPTY = [char]0x2591   # ░

# ── Helpers ───────────────────────────────────────────────────────────────────
function Pct-Color([int]$p) {
    if ($p -lt 50) { return $green }
    if ($p -lt 65) { return $yellow }
    if ($p -lt 80) { return $orange }
    return $red
}

# Inverted scale: high cache hit rate is good (green), low is bad (red)
function Cache-Color([int]$p) {
    if ($p -gt 65) { return $green }
    if ($p -gt 30) { return $orange }
    return $red
}

function Bar-Plain([int]$p) {
    $f = [math]::Min([math]::Round($BAR_W * $p / 100), $BAR_W)
    return ($FULL.ToString() * $f) + ($EMPTY.ToString() * ($BAR_W - $f))
}

function Time-Until([long]$epoch) {
    if ($epoch -le 0) { return "" }
    $diff = [System.DateTimeOffset]::FromUnixTimeSeconds($epoch).UtcDateTime - [DateTime]::UtcNow
    if ($diff.TotalSeconds -le 0) { return "now" }
    if ($diff.TotalDays   -ge 1)  { return "$([math]::Floor($diff.TotalDays))d$([math]::Floor($diff.Hours))h" }
    if ($diff.TotalHours  -ge 1)  { return "$([math]::Floor($diff.TotalHours))h$($diff.Minutes)m" }
    return "$($diff.Minutes)m"
}

# Returns a colored segment: "LABEL bar pct [↻reset]"
# $rstW = per-column reset width; 0 means no reset column rendered.
# $invertColor: if $true, use Cache-Color (high = good) instead of Pct-Color (high = bad)
function Segment([string]$label, [int]$pct, [string]$reset, [bool]$invertColor = $false, [int]$rstW = 0) {
    $c      = if ($invertColor) { Cache-Color $pct } else { Pct-Color $pct }
    $lbl    = $label.PadRight($LABEL_W)
    $bar    = Bar-Plain $pct
    $pctStr = $pct.ToString().PadLeft(3) + "%"   # " 63%"
    $rstStr = ""
    if ($rstW -gt 0) {
        if ($reset) {
            $rstPlain = ("↻ " + $reset).PadRight($rstW)
            $rstStr   = " ${white}${rstPlain}${R}"
        } else {
            $rstStr   = " " + (" " * $rstW)
        }
    }
    return "${lbl_c}${lbl}${R} ${c}${bar} ${pctStr}${R}${rstStr}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
try {
    $d = $jsonInput | ConvertFrom-Json

    # ── Model ─────────────────────────────────────────────────────────────────
    $modelName  = if ($d.model.display_name) { $d.model.display_name } else { "Claude" }
    $mLow       = $modelName.ToLower()
    $modelColor = if ($mLow -match "haiku|small|mini|lite") { $yellow }
                  elseif ($mLow -match "opus|large")         { $red }
                  else                                        { $green }

    # ── Effort ────────────────────────────────────────────────────────────────
    $effortRaw   = "$($d.effort.level)"
    $effortMap   = @{ low="low"; medium="med"; high="high"; xhigh="xhigh"; max="max" }
    $effortCMap  = @{ low=$yellow; medium=$green; high=$orange; xhigh=$red; max=$red }
    $effortLabel = $effortMap[$effortRaw]
    $effortColor = $effortCMap[$effortRaw]

    # ── col1 plain-text widths — compute AFTER we know branch/cost ───────────
    # We need to read branch/cost first; col1W is set after those sections.

    # ── Context usage ─────────────────────────────────────────────────────────
    $ctxPct = if ($null -ne $d.context_window.used_percentage) {
                  [math]::Round($d.context_window.used_percentage) } else { $null }

    # ── Cache hit rate ────────────────────────────────────────────────────────
    $cu      = $d.context_window.current_usage
    $totalIn = [long]($cu.input_tokens) + [long]($cu.cache_read_input_tokens) + [long]($cu.cache_creation_input_tokens)
    $cacheHitPct = if ($totalIn -gt 0) {
                       [math]::Round(100 * [long]($cu.cache_read_input_tokens) / $totalIn)
                   } else { $null }

    # Track cache creation timestamp for 5-min TTL countdown
    $cacheStamp = "$env:TEMP\claude-cache-stamp.txt"
    $cacheReset = ""
    if ([long]($cu.cache_creation_input_tokens) -gt 0) {
        [DateTime]::UtcNow.ToString("o") | Set-Content $cacheStamp -NoNewline
    }
    if (Test-Path $cacheStamp) {
        try {
            $age  = ([DateTime]::UtcNow - [DateTime]::Parse((Get-Content $cacheStamp))).TotalSeconds
            $left = 300 - $age
            if ($left -gt 5) {
                $cacheReset = "$([math]::Floor($left/60))m$([math]::Floor($left % 60).ToString('00'))s"
            }
        } catch {}
    }

    # ── Git ───────────────────────────────────────────────────────────────────
    $cwd    = if ($d.workspace.current_dir) { $d.workspace.current_dir } else { "$PWD" }
    $branch = (git -C $cwd branch --show-current 2>$null) -join ""
    $dirty  = (git -C $cwd status --porcelain 2>$null | Measure-Object).Count -gt 0

    # ── Cost ─────────────────────────────────────────────────────────────────
    $costUsd   = $d.cost.total_cost_usd
    $costPlain = if ($null -ne $costUsd) {
                     "`$$([math]::Round($costUsd,2).ToString('F2'))" } else { "" }

    # ── Rate limits ───────────────────────────────────────────────────────────
    $fivePct = $null; $fiveReset = ""
    $weekPct = $null; $weekReset = ""
    if ($d.rate_limits.five_hour) {
        $fivePct   = [math]::Round($d.rate_limits.five_hour.used_percentage)
        $fiveReset = Time-Until $d.rate_limits.five_hour.resets_at
    }
    if ($d.rate_limits.seven_day) {
        $weekPct   = [math]::Round($d.rate_limits.seven_day.used_percentage)
        $weekReset = Time-Until $d.rate_limits.seven_day.resets_at
    }

    # ── Per-column RST widths — max reset-string visual width per column ────────
    # Column 2: ctx (no reset) vs 5h; Column 3: cache vs 7d
    function Rst-Vis([string]$s) { if ($s) { return 2 + $s.Length } else { return 0 } }
    $col2Rst = Rst-Vis $fiveReset
    $col3Rst = [math]::Max((Rst-Vis $cacheReset), (Rst-Vis $weekReset))

    # ── col1 plain widths — now we know branch/cost ───────────────────────────
    $line1col1Plain = $modelName
    if ($effortLabel) { $line1col1Plain += " [$effortLabel]" }
    $line1col1W = $line1col1Plain.Length

    $branchPlainLen = if ($branch) { 2 + $branch.Length + $(if ($dirty) { 2 } else { 0 }) } else { 0 }
    $gapLen         = if ($branch -and $costPlain) { 2 } else { 0 }
    $line2col1PlainLen = $branchPlainLen + $gapLen + $costPlain.Length

    # Both lines' col1 padded to the same width so │ aligns
    $col1W = [math]::Max($line1col1W, $line2col1PlainLen)

    # ══ LINE 1 ═══════════════════════════════════════════════════════════════
    # model [effort]  (padded to col1W) │ ctx bar pct │ cache bar pct ↻reset
    $line1 = "${modelColor}${bold}${modelName}${R}"
    if ($effortLabel) { $line1 += " ${effortColor}[${effortLabel}]${R}" }
    # Pad line1 col1 to col1W
    $pad1 = $col1W - $line1col1W
    if ($pad1 -gt 0) { $line1 += " " * $pad1 }
    if ($null -ne $ctxPct)      { $line1 += $SEP + (Segment "ctx"   $ctxPct      ""           $false $col2Rst) }
    if ($null -ne $cacheHitPct) { $line1 += $SEP + (Segment "cache" $cacheHitPct $cacheReset  $true  $col3Rst) }

    # ══ LINE 2 ═══════════════════════════════════════════════════════════════
    # ⎇ branch  $cost (padded to col1W) │ 5h bar pct ↻reset │ 7d bar pct ↻reset
    $line2col1 = ""
    if ($branch) {
        $dirtyStr   = if ($dirty) { " ${orange}●${R}" } else { "" }
        $line2col1 += "${cyan}⎇ ${branch}${R}${dirtyStr}"
    }
    if ($branch -and $costPlain) { $line2col1 += "  " }
    if ($costPlain)              { $line2col1 += "${gold}${costPlain}${R}" }
    # Pad to col1W so │ aligns with line1
    $pad2 = $col1W - $line2col1PlainLen
    if ($pad2 -gt 0) { $line2col1 += " " * $pad2 }

    $line2 = $line2col1
    if ($null -ne $fivePct) { $line2 += $SEP + (Segment "5h"  $fivePct $fiveReset $false $col2Rst) }
    if ($null -ne $weekPct) { $line2 += $SEP + (Segment "7d"  $weekPct $weekReset $false $col3Rst) }

    # ══ Emit ══════════════════════════════════════════════════════════════════
    $hasLine2 = ($branch -or $costPlain -or $null -ne $fivePct -or $null -ne $weekPct)
    $out = $line1
    if ($hasLine2) { $out += "`n" + $line2 }

    [System.Console]::Write($out)
    [System.Console]::Out.Flush()

} catch {
    [System.Console]::Write("${green}${bold}Claude${R}")
    [System.Console]::Out.Flush()
}

exit 0
