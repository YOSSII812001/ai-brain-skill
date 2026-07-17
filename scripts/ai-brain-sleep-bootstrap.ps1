[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$RuntimeRoot,
  [switch]$Preflight,
  [string]$PreflightToken,
  [switch]$ManualRequest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Read-BootstrapJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
    throw "BOOTSTRAP_BOM_NOT_ALLOWED"
  }
  $utf8 = New-Object Text.UTF8Encoding($false, $true)
  return $utf8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
}

function Get-BootstrapHash {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

$runtime = [IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\')
$local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$expectedPrefix = [IO.Path]::GetFullPath((Join-Path $local 'ai-brain')).TrimEnd('\') + '\'
if (-not $runtime.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "BOOTSTRAP_RUNTIME_OUTSIDE_LOCALAPPDATA"
}
$activePath = Join-Path $runtime 'active-package.json'
$active = Read-BootstrapJson -Path $activePath
if ([int]$active.schemaVersion -ne 1 -or [string]$active.packageId -notmatch '^[a-f0-9]{64}$') {
  throw "BOOTSTRAP_MANIFEST_INVALID"
}
$packagePath = [IO.Path]::GetFullPath((Join-Path $runtime ([string]$active.packageRelativePath)))
$packagePrefix = [IO.Path]::GetFullPath((Join-Path $runtime 'packages')).TrimEnd('\') + '\'
if (-not $packagePath.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "BOOTSTRAP_PACKAGE_OUTSIDE_CACHE"
}
foreach ($entry in @($active.files)) {
  $relative = [string]$entry.path
  if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains('..') -or $relative.Contains(':')) {
    throw "BOOTSTRAP_PACKAGE_PATH_INVALID"
  }
  $file = [IO.Path]::GetFullPath((Join-Path $packagePath $relative))
  if (-not $file.StartsWith($packagePath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "BOOTSTRAP_PACKAGE_PATH_INVALID"
  }
  if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-BootstrapHash -Path $file) -ne [string]$entry.sha256) {
    throw "BOOTSTRAP_PACKAGE_HASH_MISMATCH"
  }
}
$orchestrator = Join-Path $packagePath 'scripts\invoke-ai-brain-sleep.ps1'
if (-not (Test-Path -LiteralPath $orchestrator -PathType Leaf)) {
  throw "BOOTSTRAP_ORCHESTRATOR_MISSING"
}
if ($Preflight) {
  & $orchestrator -RuntimeRoot $runtime -Preflight -PreflightToken $PreflightToken
} elseif ($ManualRequest) {
  & $orchestrator -RuntimeRoot $runtime -ManualRequest
} else {
  & $orchestrator -RuntimeRoot $runtime
}
exit $LASTEXITCODE
