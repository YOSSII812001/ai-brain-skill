[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Status', 'Configure', 'Enable', 'Disable', 'RunNow', 'Doctor', 'ApproveBulk', 'Uninstall')]
  [string]$Action,
  [string]$RuntimeRoot,
  [string]$VaultPath,
  [ValidateSet('compile', 'lint')]
  [string]$Operation = 'compile',
  [string]$Scope = 'all',
  [ValidateRange(0, 10080)]
  [int]$CompileMinutes = 0,
  [string]$LintLocalTime = '',
  [switch]$Repair,
  [switch]$ApproveScheduleChange,
  [switch]$ApproveDisable,
  [switch]$ApproveUninstall,
  [switch]$ApproveStateReset,
  [ValidateRange(0, 1000)]
  [int]$BulkMaxFiles = 0,
  [ValidateRange(0, 1073741824)]
  [long]$BulkMaxBytes = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$libraryRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libraryRoot 'AiBrain.Common.ps1')
. (Join-Path $libraryRoot 'AiBrain.Schedule.ps1')
. (Join-Path $libraryRoot 'AiBrain.Process.ps1')
. (Join-Path $libraryRoot 'AiBrain.Requests.ps1')
. (Join-Path $libraryRoot 'AiBrain.Tasks.ps1')
. (Join-Path $libraryRoot 'AiBrain.Transaction.ps1')

function Resolve-AiBrainControlRuntime {
  param([string]$RequestedRuntime, [string]$RequestedVault)
  if (-not [string]::IsNullOrWhiteSpace($RequestedRuntime)) {
    return Get-AiBrainCanonicalPath -Path $RequestedRuntime -MustExist
  }
  if ([string]::IsNullOrWhiteSpace($RequestedVault)) { throw "RUNTIME_OR_VAULT_REQUIRED" }
  $vaultId = Get-AiBrainVaultId -VaultPath $RequestedVault
  return Get-AiBrainExpectedRuntimeRoot -VaultId $vaultId
}

function Get-AiBrainPackageHealth {
  param([Parameter(Mandatory = $true)][object]$Paths)
  $active = Read-AiBrainJson -Path $Paths.ActivePackage
  if ([int]$active.schemaVersion -ne 1 -or [string]$active.packageId -notmatch '^[a-f0-9]{64}$') {
    throw "PACKAGE_MANIFEST_INVALID"
  }
  $package = Resolve-AiBrainChildPath -Root $Paths.Root -RelativePath ([string]$active.packageRelativePath)
  foreach ($entry in @($active.files)) {
    $file = Resolve-AiBrainChildPath -Root $package -RelativePath ([string]$entry.path)
    if ((Get-AiBrainFileSha256 $file) -ne [string]$entry.sha256) { throw "PACKAGE_HASH_MISMATCH" }
  }
  return [pscustomobject]@{ Active = $active; PackageRoot = $package }
}

function Repair-AiBrainOrphanedRun {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$State
  )
  foreach ($recovery in Recover-AiBrainJournals -Config $Config -Paths $Paths) {
    if ([string]$recovery.action -eq 'finalize_state') {
      $journal = $recovery.journal
      $slotId = [string](Get-AiBrainProperty $journal 'slotId' '')
      if ([string]$journal.operation -eq 'compile' -and -not [string]::IsNullOrWhiteSpace($slotId)) {
        Complete-AiBrainOperationSlot -State $State -Operation compile -SlotId $slotId
        $State.lastCompileInputFingerprint = [string]$journal.finalFingerprint
      } elseif ([string]$journal.operation -eq 'lint' -and -not [string]::IsNullOrWhiteSpace($slotId)) {
        Complete-AiBrainOperationSlot -State $State -Operation lint -SlotId $slotId
      }
      Set-AiBrainState -Paths $Paths -State $State
      Complete-AiBrainJournal -JournalPath ([string]$recovery.path)
    } elseif ([string]$recovery.action -eq 'rolled_back') {
      $State.lastRollbackPerformed = $true
      $State.lastRecoveryCode = 'JOURNAL_ROLLED_BACK'
    }
  }
  Recover-AiBrainClaimedRequests -Paths $Paths -State $State
  $State.status = $(if ([bool]$Config.enabled) { 'ready' } else { 'off' })
  $State.runId = $null
  $State.activeRequestId = $null
  $State.child = $null
  $State.lastHeartbeatUtc = [DateTime]::UtcNow.ToString('o')
  $State.lastRecoveryCode = 'ORPHANED_RUN_RECOVERED'
  Reset-AiBrainFailure -State $State
  Set-AiBrainState -Paths $Paths -State $State
}

function Invoke-AiBrainDoctor {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$State,
    [switch]$ApplyRepair,
    [switch]$AllowAttentionClear
  )
  $issues = New-Object System.Collections.ArrayList
  $repairs = New-Object System.Collections.ArrayList
  $currentZoneId = [TimeZoneInfo]::Local.Id
  if ([string]$Config.timeZoneId -ne $currentZoneId) {
    if ($ApplyRepair) {
      $Config.timeZoneId = $currentZoneId
      $lint = Get-AiBrainLintSlot -NowUtc ([DateTime]::UtcNow) -LocalTime ([string]$Config.lintLocalTime) -TimeZoneId $currentZoneId
      $State.lastLintSlotId = $lint.Id
      $State.nextLintUtc = $(if ([bool]$Config.enabled -and [bool]$Config.lintEnabled) { $lint.NextUtc.ToString('o') } else { $null })
      [void]$repairs.Add('time-zone')
    } else {
      [void]$issues.Add('TIME_ZONE_CHANGED')
    }
  }
  $packageHealth = $null
  try { $packageHealth = Get-AiBrainPackageHealth -Paths $Paths } catch { [void]$issues.Add([string]$_.Exception.Message) }
  $bootstrapHealthy = Test-Path -LiteralPath $Paths.Bootstrap -PathType Leaf
  if ($bootstrapHealthy -and $null -ne $packageHealth) {
    $packageBootstrap = Join-Path $packageHealth.PackageRoot 'scripts\ai-brain-sleep-bootstrap.ps1'
    $bootstrapHealthy = (Get-AiBrainFileSha256 $packageBootstrap) -eq (Get-AiBrainFileSha256 $Paths.Bootstrap)
  }
  if (-not $bootstrapHealthy) {
    [void]$issues.Add('BOOTSTRAP_DRIFT')
  }

  $task = Get-AiBrainTaskStatus -Config $Config
  $taskHashDrift = $task.Exists -and
    -not [string]::IsNullOrWhiteSpace([string]$Config.managedTaskXmlHash) -and
    [string]$task.XmlHash -ne [string]$Config.managedTaskXmlHash
  $taskNeedsRepair = $(if ([bool]$Config.enabled) {
    -not $task.Exists -or -not $task.Enabled -or $taskHashDrift
  } else {
    -not $task.Exists -or $task.Enabled -or $taskHashDrift
  })
  if ($taskNeedsRepair) {
    if ($ApplyRepair -and
        [string]$State.taskGeneration -eq [string]$Config.taskGeneration -and $bootstrapHealthy) {
      Test-AiBrainS4UPreflight -Config $Config -Paths $Paths -BootstrapPath $Paths.Bootstrap | Out-Null
      $registered = Register-AiBrainSleepTask -Config $Config -BootstrapPath $Paths.Bootstrap
      $Config.managedTaskXmlHash = $registered.Hash
      $Config.lastControlAction = 'doctor-repair'
      Write-AiBrainJsonAtomic -Path $Paths.Config -Value $Config
      [void]$repairs.Add('task')
      $task = Get-AiBrainTaskStatus -Config $Config
    } else {
      if (-not $task.Exists) { [void]$issues.Add('TASK_MISSING') }
      elseif (-not $task.Enabled) { [void]$issues.Add('TASK_DISABLED_EXTERNALLY') }
      else { [void]$issues.Add('TASK_XML_DRIFT') }
    }
  }

  if ($null -eq $Config.agentCapability -or -not [bool](Get-AiBrainProperty $Config.agentCapability 'verified' $false)) {
    [void]$issues.Add('AGENT_CAPABILITY_UNKNOWN')
  }
  if ([string]$State.status -eq 'running') {
    if ($ApplyRepair) {
      try {
        Repair-AiBrainOrphanedRun -Config $Config -Paths $Paths -State $State
        [void]$repairs.Add('orphaned-run')
      } catch {
        [void]$issues.Add('ORPHANED_RUN_RECOVERY_FAILED')
      }
    } else {
      [void]$issues.Add('ORPHANED_RUNNING_STATE')
    }
  }
  $heartbeatText = [string](Get-AiBrainProperty $State 'lastHeartbeatUtc' '')
  if ([string]::IsNullOrWhiteSpace($heartbeatText)) { $heartbeatText = [string]$Config.installedUtc }
  $heartbeat = [DateTimeOffset]::MinValue
  $heartbeatStale = -not [DateTimeOffset]::TryParse($heartbeatText, [ref]$heartbeat) -or
    ([DateTime]::UtcNow - $heartbeat.UtcDateTime).TotalHours -gt 12
  if ([bool]$Config.enabled -and $heartbeatStale) {
    [void]$issues.Add('HEARTBEAT_STALE')
  }
  $heldAttentionCode = [string](Get-AiBrainProperty $State 'attentionCode' '')
  $attentionCanClear = $false
  if ([string]$State.status -in @('attention', 'paused') -and
      -not [string]::IsNullOrWhiteSpace($heldAttentionCode)) {
    [void]$issues.Add($heldAttentionCode)
    if ($AllowAttentionClear -and
        $heldAttentionCode -notmatch '^(INITIAL_BULK_|CHANGE_SET_(?:FILE|BYTE)_LIMIT_)') {
      if ($heldAttentionCode -eq 'AGENT_AUTH_REQUIRED') {
        try {
          Test-AiBrainS4UPreflight -Config $Config -Paths $Paths -BootstrapPath $Paths.Bootstrap | Out-Null
          $attentionCanClear = $true
        } catch {}
      } elseif ($heldAttentionCode -eq 'DISK_SPACE_LOW') {
        try {
          [long]$sourceBytes = 0
          foreach ($entry in Get-AiBrainVaultManifest -VaultPath ([string]$Config.vaultPath)) {
            $sourceBytes += [long]$entry.size
          }
          Assert-AiBrainFreeSpace -Config $Config -Paths $Paths -SourceBytes $sourceBytes | Out-Null
          $attentionCanClear = $true
        } catch {}
      } else {
        # This is an explicit human resume gate. A persistent cause will stop
        # safely again on the next single attempt; Status alone never resumes.
        $attentionCanClear = $true
      }
    }
  }
  if ($attentionCanClear) {
    $otherIssues = @($issues | Where-Object { [string]$_ -ne $heldAttentionCode })
    if ($otherIssues.Count -eq 0) {
      while ($issues.Contains($heldAttentionCode)) { $issues.Remove($heldAttentionCode) }
      $State.status = $(if ([bool]$Config.enabled) { 'ready' } else { 'off' })
      Reset-AiBrainFailure -State $State
      [void]$repairs.Add('attention-resumed-by-human')
    }
  }
  if ($repairs.Count -gt 0) {
    Write-AiBrainJsonAtomic -Path $Paths.Config -Value $Config
    Set-AiBrainState -Paths $Paths -State $State
  }

  $result = [pscustomobject]@{
    healthy = $issues.Count -eq 0
    status = [string]$State.status
    taskState = [string]$task.State
    packageHealthy = $null -ne $packageHealth
    bootstrapHealthy = $bootstrapHealthy
    issues = @($issues)
    repairs = @($repairs)
    lastHeartbeatUtc = $State.lastHeartbeatUtc
    nextCompileUtc = $State.nextCompileUtc
    nextLintUtc = $State.nextLintUtc
  }
  if (-not $result.healthy) {
    $action = $(if ($null -eq $packageHealth -or @($issues) -contains 'BOOTSTRAP_DRIFT') {
      Get-AiBrainMessage -Name action_setup
    } else {
      Get-AiBrainMessage -Name action_repair
    })
    if ([string]$State.attentionCode -eq [string]$issues[0] -and
        -not [string]::IsNullOrWhiteSpace([string]$State.attentionAction)) {
      $action = [string]$State.attentionAction
    }
    Set-AiBrainAttention -Paths $Paths -State $State -Code ([string]$issues[0]) -Action $action
  }
  Write-AiBrainSleepReport -Config $Config -State $State
  return $result
}

function Start-AiBrainRequestWithHandshake {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$RequestId,
    [switch]$Direct
  )
  if ($Direct) {
    $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $result = Invoke-AiBrainHiddenProcess `
      -CommandPath $shell `
      -Arguments @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', [string]$Paths.Bootstrap, '-RuntimeRoot', [string]$Paths.Root, '-ManualRequest'
      ) `
      -WorkingDirectory ([string]$Paths.Root) `
      -TimeoutSeconds ([int]$Config.limits.timeoutSeconds + 60) `
      -MaxCaptureBytes ([int]$Config.limits.maxCaptureBytes)
    if ($result.TimedOut -or -not $result.TreeTerminated -or $result.ExitCode -ne 0) { throw "MANUAL_RUN_FAILED" }
    return Get-AiBrainRequestLocation -Paths $Paths -RequestId $RequestId
  }
  Start-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop
  $deadline = [DateTime]::UtcNow.AddSeconds([int]$Config.limits.requestWaitSeconds)
  $lastStart = [DateTime]::UtcNow
  while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
    $location = Get-AiBrainRequestLocation -Paths $Paths -RequestId $RequestId
    if ($null -eq $location) { throw "REQUEST_LOST" }
    if ($location.Status -in @('completed', 'failed')) { return $location }
    if ($location.Status -eq 'pending') {
      $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop
      if ([string]$task.State -eq 'Ready' -and ([DateTime]::UtcNow - $lastStart).TotalSeconds -ge 1) {
        Start-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop
        $lastStart = [DateTime]::UtcNow
      }
    }
  }
  return Get-AiBrainRequestLocation -Paths $Paths -RequestId $RequestId
}

function Get-AiBrainBulkEstimate {
  param([Parameter(Mandatory = $true)][object]$Config)
  $manifest = Get-AiBrainVaultManifest -VaultPath ([string]$Config.vaultPath)
  $estimated = @($manifest | Where-Object { $_.path -like 'main/*' -or $_.path -like 'raw/*' })
  [long]$estimatedBytes = 0
  foreach ($entry in $estimated) { $estimatedBytes += [long]$entry.size }
  return [pscustomobject]@{
    estimatedSourceFiles = $estimated.Count
    estimatedSourceBytes = $estimatedBytes
    proposedMaxChangeFiles = 100
    proposedMaxChangeBytes = [Math]::Min(
      [long]1073741824,
      [Math]::Max([long]$Config.limits.maxChangeBytes, $estimatedBytes * 2)
    )
  }
}

function Uninstall-AiBrainSleep {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$State
  )
  $backupRoot = Join-Path $Paths.Migration ('uninstall-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
  $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction SilentlyContinue
  if ($null -ne $task) {
    $xml = Export-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName)
    Write-AiBrainTextAtomic -Path (Join-Path $backupRoot 'sleep-task.xml') -Text $xml
    Disable-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction SilentlyContinue | Out-Null
    if ([string]$task.State -eq 'Running') {
      Stop-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction SilentlyContinue
    }
    Unregister-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -Confirm:$false -ErrorAction Stop
  }
  $Config.enabled = $false
  $Config.lastControlAction = 'uninstall'
  Write-AiBrainJsonAtomic -Path $Paths.Config -Value $Config
  $State.status = 'off'
  Set-AiBrainState -Paths $Paths -State $State
  return [pscustomobject]@{ uninstalled = $true; runtimePreserved = $true; recoveryPath = $Paths.Root }
}

$resolvedRuntime = Resolve-AiBrainControlRuntime -RequestedRuntime $RuntimeRoot -RequestedVault $VaultPath
$paths = Get-AiBrainRuntimePaths -RuntimeRoot $resolvedRuntime
Initialize-AiBrainRuntimeDirectories -Paths $paths
$config = $null
try {
  $config = Read-AiBrainJson -Path $paths.Config
  Assert-AiBrainConfig -Config $config | Out-Null
} catch {
  $configCode = Get-AiBrainErrorCode -ErrorRecord $_
  $configAction = $(if ($configCode -eq 'VAULT_NOT_FOUND_OR_MOVED') {
    Get-AiBrainMessage -Name action_vault
  } else {
    Get-AiBrainMessage -Name action_config_reset
  })
  try {
    Write-AiBrainLogEvent -Paths $paths -EventCode $configCode -Level attention
    Write-AiBrainRuntimeAttention -Paths $paths -Code $configCode -Action $configAction
  } catch {}
  if ($Action -in @('Status', 'Doctor')) {
    [pscustomobject]@{
      status = 'attention'
      healthy = $false
      issues = @($configCode)
      attentionAction = $configAction
      runtimeAttentionPath = $paths.Attention
      statePreserved = $true
    }
    return
  }
  throw $configCode
}

$controlLock = $null
if ($Action -in @('Status', 'Configure', 'Enable', 'Disable', 'Doctor', 'ApproveBulk', 'Uninstall')) {
  $controlLock = Enter-AiBrainMutex -VaultId ([string]$config.vaultId) -TimeoutMilliseconds 0
  if (-not $controlLock.Acquired) {
    Exit-AiBrainMutex -Lock $controlLock
    throw "CONTROL_RUNTIME_BUSY"
  }
}
try {
$stateResetBackup = $null
try {
  $state = Read-AiBrainState -Paths $paths -Config $config -Repair
} catch {
  $stateCode = Get-AiBrainErrorCode -ErrorRecord $_
  Write-AiBrainLogEvent -Paths $paths -EventCode 'STATE_UNREADABLE' -SafeData @{ code = $stateCode }
  if ($Action -notin @('Status', 'Doctor')) { throw }
  if (-not ($Action -eq 'Doctor' -and $Repair -and $ApproveStateReset)) {
    $ephemeral = New-AiBrainState -Enabled ([bool]$config.enabled)
    $ephemeral.status = 'attention'
    $ephemeral.lastHeartbeatUtc = [DateTime]::UtcNow.ToString('o')
    $ephemeral.attentionCode = $stateCode
    $ephemeral.attentionAction = Get-AiBrainMessage -Name action_state_reset
    Write-AiBrainSleepReport -Config $config -State $ephemeral
    [pscustomobject]@{
      status = 'attention'
      healthy = $false
      issues = @($stateCode)
      attentionAction = $ephemeral.attentionAction
      statePreserved = $true
    }
    return
  }
  $stateResetBackup = Join-Path $paths.Migration ('state-human-gate-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [Guid]::NewGuid().ToString('N'))
  Copy-Item -LiteralPath $paths.State -Destination $stateResetBackup -ErrorAction Stop
  $state = New-AiBrainState -Enabled ([bool]$config.enabled)
  $state.packageId = [string]$config.packageId
  $state.taskGeneration = [string]$config.taskGeneration
  $state.lastRecoveryCode = 'STATE_RESET_APPROVED'
  $state.lastCompileInputFingerprint = $null
  Set-AiBrainState -Paths $paths -State $state
}
switch ($Action) {
  'Status' {
    $doctor = Invoke-AiBrainDoctor -Config $config -Paths $paths -State $state -ApplyRepair
    if (@($doctor.issues) -contains 'HEARTBEAT_STALE' -and
        [bool]$doctor.packageHealthy -and [bool]$doctor.bootstrapHealthy) {
      $taskBeforeHeartbeat = Get-AiBrainTaskStatus -Config $config
      if ($taskBeforeHeartbeat.Exists -and $taskBeforeHeartbeat.Enabled) {
        $previousHeartbeat = [string]$state.lastHeartbeatUtc
        Exit-AiBrainMutex -Lock $controlLock
        $controlLock = $null
        Wait-AiBrainTaskRun -Config $config -Paths $paths -PreviousHeartbeat $previousHeartbeat -TimeoutSeconds ([int]$config.limits.timeoutSeconds + 60) | Out-Null
        $controlLock = Enter-AiBrainMutex -VaultId ([string]$config.vaultId) -TimeoutMilliseconds ([int]$config.limits.requestWaitSeconds * 1000)
        if (-not $controlLock.Acquired) { throw "CONTROL_RUNTIME_BUSY" }
        $state = Read-AiBrainState -Paths $paths -Config $config -Repair
        $state.lastRecoveryCode = 'HEARTBEAT_REVALIDATED'
        Set-AiBrainState -Paths $paths -State $state
        $doctor = Invoke-AiBrainDoctor -Config $config -Paths $paths -State $state -ApplyRepair
      }
    }
    $task = Get-AiBrainTaskStatus -Config $config
    $bulkEstimate = $null
    if ([string]$state.attentionCode -match '^(INITIAL_BULK_|CHANGE_SET_(?:FILE|BYTE)_LIMIT_)') {
      $bulkEstimate = Get-AiBrainBulkEstimate -Config $config
    }
    [pscustomobject]@{
      status = $state.status
      healthy = [bool]$doctor.healthy
      issues = @($doctor.issues)
      enabled = [bool]$config.enabled
      compileEnabled = [bool]$config.compileEnabled
      lintEnabled = [bool]$config.lintEnabled
      compileEveryHours = [int]$config.compileIntervalHours
      lintLocalTime = [string]$config.lintLocalTime
      timeZoneId = [string]$config.timeZoneId
      lastHeartbeatUtc = $state.lastHeartbeatUtc
      lastResultCode = $state.lastResultCode
      lastChangeCount = $state.lastChangeCount
      lastRecoveryCode = $state.lastRecoveryCode
      lastCompileUtc = $state.lastCompileSuccessUtc
      lastLintUtc = $state.lastLintSuccessUtc
      nextCompileUtc = $state.nextCompileUtc
      nextLintUtc = $state.nextLintUtc
      taskState = $task.State
      attentionAction = $state.attentionAction
      bulkEstimate = $bulkEstimate
    }
  }
  'Configure' {
    if (-not $ApproveScheduleChange) { throw "HUMAN_GATE_REQUIRED_SCHEDULE_CHANGE" }
    if ($CompileMinutes -lt 60 -or $CompileMinutes -gt 10080 -or $CompileMinutes % 60 -ne 0) {
      throw "COMPILE_MINUTES_INVALID"
    }
    if ($LintLocalTime -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$') { throw "LINT_TIME_INVALID" }
    $task = Get-AiBrainTaskStatus -Config $config
    if (-not $task.Exists) { throw "TASK_MISSING_RUN_DOCTOR_REPAIR" }
    if (-not [string]::IsNullOrWhiteSpace([string]$config.managedTaskXmlHash) -and
        [string]$task.XmlHash -ne [string]$config.managedTaskXmlHash) {
      throw "TASK_XML_DRIFT"
    }
    $backupRoot = Join-Path $paths.Migration ('schedule-human-gate-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backupRoot -ErrorAction Stop | Out-Null
    $configBackup = Join-Path $backupRoot 'config-before.json'
    $stateBackup = Join-Path $backupRoot 'state-before.json'
    $taskBackup = Join-Path $backupRoot 'task-before.xml'
    Write-AiBrainTextAtomic -Path $configBackup -Text (Read-AiBrainUtf8 -Path $paths.Config)
    Write-AiBrainTextAtomic -Path $stateBackup -Text (Read-AiBrainUtf8 -Path $paths.State)
    Write-AiBrainTextAtomic -Path $taskBackup -Text (Export-AiBrainTaskXml -TaskPath ([string]$config.taskPath) -TaskName ([string]$config.taskName))
    try {
      Disable-ScheduledTask -TaskPath ([string]$config.taskPath) -TaskName ([string]$config.taskName) -ErrorAction Stop | Out-Null
      $config.compileIntervalHours = [int]($CompileMinutes / 60)
      $config.lintLocalTime = $LintLocalTime
      $config.timeZoneId = [TimeZoneInfo]::Local.Id
      $config.taskGeneration = [Guid]::NewGuid().ToString('N')
      $config.lastControlAction = 'configure'
      $state.taskGeneration = $config.taskGeneration
      $compile = Get-AiBrainCompileSlot -NowUtc ([DateTime]::UtcNow) -IntervalHours ([int]$config.compileIntervalHours)
      $lint = Get-AiBrainLintSlot -NowUtc ([DateTime]::UtcNow) -LocalTime ([string]$config.lintLocalTime) -TimeZoneId ([string]$config.timeZoneId)
      $state.lastCompileSlotUtc = $compile.Id
      $state.lastLintSlotId = $lint.Id
      $state.nextCompileUtc = $(if ([bool]$config.enabled -and [bool]$config.compileEnabled) { $compile.NextUtc.ToString('o') } else { $null })
      $state.nextLintUtc = $(if ([bool]$config.enabled -and [bool]$config.lintEnabled) { $lint.NextUtc.ToString('o') } else { $null })
      Test-AiBrainS4UPreflight -Config $config -Paths $paths -BootstrapPath $paths.Bootstrap | Out-Null
      $registered = Register-AiBrainSleepTask -Config $config -BootstrapPath $paths.Bootstrap
      $config.managedTaskXmlHash = $registered.Hash
      Write-AiBrainJsonAtomic -Path $paths.Config -Value $config
      Set-AiBrainState -Paths $paths -State $state
      Write-AiBrainSleepReport -Config $config -State $state
      [pscustomobject]@{
        configured = $true
        compileMinutes = $CompileMinutes
        lintLocalTime = $LintLocalTime
        timeZoneId = $config.timeZoneId
        backupPath = $backupRoot
      }
    } catch {
      $configureError = $_
      Register-AiBrainTaskXml -TaskPath ([string]$config.taskPath) -TaskName ([string]$config.taskName) -Xml (Read-AiBrainUtf8 -Path $taskBackup)
      Write-AiBrainTextAtomic -Path $paths.Config -Text (Read-AiBrainUtf8 -Path $configBackup)
      Write-AiBrainTextAtomic -Path $paths.State -Text (Read-AiBrainUtf8 -Path $stateBackup)
      throw $configureError
    }
  }
  'Enable' {
    $task = Get-AiBrainTaskStatus -Config $config
    if (-not $task.Exists) { throw "TASK_MISSING_RUN_DOCTOR_REPAIR" }
    if (-not [string]::IsNullOrWhiteSpace([string]$config.managedTaskXmlHash) -and [string]$task.XmlHash -ne [string]$config.managedTaskXmlHash) {
      throw "TASK_XML_DRIFT"
    }
    Enable-ScheduledTask -TaskPath ([string]$config.taskPath) -TaskName ([string]$config.taskName) -ErrorAction Stop | Out-Null
    $enabledTask = Get-AiBrainTaskStatus -Config $config
    $config.enabled = $true
    $config.lastControlAction = 'enable'
    $config.managedTaskXmlHash = $enabledTask.XmlHash
    Write-AiBrainJsonAtomic -Path $paths.Config -Value $config
    $state.status = 'ready'
    $compile = Get-AiBrainCompileSlot -NowUtc ([DateTime]::UtcNow) -IntervalHours ([int]$config.compileIntervalHours)
    $lint = Get-AiBrainLintSlot -NowUtc ([DateTime]::UtcNow) -LocalTime ([string]$config.lintLocalTime) -TimeZoneId ([string]$config.timeZoneId)
    $state.nextCompileUtc = $(if ([bool]$config.compileEnabled) { $compile.NextUtc.ToString('o') } else { $null })
    $state.nextLintUtc = $(if ([bool]$config.lintEnabled) { $lint.NextUtc.ToString('o') } else { $null })
    Reset-AiBrainFailure -State $state
    Set-AiBrainState -Paths $paths -State $state
    Write-AiBrainSleepReport -Config $config -State $state
  }
  'Disable' {
    if (-not $ApproveDisable) { throw "HUMAN_GATE_REQUIRED_DISABLE" }
    $currentTask = Get-AiBrainTaskStatus -Config $config
    if ($currentTask.Exists -and -not [string]::IsNullOrWhiteSpace([string]$config.managedTaskXmlHash) -and
        [string]$currentTask.XmlHash -ne [string]$config.managedTaskXmlHash) {
      throw "TASK_XML_DRIFT"
    }
    Disable-ScheduledTask -TaskPath ([string]$config.taskPath) -TaskName ([string]$config.taskName) -ErrorAction SilentlyContinue | Out-Null
    $disabledTask = Get-AiBrainTaskStatus -Config $config
    $config.enabled = $false
    $config.lastControlAction = 'disable'
    if ($disabledTask.Exists) { $config.managedTaskXmlHash = $disabledTask.XmlHash }
    Write-AiBrainJsonAtomic -Path $paths.Config -Value $config
    $state.status = 'off'
    $state.nextCompileUtc = $null
    $state.nextLintUtc = $null
    Set-AiBrainState -Paths $paths -State $state
    Write-AiBrainSleepReport -Config $config -State $state
  }
  'RunNow' {
    if ($state.status -in @('paused', 'attention')) {
      throw "SLEEP_MODE_NOT_READY_RUN_DOCTOR"
    }
    if ([bool]$config.enabled) {
      $task = Get-AiBrainTaskStatus -Config $config
      if (-not $task.Exists -or -not $task.Enabled) { throw "TASK_NOT_READY_RUN_DOCTOR" }
    } else {
      if (-not (Test-Path -LiteralPath $paths.Bootstrap -PathType Leaf)) { throw "BOOTSTRAP_MISSING" }
    }
    $request = New-AiBrainRequest -Paths $paths -Operation $Operation -Scope $Scope
    try {
      if ([bool]$config.enabled) {
        Start-AiBrainRequestWithHandshake -Config $config -Paths $paths -RequestId ([string]$request.requestId)
      } else {
        Start-AiBrainRequestWithHandshake -Config $config -Paths $paths -RequestId ([string]$request.requestId) -Direct
      }
    } catch {
      Fail-AiBrainPendingRequest -Paths $paths -RequestId ([string]$request.requestId) -ResultCode 'launch_failed' | Out-Null
      throw
    }
  }
  'Doctor' {
    $doctor = Invoke-AiBrainDoctor -Config $config -Paths $paths -State $state -ApplyRepair:$Repair -AllowAttentionClear
    if ($Repair -and @($doctor.issues) -contains 'HEARTBEAT_STALE' -and
        [bool]$doctor.packageHealthy -and [bool]$doctor.bootstrapHealthy) {
      $taskBeforeHeartbeat = Get-AiBrainTaskStatus -Config $config
      if ($taskBeforeHeartbeat.Exists -and $taskBeforeHeartbeat.Enabled) {
        $previousHeartbeat = [string]$state.lastHeartbeatUtc
        Exit-AiBrainMutex -Lock $controlLock
        $controlLock = $null
        Wait-AiBrainTaskRun -Config $config -Paths $paths -PreviousHeartbeat $previousHeartbeat -TimeoutSeconds ([int]$config.limits.timeoutSeconds + 60) | Out-Null
        $controlLock = Enter-AiBrainMutex -VaultId ([string]$config.vaultId) -TimeoutMilliseconds ([int]$config.limits.requestWaitSeconds * 1000)
        if (-not $controlLock.Acquired) { throw "CONTROL_RUNTIME_BUSY" }
        $state = Read-AiBrainState -Paths $paths -Config $config -Repair
        $state.lastRecoveryCode = 'HEARTBEAT_REVALIDATED'
        Set-AiBrainState -Paths $paths -State $state
        $doctor = Invoke-AiBrainDoctor -Config $config -Paths $paths -State $state -ApplyRepair -AllowAttentionClear
      }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$stateResetBackup)) {
      $doctor | Add-Member -NotePropertyName stateResetBackupPath -NotePropertyValue $stateResetBackup -Force
    }
    $doctor
  }
  'ApproveBulk' {
    if ([string]$state.attentionCode -notmatch '^(INITIAL_BULK_|CHANGE_SET_(?:FILE|BYTE)_LIMIT_)' -and
        -not [string]::IsNullOrWhiteSpace([string]$state.lastCompileSuccessUtc)) {
      throw "BULK_APPROVAL_NOT_REQUIRED"
    }
    $estimate = Get-AiBrainBulkEstimate -Config $config
    $approvedFiles = $(if ($BulkMaxFiles -gt 0) { $BulkMaxFiles } else {
      [int]$estimate.proposedMaxChangeFiles
    })
    $approvedBytes = $(if ($BulkMaxBytes -gt 0) { $BulkMaxBytes } else {
      [long]$estimate.proposedMaxChangeBytes
    })
    if ($approvedFiles -lt [int]$config.limits.maxChangeFiles -or
        $approvedBytes -lt [long]$config.limits.maxChangeBytes) { throw "BULK_APPROVAL_LIMIT_INVALID" }
    Set-AiBrainProperty -Object $config -Name 'bulkApproval' -Value ([ordered]@{
      approvedUtc = [DateTime]::UtcNow.ToString('o')
      expiresUtc = [DateTime]::UtcNow.AddHours(24).ToString('o')
      estimatedSourceFiles = [int]$estimate.estimatedSourceFiles
      estimatedSourceBytes = [long]$estimate.estimatedSourceBytes
      maxChangeFiles = $approvedFiles
      maxChangeBytes = $approvedBytes
      consumed = $false
      consumedUtc = $null
    })
    Assert-AiBrainConfig -Config $config | Out-Null
    Write-AiBrainJsonAtomic -Path $paths.Config -Value $config
    $state.status = $(if ([bool]$config.enabled) { 'ready' } else { 'off' })
    Reset-AiBrainFailure -State $state
    Set-AiBrainState -Paths $paths -State $state
    Write-AiBrainSleepReport -Config $config -State $state
    [pscustomobject]@{
      approved = $true
      estimatedSourceFiles = [int]$estimate.estimatedSourceFiles
      estimatedSourceBytes = [long]$estimate.estimatedSourceBytes
      maxChangeFiles = $approvedFiles
      maxChangeBytes = $approvedBytes
      expiresUtc = $config.bulkApproval.expiresUtc
    }
  }
  'Uninstall' {
    if (-not $ApproveUninstall) { throw "HUMAN_GATE_REQUIRED_UNINSTALL" }
    Uninstall-AiBrainSleep -Config $config -Paths $paths -State $state
  }
}
} finally {
  Exit-AiBrainMutex -Lock $controlLock
}
