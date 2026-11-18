<#
Economics of the Copilot runs in a time window, from .work/runs and git (Windows edition of
.claude/scripts/macos/pipeline-stats.sh: same arguments, same report lines).

  pwsh -NoProfile -File .claude/scripts/windows/pipeline-stats.ps1 [--since "YYYY-MM-DD HH:MM"] [--until "YYYY-MM-DD HH:MM"]

Default window: the last 24 hours. Code produced = lines added + deleted in commits made in the window under
STATS_PATHS (.claude/pipeline.env; ":"-separated, default lib/:test/), so uncommitted work is not counted.
Run types come from the agent name and the brief's file name (*review*, *fix*, *plan*; everything else builds).
ASCII only on purpose (Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI).
#>
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$inv = [Globalization.CultureInfo]::InvariantCulture
$root = ((& git rev-parse --show-toplevel) | Select-Object -First 1).Trim()
Set-Location $root

$since = ''; $until = ''
for ($i = 0; $i -lt $args.Count; $i++) {
  switch ([string]$args[$i]) {
    '--since' { $i++; $since = [string]$args[$i] }
    '--until' { $i++; $until = [string]$args[$i] }
    { $_ -in '-h', '--help' } { Get-Content -LiteralPath $PSCommandPath -Encoding UTF8 | Select-Object -Skip 5 -First 5 | ForEach-Object { $_ }; exit 0 }
    default { [Console]::Error.WriteLine("unknown argument: $($args[$i])"); exit 2 }
  }
}
if (-not $since) { $since = (Get-Date).AddHours(-24).ToString('yyyy-MM-dd HH:mm', $inv) }
if (-not $until) { $until = (Get-Date).ToString('yyyy-MM-dd HH:mm', $inv) }
# RUN_IDs are YYYYMMDD-HHMMSS-<agent>: compare them as strings against the window.
function To-Id([string]$t) { $d = (($t -replace '[^0-9]', '') + '000000000000'); return ($d.Substring(0, 8) + '-' + $d.Substring(8, 6)) }
$fromId = To-Id $since; $toId = To-Id $until

$statsPaths = ''
$envFile = Join-Path $root '.claude\pipeline.env'
if (Test-Path -LiteralPath $envFile) {
  $m = Select-String -LiteralPath $envFile -Pattern '^STATS_PATHS=(.*)$' | Select-Object -Last 1
  if ($m) { $statsPaths = $m.Matches[0].Groups[1].Value.Trim('"') }
}
if (-not $statsPaths) { $statsPaths = 'lib/:test/' }
$paths = @($statsPaths -split ':' | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
if ($paths.Count -eq 0) { $paths = @('.') }

$runsDir = Join-Path $root '.work\runs'
$runs = @()
if (Test-Path -LiteralPath $runsDir) {
  $runs = @(Get-ChildItem -LiteralPath $runsDir -Directory | Where-Object { $_.Name -match '^[0-9]{8}-[0-9]{6}-' -and [string]::CompareOrdinal($_.Name, $fromId) -ge 0 -and [string]::CompareOrdinal($_.Name, $toId) -lt 0 } | Sort-Object Name)
}
if ($runs.Count -eq 0) { "No runs between $since and $until."; exit 0 }

function Read-Opt([string]$path) { if (Test-Path -LiteralPath $path) { ([IO.File]::ReadAllText($path)).Trim() } else { '' } }
function To-Number([string]$v, [string]$unit) { $x = [double]::Parse($v, $inv); if ($unit -eq 'm') { return $x * 1e6 } elseif ($unit -eq 'k') { return $x * 1e3 } else { return $x } }
$dotC = [string][char]0x25CF; $crossC = [string][char]0x2717
$tokRe = New-Object Text.RegularExpressions.Regex(([string][char]0x2191 + ' ([\d.]+)([mk]?) \(([\d.]+)([mk]?) cached\) ' + [char]0x2022 + ' ' + [char]0x2193 + ' ([\d.]+)([mk]?)'))

$N = 0; $R = 0; $M = 0.0; $reqs = @(); $stops = @{}; $I = 0.0; $C = 0.0; $O = 0.0; $K = @{}; $missing = 0
$longCount = 0; $LT = 0.0; $firsts = @(); $topreads = @(); $slow = 0
foreach ($d in $runs) {
  $r = $d.FullName; $o = Join-Path $r 'output.log'
  if (-not (Test-Path -LiteralPath $o)) { continue }
  if (-not (Test-Path -LiteralPath (Join-Path $r 'started_epoch'))) { continue }
  $agent = Read-Opt (Join-Path $r 'agent'); if (-not $agent) { $agent = '?' }
  $brief = Split-Path -Leaf (Read-Opt (Join-Path $r 'prompt_file'))
  $kind = 'build'
  if ($agent -in 'conductor', 'conductor-v2') { $kind = 'plan' } elseif ($agent -eq 'code-reviewer') { $kind = 'review' }
  if ($brief -match 'review') { $kind = 'review' } elseif ($brief -match 'fix') { $kind = 'fix' } elseif ($brief -match 'plan') { $kind = 'plan' }
  $proxy = Join-Path $r 'proxy.log'
  $req = 0; if (Test-Path -LiteralPath $proxy) { $req = @(Select-String -LiteralPath $proxy -Pattern ' -> ').Count }
  $lines = @(Get-Content -LiteralPath $o -Encoding UTF8)
  $callLines = @($lines | Where-Object { $_.StartsWith($dotC + ' ') -or $_.StartsWith($crossC + ' ') -or $_.StartsWith('/ ') })
  $calls = $callLines.Count
  $started = [double](Read-Opt (Join-Path $r 'started_epoch'))
  $mtime = [DateTimeOffset]::new((Get-Item -LiteralPath $o).LastWriteTimeUtc).ToUnixTimeSeconds()
  $min = ($mtime - $started) / 60.0
  $impl = ($agent -notin 'conductor', 'conductor-v2', 'code-reviewer')
  $first = -1.0
  if ($impl -and $calls -ge 10) {
    $n = 0; for ($i = 0; $i -lt $callLines.Count; $i++) { if ($callLines[$i] -match ('^' + $dotC + ' (Edit|Create)')) { $n = $i + 1; break } }
    if ($n -eq 0) { $n = $calls }
    $first = $min * $n / $calls
  }
  $reads = @{}
  for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    if ($lines[$i].StartsWith($dotC + ' Read ') -and $lines[$i + 1].StartsWith('  ' + [char]0x2502 + ' ')) { $reads[$lines[$i + 1]] = 1 + [int]$reads[$lines[$i + 1]] }
  }
  $topread = 0; if ($reads.Count -gt 0) { $topread = [int]($reads.Values | Measure-Object -Maximum).Maximum }
  $tok = @($lines | Where-Object { $_ -match '^Tokens' } | Select-Object -Last 1)
  $stop = Read-Opt (Join-Path $r 'stop_reason')
  $N++; $R += $req; $M += $min; $reqs += $req
  if ($stop) { $stops[$stop] = 1 + [int]$stops[$stop] }
  $mt = $null; if ($tok.Count -gt 0) { $mt = $tokRe.Match([string]$tok[0]) }
  if ($mt -and $mt.Success) {
    $in = To-Number $mt.Groups[1].Value $mt.Groups[2].Value
    $I += $in; $C += (To-Number $mt.Groups[3].Value $mt.Groups[4].Value); $O += (To-Number $mt.Groups[5].Value $mt.Groups[6].Value)
    $K[$kind] = $in + [double]$K[$kind]
    if ($impl -and $min -ge 45) { $longCount++; $LT += $in }
  } else { $missing++ }
  if ($impl -and $first -ge 0) { $firsts += $first; $topreads += $topread; if ($first -ge 15) { $slow++ } }
}

$changed = 0
$hashes = @(& git log --since="$since" --until="$until" --format=%h 2>$null)
$commits = $hashes.Count
foreach ($h in @(& git log --since="$since" --until="$until" --format=%h -- @paths 2>$null)) {
  $sh = (& git show --shortstat --format= $h -- @paths 2>$null | Select-Object -Last 1)
  foreach ($mm in [regex]::Matches([string]$sh, '(\d+) (insertion|deletion)')) { $changed += [int]$mm.Groups[1].Value }
}
function Median($a) { $s = @($a | Sort-Object); if ($s.Count -eq 0) { return 0 }; return $s[[int][Math]::Floor(($s.Count - 1) / 2)] }
function Avg($a) { $s = @($a); if ($s.Count -eq 0) { return 0.0 }; return (($s | Measure-Object -Sum).Sum / $s.Count) }
function F([string]$fmt, $v) { ([double]$v).ToString($fmt, $inv) }

"Window: $since -> $until"
"Runs: $N ($missing without a token total) $([char]0xB7) agent time $(F '0' $M) min $([char]0xB7) model requests $R (median $(Median $reqs) per run)"
$cachePct = 0.0; if ($I -gt 0) { $cachePct = 100 * $C / $I }
$perReq = 0.0; if ($R -gt 0) { $perReq = $I / $R / 1e3 }
"Input tokens: $(F '0.0' ($I / 1e6))M ($(F '0' $cachePct)% cache reads) $([char]0xB7) output $(F '0.00' ($O / 1e6))M $([char]0xB7) $(F '0' $perReq)k per request"
$perLine = 'no committed code in the window'; if ($changed -gt 0) { $perLine = "$(F '0.0' ($I / $changed / 1e3))k input tokens per changed line" }
"Code produced: $changed lines changed in $commits commits $([char]0xB7) $perLine"
$where = @($K.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { '{0} {1}%' -f $_.Key, (F '0' $(if ($I -gt 0) { 100 * $_.Value / $I } else { 0 })) }) -join " $([char]0xB7) "
"Where the tokens went: $where"
$longPct = 0.0; if ($I -gt 0) { $longPct = 100 * $LT / $I }
"Implementers: first edit median $(F '0.0' (Median $firsts)) min ($slow of $($firsts.Count) runs read 15+ min first) $([char]0xB7) most re-read file $(F '0.0' (Avg $topreads)) reads on average $([char]0xB7) runs of 45+ min: $longCount ($(F '0' $longPct)% of tokens)"
$stopText = 'none'; if ($stops.Count -gt 0) { $stopText = (@($stops.GetEnumerator() | Sort-Object Key | ForEach-Object { '{0} {1}' -f $_.Key, $_.Value }) -join ', ') }
"Automatic stops: $stopText"
