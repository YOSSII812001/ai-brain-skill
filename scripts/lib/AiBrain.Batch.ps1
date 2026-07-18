if (-not (Get-Command Get-AiBrainProperty -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Common.ps1')
}
if (-not (Get-Command New-AiBrainAgentPrompt -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Transaction.ps1')
}

$script:AiBrainBatchProtocolVersion = 'ai-brain-batch-v1'

function Get-AiBrainPromptLimitBytes {
  param([Parameter(Mandatory = $true)][object]$Config)
  $fallback = [Math]::Min(
    [long]$Config.limits.maxSourceBytes,
    [long]$script:AiBrainDefaultPromptBytes)
  return [long](Get-AiBrainProperty $Config.limits 'maxPromptBytes' $fallback)
}

function Get-AiBrainWorkerChangeLimit {
  param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 100000)][int]$TotalWorkers,
    [Parameter(Mandatory = $true)][ValidateRange(0, 99999)][int]$Ordinal,
    [Parameter(Mandatory = $true)][ValidateRange(0, 1000)][int]$MaxChangeFiles,
    [ValidateRange(0, 2)][int]$FinalizerReserve = 2
  )
  if ($Ordinal -ge $TotalWorkers) { throw "BATCH_WORKER_ORDINAL_INVALID" }
  $reserved = [Math]::Min($FinalizerReserve, $MaxChangeFiles)
  $workerBudget = $MaxChangeFiles - $reserved
  $base = [Math]::Floor($workerBudget / $TotalWorkers)
  $extra = $workerBudget % $TotalWorkers
  return [int]$base + $(if ($Ordinal -lt $extra) { 1 } else { 0 })
}

function Get-AiBrainPromptByteCount {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prompt)
  return [long]$script:AiBrainUtf8NoBom.GetByteCount($Prompt)
}

function Get-AiBrainChunkFingerprint {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries)
  $lines = @(
    $Entries |
      Sort-Object { ([string]$_.path).ToLowerInvariant() } |
      ForEach-Object { '{0}|{1}' -f ([string]$_.path).ToLowerInvariant(), [string]$_.sha256 }
  )
  return Get-AiBrainStringSha256 -Text (($lines -join "`n") + "`n")
}

function Get-AiBrainChunkPromptInfo {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][string]$ChunkKey,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries
  )
  $bundle = [ordered]@{ schemaVersion = 1; files = @($Entries) }
  $prompt = New-AiBrainAgentPrompt `
    -Operation $Operation `
    -Scope $Scope `
    -SourceBundle $bundle `
    -Mode worker `
    -ChunkKey $ChunkKey
  [long]$inputBytes = 0
  foreach ($entry in $Entries) { $inputBytes += [long](Get-AiBrainProperty $entry 'bytes' 0) }
  return [pscustomobject]@{
    Prompt = $prompt
    PromptBytes = Get-AiBrainPromptByteCount -Prompt $prompt
    PromptHash = Get-AiBrainStringSha256 -Text $prompt
    InputBytes = $inputBytes
  }
}

function Add-AiBrainChunkBucket {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
    [Parameter(Mandatory = $true)][int]$Depth,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prefix,
    [Parameter(Mandatory = $true)][int]$MaxFiles,
    [Parameter(Mandatory = $true)][long]$MaxInputBytes,
    [Parameter(Mandatory = $true)][long]$MaxPromptBytes,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Collector
  )
  if ($Entries.Count -eq 0) { return }
  $key = $(if ([string]::IsNullOrWhiteSpace($Prefix)) { 'root' } else { $Prefix })
  $promptInfo = Get-AiBrainChunkPromptInfo `
    -Operation $Operation `
    -Scope $Scope `
    -ChunkKey $key `
    -Entries $Entries
  if ($Entries.Count -le $MaxFiles -and
      [long]$promptInfo.InputBytes -le $MaxInputBytes -and
      [long]$promptInfo.PromptBytes -le $MaxPromptBytes) {
    $sourceFingerprint = Get-AiBrainChunkFingerprint -Entries $Entries
    $fingerprint = Get-AiBrainStringSha256 -Text (
      '{0}|{1}|{2}' -f
        $script:AiBrainBatchProtocolVersion,
        $sourceFingerprint,
        [string]$promptInfo.PromptHash)
    [void]$Collector.Add([pscustomobject]@{
      Key = $key
      ChunkId = Get-AiBrainStringSha256 -Text (
        '{0}|{1}|{2}|{3}|{4}|{5}' -f
          $script:AiBrainBatchProtocolVersion,
          $Operation,
          $Scope,
          $key,
          $fingerprint,
          $MaxPromptBytes)
      Fingerprint = $fingerprint
      SourceFingerprint = $sourceFingerprint
      PromptHash = [string]$promptInfo.PromptHash
      Files = @($Entries | Sort-Object { ([string]$_.path).ToLowerInvariant() })
      InputFiles = $Entries.Count
      InputBytes = [long]$promptInfo.InputBytes
      PromptBytes = [long]$promptInfo.PromptBytes
    })
    return
  }
  if ($Entries.Count -eq 1) { throw "SOURCE_FILE_PROMPT_LIMIT_EXCEEDED" }
  if ($Depth -ge 256) { throw "CHUNK_ROUTE_COLLISION" }

  $groups = @{}
  foreach ($entry in $Entries) {
    $routeHash = Get-AiBrainStringSha256 -Text ([string]$entry.path).ToLowerInvariant()
    $nibbleIndex = [Math]::Floor($Depth / 4)
    $bitIndex = 3 - ($Depth % 4)
    $nibble = [Convert]::ToInt32($routeHash.Substring($nibbleIndex, 1), 16)
    $routePart = [string](($nibble -shr $bitIndex) -band 1)
    if (-not $groups.ContainsKey($routePart)) {
      $groups[$routePart] = New-Object System.Collections.ArrayList
    }
    [void]$groups[$routePart].Add($entry)
  }
  foreach ($routePart in @($groups.Keys | Sort-Object)) {
    Add-AiBrainChunkBucket `
      -Operation $Operation `
      -Scope $Scope `
      -Entries @($groups[$routePart]) `
      -Depth ($Depth + 1) `
      -Prefix ($Prefix + $routePart) `
      -MaxFiles $MaxFiles `
      -MaxInputBytes $MaxInputBytes `
      -MaxPromptBytes $MaxPromptBytes `
      -Collector $Collector
  }
}

function New-AiBrainChunkPlan {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][object]$SourceInventory
  )
  [long]$promptLimit = Get-AiBrainPromptLimitBytes -Config $Config
  $packageId = [string](Get-AiBrainProperty $Config 'packageId' '')
  if ($packageId -notmatch '^[a-f0-9]{64}$') {
    $packageId = Get-AiBrainStringSha256 -Text ('unpackaged|' + $script:AiBrainBatchProtocolVersion)
  }
  $chunks = New-Object System.Collections.ArrayList
  Add-AiBrainChunkBucket `
    -Operation $Operation `
    -Scope $Scope `
    -Entries @($SourceInventory.files) `
    -Depth 0 `
    -Prefix '' `
    -MaxFiles ([int]$Config.limits.maxSourceFiles) `
    -MaxInputBytes ([long]$Config.limits.maxSourceBytes) `
    -MaxPromptBytes $promptLimit `
    -Collector $chunks
  $ordered = @($chunks | Sort-Object Key)
  $planLines = @($ordered | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}' -f
      $_.Key, $_.Fingerprint, $_.InputFiles, $_.PromptBytes, $_.PromptHash
  })
  return [pscustomobject]@{
    SchemaVersion = 1
    ProtocolVersion = $script:AiBrainBatchProtocolVersion
    PackageId = $packageId
    Operation = $Operation
    Scope = $Scope
    PromptBudgetBytes = $promptLimit
    Fingerprint = Get-AiBrainStringSha256 -Text (
      (($script:AiBrainBatchProtocolVersion, $packageId) + $planLines -join "`n") + "`n")
    Chunks = $ordered
  }
}

function Get-AiBrainCompileChunkFingerprintMap {
  param([Parameter(Mandatory = $true)][object]$State)
  $map = @{}
  foreach ($entry in @((Get-AiBrainProperty $State 'lastCompileChunkFingerprints' @()))) {
    $key = [string](Get-AiBrainProperty $entry 'key' '')
    $fingerprint = [string](Get-AiBrainProperty $entry 'fingerprint' '')
    if (-not [string]::IsNullOrWhiteSpace($key) -and $fingerprint -match '^[a-f0-9]{64}$') {
      $map[$key] = $fingerprint
    }
  }
  return $map
}

function Get-AiBrainChunksToProcess {
  param(
    [Parameter(Mandatory = $true)][object]$Plan,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][object]$State
  )
  if ($Operation -eq 'lint') { return @($Plan.Chunks) }
  $previous = Get-AiBrainCompileChunkFingerprintMap -State $State
  return @($Plan.Chunks | Where-Object {
    -not $previous.ContainsKey([string]$_.Key) -or
    [string]$previous[[string]$_.Key] -ne [string]$_.Fingerprint
  })
}

function New-AiBrainCompileChunkCheckpoint {
  param([Parameter(Mandatory = $true)][object]$Plan)
  return @($Plan.Chunks | Sort-Object Key | ForEach-Object {
    [ordered]@{ key = [string]$_.Key; fingerprint = [string]$_.Fingerprint }
  })
}

function Get-AiBrainBatchId {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][string]$BaselineFingerprint,
    [Parameter(Mandatory = $true)][long]$PromptBudgetBytes,
    [Parameter(Mandatory = $true)][string]$PackageId
  )
  if ($PackageId -notmatch '^[a-f0-9]{64}$') { throw "PACKAGE_ID_INVALID" }
  $identity = '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f
    $script:AiBrainBatchProtocolVersion,
    $PackageId,
    $Operation,
    $Scope,
    $BaselineFingerprint,
    $PromptBudgetBytes,
    $script:AiBrainSecretDetectorVersion
  return (Get-AiBrainStringSha256 -Text $identity).Substring(0, 32)
}

function Initialize-AiBrainBatchWorkspace {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$BatchId
  )
  if ($BatchId -notmatch '^[a-f0-9]{32}$') { throw "BATCH_ID_INVALID" }
  $workspace = Join-Path $Paths.Staging ('batch-' + $BatchId)
  foreach ($directory in @(
    $workspace,
    (Join-Path $workspace 'snapshot'),
    (Join-Path $workspace 'staged'),
    (Join-Path $workspace 'outputs'),
    (Join-Path $workspace 'agents')
  )) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
      New-AiBrainDirectorySafe -Path $directory | Out-Null
    }
  }
  return [pscustomobject]@{
    Root = $workspace
    Snapshot = Join-Path $workspace 'snapshot'
    Staged = Join-Path $workspace 'staged'
    Outputs = Join-Path $workspace 'outputs'
    Agents = Join-Path $workspace 'agents'
    Journal = Join-Path $workspace 'batch.json'
  }
}

function Write-AiBrainBatchJournal {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Journal
  )
  Set-AiBrainProperty -Object $Journal -Name 'updatedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
  Write-AiBrainJsonAtomic -Path $Path -Value $Journal
}

function Assert-AiBrainBatchJournal {
  param(
    [Parameter(Mandatory = $true)][object]$Journal,
    [Parameter(Mandatory = $true)][string]$BatchId,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][string]$BaselineFingerprint,
    [Parameter(Mandatory = $true)][object]$Plan,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ActiveChunks
  )
  if ([int](Get-AiBrainProperty $Journal 'schemaVersion' 0) -ne 1 -or
      [string](Get-AiBrainProperty $Journal 'kind' '') -ne 'ai-brain-batch' -or
      [string](Get-AiBrainProperty $Journal 'protocolVersion' '') -ne [string]$Plan.ProtocolVersion -or
      [string](Get-AiBrainProperty $Journal 'packageId' '') -ne [string]$Plan.PackageId -or
      [string](Get-AiBrainProperty $Journal 'batchId' '') -ne $BatchId -or
      [string](Get-AiBrainProperty $Journal 'operation' '') -ne $Operation -or
      [string](Get-AiBrainProperty $Journal 'scopeHash' '') -ne (Get-AiBrainStringSha256 -Text $Scope) -or
      [string](Get-AiBrainProperty $Journal 'baselineFingerprint' '') -ne $BaselineFingerprint -or
      [string](Get-AiBrainProperty $Journal 'planFingerprint' '') -ne [string]$Plan.Fingerprint -or
      [long](Get-AiBrainProperty $Journal 'promptBudgetBytes' 0) -ne [long]$Plan.PromptBudgetBytes) {
    throw "BATCH_JOURNAL_INVALID"
  }
  $journalChunks = @($Journal.chunks)
  if ($journalChunks.Count -ne $ActiveChunks.Count) { throw "BATCH_JOURNAL_INVALID" }
  for ($index = 0; $index -lt $ActiveChunks.Count; $index++) {
    if ([int](Get-AiBrainProperty $journalChunks[$index] 'ordinal' -1) -ne $index -or
        [string](Get-AiBrainProperty $journalChunks[$index] 'chunkId' '') -ne [string]$ActiveChunks[$index].ChunkId -or
        [string](Get-AiBrainProperty $journalChunks[$index] 'inputFingerprint' '') -ne [string]$ActiveChunks[$index].Fingerprint -or
        [string](Get-AiBrainProperty $journalChunks[$index] 'promptHash' '') -ne [string]$ActiveChunks[$index].PromptHash) {
      throw "BATCH_JOURNAL_INVALID"
    }
  }
  return $true
}

function Get-OrNewAiBrainBatchJournal {
  param(
    [Parameter(Mandatory = $true)][object]$Workspace,
    [Parameter(Mandatory = $true)][string]$BatchId,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][string]$BaselineFingerprint,
    [Parameter(Mandatory = $true)][object]$Plan,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ActiveChunks,
    [string]$RequestId
  )
  if (Test-Path -LiteralPath $Workspace.Journal -PathType Leaf) {
    $journal = Read-AiBrainJson -Path $Workspace.Journal
    Assert-AiBrainBatchJournal `
      -Journal $journal `
      -BatchId $BatchId `
      -Operation $Operation `
      -Scope $Scope `
      -BaselineFingerprint $BaselineFingerprint `
      -Plan $Plan `
      -ActiveChunks $ActiveChunks | Out-Null
    Set-AiBrainProperty -Object $journal -Name 'requestId' -Value $RequestId
    Write-AiBrainBatchJournal -Path $Workspace.Journal -Journal $journal
    return $journal
  }
  $chunks = New-Object System.Collections.ArrayList
  for ($index = 0; $index -lt $ActiveChunks.Count; $index++) {
    $chunk = $ActiveChunks[$index]
    [void]$chunks.Add([ordered]@{
      ordinal = $index
      chunkId = [string]$chunk.ChunkId
      routeHash = Get-AiBrainStringSha256 -Text ([string]$chunk.Key)
      inputFingerprint = [string]$chunk.Fingerprint
      promptHash = [string]$chunk.PromptHash
      inputFiles = [int]$chunk.InputFiles
      inputBytes = [long]$chunk.InputBytes
      promptBytes = [long]$chunk.PromptBytes
      status = 'pending'
      resultHash = $null
      changeCount = 0
      changeBytes = 0
    })
  }
  $journal = [ordered]@{
    schemaVersion = 1
    kind = 'ai-brain-batch'
    protocolVersion = [string]$Plan.ProtocolVersion
    packageId = [string]$Plan.PackageId
    batchId = $BatchId
    operation = $Operation
    scopeHash = Get-AiBrainStringSha256 -Text $Scope
    requestId = $RequestId
    baselineFingerprint = $BaselineFingerprint
    planFingerprint = [string]$Plan.Fingerprint
    promptBudgetBytes = [long]$Plan.PromptBudgetBytes
    status = 'running'
    totalChunks = $ActiveChunks.Count
    completedChunks = 0
    chunks = @($chunks)
    finalizer = [ordered]@{
      status = 'pending'
      resultHash = $null
      changeCount = 0
      changeBytes = 0
    }
    createdUtc = [DateTime]::UtcNow.ToString('o')
  }
  Write-AiBrainBatchJournal -Path $Workspace.Journal -Journal $journal
  return $journal
}

function Set-AiBrainBatchChunkRunning {
  param(
    [Parameter(Mandatory = $true)][object]$Journal,
    [Parameter(Mandatory = $true)][string]$JournalPath,
    [Parameter(Mandatory = $true)][int]$Ordinal
  )
  $entry = @($Journal.chunks)[$Ordinal]
  $entry.status = 'running'
  Write-AiBrainBatchJournal -Path $JournalPath -Journal $Journal
}

function Set-AiBrainBatchChunkCompleted {
  param(
    [Parameter(Mandatory = $true)][object]$Journal,
    [Parameter(Mandatory = $true)][string]$JournalPath,
    [Parameter(Mandatory = $true)][int]$Ordinal,
    [Parameter(Mandatory = $true)][string]$ResultHash,
    [int]$ChangeCount,
    [long]$ChangeBytes
  )
  $entry = @($Journal.chunks)[$Ordinal]
  $entry.status = 'completed'
  $entry.resultHash = $ResultHash
  $entry.changeCount = $ChangeCount
  $entry.changeBytes = $ChangeBytes
  $Journal.completedChunks = @($Journal.chunks | Where-Object { [string]$_.status -eq 'completed' }).Count
  Write-AiBrainBatchJournal -Path $JournalPath -Journal $Journal
}

function Get-AiBrainBatchOutputPath {
  param(
    [Parameter(Mandatory = $true)][object]$Workspace,
    [Parameter(Mandatory = $true)][ValidateSet('worker', 'finalizer')][string]$Kind,
    [int]$Ordinal = 0
  )
  $name = $(if ($Kind -eq 'finalizer') { 'finalizer.json' } else { 'worker-{0:D4}.json' -f $Ordinal })
  return Join-Path $Workspace.Outputs $name
}

function Set-AiBrainBatchFinalizerRunning {
  param(
    [Parameter(Mandatory = $true)][object]$Journal,
    [Parameter(Mandatory = $true)][string]$JournalPath
  )
  $Journal.finalizer.status = 'running'
  Write-AiBrainBatchJournal -Path $JournalPath -Journal $Journal
}

function Set-AiBrainBatchFinalizerCompleted {
  param(
    [Parameter(Mandatory = $true)][object]$Journal,
    [Parameter(Mandatory = $true)][string]$JournalPath,
    [Parameter(Mandatory = $true)][string]$ResultHash,
    [int]$ChangeCount,
    [long]$ChangeBytes
  )
  $Journal.finalizer.status = 'completed'
  $Journal.finalizer.resultHash = $ResultHash
  $Journal.finalizer.changeCount = $ChangeCount
  $Journal.finalizer.changeBytes = $ChangeBytes
  Write-AiBrainBatchJournal -Path $JournalPath -Journal $Journal
}

function Get-AiBrainChangeSetByteCount {
  param([Parameter(Mandatory = $true)][object]$ChangeSet)
  [long]$bytes = 0
  foreach ($change in @($ChangeSet.changes)) {
    if ([string]$change.action -eq 'write') {
      $bytes += [long]$script:AiBrainUtf8NoBom.GetByteCount([string]$change.content)
    }
  }
  return $bytes
}

function Initialize-AiBrainAggregateStaging {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$Workspace,
    [Parameter(Mandatory = $true)][object]$SourceInventory
  )
  if (Test-Path -LiteralPath $Workspace.Staged -PathType Container) {
    Remove-AiBrainRuntimeItem -Paths $Paths -Path $Workspace.Staged -Recurse
  }
  New-AiBrainDirectorySafe -Path $Workspace.Staged | Out-Null
  foreach ($layer in @('main', 'raw', 'wiki')) {
    New-AiBrainDirectorySafe -Path (Join-Path $Workspace.Staged $layer) | Out-Null
  }
  foreach ($entry in @($SourceInventory.files)) {
    $destination = Resolve-AiBrainChildPath `
      -Root $Workspace.Staged `
      -RelativePath ([string]$entry.path) `
      -AllowMissingLeaf
    Write-AiBrainTextAtomic -Path $destination -Text ([string]$entry.content)
  }
}

function Get-AiBrainProjectedSourceInventory {
  param(
    [Parameter(Mandatory = $true)][object]$SourceInventory,
    [Parameter(Mandatory = $true)][object]$ChangeSet
  )
  $map = @{}
  foreach ($entry in @($SourceInventory.files)) {
    $map[([string]$entry.path).ToLowerInvariant()] = [ordered]@{
      path = [string]$entry.path
      sha256 = [string]$entry.sha256
      bytes = [long]$entry.bytes
      content = [string]$entry.content
    }
  }
  foreach ($change in @($ChangeSet.changes)) {
    $path = ([string]$change.path).Replace('\', '/')
    $key = $path.ToLowerInvariant()
    if ([string]$change.action -eq 'delete') {
      $map.Remove($key)
      continue
    }
    $content = [string]$change.content
    $map[$key] = [ordered]@{
      path = $path
      sha256 = Get-AiBrainStringSha256 -Text $content
      bytes = [long]$script:AiBrainUtf8NoBom.GetByteCount($content)
      content = $content
    }
  }
  [long]$bytes = 0
  foreach ($entry in $map.Values) { $bytes += [long]$entry.bytes }
  return [ordered]@{
    schemaVersion = 1
    files = @($map.Values | Sort-Object { ([string]$_.path).ToLowerInvariant() })
    includedCount = $map.Count
    includedBytes = $bytes
    excludedCount = [int](Get-AiBrainProperty $SourceInventory 'excludedCount' 0)
    excludedByNameCount = [int](Get-AiBrainProperty $SourceInventory 'excludedByNameCount' 0)
    excludedByContentCount = [int](Get-AiBrainProperty $SourceInventory 'excludedByContentCount' 0)
    detectorVersion = [string](Get-AiBrainProperty $SourceInventory 'detectorVersion' '')
    protectedWikiPaths = @((Get-AiBrainProperty $SourceInventory 'protectedWikiPaths' @()))
  }
}

function Get-AiBrainProtectedWikiPathSet {
  param([Parameter(Mandatory = $true)][object]$SourceInventory)
  $set = @{}
  foreach ($path in @((Get-AiBrainProperty $SourceInventory 'protectedWikiPaths' @()))) {
    $normalized = ([string]$path).Replace('\', '/').ToLowerInvariant()
    $set[$normalized] = $true
  }
  return $set
}

function Test-AiBrainProtectedPageScope {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][hashtable]$ProtectedWikiPaths
  )
  if ($Operation -ne 'compile' -or
      -not $Scope.StartsWith('page:', [StringComparison]::OrdinalIgnoreCase)) {
    return $false
  }
  foreach ($path in $ProtectedWikiPaths.Keys) {
    if (Test-AiBrainScopePath -Operation compile -Scope $Scope -RelativePath ([string]$path)) {
      return $true
    }
  }
  return $false
}

function Test-AiBrainChunkChangeSet {
  param(
    [Parameter(Mandatory = $true)][object]$ChangeSet,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][hashtable]$ProtectedWikiPaths,
    [switch]$Worker,
    [string[]]$AllowedPaths = @(),
    [string[]]$RetainPaths = @(),
    [ValidateRange(-1, 1000)][int]$MaxChanges = -1
  )
  $allowed = @{}
  foreach ($allowedPath in $AllowedPaths) {
    $allowed[$allowedPath.Replace('\', '/').ToLowerInvariant()] = $true
  }
  $retained = @{}
  foreach ($retainedPath in $RetainPaths) {
    $retained[$retainedPath.Replace('\', '/').ToLowerInvariant()] = $true
  }
  $seen = @{}
  $safeChanges = New-Object System.Collections.ArrayList
  foreach ($change in @($ChangeSet.changes)) {
    foreach ($property in $change.PSObject.Properties) {
      if ($property.Name -notin @('path', 'action', 'content')) { throw "CHANGE_SET_UNKNOWN_CHANGE_FIELD" }
    }
    $path = ([string](Get-AiBrainProperty $change 'path' '')).Replace('\', '/')
    $action = [string](Get-AiBrainProperty $change 'action' '')
    if (-not (Test-AiBrainRelativePath -Path $path) -or
        -not (Test-AiBrainScopePath -Operation $Operation -Scope $Scope -RelativePath $path)) {
      throw "CHANGE_SET_PATH_OUT_OF_SCOPE"
    }
    if ($path -ieq 'wiki/_meta/sleep-report.md') { throw "CHANGE_SET_PATH_OUT_OF_SCOPE" }
    if ($null -ne (Test-AiBrainContainsSecret -Text $path) -or
        (Test-AiBrainDeniedFileName -Name ([IO.Path]::GetFileName($path)))) {
      throw "CHANGE_SET_PATH_SENSITIVE"
    }
    $key = $path.ToLowerInvariant()
    if ($action -notin @('write', 'delete')) { throw "CHANGE_SET_ACTION_INVALID" }
    $text = $null
    if ($action -eq 'write') {
      $content = Get-AiBrainProperty $change 'content' $null
      if ($null -eq $content) { throw "CHANGE_SET_CONTENT_REQUIRED" }
      $text = [string]$content
      if ($null -ne (Test-AiBrainContainsSecret -Text $text)) { throw "CHANGE_SET_SECRET_DETECTED" }
    } elseif ($null -ne (Get-AiBrainProperty $change 'content' $null)) {
      throw "CHANGE_SET_DELETE_CONTENT_NOT_ALLOWED"
    }
    if ($ProtectedWikiPaths.ContainsKey($key)) { continue }
    if ($Worker -and $key -in @('wiki/index.md', 'wiki/log.md')) {
      throw "BATCH_RESERVED_PATH_CONFLICT"
    }
    if ($allowed.Count -gt 0 -and -not $allowed.ContainsKey($key)) {
      throw "BATCH_FINALIZER_PATH_INVALID"
    }
    if ($seen.ContainsKey($key)) { throw "BATCH_CHANGE_PATH_CONFLICT" }
    $seen[$key] = $true
    if ($action -eq 'write') {
      $text = ConvertTo-AiBrainCanonicalFrontmatter -Content $text
      Test-AiBrainFrontmatter -Content $text | Out-Null
      [void]$safeChanges.Add([pscustomobject]@{ path = $path; action = 'write'; content = $text })
    } else {
      [void]$safeChanges.Add([pscustomobject]@{ path = $path; action = 'delete'; content = $null })
    }
  }
  $selectedChanges = @($safeChanges)
  if ($retained.Count -gt 0) {
    $selectedChanges = @($selectedChanges | Where-Object {
      $retained.ContainsKey(([string]$_.path).Replace('\', '/').ToLowerInvariant())
    })
  }
  if ($MaxChanges -ge 0) {
    $selectedChanges = @($selectedChanges | Select-Object -First $MaxChanges)
  }
  return [pscustomobject]@{
    schemaVersion = 'ai-brain-change-set-v1'
    operation = $Operation
    changes = $selectedChanges
  }
}

function Repair-AiBrainChangeSetWikiLinks {
  param(
    [Parameter(Mandatory = $true)][object]$ChangeSet,
    [Parameter(Mandatory = $true)][object]$SourceInventory
  )
  $known = @{}
  foreach ($entry in @($SourceInventory.files)) {
    $path = ([string]$entry.path).Replace('\', '/').ToLowerInvariant()
    if ($path -notmatch '^wiki/.+\.md$') { continue }
    $known[$path] = $true
    $known[[IO.Path]::GetFileNameWithoutExtension($path)] = $true
  }
  foreach ($pathValue in @((Get-AiBrainProperty $SourceInventory 'protectedWikiPaths' @()))) {
    $path = ([string]$pathValue).Replace('\', '/').ToLowerInvariant()
    if ($path -notmatch '^wiki/.+\.md$') { continue }
    $known[$path] = $true
    $known[[IO.Path]::GetFileNameWithoutExtension($path)] = $true
  }
  foreach ($change in @($ChangeSet.changes)) {
    $path = ([string]$change.path).Replace('\', '/').ToLowerInvariant()
    if ([string]$change.action -eq 'write') {
      $known[$path] = $true
      $known[[IO.Path]::GetFileNameWithoutExtension($path)] = $true
    } else {
      $known.Remove($path)
      $known.Remove([IO.Path]::GetFileNameWithoutExtension($path))
    }
  }

  $changes = New-Object System.Collections.ArrayList
  foreach ($change in @($ChangeSet.changes)) {
    $content = $null
    if ([string]$change.action -eq 'write') {
      $content = [regex]::Replace(
        [string]$change.content,
        '!?\[\[(?<target>[^\]|#]+)(?:#[^\]|]*)?(?:\|(?<label>[^\]]+))?\]\]',
        [Text.RegularExpressions.MatchEvaluator]{
          param($linkMatch)
          $target = $linkMatch.Groups['target'].Value.Trim().Replace('\', '/')
          if ([string]::IsNullOrWhiteSpace($target) -or
              [IO.Path]::IsPathRooted($target) -or
              $target.Contains('..') -or
              (Test-AiBrainWikiLinkTargetKnown -Target $target -KnownWikiPaths $known)) {
            return $linkMatch.Value
          }
          $label = $(if ($linkMatch.Groups['label'].Success) {
            $linkMatch.Groups['label'].Value.Trim()
          } else {
            $target
          })
          return $(if ([string]::IsNullOrWhiteSpace($label)) { $target } else { $label })
        })
    }
    [void]$changes.Add([pscustomobject]@{
      path = [string]$change.path
      action = [string]$change.action
      content = $content
    })
  }
  return [pscustomobject]@{
    schemaVersion = 'ai-brain-change-set-v1'
    operation = [string]$ChangeSet.operation
    changes = @($changes)
  }
}

function Merge-AiBrainChunkChangeSets {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ChangeSets
  )
  $seen = @{}
  $changes = New-Object System.Collections.ArrayList
  foreach ($changeSet in $ChangeSets) {
    foreach ($change in @($changeSet.changes)) {
      $key = ([string]$change.path).Replace('\', '/').ToLowerInvariant()
      if ($seen.ContainsKey($key)) { throw "BATCH_CHANGE_PATH_CONFLICT" }
      $seen[$key] = $true
      [void]$changes.Add($change)
    }
  }
  return [pscustomobject]@{
    schemaVersion = 'ai-brain-change-set-v1'
    operation = $Operation
    changes = @($changes)
  }
}

function Get-AiBrainChangeMetadata {
  param([Parameter(Mandatory = $true)][object]$ChangeSet)
  $records = New-Object System.Collections.ArrayList
  foreach ($change in @($ChangeSet.changes)) {
    $record = [ordered]@{
      path = ([string]$change.path).Replace('\', '/')
      action = [string]$change.action
      title = $null
      type = $null
      status = $null
    }
    if ([string]$change.action -eq 'write') {
      $frontmatter = [regex]::Match([string]$change.content, '(?s)\A---\r?\n(?<yaml>.+?)\r?\n---\r?\n')
      if ($frontmatter.Success) {
        foreach ($line in ($frontmatter.Groups['yaml'].Value -split '\r?\n')) {
          if ($line -match '^(title|type|status):[ \t]*(.+)$') {
            $name = $Matches[1].ToLowerInvariant()
            $value = $Matches[2].Trim().Trim('"', "'")
            $record[$name] = $value
          }
        }
      }
    }
    [void]$records.Add($record)
  }
  return @($records)
}

function Get-AiBrainFinalizerInput {
  param(
    [Parameter(Mandatory = $true)][object]$SourceInventory,
    [Parameter(Mandatory = $true)][object]$WorkerChangeSet
  )
  $protected = Get-AiBrainProtectedWikiPathSet -SourceInventory $SourceInventory
  $allowed = New-Object System.Collections.ArrayList
  foreach ($path in @('wiki/index.md', 'wiki/log.md')) {
    if (-not $protected.ContainsKey($path)) { [void]$allowed.Add($path) }
  }
  $files = @($SourceInventory.files | Where-Object {
    ([string]$_.path).ToLowerInvariant() -in @('wiki/index.md', 'wiki/log.md')
  })
  return [pscustomobject]@{
    SourceBundle = [ordered]@{ schemaVersion = 1; files = $files }
    AllowedPaths = @($allowed)
    ChangeSummary = @(Get-AiBrainChangeMetadata -ChangeSet $WorkerChangeSet)
  }
}
