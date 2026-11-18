<#
Runs one agent of the crew (the governor's own team, see .claude/crew.md) as a GitHub Copilot CLI custom
agent in the background and prints a compact summary. Several runs can be alive at once.
Windows (PowerShell) edition of .claude/scripts/macos/crew-run.sh: same commands, same run-dir layout under
.work/runs/<RUN_ID>/, same summary lines, same exit conventions (124 = timeout, mapped to STOPPED/max_runtime).

  pwsh -NoProfile -File .claude/scripts/windows/crew-run.ps1 start  <crew-agent> <prompt-file> [--scope g1,g2] [--model m] [--allow-overlap] [--dry-run]
  pwsh -NoProfile -File .claude/scripts/windows/crew-run.ps1 wait   <RUN_ID>   (blocks up to WAIT_MINUTES; run it in the background)
  pwsh -NoProfile -File .claude/scripts/windows/crew-run.ps1 status <RUN_ID>   (returns at once)
  pwsh -NoProfile -File .claude/scripts/windows/crew-run.ps1 stop   <RUN_ID>
  pwsh -NoProfile -File .claude/scripts/windows/crew-run.ps1 list
  pwsh -NoProfile -File .claude/scripts/windows/crew-run.ps1 check  <crew-agent> [--scope g1,g2]   (dry run: what would be granted)
  pwsh -NoProfile -File .claude/scripts/windows/crew-run.ps1 doctor     (is this machine ready: tools, files, key present or not)
  pwsh -NoProfile -File .claude/scripts/windows/crew-run.ps1 selftest   (end to end with a FAKE copilot: needs no key, no network)

Same rules as the macOS runner: only crew-* agents; settings from .claude/crew.env (an environment variable of
the same name overrides it); write access is a SCOPE inside the agent's ceiling
(.github/copilot/permissions/crew-<name>.flags); no two live runs with overlapping scopes; at most
MAX_PARALLEL_WRITERS writers at once; health looks only at the run's own scope.

What differs on Windows (details in .work/windows-harness-notes.md):
  - the agent's one shell command is the Windows gateway, .github/copilot/scripts/windows/gateway.cmd (a launcher for
    gateway.ps1). The runner swaps the macOS gateway allow-rule in common.flags for the Windows spelling at run time
    (the files themselves are never edited) and tells the agent so in its prompt file;
  - the full prompt (standing rules, hang notes, Windows note) is written to .work/runs/<id>/prompt.md and the agent
    is told to read it: a 12 KB prompt with quotes and newlines does not survive a Windows command line;
  - the local OpenCode proxy is started by the worker itself (same logic as with-opencode.ps1), and a .cmd shim of
    copilot is resolved to node + script, because cmd.exe cuts command lines at 8191 characters;
  - dependencies: PowerShell 5.1 or 7, git, the copilot CLI, node 18+ (proxy). No perl, awk, pgrep or flock needed.
ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI.
#>
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptPath
$OrigPwd = (Get-Location).Path
$Cmd = ''; if ($args.Count -gt 0) { $Cmd = [string]$args[0] }
$Rest = @()
if ($args.Count -gt 1) {
  # a comma list typed inside PowerShell arrives as an array; with -File it arrives as one string
  $Rest = @($args[1..($args.Count - 1)] | ForEach-Object { if ($_ -is [array]) { ($_ -join ',') } else { [string]$_ } })
}

$RepoRoot = $null
try { $RepoRoot = ((& git rev-parse --show-toplevel 2>$null) | Select-Object -First 1) } catch { }
if (-not $RepoRoot) { [Console]::Error.WriteLine('crew-run: not inside a git repository (or git is not on PATH)'); exit 2 }
$RepoRoot = [IO.Path]::GetFullPath(([string]$RepoRoot).Trim())
Set-Location $RepoRoot
$Runs = Join-Path $RepoRoot '.work\runs'
New-Item -ItemType Directory -Force -Path $Runs | Out-Null
$AgentsDir = Join-Path $RepoRoot '.github\agents'
$PermissionsDir = Join-Path $RepoRoot '.github\copilot\permissions'

# The agents' one shell command. The macOS spelling is what common.flags, crew-rules.md and the agent files name.
$MacGateway = '.github/copilot/scripts/macos/gateway.sh'
$WinGateway = '.github/copilot/scripts/windows/gateway.cmd'
$WinGatewayPs1 = '.github/copilot/scripts/windows/gateway.ps1'
$MidDot = [string][char]0xB7
$Times = [string][char]0xD7

# ---- Small helpers -------------------------------------------------------------------------------
function P([string]$dir, [string]$name) { [IO.Path]::Combine($dir, $name) }
function Write-Text([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text) }
function Read-Text([string]$path) { if (Test-Path -LiteralPath $path) { ([IO.File]::ReadAllText($path)).Trim() } else { '' } }
function Get-Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Fmt1([double]$x) { $x.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) }
function Get-MinutesSince([long]$epoch) { Fmt1(((Get-Now) - $epoch) / 60.0) }
function Get-Epoch([string]$path, [long]$default) { $t = Read-Text $path; if ($t -match '^\d+$') { return [long]$t }; return $default }
function Quote-Arg([string]$a) {
  if ($null -eq $a -or $a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $s = $a -replace '(\\*)"', '$1$1\"'
  $s = $s -replace '(\\+)$', '$1$1'
  return '"' + $s + '"'
}
function Join-Args($list) { (@($list) | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ' }
function Get-RelPath([string]$abs) {
  $root = $RepoRoot.TrimEnd('\') + '\'
  $a = $abs.Replace('/', '\')
  if ($a.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $a.Substring($root.Length).Replace('\', '/') }
  return $abs.Replace('\', '/')
}
# Reads a file another process may still be writing (the agent's log); never throws.
function Read-Lines([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return @() }
  $text = ''
  try {
    $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $text = $sr.ReadToEnd() } finally { $fs.Dispose() }
  } catch { return @() }
  if ($text.Length -eq 0) { return @() }
  $lines = @($text -split "`r?`n")
  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
  return $lines
}
# Length through an open handle: directory listings can lag behind a file that is still being written.
function Get-FileLength([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return -1 }
  try {
    $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { return [long]$fs.Length } finally { $fs.Dispose() }
  } catch { return -1 }
}
function Find-OnPath([string]$name) {
  if ($name -match '[\\/]' -or [IO.Path]::IsPathRooted($name)) {
    foreach ($ext in @('', '.exe', '.cmd', '.bat', '.ps1', '.js')) { if (Test-Path -LiteralPath ($name + $ext) -PathType Leaf) { return [IO.Path]::GetFullPath($name + $ext) } }
    return $null
  }
  foreach ($dir in ($env:PATH -split ';')) {
    if (-not $dir) { continue }
    foreach ($ext in @('.exe', '.cmd', '.bat', '.ps1')) {
      $c = Join-Path $dir ($name + $ext)
      if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
  }
  return $null
}
function Get-SelfExe { (Get-Process -Id $PID).Path }

# ---- Settings (.claude/crew.env, with environment overrides) --------------------------------------
$ConfigKeys = 'WAIT_MINUTES TAIL_LINES POLL_SECONDS COPILOT_BIN COPILOT_WRAPPER MAX_RUN_MINUTES STALL_MINUTES REPEAT_STOP NO_WRITE_STOP LONG_RUN_MINUTES COPILOT_NO_CUSTOM_INSTRUCTIONS COPILOT_REASONING_EFFORT HUNG_CHILD_MINUTES MAX_PARALLEL_WRITERS DENIED_STOP CHECKER_REPEAT_STOP CHECKER_READ_STOP'.Split(' ')
$FileVars = @{}
function Expand-Vars([string]$v) {
  # the file is a shell file: "$GLM" refers to an earlier line
  return [regex]::Replace($v, '\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?', { param($m) if ($script:FileVars.ContainsKey($m.Groups[1].Value)) { $script:FileVars[$m.Groups[1].Value] } else { '' } })
}
function Load-Config {
  $file = Join-Path $RepoRoot '.claude\crew.env'
  if (-not (Test-Path -LiteralPath $file)) { [Console]::Error.WriteLine('Missing .claude/crew.env'); exit 2 }
  $script:FileVars = @{}
  foreach ($raw in (Get-Content -LiteralPath $file -Encoding UTF8)) {
    $line = $raw.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
      $k = $Matches[1]; $v = $Matches[2].Trim()
      if ($v -match '^"(.*)"$') { $v = Expand-Vars $Matches[1] }
      elseif ($v -match "^'(.*)'$") { $v = $Matches[1] }
      else { $v = ($v -replace '\s+#.*$', ''); $v = Expand-Vars $v }
      $script:FileVars[$k] = $v
    }
  }
  function Get-One([string]$name, [string]$default) {
    $e = [Environment]::GetEnvironmentVariable($name)
    if ($null -ne $e -and $e -ne '') { return $e }
    if ($script:FileVars.ContainsKey($name)) { return $script:FileVars[$name] }
    return $default
  }
  $script:WaitMinutes = [double](Get-One 'WAIT_MINUTES' '25')
  $script:TailLines = [int](Get-One 'TAIL_LINES' '40')
  $script:PollSeconds = [double](Get-One 'POLL_SECONDS' '15')
  $script:CopilotBin = Get-One 'COPILOT_BIN' 'copilot'
  $script:CopilotWrapper = Get-One 'COPILOT_WRAPPER' ''
  $script:MaxRunMinutes = [double](Get-One 'MAX_RUN_MINUTES' '90')
  $script:StallMinutes = [double](Get-One 'STALL_MINUTES' '20')
  $script:RepeatStop = [int](Get-One 'REPEAT_STOP' '40')
  $script:NoWriteStop = [double](Get-One 'NO_WRITE_STOP' '15')
  $script:LongRunMinutes = [double](Get-One 'LONG_RUN_MINUTES' '25')
  $script:HungChildMinutes = [double](Get-One 'HUNG_CHILD_MINUTES' '10')
  $script:NoCustomInstructions = (Get-One 'COPILOT_NO_CUSTOM_INSTRUCTIONS' '1') -eq '1'
  $script:ReasoningEffort = Get-One 'COPILOT_REASONING_EFFORT' ''
  $script:MaxParallelWriters = [int](Get-One 'MAX_PARALLEL_WRITERS' '2')
  $script:DeniedStop = [int](Get-One 'DENIED_STOP' '12')
  $script:CheckerRepeatStop = [int](Get-One 'CHECKER_REPEAT_STOP' '25')
  $script:CheckerReadStop = [int](Get-One 'CHECKER_READ_STOP' '25')
  if ($script:ReasoningEffort -notin @('', 'none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max')) {
    [Console]::Error.WriteLine('COPILOT_REASONING_EFFORT must be empty or one of none|minimal|low|medium|high|xhigh|max'); exit 2
  }
  # the .sh wrapper name in crew.env maps to its Windows counterpart
  if ($script:CopilotWrapper -match '\.sh$') { $script:CopilotWrapper = ($script:CopilotWrapper -replace '\.sh$', '.ps1') }
  # selftest: a fake copilot, no proxy, no key
  $script:SelfTest = $false
  if ($env:CREW_SELFTEST_BIN) { $script:CopilotBin = $env:CREW_SELFTEST_BIN; $script:CopilotWrapper = ''; $script:SelfTest = $true }
}
Load-Config

# ---- Roles (same lists as crew-run.sh) -------------------------------------------------------------
function Test-Writer([string]$a) { $a -in @('crew-builder-data', 'crew-builder-app', 'crew-builder-watch', 'crew-prover', 'crew-docs-keeper') }
function Test-Implementer([string]$a) { $a -in @('crew-builder-data', 'crew-builder-app', 'crew-builder-watch') }
function Test-Checker([string]$a) { $a -in @('crew-scout', 'crew-architect', 'crew-reviewer') }
function Get-ModelFor([string]$agent) {
  $var = 'CREW_MODEL_' + ($agent -replace '-', '_')
  if ($script:FileVars.ContainsKey($var)) { return $script:FileVars[$var] }
  return ''
}

# ---- Permissions and scope -------------------------------------------------------------------------
function Get-LiteralPrefix([string]$g) { [regex]::Match($g, '^[^*?\[]*').Value }
function Test-StartsWith([string]$s, [string]$prefix) { $s.StartsWith($prefix, [StringComparison]::Ordinal) }
$script:PermFlags = @(); $script:Ceiling = @(); $script:Effective = @()

function Load-Permissions([string]$agent, [string]$scopeCsv) {
  $flags = New-Object System.Collections.Generic.List[string]
  $ceiling = New-Object System.Collections.Generic.List[string]
  $effective = New-Object System.Collections.Generic.List[string]
  $agentFile = Join-Path $PermissionsDir ($agent + '.flags')
  $sawGateway = $false
  foreach ($file in @((Join-Path $PermissionsDir 'common.flags'), $agentFile)) {
    $rel = Get-RelPath $file
    if (-not (Test-Path -LiteralPath $file)) { [Console]::Error.WriteLine("No permission profile: $rel - refusing to run '$agent'."); exit 2 }
    foreach ($raw in (Get-Content -LiteralPath $file -Encoding UTF8)) {
      $line = $raw.Trim()
      if ($line -eq '' -or $line.StartsWith('#')) { continue }
      if ($line -match '^--(allow-all-tools|allow-all|yolo|allow-all-paths|allow-all-urls)(=|$)') {
        [Console]::Error.WriteLine("Refusing to run: $rel grants everything ($line)."); exit 2
      }
      if ($line -eq '--allow-tool=write') {
        [Console]::Error.WriteLine("Refusing to run: $rel grants unscoped write. Crew profiles list paths: --allow-tool=write(<glob>)."); exit 2
      }
      # An interpreter may only appear in a deny rule (same check as crew-run.sh, plus the Windows shells).
      if ($line -notmatch '^--deny-tool=' -and $line -match 'shell\((bash|sh|zsh|fish|pwsh|powershell|cmd|python|node|perl|ruby|env|xargs|eval|exec|iex|py)') {
        [Console]::Error.WriteLine("Refusing to run: $rel allows an interpreter ($line)."); exit 2
      }
      if ($line -match '^--allow-tool=write\((.*)\)$') {
        if ($file -eq $agentFile) { $ceiling.Add($Matches[1]); continue }   # re-added below, as the run's scope
      }
      if (-not $line.StartsWith('--')) { [Console]::Error.WriteLine("Refusing to run: $rel has a line that is not a flag: $line"); exit 2 }
      # The macOS gateway is the only shell command allowed; on Windows the same menu is the Windows gateway.
      if ($line -eq ('--allow-tool=shell(' + $MacGateway + ':*)')) {
        $sawGateway = $true
        $flags.Add('--allow-tool=shell(' + $WinGateway + ':*)')
        $flags.Add('--allow-tool=shell(' + $WinGatewayPs1 + ':*)')
        continue
      }
      $flags.Add($line)
    }
  }
  if (-not $sawGateway) {
    $flags.Add('--allow-tool=shell(' + $WinGateway + ':*)')
    $flags.Add('--allow-tool=shell(' + $WinGatewayPs1 + ':*)')
  }
  if ($scopeCsv) {
    foreach ($g in ($scopeCsv -split ',')) {
      if ($g -eq '' -or $g.StartsWith('/') -or $g.StartsWith('~') -or $g.Contains('..') -or $g -match '^[A-Za-z]:' -or $g.Contains('\')) {
        [Console]::Error.WriteLine("Refusing scope '$g': it must be a repository-relative glob with forward slashes and no '..'."); exit 2
      }
      $lp = Get-LiteralPrefix $g; $ok = $false
      foreach ($c in $ceiling) { if (Test-StartsWith $lp (Get-LiteralPrefix $c)) { $ok = $true } }
      if (-not $ok) {
        $cl = if ($ceiling.Count -gt 0) { $ceiling -join ' ' } else { 'nothing' }
        [Console]::Error.WriteLine("Refusing scope '$g': outside what $agent may write ($cl)."); exit 2
      }
      $effective.Add($g)
    }
  } else {
    foreach ($g in $ceiling) { $effective.Add($g) }
  }
  # A narrowed scope must not cost the agent its reports: .work/crew/** stays writable whenever the ceiling has it.
  if ($ceiling.Contains('.work/crew/**') -and -not $effective.Contains('.work/crew/**')) { $effective.Add('.work/crew/**') }
  foreach ($g in $effective) { $flags.Add('--allow-tool=write(' + $g + ')') }
  $script:PermFlags = $flags.ToArray(); $script:Ceiling = $ceiling.ToArray(); $script:Effective = $effective.ToArray()
}

function Get-ScopeSpecs([string]$dir) {
  $specs = @()
  $f = P $dir 'scope'
  if (-not (Test-Path -LiteralPath $f) -or (Get-Item -LiteralPath $f).Length -eq 0) { return @() }
  foreach ($g in (Get-Content -LiteralPath $f -Encoding UTF8)) {
    if (-not $g -or $g.StartsWith('.work/')) { continue }
    $specs += (':(glob)' + $g)
  }
  return $specs
}
function Test-GlobsOverlap([string]$x, [string]$y) {
  $a = Get-LiteralPrefix $x; $b = Get-LiteralPrefix $y
  return ((Test-StartsWith $a $b) -or (Test-StartsWith $b $a))
}

# Refuses a start that would overlap a live run's scope or exceed MAX_PARALLEL_WRITERS. Returns $true when clear.
function Test-ParallelClear([string]$agent) {
  $writers = 0
  foreach ($d in @(Get-ChildItem -LiteralPath $Runs -Directory -ErrorAction SilentlyContinue)) {
    $dir = $d.FullName
    if (Test-Path -LiteralPath (P $dir 'exit')) { continue }
    if (-not (Test-WorkerAlive $dir)) { continue }
    if (Test-Writer (Read-Text (P $dir 'agent'))) { $writers++ }
    $sf = P $dir 'scope'
    if (-not (Test-Path -LiteralPath $sf) -or (Get-Item -LiteralPath $sf).Length -eq 0) { continue }
    foreach ($g in $script:Effective) {
      if ($g.StartsWith('.work/')) { continue }
      foreach ($h in (Get-Content -LiteralPath $sf -Encoding UTF8)) {
        if (-not $h -or $h.StartsWith('.work/')) { continue }
        if (Test-GlobsOverlap $g $h) {
          [Console]::Error.WriteLine("Refusing to start ${agent}: its scope '$g' overlaps '$h' of live run $($d.Name) ($(Read-Text (P $dir 'agent'))). Narrow --scope, wait for that run, or pass --allow-overlap.")
          return $false
        }
      }
    }
  }
  if ((Test-Writer $agent) -and $writers -ge $script:MaxParallelWriters) {
    [Console]::Error.WriteLine("Refusing to start ${agent}: $writers writer run(s) are already live (MAX_PARALLEL_WRITERS=$($script:MaxParallelWriters)).")
    return $false
  }
  return $true
}

# ---- Prompt pieces ---------------------------------------------------------------------------------
function Get-CrewRules([string]$agent) {
  $file = Join-Path $RepoRoot '.github\copilot\crew-rules.md'
  if (-not (Test-Path -LiteralPath $file)) { return '' }
  $out = New-Object System.Collections.Generic.List[string]; $inc = $false; $comment = $false
  foreach ($l in (Get-Content -LiteralPath $file -Encoding UTF8)) {
    if ($l.StartsWith('<!--')) { $comment = $true }
    if ($comment) { if ($l -match '-->') { $comment = $false }; continue }
    if ($l.StartsWith('## ')) {
      $inc = $l.StartsWith('## Every agent')
      if ($l -match '\(([^)]*)\)') { if (($Matches[1] -split '[ ,]+') -contains $agent) { $inc = $true } }
    }
    if ($inc) { $out.Add($l) }
  }
  return ($out -join "`n")
}
function Get-KnownHangs {
  $file = Join-Path $RepoRoot 'AGENTS.md'
  if (-not (Test-Path -LiteralPath $file)) { return '' }
  $out = New-Object System.Collections.Generic.List[string]; $on = $false; $comment = $false
  foreach ($l in (Get-Content -LiteralPath $file -Encoding UTF8)) {
    if ($l.StartsWith('## Known long-running or hanging commands')) { $on = $true; continue }
    if (-not $on) { continue }
    if ($l.StartsWith('## ')) { break }
    if ($l -match '<!--') { $comment = $true }
    if ($comment) { if ($l -match '-->') { $comment = $false }; continue }
    if ($l.Trim()) { $out.Add($l) }
  }
  return ($out -join "`n")
}
# Copilot refuses an agent whose frontmatter is not valid YAML (an unquoted description with ": ").
function Test-Frontmatter([string]$agent) {
  $f = Join-Path $AgentsDir ($agent + '.agent.md')
  $lines = @(Get-Content -LiteralPath $f -Encoding UTF8 -TotalCount 6)
  $desc = ''
  foreach ($l in @($lines | Select-Object -Skip 1)) { if ($l -match '^description:\s*(.*)$') { $desc = $Matches[1]; break } }
  if (-not ($desc -match '^".*"$') -and ($desc.Contains(': ') -or $desc.Contains(' #'))) {
    [Console]::Error.WriteLine("Agent ${agent}: description in $f contains ': ' or ' #' and is not quoted; Copilot will refuse to load it. Wrap it in double quotes."); exit 2
  }
  if ($lines.Count -lt 1 -or $lines[0] -ne '---') { [Console]::Error.WriteLine("Agent ${agent}: $f does not start with '---'."); exit 2 }
}

function Show-Usage {
  foreach ($l in (Get-Content -LiteralPath $ScriptPath -Encoding UTF8 | Select-Object -Skip 6 -First 8)) { [Console]::Error.WriteLine($l.Trim()) }
  exit 2
}

# ---- Git helpers (scope-aware, like crew-run.sh) ----------------------------------------------------
function Get-StatusLines { @(& git -c core.quotepath=off status --porcelain=v1 -uall 2>$null) }
function Get-RunStatusLines([string]$dir) {
  $specs = @(Get-ScopeSpecs $dir)
  if ($specs.Count -eq 0) { return @() }
  return @(& git -c core.quotepath=off status --porcelain=v1 -uall -- @specs 2>$null)
}
function Get-DiffFingerprint([string]$dir) {
  $specs = @(Get-ScopeSpecs $dir)
  if ($specs.Count -eq 0) { return '0' }
  $text = ((@(& git -c core.quotepath=off diff --numstat -- @specs 2>$null) + @(& git -c core.quotepath=off ls-files --others --exclude-standard -- @specs 2>$null)) -join "`n")
  $sha = [Security.Cryptography.SHA1]::Create()
  return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '')
}

function Get-RunDir([string]$id) {
  $dir = Join-Path $Runs $id
  if (-not (Test-Path -LiteralPath $dir)) { [Console]::Error.WriteLine("Unknown run id: $id"); exit 2 }
  return $dir
}
function Test-WorkerAlive([string]$dir) {
  $t = Read-Text (P $dir 'pid')
  if ($t -notmatch '^\d+$') { return $false }
  $p = Get-Process -Id ([int]$t) -ErrorAction SilentlyContinue
  if (-not $p) { return $false }
  return ($p.ProcessName -match '^(pwsh|powershell)$')   # a recycled pid is not our worker
}
function Get-Descendants([int]$parent) {
  $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CreationDate, KernelModeTime, UserModeTime, CommandLine)
  $result = @(); $queue = @($parent)
  while ($queue.Count -gt 0) {
    $p = $queue[0]; $queue = @($queue | Select-Object -Skip 1)
    foreach ($c in @($all | Where-Object { $_.ParentProcessId -eq $p })) { $result += $c; $queue += [int]$c.ProcessId }
  }
  return $result
}
function Stop-Tree([int]$procId) { & taskkill.exe /PID $procId /T /F *> $null }

# ---- Launching copilot -----------------------------------------------------------------------------
# Returns @{ File; Prefix; Note; Kind } or $null when the command cannot be found.
#  .exe            run directly
#  .cmd/.bat shim  npm's shim is cmd.exe and cmd.exe cuts a command line at 8191 characters; our flag list is
#                  longer, so the shim is resolved to node + its script (the same thing it runs)
#  .js             node <script>
#  .ps1            pwsh -File <script>
function Resolve-Launcher([string]$bin) {
  $path = Find-OnPath $bin
  if (-not $path) { return $null }
  $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
  $dir = Split-Path -Parent $path
  $node = $null
  $localNode = Join-Path $dir 'node.exe'
  if (Test-Path -LiteralPath $localNode) { $node = $localNode } else { $node = Find-OnPath 'node' }
  switch ($ext) {
    '.exe' { return @{ File = $path; Prefix = ''; Note = ''; Kind = 'exe' } }
    '.js' { if (-not $node) { return $null }; return @{ File = $node; Prefix = (Quote-Arg $path); Note = ''; Kind = 'node' } }
    '.ps1' { return @{ File = (Get-SelfExe); Prefix = ('-NoProfile -ExecutionPolicy Bypass -File ' + (Quote-Arg $path)); Note = ''; Kind = 'ps1' } }
    { $_ -in '.cmd', '.bat' } {
      $txt = ''; try { $txt = [IO.File]::ReadAllText($path) } catch { }
      if ($node -and $txt -match '"%dp0%\\(?<rel>[^"]+?\.(js|mjs|cjs))"') {
        $js = Join-Path $dir $Matches['rel']
        if (Test-Path -LiteralPath $js) { return @{ File = $node; Prefix = (Quote-Arg $js); Note = "shim $path resolved to node $js"; Kind = 'node' } }
      }
      return @{ File = $env:ComSpec; Prefix = ('/d /c ' + (Quote-Arg $path)); Note = "WARNING: could not resolve the shim $path to node + script; cmd.exe may refuse the long flag list (8191 chars). Install copilot.exe (winget install GitHub.Copilot) or set COPILOT_BIN to the package's .js file."; Kind = 'cmd' }
    }
  }
  return $null
}

# ---- Worker (the detached background process) --------------------------------------------------------
function Build-PromptFile([string]$agent, [string]$promptFile) {
  $header = "Your task brief is in the file $promptFile. Read the whole file and carry it out. You cannot ask the user questions in this run. If something is unclear, make the most reasonable choice and list each such choice under an Open questions heading at the end of your final response."
  $text = $header
  $rules = Get-CrewRules $agent
  if ($rules) { $text += "`n`nStanding rules for every run (a brief may add to them, never relax them):`n`n" + $rules }
  $hangs = Get-KnownHangs
  if ($hangs) { $text += "`n`nKnown long-running or hanging commands in this repository:`n`n" + $hangs }
  $text += "`n`nThis machine runs Windows. Your one shell command is ``$WinGateway`` (same checks and arguments as ``$MacGateway``). " +
    "Wherever these rules, the brief or your agent file name ``$MacGateway``, run ``$WinGateway`` instead, spelled exactly like that " +
    "(relative, forward slashes, never absolute, never piped or chained). Only that spelling is permitted. " +
    "The checks ``build`` (iOS) and ``swift-test`` need a Mac: if the brief asks for them, report them as not run on Windows and continue."
  return $text
}

function Invoke-Worker([string]$dir) {
  $agent = Read-Text (P $dir 'agent')
  $promptFile = Read-Text (P $dir 'prompt_file')
  $model = Read-Text (P $dir 'model')
  $log = P $dir 'output.log'; $errLog = P $dir 'output.err'
  $proxy = $null; $code = 1
  try {
    Load-Permissions $agent (Read-Text (P $dir 'scope_arg'))
    $full = Build-PromptFile $agent $promptFile
    $promptMd = P $dir 'prompt.md'
    Write-Text $promptMd $full
    $promptRel = '.work/runs/' + (Split-Path -Leaf $dir) + '/prompt.md'
    if ($env:CREW_PROMPT_MODE -eq 'inline') { $promptArg = $full }
    else { $promptArg = "Your instructions are in the file $promptRel. Read the whole file first, then carry out the task brief it names. You cannot ask the user questions in this run. If something is unclear, make the most reasonable choice and list each such choice under an Open questions heading at the end of your final response." }
    $a = New-Object System.Collections.Generic.List[string]
    $a.Add('-p'); $a.Add($promptArg); $a.Add('--agent'); $a.Add($agent); $a.Add('--no-ask-user')
    foreach ($f in $script:PermFlags) { $a.Add($f) }
    if ($script:NoCustomInstructions) { $a.Add('--no-custom-instructions') }
    $a.Add('--disable-builtin-mcps'); $a.Add('--usage-output-file'); $a.Add((P $dir 'usage.json'))
    if ($model) {
      $a.Add('--model'); $a.Add($model)
      $env:COPILOT_MODEL = $model; $env:COPILOT_PROVIDER_MODEL_ID = $model; $env:COPILOT_PROVIDER_WIRE_MODEL = $model
    }
    if ($script:ReasoningEffort) { $a.Add('--reasoning-effort'); $a.Add($script:ReasoningEffort) }
    $env:OPENCODE_SESSION = 'crew-' + (Split-Path -Leaf $dir)
    $env:OPENCODE_PROXY_LOG = P $dir 'proxy.log'

    $launch = Resolve-Launcher $script:CopilotBin
    if (-not $launch) { [IO.File]::AppendAllText($log, "crew-run: cannot find '$($script:CopilotBin)' on PATH`n"); $code = 127; return }
    if ($launch.Note) { [IO.File]::AppendAllText($log, "crew-run: $($launch.Note)`n") }

    # The local OpenCode proxy (same logic as with-opencode.ps1): one proxy and session per run.
    if ($script:CopilotWrapper -match '^with-opencode') {
      $node = Find-OnPath 'node'
      if (-not $node) { [IO.File]::AppendAllText($log, "OpenCode proxy failed to start: node not found on PATH`n"); $code = 1; return }
      $tmp = Join-Path ([IO.Path]::GetTempPath()) ('crew-proxy-' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $tmp | Out-Null
      $portFile = Join-Path $tmp 'port'
      $proxyScript = [IO.Path]::GetFullPath((Join-Path $ScriptDir '..\common\opencode-proxy.mjs'))
      $proxy = Start-Process -FilePath $node -ArgumentList (Quote-Arg $proxyScript) -RedirectStandardOutput $portFile -RedirectStandardError $env:OPENCODE_PROXY_LOG -WindowStyle Hidden -PassThru
      $port = ''
      for ($i = 0; $i -lt 100 -and -not $port; $i++) {
        $line = @(Read-Lines $portFile | Select-Object -First 1)
        if ($line.Count -gt 0 -and ([string]$line[0]).Trim() -match '^\d+$') { $port = ([string]$line[0]).Trim(); break }
        Start-Sleep -Milliseconds 100
      }
      if (-not $port) {
        [IO.File]::AppendAllText($log, "OpenCode proxy failed to start:`n" + ((Read-Lines $env:OPENCODE_PROXY_LOG) -join "`n") + "`n")
        $code = 1; return
      }
      $env:COPILOT_PROVIDER_BASE_URL = "http://127.0.0.1:$port/v1"
    } elseif ($script:CopilotWrapper) {
      [IO.File]::AppendAllText($log, "crew-run: unknown wrapper '$($script:CopilotWrapper)' (only with-opencode is supported on Windows)`n"); $code = 2; return
    }

    $argLine = $launch.Prefix + $(if ($launch.Prefix) { ' ' } else { '' }) + (Join-Args $a)
    $p = Start-Process -FilePath $launch.File -ArgumentList $argLine -WorkingDirectory $RepoRoot -RedirectStandardOutput $log -RedirectStandardError $errLog -WindowStyle Hidden -PassThru
    $null = $p.Handle   # keep the handle so ExitCode is readable after exit
    $ok = $true
    if ($script:MaxRunMinutes -gt 0) { $ok = $p.WaitForExit([int]($script:MaxRunMinutes * 60 * 1000)) } else { $p.WaitForExit() }
    if (-not $ok) {
      Stop-Tree $p.Id
      $null = $p.WaitForExit(5000)
      $code = 124
    } else {
      $p.WaitForExit()
      $code = $p.ExitCode
    }
    if (Test-Path -LiteralPath $errLog) {
      $e = Read-Lines $errLog
      if ($e.Count -gt 0) { [IO.File]::AppendAllText($log, "`n--- stderr ---`n" + ($e -join "`n") + "`n") }
    }
  } catch {
    try { [IO.File]::AppendAllText($log, "crew-run: $($_.Exception.Message)`n") } catch { }
    $code = 1
  } finally {
    if ($proxy -and -not $proxy.HasExited) { Stop-Tree $proxy.Id }
    if (-not (Test-Path -LiteralPath (P $dir 'exit'))) {
      if ($code -eq 124 -and $script:MaxRunMinutes -gt 0) {
        Write-Text (P $dir 'stop_reason') 'max_runtime'
        Write-Text (P $dir 'exit') 'stopped'
      } else {
        Write-Text (P $dir 'exit') "$code"
      }
    }
  }
}

function Start-Run([string]$agent, [string]$promptFile, [string]$scopeArg, [string]$model, [bool]$overlap, [bool]$dryRun) {
  if ($agent -notlike 'crew-*') { [Console]::Error.WriteLine("The crew runner only runs crew-* agents (got '$agent'). The shared pipeline's agents run through run-agent.ps1."); exit 2 }
  $abs = $promptFile
  if (-not [IO.Path]::IsPathRooted($abs)) { $abs = Join-Path $OrigPwd $promptFile }
  if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { [Console]::Error.WriteLine("Prompt file not found: $promptFile"); exit 2 }
  $abs = [IO.Path]::GetFullPath($abs)
  $rel = Get-RelPath $abs
  if (-not (Test-Path -LiteralPath (Join-Path $AgentsDir ($agent + '.agent.md')))) { [Console]::Error.WriteLine("No agent .github/agents/$agent.agent.md"); exit 2 }
  Test-Frontmatter $agent
  Load-Permissions $agent $scopeArg   # validate now: a bad profile or scope fails before anything starts
  if (-not $model) { $model = Get-ModelFor $agent }
  if ($model -notin @('deepseek-v4.1-flash', 'glm-5.3-flash')) {
    [Console]::Error.WriteLine("Model '$model' is not one of the crew's two models (deepseek-v4.1-flash, glm-5.3-flash)."); exit 2
  }
  if (-not $overlap) { if (-not (Test-ParallelClear $agent)) { exit 2 } }
  $launch = Resolve-Launcher $script:CopilotBin
  if (-not $dryRun -and -not $launch) {
    [Console]::Error.WriteLine("Cannot find the copilot CLI ('$($script:CopilotBin)') on PATH. Install it (npm install -g @github/copilot, or winget install GitHub.Copilot) and run: crew-run.ps1 doctor"); exit 2
  }
  if ($dryRun) {
    $o = [Console]::Out
    $o.WriteLine('DRY RUN (nothing started, no run directory created)')
    $o.WriteLine("AGENT: $agent (model: $model)")
    $o.WriteLine("PROMPT_FILE: $rel")
    $o.WriteLine("WRITE_SCOPE: $($script:Effective -join ' ')")
    $o.WriteLine("PERMISSION_FLAGS: $($script:PermFlags.Count) (gateway allowed as: $WinGateway)")
    if ($launch) { $o.WriteLine("COPILOT: $($launch.File) $($launch.Prefix)"); if ($launch.Note) { $o.WriteLine("NOTE: $($launch.Note)") } } else { $o.WriteLine("COPILOT: NOT FOUND on PATH ('$($script:CopilotBin)')") }
    $o.WriteLine("WRAPPER: $(if ($script:CopilotWrapper) { $script:CopilotWrapper } else { 'none' })")
    return $null
  }

  $base = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ($agent -replace '[^A-Za-z0-9_-]', '')
  $id = $base; $n = 1
  while (Test-Path -LiteralPath (Join-Path $Runs $id)) { $n++; $id = "$base-$n" }
  $dir = Join-Path $Runs $id
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Write-Text (P $dir 'agent') $agent
  Write-Text (P $dir 'prompt_file') $rel
  Write-Text (P $dir 'model') $model
  Write-Text (P $dir 'scope_arg') $scopeArg
  Write-Text (P $dir 'scope') ((($script:Effective -join "`n")) + $(if ($script:Effective.Count -gt 0) { "`n" } else { '' }))
  Write-Text (P $dir 'wrapper') $(if ($script:CopilotWrapper) { $script:CopilotWrapper } else { 'none' })
  Write-Text (P $dir 'team') "crew`n"
  Write-Text (P $dir 'before') ((@(Get-RunStatusLines $dir) -join "`n"))
  Write-Text (P $dir 'started_epoch') "$(Get-Now)"
  Write-Text (P $dir 'diff_fp') (Get-DiffFingerprint $dir)
  Write-Text (P $dir 'diff_changed_epoch') "$(Get-Now)"
  Write-Text (P $dir 'started') ''
  Write-Text (Join-Path $Runs 'latest.txt') "$id`n"

  $argLine = '-NoProfile -ExecutionPolicy Bypass -File ' + (Quote-Arg $ScriptPath) + ' __worker ' + (Quote-Arg $dir)
  $w = Start-Process -FilePath (Get-SelfExe) -ArgumentList $argLine -WindowStyle Hidden -PassThru
  Write-Text (P $dir 'pid') "$($w.Id)"
  return $id
}

# ---- Health ----------------------------------------------------------------------------------------
# Loop signals from the agent log (same rules as crew-run.sh log_stats): Action = the most repeated tool call,
# Command = the most repeated one that is not an edit/create, Read = the most re-read file, Denied, Text.
function Get-LogStats([string]$log) {
  $r = @{ Action = 0; ActionKey = '-'; Denied = 0; Text = 0; TextKey = '-'; Read = 0; ReadKey = '-'; Command = 0; CommandKey = '-' }
  $lines = @(Read-Lines $log)
  if ($lines.Count -eq 0) { return $r }
  $dot = [string][char]0x25CF + ' '; $cross = [string][char]0x2717 + ' '
  $bar = '  ' + [char]0x2502 + ' '; $corner = '  ' + [char]0x2514 + ' '
  $act = @{}; $text = @{}; $reads = @{}; $key = ''; $kind = ''; $stage = 0
  foreach ($l in $lines) {
    if ($l.StartsWith($dot) -or $l.StartsWith($cross) -or $l.StartsWith('/ ')) {
      if ($key) { $act[$key] = 1 + [int]$act[$key] }
      $t = (($l.Substring(2) -replace '\s+[0-9.]+m?s\s*$', '') -replace '\s+', ' ').Trim().ToLowerInvariant() -replace '[0-9]+', '#'
      $kind = if ($t -match '\(shell\)$') { 'shell' } else { ($t -split ' ')[0] }
      $key = $t; $stage = if ($kind -in @('edit', 'create')) { 0 } else { 1 }
      continue
    }
    if ($stage -eq 1 -and $l.StartsWith($bar)) {
      $c = ($l.Substring(4) -replace '\s+', ' ').Trim(); $key = $kind + ': ' + $c
      if ($kind -eq 'read') { $reads[$c] = 1 + [int]$reads[$c] }
      $stage = 2; continue
    }
    if ($stage -eq 2 -and $l.StartsWith($corner) -and $l.Substring(4) -match '^(L[0-9]+:[0-9]+)') { $key = $key + ' ' + $Matches[1]; $stage = 0; continue }
    if ($l -match 'Permission denied and could not request permission|Permission to run this tool was denied') { $r.Denied++ }
    if ($l -match '^\s*$' -or $l.StartsWith($bar) -or $l.StartsWith($corner)) { continue }
    $stage = 0
    $x = ($l -replace '\s+', ' ').Trim().ToLowerInvariant()
    if ($x.Length -ge 8) { $text[$x] = 1 + [int]$text[$x] }
  }
  if ($key) { $act[$key] = 1 + [int]$act[$key] }
  if ($act.Count -gt 0) {
    $top = $act.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
    $r.Action = [int]$top.Value; $r.ActionKey = ([string]$top.Key); if ($r.ActionKey.Length -gt 100) { $r.ActionKey = $r.ActionKey.Substring(0, 100) }
    $cmds = @($act.GetEnumerator() | Where-Object { $_.Key -notmatch '^(edit|create)' } | Sort-Object Value -Descending)
    if ($cmds.Count -gt 0) { $r.Command = [int]$cmds[0].Value; $r.CommandKey = ([string]$cmds[0].Key); if ($r.CommandKey.Length -gt 100) { $r.CommandKey = $r.CommandKey.Substring(0, 100) } }
  }
  if ($text.Count -gt 0) {
    $top = $text.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
    $r.Text = [int]$top.Value; $r.TextKey = ([string]$top.Key); if ($r.TextKey.Length -gt 80) { $r.TextKey = $r.TextKey.Substring(0, 80) }
  }
  if ($reads.Count -gt 0) {
    $top = $reads.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
    $r.Read = [int]$top.Value; $r.ReadKey = ([string]$top.Key); if ($r.ReadKey.Length -gt 100) { $r.ReadKey = $r.ReadKey.Substring(0, 100) }
  }
  return $r
}
function Get-FillerLimit { [Math]::Max(200, $script:RepeatStop * 5) }

# Minutes since the log last grew, measured through an open handle (see Get-FileLength).
function Update-LogActivity([string]$dir) {
  $len = Get-FileLength (P $dir 'output.log')
  if ($len -lt 0) { return }
  $old = Read-Text (P $dir 'log_len')
  if ("$len" -ne $old) { Write-Text (P $dir 'log_len') "$len"; Write-Text (P $dir 'log_changed_epoch') "$(Get-Now)" }
}
function Get-LogIdleMinutes([string]$dir) {
  Update-LogActivity $dir
  $started = Get-Epoch (P $dir 'started_epoch') (Get-Now)
  $e = Get-Epoch (P $dir 'log_changed_epoch') $started
  return (((Get-Now) - $e) / 60.0)
}

function Get-HungChildren([string]$dir) {
  if (-not (Test-WorkerAlive $dir)) { return @() }
  $out = @()
  foreach ($c in @(Get-Descendants ([int](Read-Text (P $dir 'pid'))))) {
    if ($c.Name -match '^(copilot|node|pwsh|powershell|cmd|conhost|taskkill)(\.exe)?$') { continue }
    if (-not $c.CreationDate) { continue }
    $ageMin = ((Get-Date) - $c.CreationDate).TotalMinutes
    $cpuSec = ([double]$c.KernelModeTime + [double]$c.UserModeTime) / 1e7
    if ($ageMin -ge $script:HungChildMinutes -and $cpuSec -lt ($ageMin * 60 * 0.01)) {
      $cmdText = [string]$c.CommandLine; if ($cmdText.Length -gt 120) { $cmdText = $cmdText.Substring(0, 120) }
      $out += ('{0} {1}m {2}' -f $c.ProcessId, [int]$ageMin, $cmdText)
    }
  }
  return $out
}

function Test-NoWriteYet([string]$dir) { (Read-Text (P $dir 'diff_changed_epoch')) -eq (Read-Text (P $dir 'started_epoch')) }

function Update-Health([string]$dir) {
  $fp = Get-DiffFingerprint $dir
  if ($fp -ne (Read-Text (P $dir 'diff_fp'))) {
    Write-Text (P $dir 'diff_fp') $fp
    Write-Text (P $dir 'diff_changed_epoch') "$(Get-Now)"
  }
  if (Test-Path -LiteralPath (P $dir 'exit')) { return }
  if (-not (Test-WorkerAlive $dir)) { return }
  $id = Split-Path -Leaf $dir
  $agent = Read-Text (P $dir 'agent')
  $st = Get-LogStats (P $dir 'output.log')
  # Measured on 363 runs (2026-10-13, see crew.env): healthy runs peak at 10 denied calls; checkers at 20 repeats of
  # one command and 13 reads of one file; the loops reached 43 denied, 40-50 repeats, 73 reads.
  if ($script:DeniedStop -gt 0 -and $st.Denied -ge $script:DeniedStop) { Stop-Run $id 'denied' | Out-Null; return }
  if (Test-Checker $agent) {
    if ($script:CheckerRepeatStop -gt 0 -and $st.Command -ge $script:CheckerRepeatStop) { Stop-Run $id 'loop' | Out-Null; return }
    # Not the architect: it re-reads the plan it is writing after each edit (41 reads on a healthy run).
    if ($agent -ne 'crew-architect' -and $script:CheckerReadStop -gt 0 -and $st.Read -ge $script:CheckerReadStop) { Stop-Run $id 'loop' | Out-Null; return }
  }
  if ($script:RepeatStop -gt 0) {
    if ($st.Action -ge $script:RepeatStop) { Stop-Run $id 'loop' | Out-Null; return }
    if ($st.Denied -ge $script:RepeatStop) { Stop-Run $id 'denied' | Out-Null; return }
    if ($st.Text -ge (Get-FillerLimit)) { Stop-Run $id 'filler' | Out-Null; return }
  }
  $started = Get-Epoch (P $dir 'started_epoch') (Get-Now)
  if ($script:NoWriteStop -gt 0 -and (Test-Implementer $agent) -and (Test-NoWriteYet $dir)) {
    if ((((Get-Now) - $started) / 60.0) -ge $script:NoWriteStop) { Stop-Run $id 'no_write' | Out-Null; return }
  }
  if ($script:StallMinutes -gt 0 -and (Test-Path -LiteralPath (P $dir 'output.log'))) {
    $logIdle = Get-LogIdleMinutes $dir
    $diffIdle = ((Get-Now) - (Get-Epoch (P $dir 'diff_changed_epoch') $started)) / 60.0
    if ($logIdle -ge $script:StallMinutes -and $diffIdle -ge $script:StallMinutes) { Stop-Run $id 'stalled' | Out-Null }
  }
}

function Write-Health([string]$dir) {
  $log = P $dir 'output.log'
  $agent = Read-Text (P $dir 'agent')
  $lines = 0; $logIdle = '-'
  if (Test-Path -LiteralPath $log) { $lines = @(Read-Lines $log).Count; $logIdle = Fmt1 (Get-LogIdleMinutes $dir) }
  $st = Get-LogStats $log
  $started = Get-Epoch (P $dir 'started_epoch') (Get-Now)
  $changed = Get-Epoch (P $dir 'diff_changed_epoch') (Get-Now)
  'HEALTH:'
  "  LOG_LINES: $lines $MidDot LOG_IDLE_MIN: $logIdle"
  "  SCOPE: $((Read-Lines (P $dir 'scope')) -join ' ') $MidDot SCOPE_IDLE_MIN: $(Get-MinutesSince $changed)"
  "  TOP_REPEAT: $($st.Action)$Times `"$($st.ActionKey)`" (auto-stop at $($script:RepeatStop); 0 = off)"
  "  DENIED: $($st.Denied) (auto-stop at $($script:DeniedStop)) $MidDot TOP_TEXT_REPEAT: $($st.Text)$Times (auto-stop at $(Get-FillerLimit))"
  "  TOP_READ: $($st.Read)$Times `"$($st.ReadKey)`" (one file, any line range)"
  if (Test-Checker $agent) {
    $readStop = if ($agent -eq 'crew-architect') { 'off' } else { "$($script:CheckerReadStop)" }
    "  CHECKER_LIMITS: top command $($st.Command)$Times (stop at $($script:CheckerRepeatStop)) $MidDot top read $($st.Read)$Times (stop at $readStop)"
  }
  $done = Test-Path -LiteralPath (P $dir 'exit')
  if ((Test-Implementer $agent) -and (Test-NoWriteYet $dir) -and -not $done) {
    "  FIRST_WRITE: none yet after $(Get-MinutesSince $started) min (auto-stop at $($script:NoWriteStop); 0 = off)"
  }
  $elapsed = ((Get-Now) - $started) / 60.0
  if ($script:LongRunMinutes -gt 0 -and -not $done -and (Test-Writer $agent) -and $elapsed -ge $script:LongRunMinutes) {
    "  LONG_RUN: $(Fmt1 $elapsed) min, past $($script:LongRunMinutes); split the remaining work into its own run next time"
  }
  $proxy = P $dir 'proxy.log'
  if (Test-Path -LiteralPath $proxy) {
    $pl = @(Read-Lines $proxy)
    $req = @($pl | Where-Object { $_ -match ' -> ' }).Count
    $err = @($pl | Where-Object { $_ -match ' -> [45][0-9][0-9]' }).Count
    "  MODEL_REQUESTS: $req (errors: $err)"
  }
  $tok = @(Read-Lines $log | Where-Object { $_ -match '^Tokens ' } | Select-Object -Last 1)
  if ($tok.Count -gt 0) { "  TOKENS: $(([string]$tok[0]) -replace '^Tokens\s*', '')" }
  foreach ($h in @(Get-HungChildren $dir)) { "  HUNG_CHILD: $h" }
  $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average
  if ($cpu -ge 95) { "  HIGH_LOAD: CPU at $([int]$cpu)%; timings are unreliable (look for stray processes with Get-Process)" }
}

# ---- Summary ---------------------------------------------------------------------------------------
function Get-RunStatus([string]$dir) {
  $exitFile = P $dir 'exit'
  if (Test-Path -LiteralPath $exitFile) {
    $code = Read-Text $exitFile
    if ($code -eq '0') { return @('DONE', $code) }
    if ($code -eq 'stopped') { return @('STOPPED', $code) }
    return @('FAILED', $code)
  }
  if (Test-WorkerAlive $dir) { return @('RUNNING', '') }
  return @('FAILED', 'none (worker exited without recording an exit code)')
}

function Write-Summary([string]$id) {
  $dir = Get-RunDir $id
  $st = Get-RunStatus $dir
  $status = $st[0]; $code = $st[1]
  $model = Read-Text (P $dir 'model')
  $started = Get-Epoch (P $dir 'started_epoch') (Get-Now)
  "RUN_ID: $id"
  if ($model) { "AGENT: $(Read-Text (P $dir 'agent')) (model: $model)" } else { "AGENT: $(Read-Text (P $dir 'agent'))" }
  "STATUS: $status"
  if ($status -eq 'STOPPED') { $r = Read-Text (P $dir 'stop_reason'); if (-not $r) { $r = 'user' }; "STOP_REASON: $r" }
  if ($code -and $status -ne 'STOPPED') { "EXIT_CODE: $code" }
  "ELAPSED_MIN: $(Get-MinutesSince $started)"
  "LOG: .work/runs/$id/output.log"
  Write-Health $dir
  if ($status -eq 'RUNNING') { "NEXT: still running. Call again with: wait $id"; return }

  'FILES_CHANGED_DURING_RUN (inside this run''s scope):'
  $before = @(Read-Lines (P $dir 'before'))
  $startedTime = (Get-Item -LiteralPath (P $dir 'started')).LastWriteTime
  $any = $false
  foreach ($line in @(Get-RunStatusLines $dir)) {
    if (-not $line) { continue }
    $path = $line.Substring(3)
    if ($path -like '* -> *') { $path = $path.Substring($path.LastIndexOf(' -> ') + 4) }
    $path = $path.Trim('"')
    $newer = (Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).LastWriteTime -gt $startedTime)
    if (($before -notcontains $line) -or $newer) { "  $line"; $any = $true }
  }
  # Notes and reports under .work/crew are git-ignored, so list them by time instead.
  $crewDir = Join-Path $RepoRoot '.work\crew'
  if (Test-Path -LiteralPath $crewDir) {
    foreach ($f in @(Get-ChildItem -LiteralPath $crewDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $startedTime })) {
      "  (ignored) $(Get-RelPath $f.FullName)"; $any = $true
    }
  }
  if (-not $any) { '  (none)' }
  "--- LOG TAIL (last $($script:TailLines) lines) ---"
  if (Test-Path -LiteralPath (P $dir 'output.log')) { @(Read-Lines (P $dir 'output.log') | Select-Object -Last $script:TailLines) } else { '(no log written)' }
}

function Wait-Run([string]$id) {
  $dir = Get-RunDir $id
  $deadline = (Get-Now) + [long]($script:WaitMinutes * 60)
  while (-not (Test-Path -LiteralPath (P $dir 'exit')) -and (Get-Now) -lt $deadline) {
    if (-not (Test-WorkerAlive $dir)) { Start-Sleep -Seconds 2; break }
    Update-Health $dir
    if (Test-Path -LiteralPath (P $dir 'exit')) { break }
    Start-Sleep -Milliseconds ([int]($script:PollSeconds * 1000))
  }
  Write-Summary $id
}

function Stop-Run([string]$id, [string]$reason = 'user') {
  $dir = Get-RunDir $id
  if (Test-WorkerAlive $dir) {
    $wpid = [int](Read-Text (P $dir 'pid'))
    Write-Text (P $dir 'stop_reason') $reason
    Write-Text (P $dir 'exit') 'stopped'
    Stop-Tree $wpid
    Start-Sleep -Seconds 1
  } elseif (-not (Test-Path -LiteralPath (P $dir 'exit'))) {
    Write-Text (P $dir 'stop_reason') $reason
    Write-Text (P $dir 'exit') 'stopped'
  }
  Write-Summary $id
}

function Show-Runs {
  '{0,-36} {1,-20} {2,-18} {3,-8} {4}' -f 'RUN_ID', 'AGENT', 'MODEL', 'STATUS', 'ELAPSED_MIN'
  foreach ($d in @(Get-ChildItem -LiteralPath $Runs -Directory | Sort-Object Name)) {
    if (-not (Test-Path -LiteralPath (P $d.FullName 'team'))) { continue }
    $st = Get-RunStatus $d.FullName
    $started = Get-Epoch (P $d.FullName 'started_epoch') (Get-Now)
    '{0,-36} {1,-20} {2,-18} {3,-8} {4}' -f $d.Name, (Read-Text (P $d.FullName 'agent')), (Read-Text (P $d.FullName 'model')), $st[0], (Get-MinutesSince $started)
  }
}

# ---- check / doctor / selftest ---------------------------------------------------------------------
function Invoke-Check([string[]]$opts) {
  $agent = ''; $scope = ''
  if ($opts.Count -gt 0) { $agent = $opts[0] }
  for ($i = 1; $i -lt $opts.Count; $i++) { if ($opts[$i] -eq '--scope' -and $i + 1 -lt $opts.Count) { $scope = $opts[$i + 1]; $i++ } }
  if (-not $agent -or -not (Test-Path -LiteralPath (Join-Path $AgentsDir ($agent + '.agent.md')))) { [Console]::Error.WriteLine("No agent $agent"); exit 2 }
  Test-Frontmatter $agent
  Load-Permissions $agent $scope
  "OK $agent model=$(Get-ModelFor $agent)"
  "ceiling: $(if ($script:Ceiling.Count) { $script:Ceiling -join ' ' } else { 'none' })"
  "effective write scope: $(if ($script:Effective.Count) { $script:Effective -join ' ' } else { 'none' })"
  "shell allowed: $WinGateway (and $WinGatewayPs1) - the macOS gateway rule in common.flags is swapped at run time"
  if (Test-ParallelClear $agent) { 'parallel check: clear' }
}

$script:DoctorBad = 0
function Report([string]$level, [string]$what, [string]$detail) {
  if ($level -eq 'FAIL') { $script:DoctorBad++ }
  '{0,-5} {1}{2}' -f $level, $what, $(if ($detail) { ' - ' + $detail } else { '' })
}
function Invoke-Doctor {
  $script:DoctorBad = 0
  "OmniTrain crew harness doctor (Windows) $MidDot PowerShell $($PSVersionTable.PSVersion) $MidDot repo $RepoRoot"
  $gv = ''; try { $gv = (& git --version) } catch { }
  if ($gv) { Report 'OK' 'git' $gv } else { Report 'FAIL' 'git' 'not on PATH (install Git for Windows)' }
  $l = Resolve-Launcher $script:CopilotBin
  if ($l) { Report 'OK' "copilot ($($script:CopilotBin))" ("runs as: $($l.Kind) " + $l.File + $(if ($l.Note) { '; ' + $l.Note } else { '' })) }
  else { Report 'FAIL' "copilot ($($script:CopilotBin))" 'not found on PATH (npm install -g @github/copilot, or winget install GitHub.Copilot)' }
  if ($l -and $l.Kind -eq 'cmd') { Report 'WARN' 'copilot launcher' 'a .cmd shim that could not be resolved: the flag list may exceed cmd.exe''s 8191 characters' }
  $nodePath = Find-OnPath 'node'
  if ($script:CopilotWrapper -match '^with-opencode') {
    if ($nodePath) { Report 'OK' 'node (OpenCode proxy)' ((& node --version) + ' ' + $nodePath) } else { Report 'FAIL' 'node (OpenCode proxy)' 'not on PATH (install Node.js 18+)' }
  }
  if ($env:COPILOT_PROVIDER_API_KEY) { Report 'OK' 'COPILOT_PROVIDER_API_KEY' 'is set (value not shown)' } else { Report 'WARN' 'COPILOT_PROVIDER_API_KEY' 'not set in this shell: a real run will fail to authenticate (never put the key in a file in the repo)' }
  foreach ($t in @('flutter', 'dart')) {
    if (Find-OnPath $t) { Report 'OK' $t (Find-OnPath $t) } else { Report 'WARN' $t 'not on PATH: gateway checks lint/test/pub-get/format need it' }
  }
  $py = Find-OnPath 'python'; if (-not $py) { $py = Find-OnPath 'py' }
  if ($py) { Report 'OK' 'python (plan-lint)' $py } else { Report 'WARN' 'python (plan-lint)' 'not on PATH: plan-lint.py / plan-lint.ps1 need Python 3' }
  foreach ($rel in @('.claude/crew.env', '.github/copilot/crew-rules.md', '.github/copilot/permissions/common.flags', '.github/copilot/gateway.conf',
      '.github/copilot/scripts/windows/gateway.ps1', '.github/copilot/scripts/windows/gateway.cmd', '.claude/scripts/common/opencode-proxy.mjs', '.github/agents/crew-scout.agent.md')) {
    if (Test-Path -LiteralPath (Join-Path $RepoRoot ($rel -replace '/', '\'))) { Report 'OK' $rel '' } else { Report 'FAIL' $rel 'missing' }
  }
  $pol = ''; try { $pol = [string](Get-ExecutionPolicy) } catch { }
  Report 'INFO' 'execution policy' ("$pol (the runner starts its own pwsh with -ExecutionPolicy Bypass; gateway.cmd does the same, so this does not block)")
  $lp = $null; try { $lp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction Stop).LongPathsEnabled } catch { }
  if ($lp -eq 1) { Report 'OK' 'Windows long paths' 'enabled' } else { Report 'WARN' 'Windows long paths' 'not enabled; Flutter build trees can pass 260 characters (enable LongPathsEnabled and git config core.longpaths true)' }
  foreach ($agent in @('crew-scout', 'crew-architect', 'crew-builder-data', 'crew-builder-app', 'crew-builder-watch', 'crew-prover', 'crew-reviewer', 'crew-docs-keeper')) {
    try {
      $m = Get-ModelFor $agent
      if ($m -notin @('deepseek-v4.1-flash', 'glm-5.3-flash')) { Report 'FAIL' "model for $agent" "'$m' is not one of the crew's two models" }
    } catch { Report 'FAIL' "model for $agent" $_.Exception.Message }
  }
  if ($script:DoctorBad -eq 0) { 'RESULT: ready (WARN lines are worth a look)' } else { "RESULT: $($script:DoctorBad) problem(s) above" }
}

function Invoke-SelfTest {
  $st = Join-Path $RepoRoot '.work\selftest'
  New-Item -ItemType Directory -Force -Path $st | Out-Null
  $fake = Join-Path $st 'fake-copilot.ps1'
  $fakeBody = @'
# Stands in for the copilot CLI during `crew-run.ps1 selftest`. Prints a log shaped like Copilot's, then exits 0.
$o = [Console]::Out
$o.WriteLine(([string][char]0x25CF) + ' Read brief (read)')
$o.WriteLine('  ' + [char]0x2502 + ' .work/selftest/brief.md')
$o.WriteLine('  ' + [char]0x2514 + ' L1:3 (3 lines read)')
$o.WriteLine('fake-copilot: received ' + $args.Count + ' arguments; first: ' + $args[0] + ' ... agent=' + $args[3])
$o.WriteLine('fake-copilot: gateway allow rules seen: ' + @($args | Where-Object { "$_" -like '*windows/gateway*' }).Count)
if ($env:CREW_SELFTEST_MODE -eq 'sleep') { Start-Sleep -Seconds 120 }
$o.WriteLine('Tokens    up 1.0k (0 cached) * down 0.1k')
exit 0
'@
  [IO.File]::WriteAllText($fake, $fakeBody)
  $brief = Join-Path $st 'brief.md'
  [IO.File]::WriteAllText($brief, "Selftest brief. Do nothing.`n")
  $briefRel = Get-RelPath $brief
  $results = New-Object System.Collections.Generic.List[string]
  $failed = 0
  function Assert([bool]$cond, [string]$label) { if ($cond) { $results.Add("PASS  $label") } else { $results.Add("FAIL  $label"); $script:stFailed++ } }
  $script:stFailed = 0
  $prevLatest = Read-Text (Join-Path $Runs 'latest.txt')
  $save = @{}
  foreach ($k in @('CREW_SELFTEST_BIN', 'MAX_RUN_MINUTES', 'POLL_SECONDS', 'WAIT_MINUTES', 'CREW_SELFTEST_MODE')) { $save[$k] = [Environment]::GetEnvironmentVariable($k) }
  $ids = @()
  try {
    $env:CREW_SELFTEST_BIN = $fake; $env:POLL_SECONDS = '1'; $env:WAIT_MINUTES = '1'; $env:MAX_RUN_MINUTES = '90'; $env:CREW_SELFTEST_MODE = ''
    Load-Config
    "SELFTEST: fake copilot at $(Get-RelPath $fake); no key, no network, nothing is committed or edited."
    Invoke-Doctor
    "---"
    # A: a normal run
    $idA = Start-Run 'crew-scout' $briefRel '' '' $false $false; $ids += $idA
    $sumA = (Wait-Run $idA | Out-String)
    $dirA = Join-Path $Runs $idA
    Assert ($sumA -match 'STATUS: DONE' -and $sumA -match 'EXIT_CODE: 0') 'A: normal run ends STATUS: DONE, EXIT_CODE: 0'
    Assert ((Read-Text (P $dirA 'agent')) -eq 'crew-scout' -and (Test-Path (P $dirA 'started_epoch')) -and (Test-Path (P $dirA 'scope')) -and (Test-Path (P $dirA 'prompt_file'))) 'A: run dir has agent, started_epoch, scope, prompt_file'
    Assert ((Read-Text (Join-Path $Runs 'latest.txt')) -eq $idA) 'A: latest.txt points at the run'
    $logA = (Read-Lines (P $dirA 'output.log')) -join "`n"
    Assert ($logA -match 'fake-copilot: received') 'A: output.log holds the fake agent''s output'
    Assert ($logA -match 'gateway allow rules seen: 2') 'A: the Windows gateway allow rules reached the command line'
    $pm = Read-Text (P $dirA 'prompt.md')
    Assert ($pm.Contains($WinGateway) -and $pm.Contains('## Every agent')) 'A: prompt.md carries the standing rules and the Windows gateway note'
    Assert ((Read-Text (P $dirA 'scope')) -eq '.work/crew/**') 'A: scout scope is .work/crew/**'
    # B: the run timeout maps to STOPPED / max_runtime (the Mac's exit 124)
    $env:CREW_SELFTEST_MODE = 'sleep'; $env:MAX_RUN_MINUTES = '0.05'; Load-Config
    $idB = Start-Run 'crew-scout' $briefRel '' '' $true $false; $ids += $idB
    $sumB = (Wait-Run $idB | Out-String)
    Assert ($sumB -match 'STATUS: STOPPED' -and $sumB -match 'STOP_REASON: max_runtime') 'B: a run past MAX_RUN_MINUTES ends STOPPED / max_runtime'
    # C: stop
    $env:MAX_RUN_MINUTES = '90'; Load-Config
    $idC = Start-Run 'crew-scout' $briefRel '' '' $true $false; $ids += $idC
    Start-Sleep -Seconds 4
    $alive = Test-WorkerAlive (Join-Path $Runs $idC)
    $sumC = (Stop-Run $idC 'user' | Out-String)
    Assert ($alive -and $sumC -match 'STATUS: STOPPED' -and $sumC -match 'STOP_REASON: user') 'C: stop kills a live run and reports STOPPED / user'
    Assert (-not (Test-WorkerAlive (Join-Path $Runs $idC))) 'C: the worker process is gone after stop'
    # D: refusals
    $refusedScope = $false
    try { $null = & $ScriptPath check crew-scout --scope 'lib/**' 2>&1; $refusedScope = ($LASTEXITCODE -eq 2) } catch { $refusedScope = $true }
    Assert $refusedScope 'D: a scope outside the agent''s ceiling is refused (exit 2)'
  } finally {
    foreach ($k in $save.Keys) { [Environment]::SetEnvironmentVariable($k, $save[$k]) }
    foreach ($i in $ids) {
      $dd = Join-Path $Runs $i
      if (Test-WorkerAlive $dd) { try { Stop-Tree ([int](Read-Text (P $dd 'pid'))) } catch { } }
    }
    Start-Sleep -Seconds 1
    foreach ($i in $ids) { Remove-Item -LiteralPath (Join-Path $Runs $i) -Recurse -Force -ErrorAction SilentlyContinue }
    if ($prevLatest) { Write-Text (Join-Path $Runs 'latest.txt') "$prevLatest`n" } else { Remove-Item -LiteralPath (Join-Path $Runs 'latest.txt') -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $st -Recurse -Force -ErrorAction SilentlyContinue
  }
  $results
  if ($script:stFailed -eq 0) { 'SELFTEST RESULT: PASS (runner start/wait/stop, run-dir layout, timeout mapping, scope refusal all behaved)' }
  else { "SELFTEST RESULT: FAIL ($($script:stFailed) check(s) above)" }
}

# ---- Entry -----------------------------------------------------------------------------------------
$Self = ".claude/scripts/windows/crew-run.ps1"
switch ($Cmd) {
  'start' {
    if ($Rest.Count -lt 2) { Show-Usage }
    $scopeArg = ''; $model = ''; $overlap = $false; $dry = $false
    for ($i = 2; $i -lt $Rest.Count; $i++) {
      switch ($Rest[$i]) {
        '--scope' { $i++; if ($i -ge $Rest.Count) { Show-Usage }; $scopeArg = $Rest[$i] }
        '--model' { $i++; if ($i -ge $Rest.Count) { Show-Usage }; $model = $Rest[$i] }
        '--allow-overlap' { $overlap = $true }
        '--dry-run' { $dry = $true }
        default { [Console]::Error.WriteLine("Unknown option: $($Rest[$i])"); Show-Usage }
      }
    }
    $id = Start-Run $Rest[0] $Rest[1] $scopeArg $model $overlap $dry
    if ($id) {
      "RUN_ID: $id"; 'STATUS: STARTED'
      "NEXT: Started. Wait for it in the background (run_in_background: true): pwsh -NoProfile -File $Self wait $id"
    }
  }
  'wait' { if ($Rest.Count -ne 1) { Show-Usage }; Wait-Run $Rest[0] }
  'status' { if ($Rest.Count -ne 1) { Show-Usage }; $d = Get-RunDir $Rest[0]; Update-Health $d; Write-Summary $Rest[0] }
  'stop' { if ($Rest.Count -ne 1) { Show-Usage }; Stop-Run $Rest[0] 'user' }
  'list' { Show-Runs }
  'check' { Invoke-Check $Rest }
  'doctor' { Invoke-Doctor; exit $(if ($script:DoctorBad -eq 0) { 0 } else { 1 }) }
  'selftest' { Invoke-SelfTest; exit $(if ($script:stFailed -eq 0) { 0 } else { 1 }) }
  '__worker' { Invoke-Worker $Rest[0] }
  default { Show-Usage }
}
