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

$libraryRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libraryRoot 'AiBrain.Common.ps1')
. (Join-Path $libraryRoot 'AiBrain.Schedule.ps1')
. (Join-Path $libraryRoot 'AiBrain.Process.ps1')
. (Join-Path $libraryRoot 'AiBrain.Transaction.ps1')
. (Join-Path $libraryRoot 'AiBrain.Requests.ps1')

function Invoke-AiBrainPreflight {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$Token
  )
  if ($Token -notmatch '^[a-f0-9]{32}$') { throw "PREFLIGHT_TOKEN_INVALID" }
  Assert-AiBrainConfig -Config $Config | Out-Null
  Get-ChildItem -LiteralPath ([string]$Config.vaultPath) -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null
  $scratch = Join-Path $Paths.Staging ('preflight-' + $Token)
  New-Item -ItemType Directory -Path $scratch -ErrorAction Stop | Out-Null
  try {
    Test-AiBrainAgentAuthentication -Config $Config -ScratchDirectory $scratch | Out-Null
  } finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
  }
  $result = [ordered]@{
    schemaVersion = 1
    token = $Token
    success = $true
    timestampUtc = [DateTime]::UtcNow.ToString('o')
  }
  Write-AiBrainJsonAtomic -Path (Join-Path $Paths.Migration "preflight-$Token.json") -Value $result
}

function Complete-AiBrainRecoveredJournal {
  param(
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$Recovery
  )
  $journal = $Recovery.journal
  $slotId = [string](Get-AiBrainProperty $journal 'slotId' '')
  if ([string]$journal.operation -eq 'compile' -and -not [string]::IsNullOrWhiteSpace($slotId)) {
    Complete-AiBrainOperationSlot -State $State -Operation compile -SlotId ([string]$journal.slotId)
    $State.lastCompileInputFingerprint = [string]$journal.finalFingerprint
  } elseif ([string]$journal.operation -eq 'lint' -and -not [string]::IsNullOrWhiteSpace($slotId)) {
    Complete-AiBrainOperationSlot -State $State -Operation lint -SlotId ([string]$journal.slotId)
  }
  Set-AiBrainState -Paths $Paths -State $State
  Complete-AiBrainJournal -JournalPath ([string]$Recovery.path)
}

function Get-AiBrainOperationFailureKind {
  param([Parameter(Mandatory = $true)][string]$Code)
  if ($Code -match '^(AGENT_AUTH_REQUIRED|CONFIG_|CONSENT_|RUNTIME_|VAULT_|STATE_|JSON_|NETWORK_|LOCAL_|REPARSE_|DISK_|PACKAGE_|STAGING_|INITIAL_BULK_|CHANGE_SET_(?:FILE|BYTE)_LIMIT_|ROLLBACK_EXTERNAL_EDIT_CONFLICT|EXTERNAL_EDIT_CONFLICT|AGENT_TREE_UNCONFIRMED|JOB_)') {
    return 'attention'
  }
  return 'failure'
}

function Get-AiBrainAttentionAction {
  param([Parameter(Mandatory = $true)][string]$Code)
  if ($Code -eq 'AGENT_AUTH_REQUIRED') { return Get-AiBrainMessage -Name action_auth }
  if ($Code -match 'EXTERNAL_EDIT_CONFLICT') { return Get-AiBrainMessage -Name action_edit }
  if ($Code -match '^(INITIAL_BULK_|CHANGE_SET_(?:FILE|BYTE)_LIMIT_)') { return Get-AiBrainMessage -Name action_bulk }
  if ($Code -eq 'VAULT_NOT_FOUND_OR_MOVED') { return Get-AiBrainMessage -Name action_vault }
  return Get-AiBrainMessage -Name action_doctor
}

function Set-AiBrainLastResult {
  param(
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][string]$Code,
    [string]$Operation,
    [int]$ChangeCount = 0,
    [int]$NewConceptCount = 0,
    [int]$LinkFixCount = 0,
    [int]$MetadataFixCount = 0,
    [string]$SkipReason
  )
  $State.lastResultCode = $Code
  $State.lastResultOperation = $Operation
  $State.lastChangeCount = $ChangeCount
  $State.lastNewConceptCount = $NewConceptCount
  $State.lastLinkFixCount = $LinkFixCount
  $State.lastMetadataFixCount = $MetadataFixCount
  $State.lastSkipReason = $SkipReason
  $State.lastRunCompletedUtc = [DateTime]::UtcNow.ToString('o')
}

function Get-AiBrainChangeSummary {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$ChangeSet,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$BaselineManifest
  )
  $known = @{}
  foreach ($entry in $BaselineManifest) { $known[[string]$entry.path.ToLowerInvariant()] = $true }
  [int]$newConcepts = 0
  [int]$linkFiles = 0
  [int]$metadataFiles = 0
  foreach ($change in @($ChangeSet.changes)) {
    if ([string]$change.action -ne 'write') { continue }
    $relative = ([string]$change.path).Replace('\', '/')
    $key = $relative.ToLowerInvariant()
    if ($relative -like 'wiki/concepts/*.md' -and -not $known.ContainsKey($key)) { $newConcepts++ }
    $oldText = ''
    $oldPath = Join-Path ([string]$Config.vaultPath) $relative.Replace('/', '\')
    if (Test-Path -LiteralPath $oldPath -PathType Leaf) { $oldText = Read-AiBrainUtf8 -Path $oldPath }
    $newText = [string]$change.content
    $oldLinks = @([regex]::Matches($oldText, '\[\[[^\]]+\]\]') | ForEach-Object Value | Sort-Object)
    $newLinks = @([regex]::Matches($newText, '\[\[[^\]]+\]\]') | ForEach-Object Value | Sort-Object)
    if (($oldLinks -join "`n") -ne ($newLinks -join "`n")) { $linkFiles++ }
    $oldFrontmatter = [regex]::Match($oldText, '\A---\r?\n.*?\r?\n---', [Text.RegularExpressions.RegexOptions]::Singleline).Value
    $newFrontmatter = [regex]::Match($newText, '\A---\r?\n.*?\r?\n---', [Text.RegularExpressions.RegexOptions]::Singleline).Value
    if ($oldFrontmatter -ne $newFrontmatter) { $metadataFiles++ }
  }
  return [pscustomobject]@{
    NewConceptCount = $newConcepts
    LinkFixCount = $linkFiles
    MetadataFixCount = $metadataFiles
  }
}

function Write-AiBrainProcessTechnicalLogs {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][object]$ProcessResult
  )
  foreach ($entry in @(
    [pscustomobject]@{ Name = 'stdout'; Capture = $ProcessResult.StdOut },
    [pscustomobject]@{ Name = 'stderr'; Capture = $ProcessResult.StdErr }
  )) {
    $text = [string](Get-AiBrainProperty $entry.Capture 'Text' '')
    $record = @(
      'encoding=utf-8',
      ('stream={0}' -f $entry.Name),
      ('capturedBytes={0}' -f [long](Get-AiBrainProperty $entry.Capture 'Bytes' 0)),
      ('truncated={0}' -f [bool](Get-AiBrainProperty $entry.Capture 'Truncated' $false)),
      ('sha256={0}' -f (Get-AiBrainStringSha256 -Text $text)),
      'content=withheld-by-privacy-contract'
    )
    Write-AiBrainTextAtomic `
      -Path (Join-Path $Paths.Logs ("process-{0}.{1}.log" -f $RunId, $entry.Name)) `
      -Text (($record -join "`n") + "`n")
  }
}

function Test-AiBrainBulkApprovalActive {
  param([Parameter(Mandatory = $true)][object]$Config)
  $approval = Get-AiBrainProperty $Config 'bulkApproval' $null
  if ($null -eq $approval -or [bool](Get-AiBrainProperty $approval 'consumed' $true)) { return $false }
  $expires = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse([string](Get-AiBrainProperty $approval 'expiresUtc' ''), [ref]$expires)) { return $false }
  return $expires.UtcDateTime -gt [DateTime]::UtcNow
}

function Complete-AiBrainBulkApproval {
  param([Parameter(Mandatory = $true)][object]$Config, [Parameter(Mandatory = $true)][object]$Paths)
  if (-not (Test-AiBrainBulkApprovalActive -Config $Config)) { return }
  $approval = Get-AiBrainProperty $Config 'bulkApproval' $null
  Set-AiBrainProperty -Object $approval -Name 'consumed' -Value $true
  Set-AiBrainProperty -Object $approval -Name 'consumedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
  Write-AiBrainJsonAtomic -Path $Paths.Config -Value $Config
}

function Invoke-AiBrainOperation {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [string]$SlotId,
    [object]$Claim,
    [bool]$Scheduled,
    [string]$RunId
  )
  if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = [Guid]::NewGuid().ToString('N') }
  if ($RunId -notmatch '^[a-f0-9]{32}$') { throw "RUN_ID_INVALID" }
  $runId = $RunId
  $requestId = $(if ($null -ne $Claim) { [string]$Claim.Request.requestId } else { $null })
  $State.status = 'running'
  $State.runId = $runId
  $State.activeRequestId = $requestId
  $State.lastHeartbeatUtc = [DateTime]::UtcNow.ToString('o')
  $State.child = [ordered]@{ status = 'not_started'; operation = $Operation }
  Set-AiBrainState -Paths $Paths -State $State

  $baseline = Get-AiBrainVaultManifest -VaultPath ([string]$Config.vaultPath)
  $inputFingerprint = Get-AiBrainManifestFingerprint -Manifest $baseline
  if ($Operation -eq 'compile' -and $Scheduled -and
      -not [string]::IsNullOrWhiteSpace([string]$State.lastCompileInputFingerprint) -and
      [string]$State.lastCompileInputFingerprint -eq $inputFingerprint) {
    Complete-AiBrainOperationSlot -State $State -Operation compile -SlotId $SlotId
    $State.lastCompileInputFingerprint = $inputFingerprint
    $State.status = 'ready'
    $State.runId = $null
    $State.activeRequestId = $null
    $State.child = $null
    Set-AiBrainLastResult -State $State -Code 'no_change' -Operation $Operation -SkipReason 'source_unchanged'
    Reset-AiBrainFailure -State $State
    Set-AiBrainState -Paths $Paths -State $State
    if ($null -ne $Claim) { Complete-AiBrainRequest -Paths $Paths -Claim $Claim -ResultCode 'no_change' }
    Write-AiBrainLogEvent -Paths $Paths -EventCode 'COMPILE_NO_CHANGE'
    return 'no_change'
  }

  if ($Operation -eq 'compile' -and
      [string]::IsNullOrWhiteSpace([string]$State.lastCompileSuccessUtc) -and
      -not (Test-AiBrainBulkApprovalActive -Config $Config)) {
    $estimatedFiles = @($baseline | Where-Object { $_.path -like 'main/*' -or $_.path -like 'raw/*' }).Count
    if ($estimatedFiles -gt [int]$Config.limits.maxChangeFiles) {
      throw "INITIAL_BULK_APPROVAL_REQUIRED"
    }
  }

  [long]$sourceBytes = 0
  foreach ($entry in $baseline) { $sourceBytes += [long]$entry.size }
  Assert-AiBrainFreeSpace -Config $Config -Paths $Paths -SourceBytes $sourceBytes | Out-Null
  $runDirectory = New-AiBrainRunDirectory -Paths $Paths -RunId $runId
  $bundle = New-AiBrainSourceBundle -Config $Config -RunDirectory $runDirectory
  $prompt = New-AiBrainAgentPrompt -Operation $Operation -Scope $Scope -SourceBundle $bundle
  $invocation = New-AiBrainAgentInvocation -Config $Config -RunDirectory $runDirectory -Operation $Operation
  $State.child = [ordered]@{ status = 'starting'; operation = $Operation }
  Set-AiBrainState -Paths $Paths -State $State

  $result = Invoke-AiBrainHiddenProcess `
    -CommandPath $invocation.CommandPath `
    -Arguments $invocation.Arguments `
    -StandardInput $prompt `
    -WorkingDirectory $runDirectory `
    -TimeoutSeconds ([int]$Config.limits.timeoutSeconds) `
    -MaxCaptureBytes ([int]$Config.limits.maxCaptureBytes)
  Write-AiBrainProcessTechnicalLogs -Paths $Paths -RunId $runId -ProcessResult $result
  Write-AiBrainLogEvent -Paths $Paths -EventCode 'AGENT_PROCESS_COMPLETE' -SafeData @{
    exitCode = $result.ExitCode
    timedOut = [bool]$result.TimedOut
    drained = [bool]$result.Drained
    treeTerminated = [bool]$result.TreeTerminated
    stdoutBytes = [long]$result.StdOut.Bytes
    stderrBytes = [long]$result.StdErr.Bytes
    stdoutTruncated = [bool]$result.StdOut.Truncated
    stderrTruncated = [bool]$result.StdErr.Truncated
  }

  $State.child = [ordered]@{
    status = 'finished'
    processId = [int]$result.ProcessId
    startTimeUtc = $result.StartTimeUtc.ToString('o')
    executableHash = Get-AiBrainFileSha256 -Path ([string]$Config.agentExecutable)
  }
  Set-AiBrainState -Paths $Paths -State $State
  $finalText = Get-AiBrainAgentFinalText -Target ([string]$Config.target) -ProcessResult $result -FinalPath $invocation.FinalPath
  $changeSet = ConvertFrom-AiBrainChangeSet -Text $finalText -ExpectedOperation $Operation
  $existingWikiCount = @($baseline | Where-Object { $_.path -like 'wiki/*' }).Count
  Test-AiBrainChangeSet `
    -ChangeSet $changeSet `
    -Config $Config `
    -Operation $Operation `
    -Scope $Scope `
    -RunDirectory $runDirectory `
    -ExistingWikiCount $existingWikiCount | Out-Null
  $changeSummary = Get-AiBrainChangeSummary -Config $Config -ChangeSet $changeSet -BaselineManifest $baseline

  if (@($changeSet.changes).Count -eq 0) {
    if (-not [string]::IsNullOrWhiteSpace($SlotId)) {
      Complete-AiBrainOperationSlot -State $State -Operation $Operation -SlotId $SlotId
    }
    if ($Operation -eq 'compile') { $State.lastCompileInputFingerprint = $inputFingerprint }
    if ($Operation -eq 'compile') { Complete-AiBrainBulkApproval -Config $Config -Paths $Paths }
    $State.status = 'ready'
    $State.runId = $null
    $State.activeRequestId = $null
    $State.child = $null
    Set-AiBrainLastResult -State $State -Code 'clean' -Operation $Operation
    Reset-AiBrainFailure -State $State
    Set-AiBrainState -Paths $Paths -State $State
    if ($null -ne $Claim) { Complete-AiBrainRequest -Paths $Paths -Claim $Claim -ResultCode 'clean' }
    Write-AiBrainLogEvent -Paths $Paths -EventCode ($Operation.ToUpperInvariant() + '_CLEAN')
    Remove-AiBrainRuntimeItem -Paths $Paths -Path $runDirectory -Recurse
    return 'clean'
  }

  Materialize-AiBrainChangeSet -ChangeSet $changeSet -RunDirectory $runDirectory
  if ($null -ne $Claim) { Set-AiBrainRequestJournal -Claim $Claim -JournalId $runId }
  $transaction = Invoke-AiBrainWikiTransaction `
    -Config $Config `
    -Paths $Paths `
    -ChangeSet $changeSet `
    -RunDirectory $runDirectory `
    -BaselineManifest $baseline `
    -RunId $runId `
    -Operation $Operation `
    -Scope $Scope `
    -SlotId $SlotId `
    -RequestId $requestId

  if (-not [string]::IsNullOrWhiteSpace($SlotId)) {
    Complete-AiBrainOperationSlot -State $State -Operation $Operation -SlotId $SlotId
  }
  if ($Operation -eq 'compile') {
    $State.lastCompileInputFingerprint = [string]$transaction.Journal.finalFingerprint
    Complete-AiBrainBulkApproval -Config $Config -Paths $Paths
  }
  $State.status = 'ready'
  $State.runId = $null
  $State.activeRequestId = $null
  $State.child = $null
  Set-AiBrainLastResult `
    -State $State `
    -Code 'applied' `
    -Operation $Operation `
    -ChangeCount (@($changeSet.changes).Count) `
    -NewConceptCount ([int]$changeSummary.NewConceptCount) `
    -LinkFixCount ([int]$changeSummary.LinkFixCount) `
    -MetadataFixCount ([int]$changeSummary.MetadataFixCount)
  Reset-AiBrainFailure -State $State
  Set-AiBrainState -Paths $Paths -State $State
  Complete-AiBrainJournal -JournalPath $transaction.JournalPath
  if ($null -ne $Claim) { Complete-AiBrainRequest -Paths $Paths -Claim $Claim -ResultCode 'applied' }
  Write-AiBrainLogEvent -Paths $Paths -EventCode ($Operation.ToUpperInvariant() + '_APPLIED') -SafeData @{ changeCount = @($changeSet.changes).Count }
  Remove-AiBrainRuntimeItem -Paths $Paths -Path $runDirectory -Recurse
  return 'applied'
}

$paths = Get-AiBrainRuntimePaths -RuntimeRoot $RuntimeRoot
Initialize-AiBrainRuntimeDirectories -Paths $paths
$config = $null
$lock = $null
try {
  $config = Read-AiBrainJson -Path $paths.Config
  Assert-AiBrainConfig -Config $config | Out-Null

  if ($Preflight) {
    Invoke-AiBrainPreflight -Config $config -Paths $paths -Token $PreflightToken
    exit 0
  }

  $lock = Enter-AiBrainMutex -VaultId ([string]$config.vaultId) -TimeoutMilliseconds 0
  if (-not $lock.Acquired) {
    Write-AiBrainLogEvent -Paths $paths -EventCode 'RUN_SKIPPED_MUTEX_BUSY'
    exit 0
  }
  $state = Read-AiBrainState -Paths $paths -Config $config -Repair
  $state.lastHeartbeatUtc = [DateTime]::UtcNow.ToString('o')
  $currentZoneId = [TimeZoneInfo]::Local.Id
  if ([string]$config.timeZoneId -ne $currentZoneId) {
    $config.timeZoneId = $currentZoneId
    $config.lastControlAction = 'time-zone-auto-refresh'
    Write-AiBrainJsonAtomic -Path $paths.Config -Value $config
    Write-AiBrainLogEvent -Paths $paths -EventCode 'TIME_ZONE_AUTO_REFRESHED'
  }

  foreach ($recovery in Recover-AiBrainJournals -Config $config -Paths $paths) {
    if ($recovery.action -eq 'finalize_state') {
      Complete-AiBrainRecoveredJournal -State $state -Paths $paths -Recovery $recovery
    } elseif ($recovery.action -eq 'rolled_back') {
      $state.lastRecoveryCode = 'JOURNAL_ROLLED_BACK'
      $state.lastRollbackPerformed = $true
      $state.lastResultCode = 'recovered'
      $state.lastRunCompletedUtc = [DateTime]::UtcNow.ToString('o')
      Set-AiBrainState -Paths $paths -State $state
      Write-AiBrainLogEvent -Paths $paths -EventCode 'JOURNAL_AUTO_ROLLBACK'
    }
  }
  Recover-AiBrainClaimedRequests -Paths $paths -State $state
  $state.runId = $null
  $state.child = $null
  Set-AiBrainState -Paths $paths -State $state

  if (-not [bool]$config.enabled -and -not $ManualRequest) {
    $state.status = 'off'
    Set-AiBrainState -Paths $paths -State $state
    Write-AiBrainSleepReport -Config $config -State $state
    exit 0
  }
  if ($state.status -in @('paused', 'attention')) {
    Write-AiBrainSleepReport -Config $config -State $state
    exit 0
  }

  $dueOperations = $(if ($ManualRequest) { @() } else { @(Get-AiBrainDueOperations -Config $config -State $state) })
  Set-AiBrainState -Paths $paths -State $state
  foreach ($due in $dueOperations) {
    try {
      Invoke-AiBrainOperation `
        -Config $config `
        -Paths $paths `
        -State $state `
        -Operation ([string]$due.operation) `
        -Scope ([string]$due.scope) `
        -SlotId ([string]$due.slotId) `
        -Claim $null `
        -Scheduled $true `
        -RunId ([Guid]::NewGuid().ToString('N')) | Out-Null
    } catch {
      $code = Get-AiBrainErrorCode -ErrorRecord $_
      if ((Get-AiBrainOperationFailureKind -Code $code) -eq 'attention') {
        Set-AiBrainAttention -Paths $paths -State $state -Code $code -Action (Get-AiBrainAttentionAction -Code $code)
      } else {
        Register-AiBrainFailure -Paths $paths -State $state -Code $code
      }
      Write-AiBrainSleepReport -Config $config -State $state
      exit 1
    }
  }

  $processedRequests = 0
  # Always re-read the queue after scheduled work. A RunNow request can arrive
  # while a long compile owns the task, and Task Scheduler IgnoreNew will not
  # create a second process for it.
  $requestLimit = 1
  while ($processedRequests -lt $requestLimit) {
    $requestRunId = [Guid]::NewGuid().ToString('N')
    $claim = Claim-AiBrainRequest -Paths $paths -RunId $requestRunId
    if ($null -eq $claim) { break }
    $processedRequests++
    try {
      Invoke-AiBrainOperation `
        -Config $config `
        -Paths $paths `
        -State $state `
        -Operation ([string]$claim.Request.operation) `
        -Scope ([string]$claim.Request.scope) `
        -SlotId $null `
        -Claim $claim `
        -Scheduled $false `
        -RunId $requestRunId | Out-Null
    } catch {
      $code = Get-AiBrainErrorCode -ErrorRecord $_
      if (Test-Path -LiteralPath $claim.Path) {
        Complete-AiBrainRequest -Paths $paths -Claim $claim -ResultCode $code -Failed
      }
      if ((Get-AiBrainOperationFailureKind -Code $code) -eq 'attention') {
        Set-AiBrainAttention -Paths $paths -State $state -Code $code -Action (Get-AiBrainAttentionAction -Code $code)
      } else {
        Register-AiBrainFailure -Paths $paths -State $state -Code $code
      }
      Write-AiBrainSleepReport -Config $config -State $state
      exit 1
    }
  }

  $state.status = $(if ([bool]$config.enabled) { 'ready' } else { 'off' })
  $state.lastHeartbeatUtc = [DateTime]::UtcNow.ToString('o')
  Set-AiBrainState -Paths $paths -State $state
  Invoke-AiBrainRuntimeMaintenance -Config $config -Paths $paths
  Write-AiBrainSleepReport -Config $config -State $state
  Write-AiBrainLogEvent -Paths $paths -EventCode 'SLEEP_CYCLE_COMPLETE' -SafeData @{ requests = $processedRequests }
  exit 0
} catch {
  $code = Get-AiBrainErrorCode -ErrorRecord $_
  $action = Get-AiBrainAttentionAction -Code $code
  try {
    Write-AiBrainLogEvent -Paths $paths -EventCode $code -Level attention
    Write-AiBrainRuntimeAttention -Paths $paths -Code $code -Action $action
  } catch {}
  if ($null -ne $config) {
    $state = $null
    try {
      $state = Read-AiBrainState -Paths $paths -Config $config -Repair
      if ((Get-AiBrainOperationFailureKind -Code $code) -eq 'attention') {
        Set-AiBrainAttention -Paths $paths -State $state -Code $code -Action $action
      } else {
        Register-AiBrainFailure -Paths $paths -State $state -Code $code
      }
    } catch {
      try {
        $stateCode = Get-AiBrainErrorCode -ErrorRecord $_
        Write-AiBrainLogEvent -Paths $paths -EventCode 'STATE_UNREADABLE' -SafeData @{ code = $stateCode }
        $ephemeral = New-AiBrainState -Enabled ([bool]$config.enabled)
        $ephemeral.status = 'attention'
        $ephemeral.lastHeartbeatUtc = [DateTime]::UtcNow.ToString('o')
        $ephemeral.attentionCode = $stateCode
        $ephemeral.attentionAction = Get-AiBrainMessage -Name action_state_reset
        Write-AiBrainRuntimeAttention -Paths $paths -Code $stateCode -Action $ephemeral.attentionAction
      } catch {}
    }
    if ($null -ne $state -and
        (Test-Path -LiteralPath ([string](Get-AiBrainProperty $config 'vaultPath' '')) -PathType Container)) {
      try { Write-AiBrainSleepReport -Config $config -State $state } catch {}
    }
  }
  exit 1
} finally {
  Exit-AiBrainMutex -Lock $lock
}
