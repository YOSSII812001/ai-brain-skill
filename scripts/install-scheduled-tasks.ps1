[CmdletBinding()]
param(
  [string]$ScriptTargetDir = (Join-Path $HOME '.claude\scripts'),
  [string]$VaultPath = '',
  [string]$SkillPath = (Join-Path $HOME '.claude\skills\ai-brain'),
  [string]$LogDir = (Join-Path $HOME '.claude\logs'),
  [string]$TaskPath = '\Claude Code\',
  [string]$CompileTaskName = 'Claude Wiki Compile',
  [string]$LintTaskName = 'Claude Wiki Lint',
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$sourceCompile = Join-Path $PSScriptRoot 'wiki-compile-scheduled.ps1'
$sourceLint = Join-Path $PSScriptRoot 'wiki-lint-scheduled.ps1'
$targetCompile = Join-Path $ScriptTargetDir 'wiki-compile-scheduled.ps1'
$targetLint = Join-Path $ScriptTargetDir 'wiki-lint-scheduled.ps1'

$compileArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetCompile`" -VaultPath `"$VaultPath`" -SkillPath `"$SkillPath`" -LogDir `"$LogDir`""
$lintArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetLint`" -VaultPath `"$VaultPath`" -SkillPath `"$SkillPath`" -LogDir `"$LogDir`""

if (-not $Apply) {
  Write-Host 'DRY RUN. Add -Apply to copy scripts and register scheduled tasks.'
  Write-Host "Would copy $sourceCompile -> $targetCompile"
  Write-Host "Would copy $sourceLint -> $targetLint"
  Write-Host "Would register $CompileTaskName every 3 hours under $TaskPath"
  Write-Host "Would register $LintTaskName daily at 17:00 under $TaskPath"
  exit 0
}

New-Item -ItemType Directory -Force -Path $ScriptTargetDir | Out-Null
Copy-Item -LiteralPath $sourceCompile -Destination $targetCompile -Force
Copy-Item -LiteralPath $sourceLint -Destination $targetLint -Force

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$compileAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $compileArgs
$compileTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddHours(9) -RepetitionInterval (New-TimeSpan -Hours 3) -RepetitionDuration (New-TimeSpan -Days 365)
Register-ScheduledTask -TaskName $CompileTaskName -TaskPath $TaskPath -Action $compileAction -Trigger $compileTrigger -Settings $settings -Force | Out-Null

$lintAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $lintArgs
$lintTrigger = New-ScheduledTaskTrigger -Daily -At '17:00'
Register-ScheduledTask -TaskName $LintTaskName -TaskPath $TaskPath -Action $lintAction -Trigger $lintTrigger -Settings $settings -Force | Out-Null

Write-Host "PASS registered scheduled tasks under $TaskPath"
