[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VaultPath,
  [string]$PreviousRuntimeRoot = '',
  [string]$VaultName = '',
  [string]$ObsidianCliPath = '',
  [ValidateSet('claude', 'codex')]
  [string]$Target = 'claude',
  [string]$AgentExecutable = '',
  [ValidateSet('Ask', 'Accept', 'Custom', 'Disable')]
  [string]$SleepModeChoice = 'Ask',
  [ValidateRange(1, 168)]
  [int]$CompileIntervalHours = 4,
  [ValidatePattern('^(?:[01]\d|2[0-3]):[0-5]\d$')]
  [string]$LintTime = '17:00',
  [switch]$ReconfigureSleep,
  [switch]$ApproveInitialBulk,
  [switch]$ApproveConfigReset,
  [switch]$Apply,
  [switch]$InstallScheduledTasks,
  [switch]$SkipScheduledTask,
  [switch]$Elevated
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$libraryRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libraryRoot 'AiBrain.Common.ps1')
. (Join-Path $libraryRoot 'AiBrain.Schedule.ps1')
. (Join-Path $libraryRoot 'AiBrain.Process.ps1')
. (Join-Path $libraryRoot 'AiBrain.Tasks.ps1')

function Resolve-AiBrainAgentExecutable {
  param([string]$RequestedPath, [string]$Kind)
  if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
    return Get-AiBrainCanonicalPath -Path $RequestedPath -MustExist -AllowFile
  }
  $known = $(if ($Kind -eq 'claude') {
    @((Join-Path $HOME '.local\bin\claude.exe'))
  } else {
    @(
      (Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe'),
      (Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-arm64\vendor\aarch64-pc-windows-msvc\bin\codex.exe')
    )
  })
  foreach ($candidate in $known) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return Get-AiBrainCanonicalPath -Path $candidate -MustExist -AllowFile
    }
  }
  $command = Get-Command ($Kind + '.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
    return Get-AiBrainCanonicalPath -Path ([string]$command.Source) -MustExist -AllowFile
  }
  throw "AGENT_EXECUTABLE_NOT_FOUND"
}

function Show-AiBrainSleepExplanation {
  Write-Host ''
  Write-Host (Get-AiBrainMessage -Name setup_intro)
  Write-Host (Get-AiBrainMessage -Name setup_compile_what)
  Write-Host (Get-AiBrainMessage -Name setup_compile_when)
  Write-Host (Get-AiBrainMessage -Name setup_lint_what)
  Write-Host (Get-AiBrainMessage -Name setup_lint_when)
  Write-Host (Get-AiBrainMessage -Name setup_hidden)
  Write-Host ''
}

function Get-AiBrainConsentChoice {
  param([string]$Choice, [int]$Hours, [string]$Time)
  Show-AiBrainSleepExplanation
  if ($Choice -eq 'Ask') {
    throw "SLEEP_CONSENT_REQUIRED_USE_EXPLICIT_CHOICE"
  }
  if ($Hours -lt 1 -or $Hours -gt 168 -or $Time -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$') {
    throw "SLEEP_SCHEDULE_INVALID"
  }
  return [pscustomobject]@{
    Enabled = $Choice -ne 'Disable'
    CompileHours = $Hours
    LintTime = $Time
    Choice = $Choice
  }
}

function Get-AiBrainInitialBulkEstimate {
  param([Parameter(Mandatory = $true)][string]$CanonicalVault)
  $manifest = Get-AiBrainVaultManifest -VaultPath $CanonicalVault
  $sources = @($manifest | Where-Object { $_.path -like 'main/*' -or $_.path -like 'raw/*' })
  [long]$bytes = 0
  foreach ($entry in $sources) { $bytes += [long]$entry.size }
  return [pscustomobject]@{
    SourceFiles = $sources.Count
    SourceBytes = $bytes
    MaxChangeFiles = 100
    MaxChangeBytes = [Math]::Min([long]1073741824, [Math]::Max([long]10485760, $bytes * 2))
  }
}

function Get-AiBrainInitialBulkApproval {
  param(
    [Parameter(Mandatory = $true)][object]$Estimate,
    [bool]$Enabled,
    [bool]$NeedsApproval,
    [bool]$ExplicitApproval,
    [bool]$IsApply
  )
  if (-not $Enabled -or -not $NeedsApproval) { return $false }
  Write-Host ((Get-AiBrainMessage -Name setup_bulk_estimate) -f $Estimate.SourceFiles, $Estimate.SourceBytes, $Estimate.MaxChangeFiles)
  if (-not $IsApply) {
    Write-Host 'DRY RUN. The skill must ask for one-time initial bulk approval before Apply.'
    return $false
  }
  if ($ExplicitApproval) { return $true }
  throw "INITIAL_BULK_CONSENT_REQUIRED_USE_APPROVE_SWITCH"
}

function Save-AiBrainSetupTask {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$BackupRoot
  )
  $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction SilentlyContinue
  if ($null -eq $task) {
    return [pscustomobject]@{ Existed = $false; Enabled = $false; XmlPath = $null }
  }
  $xml = Export-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName)
  $hash = Get-AiBrainStringSha256 -Text (($xml -replace "`r`n", "`n") + "`n")
  $expectedHash = [string](Get-AiBrainProperty $Config 'managedTaskXmlHash' '')
  if (-not [string]::IsNullOrWhiteSpace($expectedHash) -and $hash -ne $expectedHash) {
    throw "TASK_XML_DRIFT"
  }
  $xmlPath = Join-Path $BackupRoot 'setup-managed-task.xml'
  Write-AiBrainTextAtomic -Path $xmlPath -Text $xml
  Disable-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop | Out-Null
  if ([string]$task.State -eq 'Running') {
    Stop-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop
  }
  return [pscustomobject]@{
    Existed = $true
    Enabled = [string]$task.State -ne 'Disabled'
    XmlPath = $xmlPath
  }
}

function Restore-AiBrainSetupTask {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Snapshot
  )
  if ([bool]$Snapshot.Existed) {
    Register-AiBrainTaskXml `
      -TaskPath ([string]$Config.taskPath) `
      -TaskName ([string]$Config.taskName) `
      -Xml (Read-AiBrainUtf8 -Path ([string]$Snapshot.XmlPath))
    if (-not [bool]$Snapshot.Enabled) {
      Disable-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop | Out-Null
    }
  } else {
    Unregister-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -Confirm:$false -ErrorAction SilentlyContinue
  }
}

function Get-AiBrainPackageSources {
  $sources = New-Object System.Collections.ArrayList
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Recurse -File -Filter '*.ps1' | Sort-Object FullName) {
    $relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\').Replace('\', '/')
    [void]$sources.Add([pscustomobject]@{
      Source = $file.FullName
      Relative = $relative
      Hash = Get-AiBrainFileSha256 -Path $file.FullName
    })
  }
  return @($sources)
}

function Install-AiBrainPackageCache {
  param([object]$Paths)
  $sources = Get-AiBrainPackageSources
  $identity = ($sources | ForEach-Object { '{0}|{1}' -f $_.Relative, $_.Hash }) -join "`n"
  $packageId = Get-AiBrainStringSha256 -Text ($identity + "`n")
  $packageRoot = Join-Path $Paths.Packages $packageId
  function Assert-PackageDirectory([string]$Directory, [object[]]$ExpectedSources) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw "PACKAGE_CACHE_MISSING" }
    $expected = @{}
    foreach ($entry in $ExpectedSources) {
      $destination = Resolve-AiBrainChildPath -Root $Directory -RelativePath $entry.Relative
      if ((Get-AiBrainFileSha256 -Path $destination) -ne $entry.Hash) { throw "PACKAGE_CACHE_HASH_MISMATCH" }
      $expected[$entry.Relative.ToLowerInvariant()] = $true
    }
    $actual = @(
      Get-ChildItem -LiteralPath $Directory -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($Directory.Length).TrimStart('\').Replace('\', '/').ToLowerInvariant()
      }
    )
    if ($actual.Count -ne $expected.Count) { throw "PACKAGE_CACHE_FILE_SET_MISMATCH" }
    foreach ($relative in $actual) {
      if (-not $expected.ContainsKey($relative)) { throw "PACKAGE_CACHE_FILE_SET_MISMATCH" }
    }
  }
  if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
    $temporaryRoot = Join-Path $Paths.Packages ('.{0}-{1}.tmp' -f $packageId, [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot -ErrorAction Stop | Out-Null
    try {
      foreach ($entry in $sources) {
        $destination = Resolve-AiBrainChildPath -Root $temporaryRoot -RelativePath $entry.Relative -AllowMissingLeaf
        Write-AiBrainTextAtomic -Path $destination -Text (Read-AiBrainUtf8 -Path $entry.Source)
        if ((Get-AiBrainFileSha256 $destination) -ne $entry.Hash) { throw "PACKAGE_COPY_HASH_MISMATCH" }
      }
      Assert-PackageDirectory -Directory $temporaryRoot -ExpectedSources $sources
      try {
        [IO.Directory]::Move($temporaryRoot, $packageRoot)
      } catch {
        if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) { throw }
      }
    } finally {
      if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        if (-not (Test-AiBrainPathWithin -Root $Paths.Packages -Candidate $temporaryRoot)) { throw "PACKAGE_TEMP_GUARD_FAILED" }
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }
  Assert-PackageDirectory -Directory $packageRoot -ExpectedSources $sources
  $manifest = [ordered]@{
    schemaVersion = 1
    packageId = $packageId
    packageRelativePath = "packages/$packageId"
    createdUtc = [DateTime]::UtcNow.ToString('o')
    files = @($sources | ForEach-Object { [ordered]@{ path = $_.Relative; sha256 = $_.Hash } })
  }
  Write-AiBrainJsonAtomic -Path $Paths.ActivePackage -Value $manifest
  $bootstrapSource = Join-Path $packageRoot 'scripts\ai-brain-sleep-bootstrap.ps1'
  Write-AiBrainTextAtomic -Path $Paths.Bootstrap -Text (Read-AiBrainUtf8 -Path $bootstrapSource)
  return [pscustomobject]@{ PackageId = $packageId; PackageRoot = $packageRoot; Manifest = $manifest }
}

function Copy-AiBrainInstallFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$BackupRoot,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Ledger
  )
  $destinationFull = [IO.Path]::GetFullPath($Destination)
  $record = [ordered]@{ destination = $destinationFull; existed = (Test-Path -LiteralPath $destinationFull -PathType Leaf); backup = $null; backupHash = $null }
  if ($record.existed) {
    $backup = Join-Path $BackupRoot ([Guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($destinationFull))
    Copy-Item -LiteralPath $destinationFull -Destination $backup -ErrorAction Stop
    $record.backup = $backup
    $record.backupHash = Get-AiBrainFileSha256 -Path $backup
  }
  [void]$Ledger.Add($record)
  $parent = Split-Path -Parent $destinationFull
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  Write-AiBrainTextAtomic -Path $destinationFull -Text (Read-AiBrainUtf8 -Path $Source)
  if ((Get-AiBrainFileSha256 -Path $destinationFull) -ne (Get-AiBrainFileSha256 -Path $Source)) {
    throw "INSTALL_FILE_VERIFY_FAILED"
  }
}

function Backup-AiBrainInstallFile {
  param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$BackupRoot,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Ledger
  )
  $destinationFull = [IO.Path]::GetFullPath($Destination)
  $record = [ordered]@{ destination = $destinationFull; existed = (Test-Path -LiteralPath $destinationFull -PathType Leaf); backup = $null; backupHash = $null }
  if ($record.existed) {
    $backup = Join-Path $BackupRoot ([Guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($destinationFull))
    Copy-Item -LiteralPath $destinationFull -Destination $backup -ErrorAction Stop
    $record.backup = $backup
    $record.backupHash = Get-AiBrainFileSha256 -Path $backup
  }
  [void]$Ledger.Add($record)
}

function Restore-AiBrainInstallLedger {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Ledger)
  [array]$records = @($Ledger)
  [array]::Reverse($records)
  foreach ($record in $records) {
    if ([bool]$record.existed) {
      if ((Get-AiBrainFileSha256 -Path ([string]$record.backup)) -ne [string]$record.backupHash) {
        throw "INSTALL_BACKUP_HASH_MISMATCH"
      }
      Write-AiBrainTextAtomic -Path ([string]$record.destination) -Text (Read-AiBrainUtf8 -Path ([string]$record.backup))
      if ((Get-AiBrainFileSha256 -Path ([string]$record.destination)) -ne [string]$record.backupHash) {
        throw "INSTALL_ROLLBACK_VERIFY_FAILED"
      }
    } elseif (Test-Path -LiteralPath ([string]$record.destination)) {
      Remove-Item -LiteralPath ([string]$record.destination) -Force -ErrorAction Stop
    }
  }
}

function Test-AiBrainAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-AiBrainElevatedSetup {
  param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$BoundParameters)
  $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
  foreach ($entry in $BoundParameters.GetEnumerator()) {
    if ([string]$entry.Key -eq 'Elevated') { continue }
    if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
      if ([bool]$entry.Value) { $arguments += ('-' + [string]$entry.Key) }
      continue
    }
    $arguments += @(('-' + [string]$entry.Key), ([string]$entry.Value))
  }
  $arguments += '-Elevated'
  try {
    $process = Start-Process `
      -FilePath $powershell `
      -ArgumentList (ConvertTo-AiBrainWindowsCommandLine -Arguments $arguments) `
      -Verb RunAs `
      -WindowStyle Hidden `
      -Wait `
      -PassThru `
      -ErrorAction Stop
  } catch {
    throw "SETUP_ELEVATION_CANCELLED_OR_FAILED"
  }
  if ([int]$process.ExitCode -ne 0) { throw "ELEVATED_SETUP_FAILED" }
}

$canonicalVault = Get-AiBrainCanonicalPath -Path $VaultPath -MustExist
if ([string]::IsNullOrWhiteSpace($VaultName)) { $VaultName = Split-Path -Leaf $canonicalVault }
if ([string]::IsNullOrWhiteSpace($ObsidianCliPath)) {
  $candidateObsidian = Join-Path $env:ProgramFiles 'Obsidian\Obsidian.exe'
  $ObsidianCliPath = $(if (Test-Path -LiteralPath $candidateObsidian) { $candidateObsidian } else { '<OBSIDIAN_CLI_PATH>' })
}
$vaultId = Get-AiBrainVaultId -VaultPath $canonicalVault
$runtimeRoot = Get-AiBrainExpectedRuntimeRoot -VaultId $vaultId
$paths = Get-AiBrainRuntimePaths -RuntimeRoot $runtimeRoot
$shouldInstallTask = -not $SkipScheduledTask -or $InstallScheduledTasks

$previousPaths = $null
$previousConfig = $null
$previousState = $null
$previousConfigText = $null
$rebindRequired = $false
if (-not [string]::IsNullOrWhiteSpace($PreviousRuntimeRoot)) {
  $previousPaths = Get-AiBrainRuntimePaths -RuntimeRoot (Get-AiBrainCanonicalPath -Path $PreviousRuntimeRoot -MustExist)
  $previousConfig = Read-AiBrainJson -Path $previousPaths.Config
  if ([int](Get-AiBrainProperty $previousConfig 'schemaVersion' 0) -ne 1 -or
      [int](Get-AiBrainProperty $previousConfig 'consentVersion' 0) -ne 1 -or
      [string](Get-AiBrainProperty $previousConfig 'vaultId' '') -notmatch '^[a-f0-9]{16}$' -or
      [string](Get-AiBrainProperty $previousConfig 'taskPath' '') -ne '\AI Brain\' -or
      [string](Get-AiBrainProperty $previousConfig 'taskName' '') -ne "AI Brain Sleep $($previousConfig.vaultId)") {
    throw "PREVIOUS_RUNTIME_CONFIG_INVALID"
  }
  $expectedPreviousRoot = Get-AiBrainExpectedRuntimeRoot -VaultId ([string]$previousConfig.vaultId)
  if (-not [string]::Equals($expectedPreviousRoot, $previousPaths.Root, [StringComparison]::OrdinalIgnoreCase)) {
    throw "PREVIOUS_RUNTIME_IDENTITY_MISMATCH"
  }
  $rebindRequired = -not [string]::Equals($previousPaths.Root, $paths.Root, [StringComparison]::OrdinalIgnoreCase)
  if (-not $rebindRequired) { throw "PREVIOUS_RUNTIME_EQUALS_NEW_RUNTIME" }
  $previousState = Read-AiBrainJson -Path $previousPaths.State
  Assert-AiBrainState -State $previousState | Out-Null
  $previousConfigText = Read-AiBrainUtf8 -Path $previousPaths.Config
}

$existingConfig = $null
$configNeedsReset = $false
try {
  $existingConfig = Read-AiBrainJson -Path $paths.Config -Optional
} catch {
  if (-not $ApproveConfigReset) { throw "SETUP_CONFIG_SCHEMA_REVIEW_REQUIRED" }
  $configNeedsReset = $true
}
if ($null -ne $existingConfig -and
    ([int](Get-AiBrainProperty $existingConfig 'schemaVersion' 0) -ne 1 -or
     [int](Get-AiBrainProperty $existingConfig 'consentVersion' 0) -ne 1)) {
  if (-not $ApproveConfigReset) { throw "SETUP_CONFIG_SCHEMA_REVIEW_REQUIRED" }
  $configNeedsReset = $true
  $existingConfig = $null
}
$existingState = Read-AiBrainJson -Path $paths.State -Optional
if ($null -ne $existingState) { Assert-AiBrainState -State $existingState | Out-Null }
if ($null -eq $existingState -and $rebindRequired) { $existingState = $previousState }

$sourceConfig = $(if ($null -ne $existingConfig) { $existingConfig } else { $previousConfig })
if ($null -ne $sourceConfig -and -not $PSBoundParameters.ContainsKey('Target')) {
  $Target = [string]$sourceConfig.target
}
if ($null -ne $sourceConfig -and -not $PSBoundParameters.ContainsKey('AgentExecutable') -and
    [string]$sourceConfig.target -eq $Target) {
  $AgentExecutable = [string]$sourceConfig.agentExecutable
}
$resolvedAgent = Resolve-AiBrainAgentExecutable -RequestedPath $AgentExecutable -Kind $Target

$consent = $null
if ($null -ne $existingConfig -and -not $ReconfigureSleep) {
  $consent = [pscustomobject]@{
    Enabled = [bool]$existingConfig.enabled
    CompileHours = [int]$existingConfig.compileIntervalHours
    LintTime = [string]$existingConfig.lintLocalTime
    Choice = 'Existing'
  }
} elseif ($rebindRequired -and -not $PSBoundParameters.ContainsKey('SleepModeChoice')) {
  $consent = [pscustomobject]@{
    Enabled = [bool]$previousConfig.enabled
    CompileHours = [int]$previousConfig.compileIntervalHours
    LintTime = [string]$previousConfig.lintLocalTime
    Choice = 'RebindExisting'
  }
} else {
  $consent = Get-AiBrainConsentChoice -Choice $SleepModeChoice -Hours $CompileIntervalHours -Time $LintTime
}

$bulkEstimate = Get-AiBrainInitialBulkEstimate -CanonicalVault $canonicalVault
$needsInitialBulk = [bool]$consent.Enabled -and $bulkEstimate.SourceFiles -gt 0 -and
  ($null -eq $existingState -or [string]::IsNullOrWhiteSpace([string](Get-AiBrainProperty $existingState 'lastCompileSuccessUtc' '')))
$initialBulkApproved = Get-AiBrainInitialBulkApproval `
  -Estimate $bulkEstimate `
  -Enabled ([bool]$consent.Enabled) `
  -NeedsApproval $needsInitialBulk `
  -ExplicitApproval ([bool]$ApproveInitialBulk) `
  -IsApply ([bool]$Apply)

if ($Target -eq 'claude') {
  $skillTarget = Join-Path $HOME '.claude\skills\ai-brain'
  $commandTarget = Join-Path $HOME '.claude\commands'
  $scriptTarget = Join-Path $HOME '.claude\scripts\ai-brain'
} else {
  $skillTarget = Join-Path $HOME '.codex\skills\ai-brain'
  $commandTarget = Join-Path $skillTarget 'commands'
  $scriptTarget = Join-Path $skillTarget 'scripts'
}
$vaultSchemaTarget = Join-Path $canonicalVault 'CLAUDE.md'

Write-Host "Target: $Target"
Write-Host "Vault: $canonicalVault"
Write-Host "Runtime: $runtimeRoot"
Write-Host "compile: every $($consent.CompileHours) hours"
Write-Host "lint: daily at $($consent.LintTime)"
Write-Host "sleep mode enabled: $($consent.Enabled)"
if (-not $Apply) {
  Write-Host 'DRY RUN. The skill must obtain human consent, then rerun with -Apply and explicit choices.'
  exit 0
}

if ($shouldInstallTask -and -not (Test-AiBrainAdministrator)) {
  if ($Elevated) { throw "S4U_ADMIN_REQUIRED" }
  Write-Host 'Windows administrator confirmation is required once to register the S4U task.'
  Invoke-AiBrainElevatedSetup -BoundParameters $PSBoundParameters
  Write-Host 'PASS setup completed'
  exit 0
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\validate-repo.ps1')
if ($LASTEXITCODE -ne 0) { throw "REPOSITORY_VALIDATION_FAILED" }

Initialize-AiBrainRuntimeDirectories -Paths $paths
$backupRoot = Join-Path $paths.Migration ('install-backup-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$configResetBackupPath = $null
if ($configNeedsReset -and (Test-Path -LiteralPath $paths.Config -PathType Leaf)) {
  $configResetBackupPath = Join-Path $paths.Migration ('config-human-gate-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [Guid]::NewGuid().ToString('N'))
  Copy-Item -LiteralPath $paths.Config -Destination $configResetBackupPath -ErrorAction Stop
  if ((Get-AiBrainFileSha256 -Path $paths.Config) -ne (Get-AiBrainFileSha256 -Path $configResetBackupPath)) {
    throw "CONFIG_RESET_BACKUP_VERIFY_FAILED"
  }
}

$ledger = New-Object System.Collections.ArrayList
$runtimeLedger = New-Object System.Collections.ArrayList
$setupLock = $null
$previousLock = $null
$taskSnapshot = $null
$previousTaskSnapshot = $null
$previousConfigUpdated = $false
$config = $null
if ($rebindRequired) {
  $previousLock = Enter-AiBrainMutex -VaultId ([string]$previousConfig.vaultId) -TimeoutMilliseconds 0
  if (-not $previousLock.Acquired) {
    Exit-AiBrainMutex -Lock $previousLock
    throw "PREVIOUS_RUNTIME_BUSY"
  }
}
$setupLock = Enter-AiBrainMutex -VaultId $vaultId -TimeoutMilliseconds 0
if (-not $setupLock.Acquired) {
  Exit-AiBrainMutex -Lock $setupLock
  Exit-AiBrainMutex -Lock $previousLock
  throw "SETUP_RUNTIME_BUSY"
}
foreach ($mutablePath in @(
  $paths.Config,
  $paths.State,
  $paths.ActivePackage,
  $paths.Bootstrap,
  (Join-Path $canonicalVault 'wiki\_meta\sleep-report.md')
)) {
  Backup-AiBrainInstallFile -Destination $mutablePath -BackupRoot $backupRoot -Ledger $runtimeLedger
}
try {
  if ($null -ne $existingConfig) {
    $taskSnapshot = Save-AiBrainSetupTask -Config $existingConfig -BackupRoot $backupRoot
  } else {
    $unexpectedTask = Get-ScheduledTask -TaskPath '\AI Brain\' -TaskName "AI Brain Sleep $vaultId" -ErrorAction SilentlyContinue
    if ($null -ne $unexpectedTask) {
      if (-not $configNeedsReset) { throw "UNOWNED_TASK_ALREADY_EXISTS" }
      $resetTaskXml = Export-ScheduledTask -TaskPath '\AI Brain\' -TaskName "AI Brain Sleep $vaultId"
      if ($resetTaskXml.IndexOf($paths.Root, [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
          $resetTaskXml.IndexOf('ai-brain-sleep-bootstrap.ps1', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "CONFIG_RESET_TASK_OWNERSHIP_UNPROVEN"
      }
      [xml]$resetTaskDocument = $resetTaskXml
      $intervalNode = @($resetTaskDocument.SelectNodes('//*[local-name()="TimeTrigger"]/*[local-name()="Repetition"]/*[local-name()="Interval"]'))[0]
      if ($null -eq $intervalNode -or [string]$intervalNode.InnerText -notmatch '^PT(\d+)H$') {
        throw "CONFIG_RESET_TASK_CONTRACT_INVALID"
      }
      Test-AiBrainTaskXmlContract -Xml $resetTaskXml -CompileIntervalHours ([int]$Matches[1]) | Out-Null
      $resetTaskIdentity = [pscustomobject]@{
        taskPath = '\AI Brain\'
        taskName = "AI Brain Sleep $vaultId"
        managedTaskXmlHash = Get-AiBrainStringSha256 -Text (($resetTaskXml -replace "`r`n", "`n") + "`n")
      }
      $taskSnapshot = Save-AiBrainSetupTask -Config $resetTaskIdentity -BackupRoot $backupRoot
    } else {
      $taskSnapshot = [pscustomobject]@{ Existed = $false; Enabled = $false; XmlPath = $null }
    }
  }
  if ($rebindRequired) {
    $previousTaskSnapshot = Save-AiBrainSetupTask -Config $previousConfig -BackupRoot (Join-Path $backupRoot 'previous')
  }

  $package = Install-AiBrainPackageCache -Paths $paths
  $config = New-AiBrainConfig `
    -VaultPath $canonicalVault `
    -Target $Target `
    -AgentExecutable $resolvedAgent `
    -CompileIntervalHours $consent.CompileHours `
    -LintLocalTime $consent.LintTime `
    -Enabled $consent.Enabled `
    -PackageId $package.PackageId
  if ($null -ne $sourceConfig) {
    $config.taskGeneration = [string](Get-AiBrainProperty $sourceConfig 'taskGeneration' $config.taskGeneration)
    if (-not $rebindRequired) {
      $config.managedTaskXmlHash = Get-AiBrainProperty $sourceConfig 'managedTaskXmlHash' $null
    }
    $config.compileEnabled = [bool](Get-AiBrainProperty $sourceConfig 'compileEnabled' $true)
    $config.lintEnabled = [bool](Get-AiBrainProperty $sourceConfig 'lintEnabled' $true)
    $config.installedUtc = [string](Get-AiBrainProperty $sourceConfig 'installedUtc' $config.installedUtc)
  }
  if ($initialBulkApproved) {
    Set-AiBrainProperty -Object $config -Name 'bulkApproval' -Value ([ordered]@{
      approvedUtc = [DateTime]::UtcNow.ToString('o')
      expiresUtc = [DateTime]::UtcNow.AddHours(24).ToString('o')
      estimatedSourceFiles = [int]$bulkEstimate.SourceFiles
      estimatedSourceBytes = [long]$bulkEstimate.SourceBytes
      maxChangeFiles = [int]$bulkEstimate.MaxChangeFiles
      maxChangeBytes = [long]$bulkEstimate.MaxChangeBytes
      consumed = $false
      consumedUtc = $null
    })
  }
  $scratch = Join-Path $paths.Staging ('capability-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $scratch -ErrorAction Stop | Out-Null
  try {
    $config.agentCapability = Test-AiBrainAgentCapability -Config ([pscustomobject]$config) -ScratchDirectory $scratch
  } finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-AiBrainJsonAtomic -Path $paths.Config -Value $config

  $state = $existingState
  $newState = $null -eq $state
  if ($newState) { $state = New-AiBrainState -Enabled $consent.Enabled }
  if ($rebindRequired) {
    Reset-AiBrainFailure -State $state
    $state.status = $(if ([bool]$consent.Enabled) { 'ready' } else { 'off' })
    $state.lastRecoveryCode = 'VAULT_REBOUND'
  }
  $now = [DateTime]::UtcNow
  $compileSlot = Get-AiBrainCompileSlot -NowUtc $now -IntervalHours $consent.CompileHours
  $lintSlot = Get-AiBrainLintSlot -NowUtc $now -LocalTime $consent.LintTime -TimeZoneId ([string]$config.timeZoneId)
  $scheduleChanged = $null -eq $sourceConfig -or
    [int](Get-AiBrainProperty $sourceConfig 'compileIntervalHours' 0) -ne [int]$consent.CompileHours -or
    [string](Get-AiBrainProperty $sourceConfig 'lintLocalTime' '') -ne [string]$consent.LintTime
  if ($newState -or $scheduleChanged) {
    $state.lastCompileSlotUtc = $compileSlot.Id
    $state.lastLintSlotId = $lintSlot.Id
  }
  if ([bool]$consent.Enabled) {
    $state.status = $(if ($state.status -in @('paused', 'attention')) { $state.status } else { 'ready' })
    $state.nextCompileUtc = $(if ([bool]$config.compileEnabled) { $compileSlot.NextUtc.ToString('o') } else { $null })
    $state.nextLintUtc = $(if ([bool]$config.lintEnabled) { $lintSlot.NextUtc.ToString('o') } else { $null })
  } else {
    $state.status = 'off'
    $state.nextCompileUtc = $null
    $state.nextLintUtc = $null
  }
  if ($newState) { $state.lastCompileInputFingerprint = $null }
  $state.runId = $null
  $state.child = $null
  $state.packageId = $package.PackageId
  $state.taskGeneration = $config.taskGeneration
  Set-AiBrainState -Paths $paths -State $state

  Copy-AiBrainInstallFile -Source (Join-Path $repoRoot 'skill\SKILL.md') -Destination (Join-Path $skillTarget 'SKILL.md') -BackupRoot $backupRoot -Ledger $ledger
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'skill\references') -File) {
    Copy-AiBrainInstallFile -Source $file.FullName -Destination (Join-Path (Join-Path $skillTarget 'references') $file.Name) -BackupRoot $backupRoot -Ledger $ledger
  }
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'commands') -Filter 'wiki-*.md' -File) {
    Copy-AiBrainInstallFile -Source $file.FullName -Destination (Join-Path $commandTarget $file.Name) -BackupRoot $backupRoot -Ledger $ledger
  }
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Recurse -File -Filter '*.ps1') {
    $relative = $file.FullName.Substring((Join-Path $repoRoot 'scripts').Length).TrimStart('\')
    Copy-AiBrainInstallFile -Source $file.FullName -Destination (Join-Path $scriptTarget $relative) -BackupRoot $backupRoot -Ledger $ledger
  }
  Copy-AiBrainInstallFile -Source (Join-Path $repoRoot 'vault\CLAUDE.md') -Destination $vaultSchemaTarget -BackupRoot $backupRoot -Ledger $ledger

  $schemaFile = Get-Item -LiteralPath $vaultSchemaTarget
  $schemaText = Read-AiBrainUtf8 -Path $schemaFile.FullName
  $schemaText = $schemaText.Replace('<VAULT_NAME>', $VaultName)
  $schemaText = $schemaText.Replace('<VAULT_PATH>', $canonicalVault)
  $schemaText = $schemaText.Replace('<OBSIDIAN_CLI_PATH>', $ObsidianCliPath)
  $schemaText = $schemaText.Replace('<AI_BRAIN_SKILL_PATH>', $skillTarget)
  $schemaText = $schemaText.Replace('<AI_BRAIN_RUNTIME_ROOT>', $runtimeRoot)
  $schemaText = $schemaText.Replace('<AI_BRAIN_SCRIPT_PATH>', $scriptTarget)
  Write-AiBrainTextAtomic -Path $schemaFile.FullName -Text $schemaText

  Write-AiBrainSleepReport -Config ([pscustomobject]$config) -State ([pscustomobject]$state)
  Exit-AiBrainMutex -Lock $setupLock
  $setupLock = $null

  if ($shouldInstallTask) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\install-scheduled-tasks.ps1') -RuntimeRoot $runtimeRoot -Apply
    if ($LASTEXITCODE -ne 0) { throw "SCHEDULED_TASK_INSTALL_FAILED" }
  } elseif ($null -ne $taskSnapshot -and [bool]$taskSnapshot.Existed) {
    Restore-AiBrainSetupTask -Config $config -Snapshot $taskSnapshot
  }

  if ($rebindRequired) {
    Unregister-ScheduledTask -TaskPath ([string]$previousConfig.taskPath) -TaskName ([string]$previousConfig.taskName) -Confirm:$false -ErrorAction SilentlyContinue
    if ($null -ne (Get-ScheduledTask -TaskPath ([string]$previousConfig.taskPath) -TaskName ([string]$previousConfig.taskName) -ErrorAction SilentlyContinue)) {
      throw "PREVIOUS_TASK_REMOVE_FAILED"
    }
    $previousConfig.enabled = $false
    $previousConfig.lastControlAction = 'rebound-to-new-vault'
    Set-AiBrainProperty -Object $previousConfig -Name 'reboundToRuntimeRoot' -Value $runtimeRoot
    Write-AiBrainJsonAtomic -Path $previousPaths.Config -Value $previousConfig
    $previousConfigUpdated = $true
  }
} catch {
  $originalError = $_
  $rollbackFailed = $false
  if ($null -eq $setupLock) {
    try {
      $setupLock = Enter-AiBrainMutex -VaultId $vaultId -TimeoutMilliseconds 120000
      if (-not $setupLock.Acquired) { $rollbackFailed = $true }
    } catch { $rollbackFailed = $true }
  }
  try {
    if ($null -ne $taskSnapshot) {
      $rollbackConfig = $(if ($null -ne $existingConfig) {
        $existingConfig
      } elseif ($null -ne $config) {
        $config
      } else {
        [pscustomobject]@{ taskPath = '\AI Brain\'; taskName = "AI Brain Sleep $vaultId" }
      })
      Restore-AiBrainSetupTask -Config $rollbackConfig -Snapshot $taskSnapshot
    }
  } catch { $rollbackFailed = $true }
  if ($rebindRequired) {
    try {
      if ($previousConfigUpdated) {
        Write-AiBrainTextAtomic -Path $previousPaths.Config -Text $previousConfigText
      }
      if ($null -ne $previousTaskSnapshot) {
        Restore-AiBrainSetupTask -Config $previousConfig -Snapshot $previousTaskSnapshot
      }
    } catch { $rollbackFailed = $true }
  }
  try { Restore-AiBrainInstallLedger -Ledger $ledger } catch { $rollbackFailed = $true }
  try { Restore-AiBrainInstallLedger -Ledger $runtimeLedger } catch { $rollbackFailed = $true }
  if ($rollbackFailed) { throw "INSTALL_ROLLBACK_FAILED" }
  throw $originalError
} finally {
  Exit-AiBrainMutex -Lock $setupLock
  Exit-AiBrainMutex -Lock $previousLock
}

Write-Host 'PASS setup completed'
if (-not [string]::IsNullOrWhiteSpace($configResetBackupPath)) {
  Write-Host "configResetBackupPath: $configResetBackupPath"
}
