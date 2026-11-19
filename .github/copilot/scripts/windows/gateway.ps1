<#
The ONLY shell command Copilot agents may run on Windows (the runner allows exactly this path, spelled
.github/copilot/scripts/windows/gateway.cmd, a three-line launcher for this file). Windows edition of
.github/copilot/scripts/macos/gateway.sh: same menu, same arguments, same output, same exit codes.

  gateway.cmd list
  gateway.cmd <check> [args...]          checks: .github/copilot/gateway.conf (plus the optional gateway.windows.conf overlay)
  gateway.cmd git-status
  gateway.cmd git-diff [<ref>] [--stat|--name-only|--name-status|--cached] [-- <path>...]
  gateway.cmd git-log [<count>] [<ref>]
  gateway.cmd git-show <ref> [--stat|--name-only|--name-status]
  gateway.cmd delete-scratch <path>      removes an untracked probe file
  gateway.cmd prove-red <ref> <check> [args...] [-- <files...>]
      runs <check> on a temporary checkout of <ref> with your versions of <files> carried over: a new or
      changed test proves something only if it FAILS there
  gateway.cmd doctor                     is this machine ready: tools on PATH for every check (read-only)

Output: a check that prints more than 200 lines or 16000 bytes is saved whole under .work/gateway/ and shown
as a summary (first lines, failure-looking lines, last lines, the log path). A check with the `full-output`
option in gateway.conf always prints everything.

Why a gateway: see gateway.sh. It runs a fixed menu, never through a shell the agent controls, with every
argument checked to stay inside the repository. Exit status: the check's own; 124 on timeout; 2 for a
refused request (also for a check that needs a Mac: `build` for iOS and `swift-test`); 127 when a tool is missing.

Windows differences (details in .work/windows-harness-notes.md):
  - checks run as `cmd.exe /d /s /c "<tool> <args> > log 2>&1"` (flutter and dart are .bat files). Because cmd.exe
    parses that line, an argument containing a double quote, a percent sign or ending in a backslash is refused
    (the Mac gateway has no shell and allows them); every other argument is quoted, so & | < > ^ are inert;
  - a drive letter (C:), a backslash lead or a UNC path counts as an absolute path and is refused;
  - git-diff tolerates a lost `--`: PowerShell can swallow it, so a word that is not a commit but is an existing
    path is taken as a path.
ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI.
#>
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$Self = $MyInvocation.MyCommand.Path
$Root = $null
try { $Root = ((& git rev-parse --show-toplevel 2>$null) | Select-Object -First 1) } catch { }
if (-not $Root) { [Console]::Error.WriteLine('gateway: not inside a git repository (or git is not on PATH)'); exit 2 }
$Root = [IO.Path]::GetFullPath(([string]$Root).Trim())
Set-Location $Root
$Conf = Join-Path $Root '.github\copilot\gateway.conf'
$LogDir = Join-Path $Root '.work\gateway'
$MainRoot = $Root
# prove-red re-runs this script inside a temporary checkout; it keeps the main checkout's checks and log folder.
# (An agent cannot set these: its shell permission only matches the gateway's own path.)
if ($env:GATEWAY_INNER -eq '1') { $Conf = $env:GATEWAY_CONF; $LogDir = $env:GATEWAY_LOG_DIR; $MainRoot = $env:GATEWAY_MAIN_ROOT }
$ConfWin = Join-Path (Split-Path -Parent $Conf) 'gateway.windows.conf'
$SummaryOver = 200
$SummaryBytes = 16000
# Untracked files whose path starts with this may be removed with delete-scratch (set by the installer).
$ScratchPrefix = 'test/zz_'

function Refuse([string]$msg) { [Console]::Error.WriteLine("gateway: refused: $msg"); exit 2 }
function Say([string]$msg) { [Console]::Error.WriteLine($msg) }
function Out-Line([string]$msg) { [Console]::Out.WriteLine($msg) }
# Runs a native command with its output streamed to stdout (not into a function's return value); returns its exit code.
function Invoke-Native([string]$exe, [string[]]$nativeArgs) {
  & $exe @nativeArgs | ForEach-Object { [Console]::Out.WriteLine([string]$_) }
  return $LASTEXITCODE
}

# An argument may be a flag or a repo-relative path, never a way out of the repository.
function Test-Arg([string]$a) {
  if ($a -match '^(/|~|\\)') { Refuse "absolute or home path: $a" }
  if ($a -match '^[A-Za-z]:([\\/]|$)') { Refuse "drive path: $a" }
  if ($a -match '=(/|~|\\)' -or $a -match '=[A-Za-z]:[\\/]' -or $a -match ':[\\/]') { Refuse "absolute or home path in option: $a" }
  if ($a -eq '..' -or $a -match '(^|[\\/])\.\.([\\/]|$)' -or $a -match '=\.\.') { Refuse "parent-directory path: $a" }
  if ($a -match "[\r\n]") { Refuse 'control characters in argument' }
  # Windows only: the check line goes through cmd.exe, so what cmd.exe would interpret inside quotes is refused.
  if ($a.Contains('"')) { Refuse "double quote in argument: $a" }
  if ($a.Contains('%')) { Refuse "percent sign in argument: $a" }
  if ($a.EndsWith('\')) { Refuse "argument ends in a backslash: $a" }
}
function Test-Commit([string]$r) {
  if ($r.StartsWith('-')) { return $false }
  & git rev-parse --verify --quiet "${r}^{commit}" *> $null
  return ($LASTEXITCODE -eq 0)
}
function Test-Ref([string]$r) {
  if ($r.StartsWith('-')) { Refuse "a ref cannot start with '-': $r" }
  if (-not (Test-Commit $r)) { Refuse "not a commit in this repository: $r" }
}
function Get-Rel([string]$abs) {
  $root = $MainRoot.TrimEnd('\') + '\'
  $a = $abs.Replace('/', '\')
  if ($a.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $a.Substring($root.Length).Replace('\', '/') }
  return $abs.Replace('\', '/')
}
function Get-SelfExe { (Get-Process -Id $PID).Path }

function Find-Tool([string]$name) {
  foreach ($dir in ($env:PATH -split ';')) {
    if (-not $dir) { continue }
    foreach ($ext in @('.exe', '.cmd', '.bat')) {
      $c = Join-Path $dir ($name + $ext)
      if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
  }
  return $null
}

# ---- Checks from gateway.conf ------------------------------------------------------------------------
function Read-Conf([string]$file) {
  $out = @()
  foreach ($raw in (Get-Content -LiteralPath $file -Encoding UTF8)) {
    if ($raw -match '^\s*(#|$)') { continue }
    $f = $raw -split '\|'
    if ($f.Count -lt 3) { continue }
    $out += [pscustomobject]@{
      Name = $f[0].Trim(); Secs = ($f[1] -replace ' ', ''); Cmd = $f[2].Trim()
      Opts = $(if ($f.Count -ge 4) { $f[3].Trim() } else { '' })
    }
  }
  return $out
}
function Get-ConfEntries {
  if (-not (Test-Path -LiteralPath $Conf)) { Refuse "missing $Conf" }
  $map = [ordered]@{}
  foreach ($e in @(Read-Conf $Conf)) { $map[$e.Name] = $e }
  if (Test-Path -LiteralPath $ConfWin) { foreach ($e in @(Read-Conf $ConfWin)) { $map[$e.Name] = $e } }   # Windows overlay wins
  return @($map.Values)
}
# A check that needs a Mac, so a Windows agent gets a plain answer instead of a stack trace.
function Get-MacOnlyReason([string]$cmd) {
  if ($cmd -match '^flutter\s+build\s+(ios|ipa|macos)') { return 'needs a Mac (iOS build)' }
  if ($cmd -match '^(swift|xcodebuild|xcrun)(\s|$)') { return 'needs a Mac (Swift/Xcode toolchain)' }
  return ''
}
function Show-Checks {
  'Checks (gateway.conf):'
  foreach ($e in @(Get-ConfEntries)) {
    $note = ''
    if ($e.Opts) { $note = "  [$($e.Opts)]" }
    $mac = Get-MacOnlyReason $e.Cmd
    if ($mac) { $note += "  (not available on Windows: $mac)" }
    '  {0,-14} {1,5}s  {2}{3}' -f $e.Name, $e.Secs, $e.Cmd, $note
  }
  'Git views: git-status ' + [char]0xB7 + ' git-diff [<ref>] [--stat|--name-only|--name-status|--cached] [-- <path>...] ' + [char]0xB7 + ' git-log [<count>] [<ref>] ' + [char]0xB7 + ' git-show <ref> [--stat|--name-only|--name-status]'
  'Proof: prove-red <ref> <check> [args...] [-- <files...>] runs a check on <ref> (e.g. HEAD) with your test files carried over; a guard must FAIL there'
  "Cleanup: delete-scratch ${ScratchPrefix}<name> (an untracked probe file you created)"
  "Output over $SummaryOver lines or $([int]($SummaryBytes / 1000)) KB is summarised; the full log path is printed (read it with your file tool)."
}

# ---- Git views ---------------------------------------------------------------------------------------
function Invoke-GitDiff([string[]]$a) {
  $opts = @(); $ref = ''; $paths = @(); $dd = $false
  foreach ($x in $a) {
    if ($dd) { Test-Arg $x; $paths += $x; continue }
    if ($x -eq '--') { $dd = $true; continue }
    if ($x -in @('--stat', '--name-only', '--name-status', '--cached', '--staged')) { $opts += $x; continue }
    if ($x.StartsWith('-')) { Refuse "git-diff option not allowed: $x" }
    Test-Arg $x
    if (-not $ref -and (Test-Commit $x)) { $ref = $x; continue }
    if (Test-Path -LiteralPath $x) { $paths += $x; continue }   # the `--` may have been swallowed on the way in
    if ($ref) { Refuse "git-diff takes at most one ref, and '$x' is not a path in this repository" }
    Refuse "not a commit in this repository: $x"
  }
  $cmd = @('--no-pager', 'diff') + $opts
  if ($ref) { $cmd += $ref }
  $cmd += '--'
  $cmd += $paths
  return (Invoke-Native 'git' $cmd)
}
function Invoke-GitLog([string[]]$a) {
  $count = 20; $ref = ''
  foreach ($x in $a) {
    if ($x -match '^[0-9]+$') { $count = [int]$x; if ($count -gt 500) { Refuse 'git-log count above 500' } }
    else { Test-Arg $x; Test-Ref $x; $ref = $x }
  }
  $cmd = @('--no-pager', 'log', '--oneline', '-n', "$count")
  if ($ref) { $cmd += $ref }
  return (Invoke-Native 'git' $cmd)
}
function Invoke-GitShow([string[]]$a) {
  if ($a.Count -lt 1) { Refuse 'git-show needs a ref' }
  $ref = $a[0]; $opt = ''
  Test-Arg $ref; Test-Ref $ref
  foreach ($x in @($a | Select-Object -Skip 1)) {
    if ($x -in @('--stat', '--name-only', '--name-status')) { $opt = $x } else { Refuse "git-show option not allowed: $x" }
  }
  $cmd = @('--no-pager', 'show')
  if ($opt) { $cmd += $opt }
  $cmd += $ref
  return (Invoke-Native 'git' $cmd)
}
# Lets an agent remove its OWN probe file: only an untracked regular file under the scratch prefix.
function Invoke-DeleteScratch([string[]]$a) {
  if ($a.Count -ne 1) { Refuse 'delete-scratch takes exactly one path' }
  $p = $a[0].Replace('\', '/')
  Test-Arg $a[0]
  $name = ''
  if ($p.StartsWith($ScratchPrefix)) { $name = $p.Substring($ScratchPrefix.Length) }
  if (-not $name -or $name -notmatch '^[A-Za-z0-9_.-]+$') { Refuse "delete-scratch only removes ${ScratchPrefix}<name> probe files: $p" }
  & git ls-files --error-unmatch -- $p *> $null
  if ($LASTEXITCODE -eq 0) { Refuse "delete-scratch will not remove a tracked file: $p" }
  $item = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
  if (-not $item -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Refuse "no such file: $p" }
  Remove-Item -LiteralPath $p -Force
  Say "gateway: removed $p"
  return 0
}

# ---- Running checks ----------------------------------------------------------------------------------
# One argument of the cmd.exe line: bare when it is plain, otherwise in double quotes (Test-Arg refused quotes).
function Format-CmdArg([string]$a) {
  if ($a -match '^[A-Za-z0-9_./:=,@+\-\\]+$') { return $a }
  return '"' + $a + '"'
}
function Get-DeletedTracked { @(& git -c core.quotepath=off ls-files --deleted 2>$null | Sort-Object) }

# A check runs code the agent wrote (a test can do anything), so it is the one way around the "no deletions"
# policy. Any tracked file a check deleted is restored, and the check fails.
function Restore-Deletions([string]$name, [string[]]$before) {
  $now = @(Get-DeletedTracked)
  $gone = @($now | Where-Object { $before -notcontains $_ })
  if ($gone.Count -eq 0) { return $true }
  foreach ($f in $gone) { & git checkout -- $f *> $null }
  Say "gateway: REVERTED: '$name' deleted tracked files, which agents may not do through a check:"
  foreach ($f in $gone) { Say "  $f" }
  Say 'List the deletions the work needs under "Governor actions" in your final report; the governor makes them.'
  return $false
}

function Invoke-Cut([string]$s) { if ($s.Length -gt 300) { return $s.Substring(0, 300) + ' ...' }; return $s }

# Runs the check; the output goes to a log under .work/gateway/ and is printed whole only when it is short
# (or full-output); otherwise as a summary that points at the log. Returns the exit code.
function Invoke-Logged([string]$name, [int]$secs, [string]$toolPath, [string[]]$toolArgs, [bool]$full) {
  New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
  Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force -ErrorAction SilentlyContinue
  $log = Join-Path $LogDir ("$name-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID.log")
  $line = '/d /s /c "' + (Format-CmdArg $toolPath) + $(if ($toolArgs.Count) { ' ' + (($toolArgs | ForEach-Object { Format-CmdArg $_ }) -join ' ') } else { '' }) + ' > "' + $log + '" 2>&1"'
  $p = Start-Process -FilePath $env:ComSpec -ArgumentList $line -WorkingDirectory $Root -NoNewWindow -PassThru
  $null = $p.Handle
  $timedOut = $false
  if (-not $p.WaitForExit($secs * 1000)) {
    $timedOut = $true
    & taskkill.exe /PID $p.Id /T /F *> $null
    $null = $p.WaitForExit(5000)
  } else { $p.WaitForExit() }
  $code = 0
  if (-not $timedOut) { $code = $p.ExitCode }
  $l = @()
  if (Test-Path -LiteralPath $log) {
    $text = [IO.File]::ReadAllText($log, [Text.Encoding]::UTF8)
    if ($text.Length -gt 0) { $l = @($text -split "`r?`n"); if ($l[$l.Count - 1] -eq '') { $l = @($l | Select-Object -First ($l.Count - 1)) } }
  }
  $size = 0; foreach ($x in $l) { $size += $x.Length + 1 }
  $out = [Console]::Out
  if ($full -or ($l.Count -le $SummaryOver -and $size -le $SummaryBytes)) {
    foreach ($x in $l) { $out.WriteLine($(if ($full) { $x } else { Invoke-Cut $x })) }
  } else {
    $fail = New-Object Text.RegularExpressions.Regex(('\b(error|errors|fail|failed|failure|failing|exception|panic|traceback|assert\w*|expected|actual|timed? ?out)\b|\[E\]|' + [char]0x2717), 'IgnoreCase')
    $hits = @(); for ($i = 0; $i -lt $l.Count; $i++) { if ($fail.IsMatch($l[$i])) { $hits += $i } }
    $more = 0; if ($hits.Count -gt 120) { $more = $hits.Count - 120; $hits = @($hits | Select-Object -First 120) }
    $rel = Get-Rel $log
    $out.WriteLine("gateway: $([IO.Path]::GetFileNameWithoutExtension($toolPath)) printed $($l.Count) lines; full output: $rel")
    $out.WriteLine('--- first 5 lines'); foreach ($x in @($l | Select-Object -First 5)) { $out.WriteLine((Invoke-Cut $x)) }
    $out.WriteLine("--- lines that look like failures ($($hits.Count + $more))$(if ($more) { ', first 120' })")
    foreach ($i in $hits) { $out.WriteLine(('{0,6}: {1}' -f ($i + 1), (Invoke-Cut $l[$i]))) }
    $out.WriteLine('--- last 40 lines'); foreach ($x in @($l | Select-Object -Last 40)) { $out.WriteLine((Invoke-Cut $x)) }
    $out.WriteLine("--- full output: $rel (read it with your file tool, by line range)")
  }
  if ($timedOut) { Say "gateway: TIMEOUT after ${secs}s: $name"; return 124 }
  return $code
}

function Get-Entry([string]$name) { @(Get-ConfEntries | Where-Object { $_.Name -eq $name }) | Select-Object -First 1 }

function Invoke-Check([string]$name, [string[]]$a) {
  $e = Get-Entry $name
  if (-not $e) { Say "gateway: unknown check '$name'."; Show-Checks | ForEach-Object { Say $_ }; return 2 }
  if ($e.Secs -notmatch '^[0-9]+$') { Refuse "bad timeout for '$name' in gateway.conf" }
  if (-not $e.Cmd) { Refuse "no command for '$name' in gateway.conf" }
  foreach ($x in $a) { Test-Arg $x }
  if ($e.Opts -match 'requires-args' -and $a.Count -eq 0) { Refuse "'$name' needs explicit file arguments (it must never run on the whole tree)" }
  if ($e.Opts -match 'new-files-only') {
    foreach ($x in $a) {
      if ($x.StartsWith('-')) { continue }
      & git ls-files --error-unmatch -- ($x.Replace('\', '/')) *> $null
      if ($LASTEXITCODE -eq 0) { Refuse "'$name' only runs on files this change created; '$x' is already tracked by git. Edit existing files with small edits instead" }
    }
  }
  $mac = Get-MacOnlyReason $e.Cmd
  if ($mac) { Say "gateway: '$name' is not available on Windows: $mac. Report it as not run; the governor runs it on the Mac."; return 2 }
  $parts = @($e.Cmd -split '\s+' | Where-Object { $_ })
  $tool = Find-Tool $parts[0]
  if (-not $tool) { Say "gateway: '$($parts[0])' (needed by '$name') is not installed or not on PATH; report it, do not work around it."; return 127 }
  $toolArgs = @(@($parts | Select-Object -Skip 1) + $a)
  Say "gateway: $name (timeout $($e.Secs)s): $($parts -join ' ') $($a -join ' ')"
  $before = @(Get-DeletedTracked)
  $code = Invoke-Logged $name ([int]$e.Secs) $tool $toolArgs ($e.Opts -match 'full-output')
  if (-not (Restore-Deletions $name $before)) { if ($code -eq 0) { $code = 3 } }
  return $code
}

# Shows that new or changed tests detect the change: runs <check> on a temporary checkout of <ref> with the
# agent's versions of the test files carried over. Green there means the tests pass without the change.
function Invoke-ProveRed([string[]]$a) {
  if ($a.Count -lt 2) { Refuse 'usage: prove-red <ref> <check> [args...] [-- <files to carry over...>]' }
  $ref = $a[0]; $name = $a[1]
  Test-Arg $ref; Test-Ref $ref
  if ($name -in @('prove-red', 'delete-scratch', 'list', 'doctor', 'base-setup') -or $name.StartsWith('git-')) { Refuse "prove-red runs a check from gateway.conf, not '$name'" }
  if (-not (Get-Entry $name)) { Refuse "unknown check '$name'" }
  $args2 = @(); $carry = @(); $split = $false
  foreach ($x in @($a | Select-Object -Skip 2)) {
    if ($split) { $carry += $x; continue }
    if ($x -eq '--') { $split = $true; continue }
    $args2 += $x
  }
  if (-not $split) { foreach ($x in $args2) { if (Test-Path -LiteralPath $x -PathType Leaf) { $carry += $x } } }
  if ($carry.Count -eq 0) { Refuse 'name the test files to carry over (after --, or as file arguments)' }
  foreach ($x in $args2) { Test-Arg $x }
  foreach ($x in $carry) {
    Test-Arg $x
    $it = Get-Item -LiteralPath $x -ErrorAction SilentlyContinue
    if (-not $it -or $it.PSIsContainer -or ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Refuse "not a file: $x" }
  }
  $wt = Join-Path $LogDir "base-$PID"
  New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
  & git worktree add --detach -q $wt $ref *> $null
  if ($LASTEXITCODE -ne 0) { Refuse "could not check out $ref" }
  $code = 0
  $saved = @{}
  foreach ($k in @('GATEWAY_INNER', 'GATEWAY_CONF', 'GATEWAY_LOG_DIR', 'GATEWAY_MAIN_ROOT')) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
  try {
    foreach ($x in $carry) {
      $dest = Join-Path $wt ($x.Replace('/', '\'))
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      Copy-Item -LiteralPath $x -Destination $dest -Force
    }
    $env:GATEWAY_INNER = '1'; $env:GATEWAY_CONF = $Conf; $env:GATEWAY_LOG_DIR = $LogDir; $env:GATEWAY_MAIN_ROOT = $MainRoot
    Say "gateway: prove-red: '$name' on $ref with your versions of: $($carry -join ' ')"
    $exe = Get-SelfExe
    Push-Location $wt
    try {
      if (Get-Entry 'base-setup') {
        & $exe -NoProfile -ExecutionPolicy Bypass -File $Self base-setup *> $null
        if ($LASTEXITCODE -ne 0) { Say "gateway: prove-red: base-setup failed on $ref"; return 2 }
      }
      $code = Invoke-Native $exe (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Self, $name) + $args2)
    } finally { Pop-Location }
  } finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    & git -C $MainRoot worktree remove --force $wt *> $null
    if (Test-Path -LiteralPath $wt) { Remove-Item -LiteralPath $wt -Recurse -Force -ErrorAction SilentlyContinue }
    & git -C $MainRoot worktree prune *> $null
  }
  if ($code -eq 124) { Say "gateway: prove-red: TIMEOUT on $ref"; return 124 }
  if ($code -eq 0) {
    Say "gateway: prove-red: GREEN AT ${ref}: these tests pass without your change, so they do not detect it. Strengthen them."
    return 1
  }
  Say "gateway: prove-red: RED AT $ref (exit $code). It proves the guard only if an assertion fails for the reason the test guards; a compile or load error means the test could not run there (use a mutation instead)."
  return 0
}

# Read-only: is every tool the checks need on PATH, and is the git view working?
function Invoke-Doctor {
  $bad = 0
  Out-Line "gateway doctor (Windows) $([char]0xB7) PowerShell $($PSVersionTable.PSVersion) $([char]0xB7) repo $Root"
  foreach ($e in @(Get-ConfEntries)) {
    $mac = Get-MacOnlyReason $e.Cmd
    if ($mac) { Out-Line ('  {0,-12} n/a   {1}' -f $e.Name, $mac); continue }
    $parts = @($e.Cmd -split '\s+' | Where-Object { $_ })
    $t = Find-Tool $parts[0]
    if ($t) { Out-Line ('  {0,-12} OK    {1}' -f $e.Name, $t) } else { Out-Line ('  {0,-12} MISSING  {1} is not on PATH' -f $e.Name, $parts[0]); $bad++ }
  }
  $head = ''; try { $head = (& git rev-parse --short HEAD 2>$null) } catch { }
  if ($head) { Out-Line "  git          OK    HEAD $head" } else { Out-Line '  git          MISSING  no commit / git not working'; $bad++ }
  Out-Line ('cmd.exe line check: ' + $(if ($env:ComSpec -and (Test-Path -LiteralPath $env:ComSpec)) { 'OK' } else { 'MISSING (ComSpec)' }))
  if ($bad -eq 0) { Out-Line 'RESULT: ready' } else { Out-Line "RESULT: $bad tool(s) missing (a check that needs one exits 127)" }
  return $(if ($bad -eq 0) { 0 } else { 1 })
}

# ---- Entry -------------------------------------------------------------------------------------------
$All = @(); foreach ($x in $args) { if ($x -is [array]) { $All += @($x | ForEach-Object { [string]$_ }) } else { $All += [string]$x } }
if ($All.Count -eq 0) { Show-Checks; exit 0 }
$Action = $All[0]
$Rest = @(); if ($All.Count -gt 1) { $Rest = @($All | Select-Object -Skip 1) }
$rc = 0
try {
  switch ($Action) {
    { $_ -in @('list', '-h', '--help') } { Show-Checks }
    'doctor' { $rc = Invoke-Doctor }
    'git-status' {
      if ($Rest.Count -ne 0) { Refuse 'git-status takes no arguments' }
      $rc = Invoke-Native 'git' @('--no-pager', 'status', '--short', '--branch')
    }
    'git-diff' { $rc = Invoke-GitDiff $Rest }
    'git-log' { $rc = Invoke-GitLog $Rest }
    'git-show' { $rc = Invoke-GitShow $Rest }
    'delete-scratch' { $rc = Invoke-DeleteScratch $Rest }
    'prove-red' { $rc = Invoke-ProveRed $Rest }
    default { $rc = Invoke-Check $Action $Rest }
  }
} catch {
  Say "gateway: internal error: $($_.Exception.Message)"
  $rc = 1
}
exit ([int](@($rc)[-1]))
