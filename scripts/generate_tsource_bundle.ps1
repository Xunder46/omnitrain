#!/usr/bin/env pwsh

# OmniTrain grounding bundle generator (.tsource)
#
# Purpose:
# - Collect source code, unit tests, docs, and settings/deployment files.
# - Exclude plan docs and generated/binary artifacts.
# - Emit one text bundle for LLM grounding.
#
# Changes vs. original:
# - Header now records the git commit and dirty-file count, so every bundle
#   is traceable to an exact repository state ("sole source of truth" needs
#   to say WHICH truth). Warns on stderr when generating from a dirty tree.
# - *.tsource added to exclusions so a bundle can never include a bundle.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-Usage {
    @"
Usage:
  ./scripts/generate_tsource_bundle.ps1 [output_path]

Description:
  Builds a single .tsource text bundle for LLM grounding.
  Includes source code, unit tests, documentation (excluding plan files),
  and settings/deployment files.

Default output path:
  ./omnitrain-grounding.tsource
"@
}

function To-LowerInvariant {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return $Value.ToLowerInvariant()
}

function Normalize-RelPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return $Path.Replace('\\', '/')
}

function To-PosixDisplayPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\', '/'
        return "/$drive/$rest"
    }

    return $Path -replace '\\', '/'
}

function Is-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $item = Get-Item -LiteralPath $FilePath
    if ($item.Length -eq 0) {
        return $true
    }

    # Heuristic parity with grep -Iq: treat files with NUL bytes as binary.
    $stream = [System.IO.File]::OpenRead($FilePath)
    try {
        $buffer = New-Object byte[] 8192
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            for ($i = 0; $i -lt $read; $i++) {
                if ($buffer[$i] -eq 0) {
                    return $false
                }
            }
        }
    }
    finally {
        $stream.Dispose()
    }

    return $true
}

function Is-ExcludedRelPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelPath
    )

    $lower = To-LowerInvariant (Normalize-RelPath $RelPath)

    switch -Wildcard ($lower) {
        '.git/*' { return $true }
        '.dart_tool/*' { return $true }
        'build/*' { return $true }
        'ios/build/*' { return $true }
        'macos/build/*' { return $true }
        'linux/build/*' { return $true }
        'windows/build/*' { return $true }
        'android/.gradle/*' { return $true }

        'ios/pods/*' { return $true }
        'macos/pods/*' { return $true }
        'ios/flutter/appframeworkinfo.plist' { return $true }
        'ios/flutter/flutter.framework/*' { return $true }
        'ios/flutter/flutter.podspec' { return $true }

        'ios/flutter/ephemeral/*' { return $true }
        'macos/flutter/ephemeral/*' { return $true }
        'android/app/build/*' { return $true }
        'web/icons/icon-*maskable*.png' { return $true }

        'native_assets/*' { return $true }
        'test_cache/*' { return $true }
        '.vscode/*' { return $true }
        '.idea/*' { return $true }
        '.ds_store' { return $true }

        'assets/icon/*' { return $true }
        'assets/sounds/*' { return $true }

        '*.ipa' { return $true }
        '*.a' { return $true }
        '*.so' { return $true }
        '*.dylib' { return $true }
        '*.jar' { return $true }
        '*.class' { return $true }
        '*.png' { return $true }
        '*.jpg' { return $true }
        '*.jpeg' { return $true }
        '*.gif' { return $true }
        '*.webp' { return $true }
        '*.mp3' { return $true }
        '*.wav' { return $true }
        '*.ogg' { return $true }
        '*.ttf' { return $true }
        '*.otf' { return $true }
        '*.z' { return $true }
        '*.zip' { return $true }
        '*.tsource' { return $true }
    }

    if ($lower.Contains('/plans/')) {
        return $true
    }

    if ($lower -like '*plan*.md') {
        return $true
    }

    return $false
}

function Classify-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelPath
    )

    $lower = To-LowerInvariant (Normalize-RelPath $RelPath)

    switch -Wildcard ($lower) {
        'test/*' { return 'unit-test' }
        '*.md' { return 'documentation' }

        'pubspec.yaml' { return 'settings-deployment' }
        'pubspec.lock' { return 'settings-deployment' }
        'analysis_options.yaml' { return 'settings-deployment' }
        '.metadata' { return 'settings-deployment' }
        '.gitignore' { return 'settings-deployment' }
        '.github/workflows/*' { return 'settings-deployment' }

        '*.gradle' { return 'settings-deployment' }
        '*.gradle.kts' { return 'settings-deployment' }
        '*.properties' { return 'settings-deployment' }
        '*podfile' { return 'settings-deployment' }
        '*.plist' { return 'settings-deployment' }
        '*.xcconfig' { return 'settings-deployment' }
        '*.pbxproj' { return 'settings-deployment' }
        '*.entitlements' { return 'settings-deployment' }
        '*/cmakelists.txt' { return 'settings-deployment' }
        'web/manifest.json' { return 'settings-deployment' }
        'android/app/src/main/androidmanifest.xml' { return 'settings-deployment' }
    }

    return 'source'
}

function Get-RelativePathFromRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$AbsolutePath
    )

    $rootPath = [System.IO.Path]::GetFullPath($Root)
    if (-not $rootPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $rootPath += [System.IO.Path]::DirectorySeparatorChar
    }

    $rootUri = [System.Uri]::new($rootPath)
    $fileUri = [System.Uri]::new([System.IO.Path]::GetFullPath($AbsolutePath))
    $relative = [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fileUri).ToString())
    return Normalize-RelPath $relative
}

function Add-DirFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Dir,
        [Parameter(Mandatory = $true)]
        [object]$Candidates
    )

    $target = Join-Path $Root $Dir
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $target -File -Recurse | ForEach-Object {
        $Candidates.Add((Get-RelativePathFromRoot -Root $Root -AbsolutePath $_.FullName))
    }
}

function Add-DocsMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [object]$Candidates
    )

    $pruneRoots = @(
        '.git',
        '.dart_tool',
        'build',
        'ios/build',
        'macos/build',
        'ios/Pods',
        'macos/Pods',
        'native_assets',
        'test_cache'
    ) | ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $Root $_)).TrimEnd([char]'\', [char]'/') }

    Get-ChildItem -LiteralPath $Root -File -Recurse | ForEach-Object {
        $full = $_.FullName
        $normalized = $full.TrimEnd([char]'\', [char]'/')

        foreach ($prune in $pruneRoots) {
            if ($normalized.StartsWith($prune + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
                $normalized.StartsWith($prune + '/', [System.StringComparison]::OrdinalIgnoreCase) -or
                $normalized.Equals($prune, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        }

        if ($_.Extension -ieq '.md') {
            $Candidates.Add((Get-RelativePathFromRoot -Root $Root -AbsolutePath $full))
        }
    }
}

function Add-RootFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [object]$Candidates
    )

    $files = @(
        'README.md',
        'pubspec.yaml',
        'pubspec.lock',
        'analysis_options.yaml',
        '.metadata',
        '.gitignore'
    )

    foreach ($rel in $files) {
        $abs = Join-Path $Root $rel
        if (Test-Path -LiteralPath $abs -PathType Leaf) {
            $Candidates.Add((Normalize-RelPath $rel))
        }
    }
}

function Get-SortedUniqueOrdinal {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$InputValues
    )

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($value in $InputValues) {
        [void]$set.Add($value)
    }

    $arr = New-Object string[] $set.Count
    $set.CopyTo($arr)
    [System.Array]::Sort($arr, [System.StringComparer]::Ordinal)
    return $arr
}

function Get-GitValueOrUnknown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    try {
        $result = & git -C $Root @Args 2>$null
        if (-not $result) {
            return 'unknown'
        }
        return ($result | Select-Object -First 1).Trim()
    }
    catch {
        return 'unknown'
    }
}

function Get-GitDirtyCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    try {
        $lines = & git -C $Root status --porcelain 2>$null
        if (-not $lines) {
            return '0'
        }
        return ([string]($lines | Measure-Object | Select-Object -ExpandProperty Count))
    }
    catch {
        return '0'
    }
}

if ($args.Count -gt 0 -and ($args[0] -eq '-h' -or $args[0] -eq '--help')) {
    Show-Usage
    exit 0
}

$scriptDir = Split-Path -Parent $PSCommandPath
$rootDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))

$outputPath = if ($args.Count -gt 0) { $args[0] } else { Join-Path $rootDir 'omnitrain-grounding.tsource' }
if (-not [System.IO.Path]::IsPathRooted($outputPath)) {
    $outputPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $outputPath))
}

$candidates = New-Object 'System.Collections.Generic.List[string]'

$collectDirs = @(
    'lib',
    'test',
    'scripts',
    'assets',
    'android',
    'ios',
    'macos',
    'linux',
    'windows',
    'web',
    '.github'
)

foreach ($dir in $collectDirs) {
    Add-DirFiles -Root $rootDir -Dir $dir -Candidates $candidates
}

Add-DocsMarkdown -Root $rootDir -Candidates $candidates
Add-RootFiles -Root $rootDir -Candidates $candidates

$uniqueCandidates = Get-SortedUniqueOrdinal -InputValues ($candidates.ToArray())

$finalList = New-Object 'System.Collections.Generic.List[string]'
foreach ($rel in $uniqueCandidates) {
    if ([string]::IsNullOrWhiteSpace($rel)) {
        continue
    }

    if (Is-ExcludedRelPath -RelPath $rel) {
        continue
    }

    $abs = Join-Path $rootDir $rel
    if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) {
        continue
    }

    if (-not (Is-TextFile -FilePath $abs)) {
        continue
    }

    $finalList.Add((Normalize-RelPath $rel))
}

$final = Get-SortedUniqueOrdinal -InputValues ($finalList.ToArray())
$fileCount = [string]$final.Count
$generatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

$gitCommit = Get-GitValueOrUnknown -Root $rootDir -Args @('rev-parse', '--short=12', 'HEAD')
$gitBranch = Get-GitValueOrUnknown -Root $rootDir -Args @('rev-parse', '--abbrev-ref', 'HEAD')
$gitDirtyCount = Get-GitDirtyCount -Root $rootDir

if ($gitDirtyCount -ne '0') {
    [Console]::Error.WriteLine("WARNING: generating bundle from a dirty working tree ($gitDirtyCount uncommitted change(s)).")
    [Console]::Error.WriteLine("         The bundle will not correspond exactly to commit $gitCommit.")
}

$outputDir = Split-Path -Parent $outputPath
if (-not [string]::IsNullOrEmpty($outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$writer = [System.IO.StreamWriter]::new($outputPath, $false, [System.Text.UTF8Encoding]::new($false))
try {
    $writer.WriteLine('# OmniTrain TSource Bundle')
    $writer.WriteLine("generated_at_utc: $generatedAt")
    $writer.WriteLine("repository_root: $(To-PosixDisplayPath $rootDir)")
    $writer.WriteLine("git_commit: $gitCommit")
    $writer.WriteLine("git_branch: $gitBranch")
    $writer.WriteLine("git_uncommitted_changes: $gitDirtyCount")
    $writer.WriteLine("included_files: $fileCount")
    $writer.WriteLine('notes:')
    $writer.WriteLine('- Plan files are excluded (paths containing /plans/ and filenames matching *plan*.md).')
    $writer.WriteLine('- Binary and generated artifacts are excluded.')
    $writer.WriteLine('- If git_uncommitted_changes > 0, this bundle does not correspond exactly to git_commit.')
    $writer.WriteLine()
    $writer.WriteLine('## Manifest')

    foreach ($rel in $final) {
        $category = Classify-File -RelPath $rel
        $writer.WriteLine("[$category] $rel")
    }

    $writer.WriteLine()
    $writer.WriteLine('## Files')

    foreach ($rel in $final) {
        $abs = Join-Path $rootDir $rel
        $writer.WriteLine("===== BEGIN FILE: $rel =====")
        $writer.Write([System.IO.File]::ReadAllText($abs))
        $writer.WriteLine()
        $writer.WriteLine("===== END FILE: $rel =====")
        $writer.WriteLine()
    }
}
finally {
    $writer.Dispose()
}

Write-Output "Bundle created: $outputPath"
Write-Output "Included files: $fileCount"
Write-Output "Commit: $gitCommit (branch: $gitBranch, uncommitted: $gitDirtyCount)"
