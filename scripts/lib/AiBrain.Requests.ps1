if (-not (Get-Command Get-AiBrainProperty -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Common.ps1')
}

function Assert-AiBrainRequestScope {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope
  )
  if ($Operation -eq 'compile') {
    if ($Scope -in @('all', 'concepts', 'sources')) { return $true }
    if ($Scope.StartsWith('page:', [StringComparison]::OrdinalIgnoreCase)) {
      $path = $Scope.Substring(5)
      if ($null -ne (Test-AiBrainContainsSecret -Text $path) -or
          (Test-AiBrainDeniedFileName -Name ([IO.Path]::GetFileName($path.Replace('\', '/'))))) {
        throw "REQUEST_SCOPE_SENSITIVE"
      }
      if (Test-AiBrainRelativePath -Path $path) { return $true }
    }
  } elseif ($Scope -in @('all', 'links', 'frontmatter', 'stale', 'naming')) {
    return $true
  }
  throw "REQUEST_SCOPE_INVALID"
}

function New-AiBrainRequest {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [string]$Scope = 'all'
  )
  Assert-AiBrainRequestScope -Operation $Operation -Scope $Scope | Out-Null
  $requestId = [Guid]::NewGuid().ToString('N')
  $request = [ordered]@{
    schemaVersion = 1
    requestId = $requestId
    operation = $Operation
    scope = $Scope
    createdUtc = [DateTime]::UtcNow.ToString('o')
    status = 'pending'
    claimedRunId = $null
    journalId = $null
    resultCode = $null
    completedUtc = $null
  }
  Write-AiBrainJsonAtomic -Path (Join-Path $Paths.PendingRequests "$requestId.json") -Value $request
  return [pscustomobject]$request
}

function Assert-AiBrainRequest {
  param([Parameter(Mandatory = $true)][object]$Request)
  if ([int](Get-AiBrainProperty $Request 'schemaVersion' 0) -ne 1) { throw "REQUEST_SCHEMA_INVALID" }
  if ([string]$Request.requestId -notmatch '^[a-f0-9]{32}$') { throw "REQUEST_ID_INVALID" }
  Assert-AiBrainRequestScope -Operation ([string]$Request.operation) -Scope ([string]$Request.scope) | Out-Null
  if ([string]$Request.status -notin @('pending', 'claimed', 'completed', 'failed')) { throw "REQUEST_STATUS_INVALID" }
  return $true
}

function Claim-AiBrainRequest {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$RunId
  )
  $candidate = Get-ChildItem -LiteralPath $Paths.PendingRequests -Filter '*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object Name |
    Select-Object -First 1
  if ($null -eq $candidate) { return $null }
  $claimedPath = Join-Path $Paths.ClaimedRequests $candidate.Name
  try {
    [IO.File]::Move($candidate.FullName, $claimedPath)
  } catch {
    return $null
  }
  try {
    $request = Read-AiBrainJson -Path $claimedPath
    Assert-AiBrainRequest -Request $request | Out-Null
    $request.status = 'claimed'
    $request.claimedRunId = $RunId
    Write-AiBrainJsonAtomic -Path $claimedPath -Value $request
    return [pscustomobject]@{ Path = $claimedPath; Request = $request }
  } catch {
    if (Test-Path -LiteralPath $claimedPath) {
      Move-Item -LiteralPath $claimedPath -Destination (Join-Path $Paths.FailedRequests $candidate.Name) -Force
    }
    throw
  }
}

function Set-AiBrainRequestJournal {
  param(
    [Parameter(Mandatory = $true)][object]$Claim,
    [Parameter(Mandatory = $true)][string]$JournalId
  )
  $Claim.Request.journalId = $JournalId
  Write-AiBrainJsonAtomic -Path $Claim.Path -Value $Claim.Request
}

function Complete-AiBrainRequest {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$Claim,
    [Parameter(Mandatory = $true)][string]$ResultCode,
    [switch]$Failed
  )
  Set-AiBrainProperty -Object $Claim.Request -Name 'status' -Value $(if ($Failed) { 'failed' } else { 'completed' })
  Set-AiBrainProperty -Object $Claim.Request -Name 'resultCode' -Value $ResultCode
  Set-AiBrainProperty -Object $Claim.Request -Name 'completedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
  Write-AiBrainJsonAtomic -Path $Claim.Path -Value $Claim.Request
  $destinationRoot = $(if ($Failed) { $Paths.FailedRequests } else { $Paths.CompletedRequests })
  $destination = Join-Path $destinationRoot ([IO.Path]::GetFileName($Claim.Path))
  if (Test-Path -LiteralPath $destination) { throw "REQUEST_DESTINATION_EXISTS" }
  [IO.File]::Move($Claim.Path, $destination)
}

function Fail-AiBrainPendingRequest {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$RequestId,
    [Parameter(Mandatory = $true)][string]$ResultCode
  )
  $path = Join-Path $Paths.PendingRequests "$RequestId.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
  $request = Read-AiBrainJson -Path $path
  Assert-AiBrainRequest -Request $request | Out-Null
  if ([string]$request.status -ne 'pending') { throw "REQUEST_PENDING_STATE_INVALID" }
  $claim = [pscustomobject]@{ Path = $path; Request = $request }
  Complete-AiBrainRequest -Paths $Paths -Claim $claim -ResultCode $ResultCode -Failed
  return $true
}

function Move-AiBrainClaimBackToPending {
  param([Parameter(Mandatory = $true)][object]$Paths, [Parameter(Mandatory = $true)][string]$ClaimedPath)
  $request = Read-AiBrainJson -Path $ClaimedPath
  Assert-AiBrainRequest -Request $request | Out-Null
  $request.status = 'pending'
  $request.claimedRunId = $null
  $request.journalId = $null
  Write-AiBrainJsonAtomic -Path $ClaimedPath -Value $request
  $destination = Join-Path $Paths.PendingRequests ([IO.Path]::GetFileName($ClaimedPath))
  if (Test-Path -LiteralPath $destination) { throw "REQUEST_PENDING_CONFLICT" }
  [IO.File]::Move($ClaimedPath, $destination)
}

function Recover-AiBrainClaimedRequests {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$State
  )
  foreach ($file in Get-ChildItem -LiteralPath $Paths.ClaimedRequests -Filter '*.json' -File -ErrorAction SilentlyContinue) {
    $request = Read-AiBrainJson -Path $file.FullName
    Assert-AiBrainRequest -Request $request | Out-Null
    $journal = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$request.journalId)) {
      $journalPath = Join-Path $Paths.Journals ("{0}.json" -f [string]$request.journalId)
      $journal = Read-AiBrainJson -Path $journalPath -Optional
    }
    if ($null -ne $journal -and [string]$journal.status -in @('committed', 'finalized')) {
      $claim = [pscustomobject]@{ Path = $file.FullName; Request = $request }
      Complete-AiBrainRequest -Paths $Paths -Claim $claim -ResultCode 'recovered_committed'
      continue
    }
    if ($null -ne $journal -and [string]$journal.status -eq 'conflict') {
      $claim = [pscustomobject]@{ Path = $file.FullName; Request = $request }
      Complete-AiBrainRequest -Paths $Paths -Claim $claim -ResultCode 'recovery_conflict' -Failed
      continue
    }
    Move-AiBrainClaimBackToPending -Paths $Paths -ClaimedPath $file.FullName
  }
  $State.activeRequestId = $null
}

function Get-AiBrainRequestLocation {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$RequestId
  )
  if ($RequestId -notmatch '^[a-f0-9]{32}$') { throw "REQUEST_ID_INVALID" }
  foreach ($entry in @(
    @{ status = 'pending'; root = $Paths.PendingRequests },
    @{ status = 'claimed'; root = $Paths.ClaimedRequests },
    @{ status = 'completed'; root = $Paths.CompletedRequests },
    @{ status = 'failed'; root = $Paths.FailedRequests }
  )) {
    $path = Join-Path $entry.root "$RequestId.json"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      return [pscustomobject]@{ Status = $entry.status; Path = $path; Request = Read-AiBrainJson -Path $path }
    }
  }
  return $null
}
