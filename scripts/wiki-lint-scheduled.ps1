[CmdletBinding()]
param(
  [string]$VaultPath = '',
  [string]$SkillPath = (Join-Path $HOME '.claude\skills\ai-brain'),
  [string]$LogDir = (Join-Path $HOME '.claude\logs'),
  [string]$ClaudeExe = 'claude'
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$logFile = Join-Path $LogDir ("wiki-lint-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-RunLog {
  param([string]$Message)
  $line = "[{0}] {1}" -f (Get-Date -Format 's'), $Message
  Add-Content -LiteralPath $logFile -Value $line
}

Write-RunLog "Starting /wiki-lint. SkillPath=$SkillPath VaultPath=$VaultPath"

if (-not [string]::IsNullOrWhiteSpace($VaultPath) -and -not (Test-Path -LiteralPath $VaultPath)) {
  Write-RunLog "VaultPath does not exist: $VaultPath"
  exit 1
}

if (-not (Test-Path -LiteralPath $SkillPath)) {
  Write-RunLog "SkillPath does not exist: $SkillPath"
  exit 1
}

if (-not [string]::IsNullOrWhiteSpace($VaultPath)) {
  Push-Location $VaultPath
}

try {
  & $ClaudeExe -p '/wiki-lint' 2>&1 | Tee-Object -FilePath $logFile -Append
  $exitCode = if ($LASTEXITCODE -eq $null) { 0 } else { $LASTEXITCODE }
  Write-RunLog "Finished /wiki-lint. ExitCode=$exitCode"
  exit $exitCode
}
finally {
  if (-not [string]::IsNullOrWhiteSpace($VaultPath)) {
    Pop-Location
  }
}
