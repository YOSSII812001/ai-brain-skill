[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VaultPath,
  [string]$VaultName = '',
  [string]$ObsidianCliPath = '',
  [ValidateSet('claude', 'codex')]
  [string]$Target = 'claude',
  [switch]$Apply,
  [switch]$InstallScheduledTasks
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($VaultName)) {
  $resolvedVaultPath = Resolve-Path -LiteralPath $VaultPath -ErrorAction SilentlyContinue
  if ($null -ne $resolvedVaultPath) {
    $VaultName = Split-Path -Leaf $resolvedVaultPath.Path
  } else {
    $VaultName = Split-Path -Leaf $VaultPath
  }
  if ([string]::IsNullOrWhiteSpace($VaultName)) {
    $VaultName = Split-Path -Leaf $VaultPath
  }
}

if ([string]::IsNullOrWhiteSpace($ObsidianCliPath)) {
  $defaultObsidianPath = Join-Path $env:ProgramFiles 'Obsidian\Obsidian.exe'
  if (Test-Path -LiteralPath $defaultObsidianPath) {
    $ObsidianCliPath = $defaultObsidianPath
  } else {
    $ObsidianCliPath = '<OBSIDIAN_CLI_PATH>'
  }
}

if ($Target -eq 'claude') {
  $SkillTarget = Join-Path $HOME '.claude\skills\ai-brain'
  $CommandTarget = Join-Path $HOME '.claude\commands'
  $ScriptTarget = Join-Path $HOME '.claude\scripts'
} else {
  $SkillTarget = Join-Path $HOME '.codex\skills\ai-brain'
  $CommandTarget = Join-Path $SkillTarget 'commands'
  $ScriptTarget = Join-Path $SkillTarget 'scripts'
}

$VaultSchemaTarget = Join-Path $VaultPath 'CLAUDE.md'

$plan = @(
  "Target: $Target",
  "VaultPath: $VaultPath",
  "VaultName: $VaultName",
  "ObsidianCliPath: $ObsidianCliPath",
  "SkillTarget: $SkillTarget",
  "CommandTarget: $CommandTarget",
  "ScriptTarget: $ScriptTarget",
  "VaultSchemaTarget: $VaultSchemaTarget"
)

if (-not $Apply) {
  Write-Host 'DRY RUN. Add -Apply to copy files.'
  $plan | ForEach-Object { Write-Host $_ }
  Write-Host 'Would copy skill files, commands, scripts, and vault schema.'
  Write-Host 'Would replace placeholders in copied files.'
  Write-Host 'Would run scripts/validate-repo.ps1.'
  if ($InstallScheduledTasks) {
    Write-Host 'Would call scripts/install-scheduled-tasks.ps1 in dry-run mode.'
  }
  exit 0
}

if (-not (Test-Path -LiteralPath $VaultPath)) {
  throw "VaultPath does not exist: $VaultPath"
}

New-Item -ItemType Directory -Force -Path $SkillTarget | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $SkillTarget 'references') | Out-Null
New-Item -ItemType Directory -Force -Path $CommandTarget | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptTarget | Out-Null

Copy-Item -LiteralPath (Join-Path $RepoRoot 'skill\SKILL.md') -Destination (Join-Path $SkillTarget 'SKILL.md') -Force
Copy-Item -Path (Join-Path $RepoRoot 'skill\references\*') -Destination (Join-Path $SkillTarget 'references') -Recurse -Force
Copy-Item -Path (Join-Path $RepoRoot 'commands\wiki-*.md') -Destination $CommandTarget -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts\wiki-compile-scheduled.ps1') -Destination $ScriptTarget -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts\wiki-lint-scheduled.ps1') -Destination $ScriptTarget -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'vault\CLAUDE.md') -Destination $VaultSchemaTarget -Force

$replacementFiles = @()
$replacementFiles += Get-ChildItem -LiteralPath $CommandTarget -Filter 'wiki-*.md' -File
$replacementFiles += Get-Item -LiteralPath $VaultSchemaTarget

foreach ($file in $replacementFiles) {
  $text = Get-Content -LiteralPath $file.FullName -Raw
  $text = $text.Replace('<YOUR_VAULT_NAME>', $VaultName)
  $text = $text.Replace('<VAULT_NAME>', $VaultName)
  $text = $text.Replace('<VAULT_PATH>', $VaultPath)
  $text = $text.Replace('<OBSIDIAN_CLI_PATH>', $ObsidianCliPath)
  $text = $text.Replace('<AI_BRAIN_SKILL_PATH>', $SkillTarget)
  Set-Content -LiteralPath $file.FullName -Value $text -Encoding UTF8
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\validate-repo.ps1')
if ($LASTEXITCODE -ne 0) {
  throw 'Repository validation failed.'
}

if ($InstallScheduledTasks) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\install-scheduled-tasks.ps1') -ScriptTargetDir $ScriptTarget -VaultPath $VaultPath -SkillPath $SkillTarget -Apply
}

Write-Host 'PASS setup completed'
