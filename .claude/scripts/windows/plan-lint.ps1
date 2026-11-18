<#
Windows launcher for the crew plan checker (the Python script is cross-platform; this only finds Python,
makes its output UTF-8 and runs it from the repository root).

  pwsh -NoProfile -File .claude/scripts/windows/plan-lint.ps1 before <plan.md>   after the plan is written, before any build run
  pwsh -NoProfile -File .claude/scripts/windows/plan-lint.ps1 after  <plan.md>   after the docs phase, before the review

Same arguments and exit codes as `python3 -I .claude/scripts/macos/plan-lint.py ...`: 0 clean, 1 defects, 2 usage.
Needs Python 3 (python, py -3 or python3 on PATH). The Microsoft Store stub (a python.exe that only opens the Store) is skipped.
ASCII only on purpose (Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI).
#>
$ErrorActionPreference = 'Stop'
if ($args.Count -ne 2 -or @('before', 'after') -notcontains [string]$args[0]) {
  [Console]::Error.WriteLine('usage: plan-lint.ps1 before|after <plan.md>'); exit 2
}
$plan = [string]$args[1]
if (-not [IO.Path]::IsPathRooted($plan)) { $plan = Join-Path (Get-Location).Path $plan }
$root = ((& git rev-parse --show-toplevel) | Select-Object -First 1).Trim()
Set-Location $root
$script = Join-Path $root '.claude\scripts\macos\plan-lint.py'

function Test-Python([string]$exe, [string[]]$pre) {
  try { $v = (& $exe @pre --version 2>&1 | Out-String); return ($v -match 'Python 3\.') } catch { return $false }
}
$py = $null; $pre = @()
foreach ($cand in @(@('python', @()), @('py', @('-3')), @('python3', @()))) {
  $c = Get-Command $cand[0] -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
  if ($c -and (Test-Python $c.Source $cand[1])) { $py = $c.Source; $pre = $cand[1]; break }
}
if (-not $py) { [Console]::Error.WriteLine('plan-lint: Python 3 not found on PATH (install it from python.org or winget install Python.Python.3.12)'); exit 2 }
# -I keeps the script isolated from the user's site-packages; -X utf8 makes the output UTF-8 (the console code page is not).
& $py @pre -X utf8 -I $script ([string]$args[0]) $plan
exit $LASTEXITCODE
