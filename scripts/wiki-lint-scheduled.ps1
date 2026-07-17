[CmdletBinding()]
param(
  [string]$RuntimeRoot = '',
  [string]$VaultPath = '',
  [string]$SkillPath = '',
  [string]$LogDir = '',
  [string]$ClaudeExe = '',
  [string]$Scope = 'all'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\AiBrain.Common.ps1')

if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
  if ([string]::IsNullOrWhiteSpace($VaultPath)) { throw "RUNTIME_OR_VAULT_REQUIRED" }
  $RuntimeRoot = Get-AiBrainExpectedRuntimeRoot -VaultId (Get-AiBrainVaultId -VaultPath $VaultPath)
}
& (Join-Path $PSScriptRoot 'manage-ai-brain-sleep.ps1') -Action RunNow -RuntimeRoot $RuntimeRoot -Operation lint -Scope $Scope
exit $LASTEXITCODE
