[CmdletBinding()]
param(
  [ValidateSet('claude', 'codex')]
  [string]$Target = 'claude',
  [string]$RepoCommandDirectory = '',
  [string]$TargetDirectory = '',
  [switch]$AllowMissing
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($RepoCommandDirectory)) {
  $RepoCommandDirectory = Join-Path $repoRoot 'commands'
}

if ([string]::IsNullOrWhiteSpace($TargetDirectory)) {
  if ($Target -eq 'claude') {
    $TargetDirectory = Join-Path $HOME '.claude\commands'
  } else {
    $TargetDirectory = Join-Path $HOME '.codex\skills\ai-brain\commands'
  }
}

function Normalize-CommandContent {
  param([string]$Content)
  $targetVaultLabel = ([string][char]0x5BFE) + ([string][char]0x8C61) + 'vault'
  $targetVaultPattern = [regex]::Escape($targetVaultLabel) + ':\s*.+'

  $text = $Content -replace "`r`n?", "`n"
  $text = $text -replace "^\uFEFF", ''
  $text = $text -replace $targetVaultPattern, 'target-vault: <VAULT_NAME>'
  $text = $text -replace '~/.claude/skills/ai-brain', '~/.skills/ai-brain'
  $text = $text -replace '~/.codex/skills/ai-brain', '~/.skills/ai-brain'
  $text = $text -replace 'C:\\Users\\[^\\]+\\.claude\\skills\\ai-brain', '~/.skills/ai-brain'
  $text = $text -replace 'C:\\Users\\[^\\]+\\.codex\\skills\\ai-brain', '~/.skills/ai-brain'
  return $text.Trim()
}

$failures = New-Object System.Collections.Generic.List[string]
$repoFiles = Get-ChildItem -LiteralPath $RepoCommandDirectory -Filter 'wiki-*.md' -File | Sort-Object Name

if (-not (Test-Path -LiteralPath $TargetDirectory)) {
  if ($AllowMissing) {
    Write-Host "SKIP target command directory does not exist: $TargetDirectory"
    exit 0
  }
  Write-Error "Target command directory does not exist: $TargetDirectory"
  exit 1
}

foreach ($repoFile in $repoFiles) {
  $targetFile = Join-Path $TargetDirectory $repoFile.Name
  if (-not (Test-Path -LiteralPath $targetFile)) {
    [void]$failures.Add("Missing target command: $($repoFile.Name)")
    continue
  }

  $repoContent = Get-Content -LiteralPath $repoFile.FullName -Raw -Encoding UTF8
  $targetContent = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8
  $repoText = Normalize-CommandContent -Content $repoContent
  $targetText = Normalize-CommandContent -Content $targetContent
  if ($repoText -ne $targetText) {
    [void]$failures.Add("Command drift: $($repoFile.Name)")
  }
}

if ($failures.Count -gt 0) {
  Write-Host 'Command sync failed:'
  $failures | ForEach-Object { Write-Host "- $_" }
  exit 1
}

Write-Host "PASS command sync: $($repoFiles.Count) files match $TargetDirectory"
