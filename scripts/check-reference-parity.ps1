[CmdletBinding()]
param(
  [string]$RootReferences = '',
  [string]$SkillReferences = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($RootReferences)) {
  $RootReferences = Join-Path $repoRoot 'references'
}

if ([string]::IsNullOrWhiteSpace($SkillReferences)) {
  $SkillReferences = Join-Path $repoRoot 'skill\references'
}

$RootReferences = (Resolve-Path -LiteralPath $RootReferences).Path
$SkillReferences = (Resolve-Path -LiteralPath $SkillReferences).Path
$failures = New-Object System.Collections.Generic.List[string]

$rootFiles = Get-ChildItem -LiteralPath $RootReferences -Recurse -File
$skillFiles = Get-ChildItem -LiteralPath $SkillReferences -Recurse -File
$rootRelative = @{}
$skillRelative = @{}

foreach ($file in $rootFiles) {
  $relative = $file.FullName.Substring($RootReferences.Length).TrimStart('\', '/').Replace('\', '/')
  $rootRelative[$relative] = $file.FullName
}

foreach ($file in $skillFiles) {
  $relative = $file.FullName.Substring($SkillReferences.Length).TrimStart('\', '/').Replace('\', '/')
  $skillRelative[$relative] = $file.FullName
}

foreach ($name in $rootRelative.Keys) {
  if (-not $skillRelative.ContainsKey($name)) {
    [void]$failures.Add("Missing in skill/references: $name")
    continue
  }

  & git diff --no-index --quiet --ignore-cr-at-eol -- $rootRelative[$name] $skillRelative[$name]
  if ($LASTEXITCODE -eq 1) {
    [void]$failures.Add("Content drift: $name")
  } elseif ($LASTEXITCODE -gt 1) {
    [void]$failures.Add("Diff failed for: $name")
  }
}

foreach ($name in $skillRelative.Keys) {
  if (-not $rootRelative.ContainsKey($name)) {
    [void]$failures.Add("Extra in skill/references: $name")
  }
}

if ($failures.Count -gt 0) {
  Write-Host 'Reference parity failed:'
  $failures | ForEach-Object { Write-Host "- $_" }
  exit 1
}

Write-Host "PASS reference parity: $($rootRelative.Count) files"
