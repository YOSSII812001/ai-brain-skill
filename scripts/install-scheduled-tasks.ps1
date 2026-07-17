[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$RuntimeRoot,
  [switch]$Apply,
  [switch]$SkipLegacyMigration,
  [switch]$SkipTestRun,
  [switch]$NoExit
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$libraryRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libraryRoot 'AiBrain.Common.ps1')
. (Join-Path $libraryRoot 'AiBrain.Process.ps1')
. (Join-Path $libraryRoot 'AiBrain.Tasks.ps1')

function Get-RegisteredObsidianVaultPaths {
  $appData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
  if ([string]::IsNullOrWhiteSpace($appData)) { return @() }
  $registryPath = Join-Path $appData 'obsidian\obsidian.json'
  if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { return @() }
  try {
    $registry = Read-AiBrainJson -Path $registryPath
  } catch {
    return @()
  }
  $result = New-Object System.Collections.ArrayList
  $vaults = Get-AiBrainProperty -Object $registry -Name 'vaults' -Default $null
  if ($null -eq $vaults) { return @() }
  foreach ($property in @($vaults.PSObject.Properties)) {
    $candidate = [string](Get-AiBrainProperty -Object $property.Value -Name 'path' -Default '')
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    try {
      [void]$result.Add((Get-AiBrainCanonicalPath -Path $candidate -MustExist))
    } catch {
      continue
    }
  }
  return @($result | Select-Object -Unique)
}

function Test-LegacyAiBrainTaskTargetsConfig {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Xml
  )
  $scriptName = $(if ($Operation -eq 'compile') { 'wiki-compile-scheduled.ps1' } else { 'wiki-lint-scheduled.ps1' })
  $commandName = $(if ($Operation -eq 'compile') { 'wiki-compile.md' } else { 'wiki-lint.md' })
  $expectedScript = Join-Path $HOME ('.claude\scripts\' + $scriptName)
  $expectedCommand = Join-Path $HOME ('.claude\commands\' + $commandName)
  if (-not (Test-Path -LiteralPath $expectedScript -PathType Leaf) -or
      -not (Test-Path -LiteralPath $expectedCommand -PathType Leaf)) {
    return $false
  }
  $commandText = Read-AiBrainUtf8 -Path $expectedCommand
  return Test-AiBrainLegacyTaskContract `
    -Xml $Xml `
    -ExpectedScriptPath $expectedScript `
    -ExpectedVaultPath ([string]$Config.vaultPath) `
    -CommandText $commandText `
    -RegisteredVaultPaths @(Get-RegisteredObsidianVaultPaths)
}

function Get-LegacyAiBrainSchedule {
  param(
    [Parameter(Mandatory = $true)][string]$Xml,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation
  )
  $document = New-Object Xml.XmlDocument
  $document.PreserveWhitespace = $true
  $document.LoadXml($Xml)
  if ($Operation -eq 'compile') {
    $nodes = @($document.SelectNodes('//*[local-name()="TimeTrigger"]/*[local-name()="Repetition"]/*[local-name()="Interval"]'))
    if ($nodes.Count -ne 1) { throw "LEGACY_COMPILE_SCHEDULE_AMBIGUOUS" }
    try { $interval = [Xml.XmlConvert]::ToTimeSpan([string]$nodes[0].InnerText) } catch { throw "LEGACY_COMPILE_SCHEDULE_INVALID" }
    if ($interval.TotalHours -lt 1 -or $interval.TotalHours -gt 168 -or $interval.TotalHours -ne [Math]::Floor($interval.TotalHours)) {
      throw "LEGACY_COMPILE_SCHEDULE_UNSUPPORTED"
    }
    return [pscustomobject]@{ CompileHours = [int]$interval.TotalHours; LintTime = $null }
  }
  $nodes = @($document.SelectNodes('//*[local-name()="CalendarTrigger"]/*[local-name()="StartBoundary"]'))
  if ($nodes.Count -ne 1) { throw "LEGACY_LINT_SCHEDULE_AMBIGUOUS" }
  $boundary = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse([string]$nodes[0].InnerText, [ref]$boundary)) { throw "LEGACY_LINT_SCHEDULE_INVALID" }
  return [pscustomobject]@{ CompileHours = $null; LintTime = $boundary.ToString('HH:mm') }
}

function Test-LegacyAiBrainTaskAlreadyMigrated {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$TaskPath,
    [Parameter(Mandatory = $true)][string]$TaskName,
    [Parameter(Mandatory = $true)][string]$CurrentXmlHash
  )
  foreach ($directory in Get-ChildItem -LiteralPath $Paths.Migration -Directory -Filter 'sleep-migration-*' -ErrorAction SilentlyContinue) {
    $journal = Read-AiBrainJson -Path (Join-Path $directory.FullName 'migration.json') -Optional
    if ($null -eq $journal -or [string]$journal.status -ne 'committed') { continue }
    foreach ($record in @($journal.legacyTasks)) {
      if ([string]$record.taskPath -eq $TaskPath -and
          [string]$record.taskName -eq $TaskName -and
          -not [string]::IsNullOrWhiteSpace([string]$record.disabledXmlHash) -and
          [string]$record.disabledXmlHash -eq $CurrentXmlHash) {
        return $true
      }
    }
  }
  return $false
}

function Get-LegacyAiBrainTasks {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths
  )
  $definitions = @(
    @{ operation = 'compile'; taskPath = '\Claude Code\'; taskName = 'Claude Wiki Compile'; commandName = 'wiki-compile.md'; scriptName = 'wiki-compile-scheduled.ps1' },
    @{ operation = 'lint'; taskPath = '\Claude Code\'; taskName = 'Claude Wiki Lint'; commandName = 'wiki-lint.md'; scriptName = 'wiki-lint-scheduled.ps1' }
  )
  $result = New-Object System.Collections.ArrayList
  foreach ($definition in $definitions) {
    $task = Get-ScheduledTask -TaskPath $definition.taskPath -TaskName $definition.taskName -ErrorAction SilentlyContinue
    if ($null -eq $task) { continue }
    $xml = Export-ScheduledTask -TaskPath $definition.taskPath -TaskName $definition.taskName
    $currentXmlHash = Get-AiBrainTaskXmlHash -Xml $xml
    if (Test-LegacyAiBrainTaskAlreadyMigrated `
        -Paths $Paths `
        -TaskPath ([string]$definition.taskPath) `
        -TaskName ([string]$definition.taskName) `
        -CurrentXmlHash $currentXmlHash) {
      continue
    }
    $targetsVault = Test-LegacyAiBrainTaskTargetsConfig `
      -Config $Config `
      -Operation ([string]$definition.operation) `
      -Xml $xml
    if (-not $targetsVault) {
      Write-Warning ("Skipping legacy task that does not provably target this vault: {0}{1}" -f $definition.taskPath, $definition.taskName)
      continue
    }
    $schedule = Get-LegacyAiBrainSchedule -Xml $xml -Operation ([string]$definition.operation)
    [void]$result.Add([pscustomobject]@{
      operation = [string]$definition.operation
      taskPath = $definition.taskPath
      taskName = $definition.taskName
      state = [string]$task.State
      enabled = [string]$task.State -ne 'Disabled'
      xml = $xml
      xmlHash = $currentXmlHash
      disabledXmlHash = $null
      compileHours = $schedule.CompileHours
      lintTime = $schedule.LintTime
    })
  }
  return @($result)
}

function Save-LegacyAiBrainTasks {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Tasks,
    [Parameter(Mandatory = $true)][string]$MigrationId
  )
  $root = Join-Path $Paths.Migration $MigrationId
  New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
  $records = New-Object System.Collections.ArrayList
  foreach ($task in $Tasks) {
    $safeName = ([string]$task.taskName -replace '[^A-Za-z0-9_-]', '_')
    $xmlName = "$safeName.xml"
    Write-AiBrainTextAtomic -Path (Join-Path $root $xmlName) -Text ([string]$task.xml)
    [void]$records.Add([ordered]@{
      operation = $task.operation
      taskPath = $task.taskPath
      taskName = $task.taskName
      state = $task.state
      enabled = $task.enabled
      xmlHash = $task.xmlHash
      xmlFile = $xmlName
      disabledXmlHash = $null
      compileHours = $task.compileHours
      lintTime = $task.lintTime
    })
  }
  return [pscustomobject]@{ Root = $root; Records = @($records) }
}

function Apply-LegacyAiBrainPreferences {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LegacyTasks
  )
  $changed = $false
  foreach ($legacy in $LegacyTasks) {
    if ([string]$legacy.operation -eq 'compile') {
      $Config.compileEnabled = [bool]$legacy.enabled
      if ([int]$legacy.compileHours -ne 3) { $Config.compileIntervalHours = [int]$legacy.compileHours }
      $changed = $true
    } elseif ([string]$legacy.operation -eq 'lint') {
      $Config.lintEnabled = [bool]$legacy.enabled
      if ([string]$legacy.lintTime -ne '17:00') { $Config.lintLocalTime = [string]$legacy.lintTime }
      $changed = $true
    }
  }
  if (-not $changed) { return $false }
  $Config.timeZoneId = [TimeZoneInfo]::Local.Id
  $Config.lastControlAction = 'legacy-preferences-migrated'
  Write-AiBrainJsonAtomic -Path $Paths.Config -Value $Config
  $state = Read-AiBrainState -Paths $Paths -Config $Config -Repair
  $now = [DateTime]::UtcNow
  $compile = Get-AiBrainCompileSlot -NowUtc $now -IntervalHours ([int]$Config.compileIntervalHours)
  $lint = Get-AiBrainLintSlot -NowUtc $now -LocalTime ([string]$Config.lintLocalTime) -TimeZoneId ([string]$Config.timeZoneId)
  $state.lastCompileSlotUtc = $compile.Id
  $state.lastLintSlotId = $lint.Id
  $state.nextCompileUtc = $(if ([bool]$Config.enabled -and [bool]$Config.compileEnabled) { $compile.NextUtc.ToString('o') } else { $null })
  $state.nextLintUtc = $(if ([bool]$Config.enabled -and [bool]$Config.lintEnabled) { $lint.NextUtc.ToString('o') } else { $null })
  Set-AiBrainState -Paths $Paths -State $state
  return $true
}

function Set-AiBrainMigrationJournal {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Journal, [Parameter(Mandatory = $true)][string]$Status)
  $Journal.status = $Status
  $Journal.updatedUtc = [DateTime]::UtcNow.ToString('o')
  Write-AiBrainJsonAtomic -Path $Path -Value $Journal
}

function Test-LegacyAiBrainProcessActive {
  try {
    foreach ($process in Get-CimInstance Win32_Process -ErrorAction Stop) {
      $commandLine = [string]$process.CommandLine
      if ($commandLine -match '(?i)(wiki-compile-scheduled\.ps1|wiki-lint-scheduled\.ps1|(?:-p|--print)\s+["'']?/wiki-(?:compile|lint))') {
        return $true
      }
    }
  } catch {
    throw "LEGACY_PROCESS_ENUMERATION_FAILED"
  }
  return $false
}

function Wait-LegacyAiBrainQuiet {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LegacyTasks,
    [int]$TimeoutSeconds
  )
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    $running = $false
    foreach ($legacy in $LegacyTasks) {
      $task = Get-ScheduledTask -TaskPath $legacy.taskPath -TaskName $legacy.taskName -ErrorAction SilentlyContinue
      if ($null -ne $task -and [string]$task.State -eq 'Running') { $running = $true }
    }
    $legacyLock = Join-Path ([string]$Config.vaultPath) 'wiki\_meta\.lock'
    if (-not $running -and -not (Test-LegacyAiBrainProcessActive) -and -not (Test-Path -LiteralPath $legacyLock)) {
      $first = Get-AiBrainManifestFingerprint (Get-AiBrainVaultManifest -VaultPath ([string]$Config.vaultPath))
      Start-Sleep -Seconds 2
      $second = Get-AiBrainManifestFingerprint (Get-AiBrainVaultManifest -VaultPath ([string]$Config.vaultPath))
      if ($first -eq $second) { return $true }
    }
    Start-Sleep -Milliseconds 500
  }
  throw "LEGACY_TASK_NOT_QUIET"
}

function Disable-LegacyAiBrainTasks {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LegacyTasks, [Parameter(Mandatory = $true)][object]$Saved)
  foreach ($legacy in $LegacyTasks) {
    Disable-ScheduledTask -TaskPath $legacy.taskPath -TaskName $legacy.taskName -ErrorAction Stop | Out-Null
    $disabledXml = Export-ScheduledTask -TaskPath $legacy.taskPath -TaskName $legacy.taskName
    $disabledHash = Get-AiBrainTaskXmlHash -Xml $disabledXml
    $record = @($Saved.Records | Where-Object { $_.taskPath -eq $legacy.taskPath -and $_.taskName -eq $legacy.taskName })[0]
    $record.disabledXmlHash = $disabledHash
  }
}

function Restore-LegacyAiBrainTasks {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Saved
  )
  foreach ($record in @($Saved.Records)) {
    $task = Get-ScheduledTask -TaskPath $record.taskPath -TaskName $record.taskName -ErrorAction SilentlyContinue
    if ($null -ne $task -and -not [string]::IsNullOrWhiteSpace([string]$record.disabledXmlHash)) {
      $currentXml = Export-ScheduledTask -TaskPath $record.taskPath -TaskName $record.taskName
      $currentHash = Get-AiBrainTaskXmlHash -Xml $currentXml
      if ($currentHash -ne [string]$record.disabledXmlHash) { throw "LEGACY_TASK_EXTERNAL_CHANGE" }
    }
    $originalXml = Read-AiBrainVerifiedTaskXml `
      -Path (Join-Path $Saved.Root ([string]$record.xmlFile)) `
      -ExpectedHash ([string]$record.xmlHash) `
      -FailureCode 'LEGACY_TASK_BACKUP_HASH_MISMATCH'
    if (-not (Test-LegacyAiBrainTaskTargetsConfig `
        -Config $Config `
        -Operation ([string]$record.operation) `
        -Xml $originalXml)) {
      throw "LEGACY_TASK_BACKUP_CONTRACT_INVALID"
    }
    Register-ScheduledTask -TaskPath ([string]$record.taskPath) -TaskName ([string]$record.taskName) -Xml $originalXml -Force | Out-Null
    if (-not [bool]$record.enabled) {
      Disable-ScheduledTask -TaskPath ([string]$record.taskPath) -TaskName ([string]$record.taskName) | Out-Null
    }
  }
}

function Remove-MigratedLegacyAiBrainTasks {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$LegacyTasks)
  foreach ($legacy in $LegacyTasks) {
    Unregister-ScheduledTask `
      -TaskPath ([string]$legacy.taskPath) `
      -TaskName ([string]$legacy.taskName) `
      -Confirm:$false `
      -ErrorAction Stop
    if ($null -ne (Get-ScheduledTask -TaskPath ([string]$legacy.taskPath) -TaskName ([string]$legacy.taskName) -ErrorAction SilentlyContinue)) {
      throw "LEGACY_TASK_REMOVE_FAILED"
    }
  }
}

function Save-ManagedAiBrainTask {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$Root
  )
  $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction SilentlyContinue
  if ($null -eq $task) {
    return [ordered]@{ existed = $false; enabled = $false; xmlFile = $null; xmlHash = $null }
  }
  $xml = Export-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName)
  Write-AiBrainTextAtomic -Path (Join-Path $Root 'managed-task.xml') -Text $xml
  return [ordered]@{
    existed = $true
    enabled = [string]$task.State -ne 'Disabled'
    xmlFile = 'managed-task.xml'
    xmlHash = Get-AiBrainTaskXmlHash -Xml $xml
  }
}

function Restore-ManagedAiBrainTask {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$Record
  )
  if ([bool]$Record.existed) {
    $xml = Read-AiBrainVerifiedTaskXml `
      -Path (Join-Path $Root ([string]$Record.xmlFile)) `
      -ExpectedHash ([string]$Record.xmlHash) `
      -FailureCode 'MANAGED_TASK_BACKUP_HASH_MISMATCH'
    $runtimePaths = Get-AiBrainRuntimePaths -RuntimeRoot ([string]$Config.runtimeRoot)
    Test-AiBrainTaskXmlContract `
      -Xml $xml `
      -CompileIntervalHours ([int]$Config.compileIntervalHours) `
      -ExpectedBootstrapPath ([string]$runtimePaths.Bootstrap) `
      -ExpectedRuntimeRoot ([string]$Config.runtimeRoot) | Out-Null
    Register-AiBrainTaskXml -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -Xml $xml
    if (-not [bool]$Record.enabled) {
      Disable-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop | Out-Null
    }
  } else {
    Unregister-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -Confirm:$false -ErrorAction SilentlyContinue
  }
}

function Repair-IncompleteAiBrainMigrations {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths
  )
  foreach ($directory in Get-ChildItem -LiteralPath $Paths.Migration -Directory -Filter 'sleep-migration-*' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTimeUtc) {
    $journalPath = Join-Path $directory.FullName 'migration.json'
    if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) { continue }
    $journal = Read-AiBrainJson -Path $journalPath
    if ([string]$journal.status -in @('committed', 'rolled_back', 'recovered')) { continue }
    if ([string]$journal.vaultId -ne [string]$Config.vaultId -or
        [string]$journal.taskGeneration -ne [string]$Config.taskGeneration) {
      throw "MIGRATION_RECOVERY_IDENTITY_MISMATCH"
    }
    $saved = [pscustomobject]@{ Root = $directory.FullName; Records = @($journal.legacyTasks) }
    Restore-ManagedAiBrainTask -Config $Config -Root $directory.FullName -Record $journal.managedTask
    Restore-LegacyAiBrainTasks -Config $Config -Saved $saved
    $configBackup = Join-Path $directory.FullName 'config-before.json'
    if (Test-Path -LiteralPath $configBackup -PathType Leaf) {
      Write-AiBrainTextAtomic -Path $Paths.Config -Text (Read-AiBrainUtf8 -Path $configBackup)
    }
    $stateBackup = Join-Path $directory.FullName 'state-before.json'
    if (Test-Path -LiteralPath $stateBackup -PathType Leaf) {
      Write-AiBrainTextAtomic -Path $Paths.State -Text (Read-AiBrainUtf8 -Path $stateBackup)
    }
    Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'recovered'
  }
}

$paths = Get-AiBrainRuntimePaths -RuntimeRoot $RuntimeRoot
$config = Read-AiBrainJson -Path $paths.Config
Assert-AiBrainConfig -Config $config | Out-Null
$bootstrap = $paths.Bootstrap
if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) { throw "BOOTSTRAP_MISSING" }

Write-Host "Task: $($config.taskPath)$($config.taskName)"
Write-Host "compile: every $($config.compileIntervalHours) hours"
Write-Host "lint: daily at $($config.lintLocalTime)"
Write-Host 'principal: S4U / Limited'
Write-Host 'window: non-interactive S4U + hidden parent + CreateNoWindow child'
if (-not $Apply) {
  Write-Host 'DRY RUN. Add -Apply to preflight, migrate legacy tasks, and register the sleep task.'
  if ($NoExit) { return }
  exit 0
}

$migrationLock = Enter-AiBrainMutex -VaultId ([string]$config.vaultId) -TimeoutMilliseconds 0
if (-not $migrationLock.Acquired) {
  Exit-AiBrainMutex -Lock $migrationLock
  throw "SCHEDULER_MIGRATION_BUSY"
}
try {
  Repair-IncompleteAiBrainMigrations -Config $config -Paths $paths
  $config = Read-AiBrainJson -Path $paths.Config
  Assert-AiBrainConfig -Config $config | Out-Null

  $migrationId = 'sleep-migration-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
  [object[]]$legacyTasks = @()
  if (-not $SkipLegacyMigration) {
    $legacyTasks = @(Get-LegacyAiBrainTasks -Config $config -Paths $paths)
  }
  $saved = Save-LegacyAiBrainTasks -Paths $paths -Tasks @($legacyTasks) -MigrationId $migrationId
  Write-AiBrainTextAtomic -Path (Join-Path $saved.Root 'config-before.json') -Text (Read-AiBrainUtf8 -Path $paths.Config)
  Write-AiBrainTextAtomic -Path (Join-Path $saved.Root 'state-before.json') -Text (Read-AiBrainUtf8 -Path $paths.State)
  $managedTask = Save-ManagedAiBrainTask -Config $config -Root $saved.Root
  $journalPath = Join-Path $saved.Root 'migration.json'
  $journal = [ordered]@{
    schemaVersion = 1
    migrationId = $migrationId
    vaultId = [string]$config.vaultId
    taskGeneration = [string]$config.taskGeneration
    status = 'inventory'
    createdUtc = [DateTime]::UtcNow.ToString('o')
    packageId = [string]$config.packageId
    legacyTasks = $saved.Records
    managedTask = $managedTask
  }
  Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'inventory'

  try {
    Apply-LegacyAiBrainPreferences -Config $config -Paths $paths -LegacyTasks $legacyTasks | Out-Null
    Test-AiBrainS4UPreflight -Config $config -Paths $paths -BootstrapPath $bootstrap | Out-Null
    Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'preflighted'

    if ($legacyTasks.Count -gt 0) {
      Disable-LegacyAiBrainTasks -LegacyTasks $legacyTasks -Saved $saved
      $journal.legacyTasks = $saved.Records
      Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'old_disabled'
      Wait-LegacyAiBrainQuiet -Config $config -LegacyTasks $legacyTasks -TimeoutSeconds ([int]$config.limits.legacyWaitSeconds) | Out-Null
    }

    $registered = Register-AiBrainSleepTask -Config $config -BootstrapPath $bootstrap
    $config.managedTaskXmlHash = $registered.Hash
    $config.lastControlAction = 'install'
    Write-AiBrainJsonAtomic -Path $paths.Config -Value $config
    Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'new_registered'

    $taskStatus = Get-AiBrainTaskStatus -Config $config
    if (-not $taskStatus.Exists -or
        [bool]$taskStatus.Enabled -ne [bool]$config.enabled -or
        [string]$taskStatus.XmlHash -ne [string]$registered.Hash) {
      throw "SLEEP_TASK_REGISTRATION_VERIFY_FAILED"
    }
    if (-not $SkipTestRun -and [bool]$config.enabled) {
      $testState = Read-AiBrainState -Paths $paths -Config $config -Repair
      # The test task needs the same vault mutex. Release the migration lock
      # only after the old tasks are disabled and the new task is verified.
      Exit-AiBrainMutex -Lock $migrationLock
      $migrationLock = $null
      try {
        Wait-AiBrainTaskRun `
          -Config $config `
          -Paths $paths `
          -PreviousHeartbeat ([string]$testState.lastHeartbeatUtc) `
          -TimeoutSeconds ([int]$config.limits.requestWaitSeconds) | Out-Null
      } catch {
        Stop-ScheduledTask -TaskPath ([string]$config.taskPath) -TaskName ([string]$config.taskName) -ErrorAction SilentlyContinue
        throw
      } finally {
        $migrationLock = Enter-AiBrainMutex `
          -VaultId ([string]$config.vaultId) `
          -TimeoutMilliseconds ([int]$config.limits.requestWaitSeconds * 1000)
        if (-not $migrationLock.Acquired) { throw "SCHEDULER_MIGRATION_RELOCK_FAILED" }
      }
      Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'test_run_passed'
    }
    if ($legacyTasks.Count -gt 0) {
      Remove-MigratedLegacyAiBrainTasks -LegacyTasks $legacyTasks
      Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'old_removed'
    }
    $installedState = Read-AiBrainState -Paths $paths -Config $config -Repair
    if (Clear-AiBrainAttentionIfCode `
        -State $installedState `
        -ExpectedCode 'SCHEDULER_INSTALL_FAILED' `
        -Enabled ([bool]$config.enabled) `
        -RecoveryCode 'SCHEDULER_INSTALL_RECOVERED') {
      Set-AiBrainState -Paths $paths -State $installedState
      Write-AiBrainSleepReport -Config $config -State $installedState
    }
    Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'verified'
    Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'committed'
    Write-Host 'PASS registered one S4U sleep task with compile and lint triggers'
    if ($NoExit) { return }
    exit 0
  } catch {
    $installError = $_
    try {
      Restore-ManagedAiBrainTask -Config $config -Root $saved.Root -Record $managedTask
      if ($legacyTasks.Count -gt 0) { Restore-LegacyAiBrainTasks -Config $config -Saved $saved }
      Write-AiBrainTextAtomic -Path $paths.Config -Text (Read-AiBrainUtf8 -Path (Join-Path $saved.Root 'config-before.json'))
      Write-AiBrainTextAtomic -Path $paths.State -Text (Read-AiBrainUtf8 -Path (Join-Path $saved.Root 'state-before.json'))
      Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'rolled_back'
    } catch {
      Set-AiBrainMigrationJournal -Path $journalPath -Journal $journal -Status 'attention'
    }
    $state = Read-AiBrainState -Paths $paths
    Set-AiBrainAttention -Paths $paths -State $state -Code 'SCHEDULER_INSTALL_FAILED' -Action (Get-AiBrainMessage -Name action_admin)
    if ($NoExit) { throw $installError }
    $installCode = Get-AiBrainErrorCode -ErrorRecord $installError
    Write-Warning ("Scheduled task installation failed without interactive fallback: {0}" -f $installCode)
    Write-Error -ErrorRecord $installError
    exit 1
  }
} finally {
  Exit-AiBrainMutex -Lock $migrationLock
}
