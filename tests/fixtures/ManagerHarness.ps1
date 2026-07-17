[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ManagerPath,
  [Parameter(Mandatory = $true)][string]$RuntimeRoot,
  [Parameter(Mandatory = $true)][string]$Action,
  [string]$Operation = 'compile',
  [string]$Scope = 'all',
  [switch]$Repair,
  [switch]$ApproveStateReset,
  [int]$BulkMaxFiles = 0,
  [long]$BulkMaxBytes = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8

function Get-ScheduledTask {
  [CmdletBinding()]
  param([string]$TaskPath, [string]$TaskName)
  return [pscustomobject]@{ State = 'Disabled' }
}

function Export-ScheduledTask {
  [CmdletBinding()]
  param([string]$TaskPath, [string]$TaskName)
  return '<Task xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"></Task>'
}

try {
  $arguments = @{
    Action = $Action
    RuntimeRoot = $RuntimeRoot
    Operation = $Operation
    Scope = $Scope
  }
  if ($Repair) { $arguments.Repair = $true }
  if ($ApproveStateReset) { $arguments.ApproveStateReset = $true }
  if ($BulkMaxFiles -gt 0) { $arguments.BulkMaxFiles = $BulkMaxFiles }
  if ($BulkMaxBytes -gt 0) { $arguments.BulkMaxBytes = $BulkMaxBytes }
  $result = @(& $ManagerPath @arguments)
  $envelope = [ordered]@{
    success = $true
    error = $null
    errorId = $null
    position = $null
    stack = $null
    result = $result
  }
  [Console]::Out.Write(($envelope | ConvertTo-Json -Compress -Depth 50))
  exit 0
} catch {
  $envelope = [ordered]@{
    success = $false
    error = [string]$_.Exception.Message
    errorId = [string]$_.FullyQualifiedErrorId
    position = [string]$_.InvocationInfo.PositionMessage
    stack = [string]$_.ScriptStackTrace
    result = @()
  }
  [Console]::Out.Write(($envelope | ConvertTo-Json -Compress -Depth 20))
  exit 1
}
