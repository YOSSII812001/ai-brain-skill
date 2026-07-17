[CmdletBinding()]
param(
  [ValidateSet('All', 'Unit', 'Integration')]
  [string]$Suite = 'All'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:FixtureRoot = Join-Path $PSScriptRoot 'fixtures'
$script:LibraryRoot = Join-Path $script:RepoRoot 'scripts\lib'
$script:Passed = 0
$script:Failed = New-Object System.Collections.ArrayList
$script:MockAgentExe = $null
$script:ExternalRuntimeRoots = New-Object System.Collections.ArrayList
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
$script:IndexContent = @'
---
title: Index
date_modified: 2026-07-17
type: index
status: complete
---
# Index
'@ + "`n"
$script:TopicContent = @'
---
title: Topic
date_modified: 2026-07-17
type: concept
status: complete
---
# Topic
'@ + "`n"

. (Join-Path $script:LibraryRoot 'AiBrain.Common.ps1')
. (Join-Path $script:LibraryRoot 'AiBrain.Schedule.ps1')
. (Join-Path $script:LibraryRoot 'AiBrain.Process.ps1')
. (Join-Path $script:LibraryRoot 'AiBrain.Transaction.ps1')
. (Join-Path $script:LibraryRoot 'AiBrain.Requests.ps1')
. (Join-Path $script:LibraryRoot 'AiBrain.Tasks.ps1')

function Assert-True {
  param([Parameter(Mandatory = $true)][bool]$Condition, [string]$Message = 'Expected true.')
  if (-not $Condition) { throw $Message }
}

function Assert-False {
  param([Parameter(Mandatory = $true)][bool]$Condition, [string]$Message = 'Expected false.')
  if ($Condition) { throw $Message }
}

function Assert-Equal {
  param(
    [AllowNull()][object]$Expected,
    [AllowNull()][object]$Actual,
    [string]$Message = 'Values differ.'
  )
  if ($null -eq $Expected -and $null -eq $Actual) { return }
  if ($null -eq $Expected -or $null -eq $Actual -or -not $Expected.Equals($Actual)) {
    throw ('{0} Expected=[{1}] Actual=[{2}]' -f $Message, $Expected, $Actual)
  }
}

function Assert-Match {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [string]$Message = 'Value did not match.'
  )
  if ($Value -notmatch $Pattern) {
    throw ('{0} Pattern=[{1}] Value=[{2}]' -f $Message, $Pattern, $Value)
  }
}

function Assert-Throws {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [Parameter(Mandatory = $true)][string]$Code
  )
  try {
    & $Action
  } catch {
    if ([string]$_.Exception.Message -eq $Code -or [string]$_.Exception.Message -match [regex]::Escape($Code)) {
      return
    }
    throw ('Expected error [{0}], got [{1}]' -f $Code, $_.Exception.Message)
  }
  throw ('Expected error [{0}], but no error was thrown.' -f $Code)
}

function Test-Case {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )
  try {
    & $Action
    $script:Passed++
    [Console]::Out.WriteLine("[PASS] $Name")
  } catch {
    [void]$script:Failed.Add([pscustomobject]@{
      Name = $Name
      Message = [string]$_.Exception.Message
      Position = [string]$_.InvocationInfo.PositionMessage
    })
    [Console]::Out.WriteLine("[FAIL] $Name :: $([string]$_.Exception.Message)")
  }
}

function New-TestDirectory {
  param([Parameter(Mandatory = $true)][string]$Name)
  $path = Join-Path $script:TestRoot ($Name + '-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
  return $path
}

function New-TestVault {
  param([Parameter(Mandatory = $true)][string]$Name)
  $vault = New-TestDirectory -Name $Name
  foreach ($relative in @('main', 'raw', 'wiki', 'wiki\concepts', 'wiki\_meta')) {
    New-Item -ItemType Directory -Path (Join-Path $vault $relative) -Force -ErrorAction Stop | Out-Null
  }
  Write-AiBrainTextAtomic -Path (Join-Path $vault 'wiki\index.md') -Text $script:IndexContent
  Write-AiBrainTextAtomic -Path (Join-Path $vault 'wiki\concepts\topic.md') -Text $script:TopicContent
  return $vault
}

function New-TestLimits {
  return [pscustomobject]@{
    timeoutSeconds = 60
    maxSourceFiles = 100
    maxSourceBytes = 1048576
    maxChangeFiles = 20
    maxChangeRatio = 1.0
    maxChangeBytes = 1048576
    maxCaptureBytes = 1048576
    minFreeSpaceBytes = 1
    legacyWaitSeconds = 5
    requestWaitSeconds = 5
    retentionDays = 30
    retainedFailedRuns = 2
    retainedPackages = 2
  }
}

function New-TransactionFixture {
  param([Parameter(Mandatory = $true)][string]$Name)
  $vault = New-TestVault -Name ($Name + '-vault')
  $runtime = New-TestDirectory -Name ($Name + '-runtime')
  $paths = Get-AiBrainRuntimePaths -RuntimeRoot $runtime
  Initialize-AiBrainRuntimeDirectories -Paths $paths
  $config = [pscustomobject]@{
    vaultPath = $vault
    limits = New-TestLimits
  }
  return [pscustomobject]@{
    Vault = $vault
    Paths = $paths
    Config = $config
  }
}

function New-ChangeSet {
  param(
    [ValidateSet('compile', 'lint')][string]$Operation = 'compile',
    [Parameter(Mandatory = $true)][object[]]$Changes
  )
  return [pscustomobject]@{
    schemaVersion = 'ai-brain-change-set-v1'
    operation = $Operation
    changes = $Changes
  }
}

function New-WriteChange {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Content)
  return [pscustomobject]@{
    path = $Path
    action = 'write'
    content = $Content
  }
}

function Build-MockAgent {
  param([Parameter(Mandatory = $true)][string]$OutputPath)
  $candidates = @(
    (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
  )
  $compiler = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace([string]$compiler)) { throw 'CSC_NOT_FOUND' }
  $source = Join-Path $script:FixtureRoot 'MockAgent.cs'
  $compilerOutput = & $compiler '/nologo' '/target:exe' ("/out:$OutputPath") $source 2>&1
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw ('MOCK_AGENT_COMPILE_FAILED ' + ($compilerOutput -join ' '))
  }
}

function Set-OldTimestamp {
  param([Parameter(Mandatory = $true)][string]$Path, [int]$Days = 60)
  (Get-Item -LiteralPath $Path -Force).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-$Days)
}

function Invoke-OrchestratorProcessRaw {
  param([Parameter(Mandatory = $true)][string]$RuntimeRoot)
  $engineName = $(if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh.exe' } else { 'powershell.exe' })
  $engine = Join-Path $PSHOME $engineName
  if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
    $engine = (Get-Process -Id $PID).Path
  }
  $scriptPath = Join-Path $script:RepoRoot 'scripts\invoke-ai-brain-sleep.ps1'
  $output = & $engine `
    '-NoLogo' `
    '-NoProfile' `
    '-NonInteractive' `
    '-ExecutionPolicy' 'Bypass' `
    '-File' $scriptPath `
    '-RuntimeRoot' $RuntimeRoot 2>&1
  $code = $LASTEXITCODE
  return [pscustomobject]@{
    ExitCode = $code
    Output = @($output)
  }
}

function Invoke-OrchestratorProcess {
  param([Parameter(Mandatory = $true)][string]$RuntimeRoot)
  $result = Invoke-OrchestratorProcessRaw -RuntimeRoot $RuntimeRoot
  if ([int]$result.ExitCode -ne 0) {
    $diagnostic = New-Object System.Collections.ArrayList
    [void]$diagnostic.Add(($result.Output -join ' '))
    try {
      $paths = Get-AiBrainRuntimePaths -RuntimeRoot $RuntimeRoot
      $state = Read-AiBrainJson -Path $paths.State -Optional
      if ($null -ne $state) {
        [void]$diagnostic.Add(('status={0}' -f [string]$state.status))
        [void]$diagnostic.Add(('attention={0}' -f [string]$state.attentionCode))
        [void]$diagnostic.Add(('failures={0}' -f [int]$state.sameFailureCount))
      }
      $log = Get-ChildItem -LiteralPath $paths.Logs -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
      if ($null -ne $log) {
        $events = @(Get-Content -LiteralPath $log.FullName | Select-Object -Last 5)
        [void]$diagnostic.Add(('events={0}' -f ($events -join ',')))
      }
    } catch {
      [void]$diagnostic.Add(('diagnostic={0}' -f [string]$_.Exception.Message))
    }
    throw ('ORCHESTRATOR_EXIT_{0} {1}' -f $result.ExitCode, (($diagnostic | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_)
    }) -join ' '))
  }
}

function Wait-TestProcessGone {
  param([Parameter(Mandatory = $true)][int]$ProcessId, [int]$TimeoutSeconds = 5)
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return $true }
    Start-Sleep -Milliseconds 100
  }
  return $null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Stop-TestMockProcess {
  param([Parameter(Mandatory = $true)][int]$ProcessId)
  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if ($null -eq $process) { return }
  $actual = [IO.Path]::GetFullPath([string]$process.Path)
  $expected = [IO.Path]::GetFullPath([string]$script:MockAgentExe)
  if (-not [string]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'TEST_PROCESS_KILL_GUARD_FAILED'
  }
  Stop-Process -Id $ProcessId -Force -ErrorAction Stop
  Wait-TestProcessGone -ProcessId $ProcessId -TimeoutSeconds 5 | Out-Null
}

function Install-TestRuntimePackage {
  param([Parameter(Mandatory = $true)][object]$Fixture)
  $packageId = [string]$Fixture.Config.packageId
  $packageRoot = Join-Path $Fixture.Paths.Packages $packageId
  if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $packageRoot -ErrorAction Stop | Out-Null
  }
  $relativeFiles = @(
    'scripts/ai-brain-sleep-bootstrap.ps1',
    'scripts/invoke-ai-brain-sleep.ps1',
    'scripts/lib/AiBrain.Common.ps1',
    'scripts/lib/AiBrain.Process.ps1',
    'scripts/lib/AiBrain.Requests.ps1',
    'scripts/lib/AiBrain.Schedule.ps1',
    'scripts/lib/AiBrain.Tasks.ps1',
    'scripts/lib/AiBrain.Transaction.ps1'
  )
  $manifestFiles = New-Object System.Collections.ArrayList
  foreach ($relative in $relativeFiles) {
    $source = Join-Path $script:RepoRoot $relative.Replace('/', '\')
    $target = Resolve-AiBrainChildPath `
      -Root $packageRoot `
      -RelativePath $relative `
      -AllowMissingLeaf
    Write-AiBrainTextAtomic -Path $target -Text (Read-AiBrainUtf8 -Path $source)
    [void]$manifestFiles.Add([ordered]@{
      path = $relative
      sha256 = Get-AiBrainFileSha256 -Path $target
    })
  }
  $active = [ordered]@{
    schemaVersion = 1
    packageId = $packageId
    packageRelativePath = "packages/$packageId"
    createdUtc = [DateTime]::UtcNow.ToString('o')
    files = @($manifestFiles)
  }
  Write-AiBrainJsonAtomic -Path $Fixture.Paths.ActivePackage -Value $active
  $packageBootstrap = Join-Path $packageRoot 'scripts\ai-brain-sleep-bootstrap.ps1'
  Write-AiBrainTextAtomic `
    -Path $Fixture.Paths.Bootstrap `
    -Text (Read-AiBrainUtf8 -Path $packageBootstrap)
}

function Set-TestFixtureOff {
  param([Parameter(Mandatory = $true)][object]$Fixture)
  $Fixture.Config.enabled = $false
  $Fixture.Config.compileEnabled = $false
  $Fixture.Config.lintEnabled = $false
  $Fixture.Config.limits.timeoutSeconds = 30
  $Fixture.Config.limits.requestWaitSeconds = 5
  Write-AiBrainJsonAtomic -Path $Fixture.Paths.Config -Value $Fixture.Config
  $state = Read-AiBrainState -Paths $Fixture.Paths
  $state.status = 'off'
  $state.nextCompileUtc = $null
  $state.nextLintUtc = $null
  $state.lastHeartbeatUtc = [DateTime]::UtcNow.ToString('o')
  Set-AiBrainState -Paths $Fixture.Paths -State $state
}

function Invoke-TestManager {
  param(
    [Parameter(Mandatory = $true)][string]$RuntimeRoot,
    [Parameter(Mandatory = $true)][string]$Action,
    [ValidateSet('compile', 'lint')][string]$Operation = 'compile',
    [string]$Scope = 'all',
    [switch]$Repair,
    [switch]$ApproveStateReset,
    [int]$BulkMaxFiles = 0,
    [long]$BulkMaxBytes = 0
  )
  $engineName = $(if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh.exe' } else { 'powershell.exe' })
  $engine = Join-Path $PSHOME $engineName
  if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
    $engine = (Get-Process -Id $PID).Path
  }
  $arguments = @(
    '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $script:FixtureRoot 'ManagerHarness.ps1'),
    '-ManagerPath', (Join-Path $script:RepoRoot 'scripts\manage-ai-brain-sleep.ps1'),
    '-RuntimeRoot', $RuntimeRoot,
    '-Action', $Action,
    '-Operation', $Operation,
    '-Scope', $Scope
  )
  if ($Repair) { $arguments += '-Repair' }
  if ($ApproveStateReset) { $arguments += '-ApproveStateReset' }
  if ($BulkMaxFiles -gt 0) { $arguments += @('-BulkMaxFiles', [string]$BulkMaxFiles) }
  if ($BulkMaxBytes -gt 0) { $arguments += @('-BulkMaxBytes', [string]$BulkMaxBytes) }
  $process = Invoke-AiBrainHiddenProcess `
    -CommandPath $engine `
    -Arguments $arguments `
    -WorkingDirectory $script:RepoRoot `
    -TimeoutSeconds 180 `
    -MaxCaptureBytes 4194304
  if ($process.TimedOut -or -not $process.Drained -or $process.StdOut.Truncated) {
    throw 'MANAGER_HARNESS_PROCESS_FAILED'
  }
  try {
    $envelope = ([string]$process.StdOut.Text).Trim() | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw ('MANAGER_HARNESS_JSON_INVALID stdout={0} stderr={1}' -f
      [string]$process.StdOut.Text, [string]$process.StdErr.Text)
  }
  return [pscustomobject]@{
    ExitCode = [int]$process.ExitCode
    Envelope = $envelope
    StdErr = [string]$process.StdErr.Text
  }
}

function Get-TestManagerResult {
  param([Parameter(Mandatory = $true)][object]$Envelope)
  $items = @($Envelope.result)
  if ($items.Count -eq 0) { return $null }
  return $items[0]
}

function Get-TestManagerError {
  param([Parameter(Mandatory = $true)][object]$Envelope)
  return '{0} id={1} position={2} stack={3}' -f
    [string]$Envelope.error,
    [string]$Envelope.errorId,
    [string]$Envelope.position,
    [string]$Envelope.stack
}

function Get-TestRequestDiagnostic {
  param([Parameter(Mandatory = $true)][object]$Paths)
  $pending = @(Get-ChildItem -LiteralPath $Paths.PendingRequests -Filter '*.json' -File -ErrorAction SilentlyContinue)
  $claimed = @(Get-ChildItem -LiteralPath $Paths.ClaimedRequests -Filter '*.json' -File -ErrorAction SilentlyContinue)
  $completed = @(Get-ChildItem -LiteralPath $Paths.CompletedRequests -Filter '*.json' -File -ErrorAction SilentlyContinue)
  $failed = @(Get-ChildItem -LiteralPath $Paths.FailedRequests -Filter '*.json' -File -ErrorAction SilentlyContinue)
  $resultCode = ''
  $terminal = @($completed + $failed | Select-Object -First 1)
  if ($terminal.Count -gt 0) {
    $resultCode = [string](Read-AiBrainJson -Path $terminal[0].FullName).resultCode
  }
  return 'pending={0} claimed={1} completed={2} failed={3} result={4}' -f
    $pending.Count, $claimed.Count, $completed.Count, $failed.Count, $resultCode
}

function New-OrchestratorFixture {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex')][string]$Target,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$RequestOperation
  )
  $vault = New-TestVault -Name ("orchestrator-$Target-vault")
  $packageId = ('a' * 64)
  $config = New-AiBrainConfig `
    -VaultPath $vault `
    -Target $Target `
    -AgentExecutable $script:MockAgentExe `
    -CompileIntervalHours 4 `
    -LintLocalTime '17:00' `
    -Enabled $true `
    -PackageId $packageId
  $config.lintEnabled = $false
  $runtime = [string]$config.runtimeRoot
  if (Test-Path -LiteralPath $runtime) { throw 'TEST_RUNTIME_ALREADY_EXISTS' }
  $expectedParent = Get-AiBrainCanonicalPath -Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'ai-brain')
  $actualParent = Get-AiBrainCanonicalPath -Path (Split-Path -Parent $runtime)
  if (-not [string]::Equals($expectedParent, $actualParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'TEST_RUNTIME_PARENT_GUARD_FAILED'
  }
  if ((Split-Path -Leaf $runtime) -ne [string]$config.vaultId) { throw 'TEST_RUNTIME_LEAF_GUARD_FAILED' }
  [void]$script:ExternalRuntimeRoots.Add($runtime)
  $paths = Get-AiBrainRuntimePaths -RuntimeRoot $runtime
  Initialize-AiBrainRuntimeDirectories -Paths $paths
  Assert-AiBrainConfig -Config $config | Out-Null
  Write-AiBrainJsonAtomic -Path $paths.Config -Value $config
  Assert-AiBrainConfig -Config (Read-AiBrainJson -Path $paths.Config) | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $paths.Packages $packageId) -ErrorAction Stop | Out-Null
  Write-AiBrainJsonAtomic -Path $paths.ActivePackage -Value ([ordered]@{
    schemaVersion = 1
    packageId = $packageId
  })

  $state = New-AiBrainState -Enabled $true
  $state.packageId = $packageId
  $state.taskGeneration = [string]$config.taskGeneration
  $state.lastCompileInputFingerprint = Get-AiBrainManifestFingerprint -Manifest (Get-AiBrainVaultManifest -VaultPath $vault)
  $lint = Get-AiBrainLintSlot `
    -NowUtc ([DateTime]::UtcNow) `
    -LocalTime ([string]$config.lintLocalTime) `
    -TimeZoneId ([string]$config.timeZoneId)
  $state.lastLintSlotId = $lint.Id
  Set-AiBrainState -Paths $paths -State $state

  return [pscustomobject]@{
    Target = $Target
    RequestOperation = $RequestOperation
    Vault = $vault
    Config = $config
    Paths = $paths
    Runtime = $runtime
  }
}

function Assert-TestRootForDelete {
  param([Parameter(Mandatory = $true)][string]$Path)
  $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\')
  $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $candidate.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'TEST_DELETE_OUTSIDE_TEMP'
  }
  if ((Split-Path -Leaf $candidate) -notmatch '^ai-brain-tests-[a-f0-9]{32}$') {
    throw 'TEST_DELETE_NAME_GUARD_FAILED'
  }
}

function Assert-ExternalRuntimeForDelete {
  param([Parameter(Mandatory = $true)][string]$Path)
  $candidate = Get-AiBrainCanonicalPath -Path $Path -MustExist
  $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  $parent = Get-AiBrainCanonicalPath -Path (Join-Path $local 'ai-brain')
  $candidateParent = Get-AiBrainCanonicalPath -Path (Split-Path -Parent $candidate)
  if (-not [string]::Equals($parent, $candidateParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'EXTERNAL_TEST_DELETE_PARENT_GUARD_FAILED'
  }
  if ((Split-Path -Leaf $candidate) -notmatch '^[a-f0-9]{16}$') {
    throw 'EXTERNAL_TEST_DELETE_LEAF_GUARD_FAILED'
  }
}

$script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('ai-brain-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:TestRoot -ErrorAction Stop | Out-Null

try {
  Test-Case -Name 'fixtures compile as a direct executable' -Action {
    $script:MockAgentExe = Join-Path $script:TestRoot 'MockAgent.exe'
    Build-MockAgent -OutputPath $script:MockAgentExe
    Assert-True (Test-Path -LiteralPath $script:MockAgentExe -PathType Leaf)
  }

  if ($Suite -in @('All', 'Unit')) {
    Test-Case -Name 'compile schedule uses one current four-hour slot' -Action {
      $now = [DateTime]::SpecifyKind([datetime]'2026-07-17T10:15:00', [DateTimeKind]::Utc)
      $slot = Get-AiBrainCompileSlot -NowUtc $now -IntervalHours 4
      Assert-Equal '2026-07-17T08:00:00.0000000Z' $slot.Id
      Assert-Equal ([DateTime]::SpecifyKind([datetime]'2026-07-17T12:00:00', [DateTimeKind]::Utc)) $slot.NextUtc
      Assert-Throws -Code 'COMPILE_INTERVAL_INVALID' -Action {
        Get-AiBrainCompileSlot -NowUtc $now -IntervalHours 0 | Out-Null
      }
    }

    Test-Case -Name 'due schedule orders compile before lint and catches up once' -Action {
      $config = [pscustomobject]@{
        compileIntervalHours = 4
        lintLocalTime = '17:00'
        timeZoneId = 'Tokyo Standard Time'
      }
      $state = New-AiBrainState -Enabled $true
      $state.lastCompileSlotUtc = '2000-01-01T00:00:00.0000000Z'
      $state.lastLintSlotId = '2000-01-01T17:00|Tokyo Standard Time'
      $due = @(Get-AiBrainDueOperations `
        -Config $config `
        -State $state `
        -NowUtc ([DateTime]::SpecifyKind([datetime]'2026-07-17T12:30:00', [DateTimeKind]::Utc)))
      Assert-Equal 2 $due.Count
      Assert-Equal 'compile' ([string]$due[0].operation)
      Assert-Equal 'lint' ([string]$due[1].operation)
    }

    Test-Case -Name 'lint schedule handles DST gaps and chooses later ambiguous instant' -Action {
      $zone = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
      $gap = [DateTime]::SpecifyKind([datetime]'2026-03-08T02:30:00', [DateTimeKind]::Unspecified)
      $gapUtc = ConvertTo-AiBrainLintUtc -LocalUnspecified $gap -TimeZone $zone
      Assert-Equal ([DateTime]::SpecifyKind([datetime]'2026-03-08T07:00:00', [DateTimeKind]::Utc)) $gapUtc
      $ambiguous = [DateTime]::SpecifyKind([datetime]'2026-11-01T01:30:00', [DateTimeKind]::Unspecified)
      $ambiguousUtc = ConvertTo-AiBrainLintUtc -LocalUnspecified $ambiguous -TimeZone $zone
      Assert-Equal ([DateTime]::SpecifyKind([datetime]'2026-11-01T06:30:00', [DateTimeKind]::Utc)) $ambiguousUtc
    }

    Test-Case -Name 'task XML is S4U with two non-expiring no-wake triggers' -Action {
      $runtime = New-TestDirectory -Name 'task-runtime'
      $config = [pscustomobject]@{
        runtimeRoot = $runtime
        compileIntervalHours = 4
        lintLocalTime = '17:00'
      }
      $bootstrap = Join-Path $script:RepoRoot 'scripts\ai-brain-sleep-bootstrap.ps1'
      $xml = Get-AiBrainTaskXml -Config $config -BootstrapPath $bootstrap
      Assert-True (Test-AiBrainTaskXmlContract -Xml $xml -CompileIntervalHours 4)
      [xml]$document = $xml
      $ns = New-Object Xml.XmlNamespaceManager($document.NameTable)
      $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
      Assert-Equal 1 (@($document.SelectNodes('//t:TimeTrigger', $ns))).Count
      Assert-Equal 1 (@($document.SelectNodes('//t:CalendarTrigger', $ns))).Count
      Assert-Equal 0 (@($document.SelectNodes('//t:EndBoundary', $ns))).Count
      Assert-Equal 'false' $document.SelectSingleNode('//t:WakeToRun', $ns).InnerText
      Assert-Equal 'true' $document.SelectSingleNode('//t:Hidden', $ns).InnerText
      Assert-Equal 'PT0S' $document.SelectSingleNode('//t:ExecutionTimeLimit', $ns).InnerText
      Assert-Equal 'PT4H' $document.SelectSingleNode('//t:TimeTrigger/t:Repetition/t:Interval', $ns).InnerText
      $calendarStart = $document.SelectSingleNode('//t:CalendarTrigger/t:StartBoundary', $ns).InnerText
      Assert-Equal '17:00' $calendarStart.Substring(11, 5)
      $actionArguments = $document.SelectSingleNode('//t:Actions/t:Exec/t:Arguments', $ns).InnerText
      Assert-Match -Value $actionArguments -Pattern '(?:^|\s)-WindowStyle\s+Hidden(?:\s|$)'
      $omittedRunLevelXml = $xml.Replace('<RunLevel>LeastPrivilege</RunLevel>', '')
      Assert-True (Test-AiBrainTaskXmlContract -Xml $omittedRunLevelXml -CompileIntervalHours 4)
      $highestRunLevelXml = $xml.Replace(
        '<RunLevel>LeastPrivilege</RunLevel>',
        '<RunLevel>HighestAvailable</RunLevel>')
      Assert-Throws -Code 'TASK_NOT_LIMITED' -Action {
        Test-AiBrainTaskXmlContract -Xml $highestRunLevelXml -CompileIntervalHours 4 | Out-Null
      }
      $omittedWakeToRunXml = $xml.Replace('<WakeToRun>false</WakeToRun>', '')
      Assert-True (Test-AiBrainTaskXmlContract -Xml $omittedWakeToRunXml -CompileIntervalHours 4)
      $wakeEnabledXml = $xml.Replace('<WakeToRun>false</WakeToRun>', '<WakeToRun>true</WakeToRun>')
      Assert-Throws -Code 'TASK_WAKE_ENABLED' -Action {
        Test-AiBrainTaskXmlContract -Xml $wakeEnabledXml -CompileIntervalHours 4 | Out-Null
      }
      $limitedXml = $xml.Replace(
        '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>',
        '<ExecutionTimeLimit>PT4H</ExecutionTimeLimit>')
      Assert-Throws -Code 'TASK_EXECUTION_LIMIT_ENABLED' -Action {
        Test-AiBrainTaskXmlContract -Xml $limitedXml -CompileIntervalHours 4 | Out-Null
      }
      $secretXml = $xml.Replace(
        '</Arguments>',
        ' --api-key=abcdefghijklmnopqrstuv</Arguments>')
      Assert-Throws -Code 'TASK_ARGUMENT_SECRET_FIELD' -Action {
        Test-AiBrainTaskXmlContract -Xml $secretXml -CompileIntervalHours 4 | Out-Null
      }
      $preflightXml = Get-AiBrainTaskXml `
        -Config $config `
        -BootstrapPath $bootstrap `
        -Preflight `
        -PreflightToken ('b' * 32)
      Assert-True (Test-AiBrainTaskXmlContract -Xml $preflightXml -Preflight)
      Assert-True (Test-AiBrainTaskXmlContract `
        -Xml $xml `
        -CompileIntervalHours 4 `
        -ExpectedBootstrapPath $bootstrap `
        -ExpectedRuntimeRoot $runtime)
      $wrongBootstrap = Join-Path $runtime 'wrong-bootstrap.ps1'
      $wrongActionXml = $xml.Replace($bootstrap, $wrongBootstrap)
      Assert-Throws -Code 'TASK_ACTION_ARGUMENTS_INVALID' -Action {
        Test-AiBrainTaskXmlContract `
          -Xml $wrongActionXml `
          -CompileIntervalHours 4 `
          -ExpectedBootstrapPath $bootstrap `
          -ExpectedRuntimeRoot $runtime | Out-Null
      }
    }

    Test-Case -Name 'atomic text is strict UTF-8 without BOM' -Action {
      $directory = New-TestDirectory -Name 'atomic'
      $path = Join-Path $directory 'value.txt'
      $text = 'alpha-' + [char]0x3042 + '-omega'
      Write-AiBrainTextAtomic -Path $path -Text $text
      Assert-Equal $text (Read-AiBrainUtf8 -Path $path)
      $bytes = [IO.File]::ReadAllBytes($path)
      Assert-False ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf)
      Write-AiBrainTextAtomic -Path $path -Text 'replacement'
      Assert-Equal 'replacement' (Read-AiBrainUtf8 -Path $path)
      Assert-Equal 0 (@(Get-ChildItem -LiteralPath $directory -Filter '.ai-brain-*.tmp')).Count
      $bomPath = Join-Path $directory 'bom.txt'
      [IO.File]::WriteAllBytes($bomPath, [byte[]](0xef, 0xbb, 0xbf, 0x61))
      Assert-Throws -Code 'UTF8_BOM_NOT_ALLOWED' -Action {
        Read-AiBrainUtf8 -Path $bomPath | Out-Null
      }
    }

    Test-Case -Name 'task backup restore rejects changed XML bytes' -Action {
      $directory = New-TestDirectory -Name 'task-backup'
      $path = Join-Path $directory 'task.xml'
      $xml = '<Task><Actions /></Task>'
      Write-AiBrainTextAtomic -Path $path -Text $xml
      $hash = Get-AiBrainTaskXmlHash -Xml $xml
      Assert-Equal $xml (Read-AiBrainVerifiedTaskXml `
        -Path $path `
        -ExpectedHash $hash `
        -FailureCode 'TASK_BACKUP_HASH_MISMATCH')
      Write-AiBrainTextAtomic -Path $path -Text '<Task><Triggers /></Task>'
      Assert-Throws -Code 'TASK_BACKUP_HASH_MISMATCH' -Action {
        Read-AiBrainVerifiedTaskXml `
          -Path $path `
          -ExpectedHash $hash `
          -FailureCode 'TASK_BACKUP_HASH_MISMATCH' | Out-Null
      }
    }

    Test-Case -Name 'empty vault manifests and empty rollback bytes remain valid collections' -Action {
      $vault = New-TestDirectory -Name 'empty-vault'
      foreach ($layer in @('main', 'raw', 'wiki')) {
        New-Item -ItemType Directory -Path (Join-Path $vault $layer) -ErrorAction Stop | Out-Null
      }
      [object[]]$manifest = Get-AiBrainVaultManifest -VaultPath $vault
      Assert-Equal 0 $manifest.Count
      $fingerprint = Get-AiBrainManifestFingerprint -Manifest $manifest
      Assert-Match -Value $fingerprint -Pattern '^[a-f0-9]{64}$'
      $emptyFile = Join-Path $vault 'empty.bin'
      Write-AiBrainBytesDurable -Path $emptyFile -Bytes ([byte[]]@())
      Assert-Equal 0 ([IO.File]::ReadAllBytes($emptyFile)).Length
    }

    Test-Case -Name 'path guards isolate multiple local vaults' -Action {
      $first = New-TestVault -Name 'vault-one'
      $second = New-TestVault -Name 'vault-two'
      $firstId = Get-AiBrainVaultId -VaultPath $first
      $secondId = Get-AiBrainVaultId -VaultPath $second
      Assert-False ([string]::Equals($firstId, $secondId, [StringComparison]::OrdinalIgnoreCase))
      Assert-False ([string]::Equals(
        (Get-AiBrainExpectedRuntimeRoot -VaultId $firstId),
        (Get-AiBrainExpectedRuntimeRoot -VaultId $secondId),
        [StringComparison]::OrdinalIgnoreCase))
      Assert-False (Test-AiBrainRelativePath -Path '..\escape.md')
      Assert-False (Test-AiBrainPathWithin -Root $first -Candidate $second)
      Assert-Throws -Code 'RELATIVE_PATH_INVALID' -Action {
        Resolve-AiBrainChildPath -Root $first -RelativePath '..\escape.md' -AllowMissingLeaf | Out-Null
      }
      Assert-Throws -Code 'NETWORK_OR_DEVICE_PATH_NOT_SUPPORTED' -Action {
        Get-AiBrainCanonicalPath -Path '\\server\share' | Out-Null
      }

      $junctionRoot = New-TestDirectory -Name 'junction-root'
      $outside = New-TestDirectory -Name 'junction-outside'
      $junction = Join-Path $junctionRoot 'linked'
      New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop | Out-Null
      try {
        Assert-Throws -Code 'REPARSE_POINT_NOT_ALLOWED' -Action {
          Assert-AiBrainNoReparsePath `
            -Path (Join-Path $junction 'missing\deeper\file.md') `
            -AllowMissingLeaf | Out-Null
        }
      } finally {
        if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force }
      }
      Assert-True (Test-Path -LiteralPath $outside -PathType Container)
    }

    Test-Case -Name 'legacy task migration requires one exact canonical vault' -Action {
      $scriptRoot = New-TestDirectory -Name 'legacy-script'
      $scriptPath = Join-Path $scriptRoot 'wiki-compile-scheduled.ps1'
      Write-AiBrainTextAtomic -Path $scriptPath -Text "exit 0`n"
      $firstParent = New-TestDirectory -Name 'legacy-parent-one'
      $secondParent = New-TestDirectory -Name 'legacy-parent-two'
      $firstVault = Join-Path $firstParent 'SameVault'
      $secondVault = Join-Path $secondParent 'SameVault'
      New-AiBrainDirectorySafe -Path $firstVault | Out-Null
      New-AiBrainDirectorySafe -Path $secondVault | Out-Null
      $scriptXml = [Security.SecurityElement]::Escape($scriptPath)
      $firstVaultXml = [Security.SecurityElement]::Escape($firstVault)
      $secondVaultXml = [Security.SecurityElement]::Escape($secondVault)
      $leafOnlyXml = '<Task><Actions><Exec><Arguments>-File "' + $scriptXml +
        '"</Arguments></Exec></Actions></Task>'
      $commandText = "vault: SameVault`n"
      Assert-True (Test-AiBrainLegacyTaskContract `
        -Xml $leafOnlyXml `
        -ExpectedScriptPath $scriptPath `
        -ExpectedVaultPath $firstVault `
        -CommandText $commandText `
        -RegisteredVaultPaths @($firstVault))
      Assert-False (Test-AiBrainLegacyTaskContract `
        -Xml $leafOnlyXml `
        -ExpectedScriptPath $scriptPath `
        -ExpectedVaultPath $firstVault `
        -CommandText $commandText `
        -RegisteredVaultPaths @($firstVault, $secondVault))
      $explicitFirstXml = '<Task><Actions><Exec><Arguments>-File "' + $scriptXml +
        '" -VaultPath "' + $firstVaultXml + '"</Arguments></Exec></Actions></Task>'
      Assert-True (Test-AiBrainLegacyTaskContract `
        -Xml $explicitFirstXml `
        -ExpectedScriptPath $scriptPath `
        -ExpectedVaultPath $firstVault `
        -CommandText $commandText `
        -RegisteredVaultPaths @($firstVault, $secondVault))
      $explicitSecondXml = '<Task><Actions><Exec><Arguments>-File "' + $scriptXml +
        '" -VaultPath "' + $secondVaultXml + '"</Arguments></Exec></Actions></Task>'
      Assert-False (Test-AiBrainLegacyTaskContract `
        -Xml $explicitSecondXml `
        -ExpectedScriptPath $scriptPath `
        -ExpectedVaultPath $firstVault `
        -CommandText $commandText `
        -RegisteredVaultPaths @($firstVault, $secondVault))
    }

    Test-Case -Name 'change-set validates frontmatter links scope and secrets in staging' -Action {
      $fixture = New-TransactionFixture -Name 'change-validation'
      $runId = [Guid]::NewGuid().ToString('N')
      $run = New-AiBrainRunDirectory -Paths $fixture.Paths -RunId $runId
      New-AiBrainSourceBundle -Config $fixture.Config -RunDirectory $run | Out-Null
      $valid = @'
---
title: Linked
date_modified: 2026-07-17
type: synthesis
status: complete
---
# Linked
See [[concepts/topic]].
'@ + "`n"
      $changeSet = New-ChangeSet -Changes @(
        (New-WriteChange -Path 'wiki/linked.md' -Content $valid)
      )
      Test-AiBrainChangeSet `
        -ChangeSet $changeSet `
        -Config $fixture.Config `
        -Operation compile `
        -Scope all `
        -RunDirectory $run `
        -ExistingWikiCount 2 | Out-Null
      Materialize-AiBrainChangeSet -ChangeSet $changeSet -RunDirectory $run
      Assert-True (Test-Path -LiteralPath (Join-Path $run 'wiki\linked.md') -PathType Leaf)
      Assert-False (Test-Path -LiteralPath (Join-Path $fixture.Vault 'wiki\linked.md'))

      Assert-Throws -Code 'MARKDOWN_FRONTMATTER_REQUIRED' -Action {
        Test-AiBrainFrontmatter -Content '# Missing' | Out-Null
      }
      $brokenLink = $valid.Replace('[[concepts/topic]]', '[[missing]]')
      $brokenSet = New-ChangeSet -Changes @(
        (New-WriteChange -Path 'wiki\broken.md' -Content $brokenLink)
      )
      Assert-Throws -Code 'WIKILINK_TARGET_MISSING' -Action {
        Test-AiBrainChangeSet `
          -ChangeSet $brokenSet `
          -Config $fixture.Config `
          -Operation compile `
          -Scope all `
          -RunDirectory $run `
          -ExistingWikiCount 2 | Out-Null
      }
      $scopeSet = New-ChangeSet -Changes @(
        (New-WriteChange -Path 'wiki/linked.md' -Content $valid)
      )
      Assert-Throws -Code 'CHANGE_SET_PATH_OUT_OF_SCOPE' -Action {
        Test-AiBrainChangeSet `
          -ChangeSet $scopeSet `
          -Config $fixture.Config `
          -Operation compile `
          -Scope concepts `
          -RunDirectory $run `
          -ExistingWikiCount 2 | Out-Null
      }
      $secretContent = $valid + 'api_key=abcdefghijklmnopqrstuv' + "`n"
      $secretSet = New-ChangeSet -Changes @(
        (New-WriteChange -Path 'wiki\secret.md' -Content $secretContent)
      )
      Assert-Throws -Code 'CHANGE_SET_SECRET_DETECTED' -Action {
        Test-AiBrainChangeSet `
          -ChangeSet $secretSet `
          -Config $fixture.Config `
          -Operation compile `
          -Scope all `
          -RunDirectory $run `
          -ExistingWikiCount 2 | Out-Null
      }
    }

    Test-Case -Name 'source bundle rejects denied files and source secrets' -Action {
      $fixture = New-TransactionFixture -Name 'source-reject'
      Write-AiBrainTextAtomic -Path (Join-Path $fixture.Vault 'main\.env') -Text 'SAFE_NAME_ONLY'
      $run = New-AiBrainRunDirectory -Paths $fixture.Paths -RunId ([Guid]::NewGuid().ToString('N'))
      Assert-Throws -Code 'SOURCE_DENIED_FILE' -Action {
        New-AiBrainSourceBundle -Config $fixture.Config -RunDirectory $run | Out-Null
      }
      Remove-Item -LiteralPath (Join-Path $fixture.Vault 'main\.env') -Force
      Write-AiBrainTextAtomic `
        -Path (Join-Path $fixture.Vault 'main\note.md') `
        -Text 'password=abcdefghijklmnopqrstuv'
      $runTwo = New-AiBrainRunDirectory -Paths $fixture.Paths -RunId ([Guid]::NewGuid().ToString('N'))
      Assert-Throws -Code 'SOURCE_SECRET_DETECTED' -Action {
        New-AiBrainSourceBundle -Config $fixture.Config -RunDirectory $runTwo | Out-Null
      }
    }

    Test-Case -Name 'source bundle accepts UTF-8 BOM without weakening runtime JSON' -Action {
      $fixture = New-TransactionFixture -Name 'source-bom'
      $source = Join-Path $fixture.Vault 'main\bom.csv'
      [IO.File]::WriteAllBytes($source, [byte[]](0xef, 0xbb, 0xbf, 0x61, 0x2c, 0x62, 0x0a))
      $run = New-AiBrainRunDirectory -Paths $fixture.Paths -RunId ([Guid]::NewGuid().ToString('N'))
      $bundle = New-AiBrainSourceBundle -Config $fixture.Config -RunDirectory $run
      $entry = @($bundle.files | Where-Object { $_.path -eq 'main/bom.csv' })
      Assert-Equal 1 $entry.Count
      Assert-Equal "a,b`n" ([string]$entry[0].content)
      Assert-Throws -Code 'UTF8_BOM_NOT_ALLOWED' -Action {
        Read-AiBrainUtf8 -Path $source | Out-Null
      }
    }

    Test-Case -Name 'wiki transaction commits atomically and finalizes journal' -Action {
      $fixture = New-TransactionFixture -Name 'transaction-commit'
      $runId = [Guid]::NewGuid().ToString('N')
      $run = New-AiBrainRunDirectory -Paths $fixture.Paths -RunId $runId
      New-AiBrainSourceBundle -Config $fixture.Config -RunDirectory $run | Out-Null
      $content = @'
---
title: New Page
date_modified: 2026-07-17
type: synthesis
status: complete
---
# New Page
'@ + "`n"
      $changeSet = New-ChangeSet -Changes @(
        (New-WriteChange -Path 'wiki\new-page.md' -Content $content)
      )
      Test-AiBrainChangeSet `
        -ChangeSet $changeSet `
        -Config $fixture.Config `
        -Operation compile `
        -Scope all `
        -RunDirectory $run `
        -ExistingWikiCount 2 | Out-Null
      Materialize-AiBrainChangeSet -ChangeSet $changeSet -RunDirectory $run
      $baseline = Get-AiBrainVaultManifest -VaultPath $fixture.Vault
      $transaction = Invoke-AiBrainWikiTransaction `
        -Config $fixture.Config `
        -Paths $fixture.Paths `
        -ChangeSet $changeSet `
        -RunDirectory $run `
        -BaselineManifest $baseline `
        -RunId $runId `
        -Operation compile `
        -Scope all
      Assert-Equal $content (Read-AiBrainUtf8 -Path (Join-Path $fixture.Vault 'wiki\new-page.md'))
      Assert-Equal 'committed' ([string](Read-AiBrainJson -Path $transaction.JournalPath).status)
      Complete-AiBrainJournal -JournalPath $transaction.JournalPath
      Assert-Equal 'finalized' ([string](Read-AiBrainJson -Path $transaction.JournalPath).status)
    }

    Test-Case -Name 'wiki transaction rolls back after staged integrity failure' -Action {
      $fixture = New-TransactionFixture -Name 'transaction-rollback'
      $originalIndex = Read-AiBrainUtf8 -Path (Join-Path $fixture.Vault 'wiki\index.md')
      $originalTopic = Read-AiBrainUtf8 -Path (Join-Path $fixture.Vault 'wiki\concepts\topic.md')
      $newIndex = $originalIndex.Replace('# Index', '# Changed Index')
      $newTopic = $originalTopic.Replace('# Topic', '# Changed Topic')
      $runId = [Guid]::NewGuid().ToString('N')
      $run = New-AiBrainRunDirectory -Paths $fixture.Paths -RunId $runId
      New-AiBrainSourceBundle -Config $fixture.Config -RunDirectory $run | Out-Null
      $changeSet = New-ChangeSet -Changes @(
        (New-WriteChange -Path 'wiki\index.md' -Content $newIndex),
        (New-WriteChange -Path 'wiki\concepts\topic.md' -Content $newTopic)
      )
      Test-AiBrainChangeSet `
        -ChangeSet $changeSet `
        -Config $fixture.Config `
        -Operation compile `
        -Scope all `
        -RunDirectory $run `
        -ExistingWikiCount 2 | Out-Null
      Materialize-AiBrainChangeSet -ChangeSet $changeSet -RunDirectory $run
      Write-AiBrainTextAtomic `
        -Path (Join-Path $run 'wiki\concepts\topic.md') `
        -Text ($newTopic + 'corrupt')
      $baseline = Get-AiBrainVaultManifest -VaultPath $fixture.Vault
      Assert-Throws -Code 'STAGING_INTEGRITY_FAILED' -Action {
        Invoke-AiBrainWikiTransaction `
          -Config $fixture.Config `
          -Paths $fixture.Paths `
          -ChangeSet $changeSet `
          -RunDirectory $run `
          -BaselineManifest $baseline `
          -RunId $runId `
          -Operation compile `
          -Scope all | Out-Null
      }
      Assert-Equal $originalIndex (Read-AiBrainUtf8 -Path (Join-Path $fixture.Vault 'wiki\index.md'))
      Assert-Equal $originalTopic (Read-AiBrainUtf8 -Path (Join-Path $fixture.Vault 'wiki\concepts\topic.md'))
      $journal = Read-AiBrainJson -Path (Join-Path $fixture.Paths.Journals "$runId.json")
      Assert-Equal 'rolled_back' ([string]$journal.status)
    }

    Test-Case -Name 'journal crash recovery is idempotent' -Action {
      $fixture = New-TransactionFixture -Name 'crash-recovery'
      $target = Join-Path $fixture.Vault 'wiki\index.md'
      $beforeBytes = [IO.File]::ReadAllBytes($target)
      $beforeHash = Get-AiBrainFileSha256 -Path $target
      $appliedText = $script:IndexContent.Replace('# Index', '# Applied Before Crash')
      Write-AiBrainTextAtomic -Path $target -Text $appliedText
      $appliedHash = Get-AiBrainFileSha256 -Path $target
      $runId = [Guid]::NewGuid().ToString('N')
      $backupRelative = "$runId/wiki/index.md"
      $backup = Resolve-AiBrainChildPath `
        -Root $fixture.Paths.Backups `
        -RelativePath $backupRelative `
        -AllowMissingLeaf
      New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
      [IO.File]::WriteAllBytes($backup, $beforeBytes)
      $journal = [ordered]@{
        schemaVersion = 1
        runId = $runId
        requestId = $null
        operation = 'compile'
        scope = 'all'
        slotId = $null
        status = 'applying'
        createdUtc = [DateTime]::UtcNow.ToString('o')
        entries = @(
          [ordered]@{
            path = 'wiki/index.md'
            action = 'write'
            existed = $true
            beforeHash = $beforeHash
            stagedHash = $appliedHash
            backup = $backupRelative
            applied = $false
            appliedHash = $null
            rolledBack = $false
          }
        )
      }
      $journalPath = Join-Path $fixture.Paths.Journals "$runId.json"
      Write-AiBrainJournal -Path $journalPath -Journal $journal
      $first = @(Recover-AiBrainJournals -Config $fixture.Config -Paths $fixture.Paths)
      Assert-Equal 1 $first.Count
      Assert-Equal $beforeHash (Get-AiBrainFileSha256 -Path $target)
      Assert-Equal 'rolled_back' ([string](Read-AiBrainJson -Path $journalPath).status)
      $second = @(Recover-AiBrainJournals -Config $fixture.Config -Paths $fixture.Paths)
      Assert-Equal 0 $second.Count
      Assert-Equal $beforeHash (Get-AiBrainFileSha256 -Path $target)
    }

    Test-Case -Name 'wiki transaction detects external edits before apply' -Action {
      $fixture = New-TransactionFixture -Name 'external-edit'
      $runId = [Guid]::NewGuid().ToString('N')
      $run = New-AiBrainRunDirectory -Paths $fixture.Paths -RunId $runId
      New-AiBrainSourceBundle -Config $fixture.Config -RunDirectory $run | Out-Null
      $content = $script:TopicContent.Replace('# Topic', '# New External Test')
      $changeSet = New-ChangeSet -Changes @(
        (New-WriteChange -Path 'wiki\concepts\topic.md' -Content $content)
      )
      Test-AiBrainChangeSet `
        -ChangeSet $changeSet `
        -Config $fixture.Config `
        -Operation compile `
        -Scope all `
        -RunDirectory $run `
        -ExistingWikiCount 2 | Out-Null
      Materialize-AiBrainChangeSet -ChangeSet $changeSet -RunDirectory $run
      $baseline = Get-AiBrainVaultManifest -VaultPath $fixture.Vault
      Write-AiBrainTextAtomic `
        -Path (Join-Path $fixture.Vault 'main\human-edit.md') `
        -Text 'human edit'
      Assert-Throws -Code 'EXTERNAL_EDIT_CONFLICT' -Action {
        Invoke-AiBrainWikiTransaction `
          -Config $fixture.Config `
          -Paths $fixture.Paths `
          -ChangeSet $changeSet `
          -RunDirectory $run `
          -BaselineManifest $baseline `
          -RunId $runId `
          -Operation compile `
          -Scope all | Out-Null
      }
    }

    Test-Case -Name 'request queue scopes claims races completion and recovery' -Action {
      $runtime = New-TestDirectory -Name 'requests'
      $paths = Get-AiBrainRuntimePaths -RuntimeRoot $runtime
      Initialize-AiBrainRuntimeDirectories -Paths $paths
      Assert-Throws -Code 'REQUEST_SCOPE_INVALID' -Action {
        New-AiBrainRequest -Paths $paths -Operation lint -Scope 'page:nope' | Out-Null
      }
      $request = New-AiBrainRequest -Paths $paths -Operation compile -Scope 'page:concepts/topic'
      $runId = [Guid]::NewGuid().ToString('N')
      $claim = Claim-AiBrainRequest -Paths $paths -RunId $runId
      Assert-Equal ([string]$request.requestId) ([string]$claim.Request.requestId)
      Assert-Equal $null (Claim-AiBrainRequest -Paths $paths -RunId ([Guid]::NewGuid().ToString('N')))
      Complete-AiBrainRequest -Paths $paths -Claim $claim -ResultCode 'clean'
      $location = Get-AiBrainRequestLocation -Paths $paths -RequestId ([string]$request.requestId)
      Assert-Equal 'completed' ([string]$location.Status)

      $recoverRequest = New-AiBrainRequest -Paths $paths -Operation lint -Scope links
      $recoverRun = [Guid]::NewGuid().ToString('N')
      $recoverClaim = Claim-AiBrainRequest -Paths $paths -RunId $recoverRun
      Set-AiBrainRequestJournal -Claim $recoverClaim -JournalId $recoverRun
      Write-AiBrainJsonAtomic `
        -Path (Join-Path $paths.Journals "$recoverRun.json") `
        -Value ([ordered]@{
          schemaVersion = 1
          runId = $recoverRun
          status = 'committed'
        })
      $state = New-AiBrainState -Enabled $true
      $state.activeRequestId = [string]$recoverRequest.requestId
      Recover-AiBrainClaimedRequests -Paths $paths -State $state
      Assert-Equal $null $state.activeRequestId
      Assert-Equal 'completed' ([string](Get-AiBrainRequestLocation `
        -Paths $paths `
        -RequestId ([string]$recoverRequest.requestId)).Status)
    }

    Test-Case -Name 'three identical failures pause the scheduler' -Action {
      $runtime = New-TestDirectory -Name 'failures'
      $paths = Get-AiBrainRuntimePaths -RuntimeRoot $runtime
      Initialize-AiBrainRuntimeDirectories -Paths $paths
      $state = New-AiBrainState -Enabled $true
      $state.activeRequestId = [Guid]::NewGuid().ToString('N')
      Register-AiBrainFailure -Paths $paths -State $state -Code 'TEST_FAILURE'
      Assert-Equal 'ready' ([string]$state.status)
      Assert-Equal 1 ([int]$state.sameFailureCount)
      Assert-Equal $null $state.activeRequestId
      Register-AiBrainFailure -Paths $paths -State $state -Code 'TEST_FAILURE'
      Assert-Equal 'ready' ([string]$state.status)
      Register-AiBrainFailure -Paths $paths -State $state -Code 'TEST_FAILURE'
      Assert-Equal 'paused' ([string]$state.status)
      Assert-Equal 3 ([int]$state.sameFailureCount)
      Assert-Equal 'REPEATED_FAILURE_PAUSED' ([string]$state.attentionCode)
    }

    Test-Case -Name 'successful scheduler repair clears only its own attention' -Action {
      $state = New-AiBrainState -Enabled $true
      $state.status = 'attention'
      $state.attentionCode = 'SCHEDULER_INSTALL_FAILED'
      $state.attentionAction = 'repair scheduler'
      $state.activeRequestId = [Guid]::NewGuid().ToString('N')
      Assert-True (Clear-AiBrainAttentionIfCode `
        -State $state `
        -ExpectedCode 'SCHEDULER_INSTALL_FAILED' `
        -Enabled $true `
        -RecoveryCode 'SCHEDULER_INSTALL_RECOVERED')
      Assert-Equal 'ready' ([string]$state.status)
      Assert-Equal $null $state.attentionCode
      Assert-Equal $null $state.attentionAction
      Assert-Equal $null $state.activeRequestId
      Assert-Equal 'SCHEDULER_INSTALL_RECOVERED' ([string]$state.lastRecoveryCode)

      $other = New-AiBrainState -Enabled $true
      $other.status = 'attention'
      $other.attentionCode = 'AGENT_AUTH_REQUIRED'
      Assert-False (Clear-AiBrainAttentionIfCode `
        -State $other `
        -ExpectedCode 'SCHEDULER_INSTALL_FAILED' `
        -Enabled $true `
        -RecoveryCode 'SCHEDULER_INSTALL_RECOVERED')
      Assert-Equal 'attention' ([string]$other.status)
      Assert-Equal 'AGENT_AUTH_REQUIRED' ([string]$other.attentionCode)
    }

    Test-Case -Name 'attention clears active execution identity' -Action {
      $runtime = New-TestDirectory -Name 'attention-active-request'
      $paths = Get-AiBrainRuntimePaths -RuntimeRoot $runtime
      Initialize-AiBrainRuntimeDirectories -Paths $paths
      $state = New-AiBrainState -Enabled $true
      $state.status = 'running'
      $state.runId = [Guid]::NewGuid().ToString('N')
      $state.activeRequestId = [Guid]::NewGuid().ToString('N')
      $state.child = [ordered]@{ status = 'running' }
      Set-AiBrainAttention -Paths $paths -State $state -Code 'TEST_ATTENTION' -Action 'repair'
      Assert-Equal 'attention' ([string]$state.status)
      Assert-Equal $null $state.runId
      Assert-Equal $null $state.activeRequestId
      Assert-Equal $null $state.child
    }

    Test-Case -Name 'runtime maintenance enforces bounded retention' -Action {
      $runtime = New-TestDirectory -Name 'retention'
      $paths = Get-AiBrainRuntimePaths -RuntimeRoot $runtime
      Initialize-AiBrainRuntimeDirectories -Paths $paths
      $limits = New-TestLimits
      $config = [pscustomobject]@{ limits = $limits }
      $activeId = ('a' * 64)
      Write-AiBrainJsonAtomic -Path $paths.ActivePackage -Value ([ordered]@{ packageId = $activeId })

      $oldLog = Join-Path $paths.Logs 'sleep-old.jsonl'
      Write-AiBrainTextAtomic -Path $oldLog -Text "{}`n"
      Set-OldTimestamp -Path $oldLog
      $newLog = Join-Path $paths.Logs 'sleep-new.jsonl'
      Write-AiBrainTextAtomic -Path $newLog -Text "{}`n"

      $oldCompleted = Join-Path $paths.CompletedRequests (([Guid]::NewGuid().ToString('N')) + '.json')
      Write-AiBrainTextAtomic -Path $oldCompleted -Text "{}`n"
      Set-OldTimestamp -Path $oldCompleted

      $runId = [Guid]::NewGuid().ToString('N')
      $journalPath = Join-Path $paths.Journals "$runId.json"
      Write-AiBrainJsonAtomic -Path $journalPath -Value ([ordered]@{
        schemaVersion = 1
        runId = $runId
        status = 'finalized'
      })
      Set-OldTimestamp -Path $journalPath
      $backup = Join-Path $paths.Backups $runId
      New-Item -ItemType Directory -Path $backup | Out-Null
      Write-AiBrainTextAtomic -Path (Join-Path $backup 'value.txt') -Text 'backup'

      $stageOne = Join-Path $paths.Staging ([Guid]::NewGuid().ToString('N'))
      $stageTwo = Join-Path $paths.Staging ([Guid]::NewGuid().ToString('N'))
      $stageThree = Join-Path $paths.Staging ([Guid]::NewGuid().ToString('N'))
      foreach ($stage in @($stageOne, $stageTwo, $stageThree)) {
        New-Item -ItemType Directory -Path $stage | Out-Null
        Start-Sleep -Milliseconds 20
      }
      (Get-Item -LiteralPath $stageOne).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-3)
      (Get-Item -LiteralPath $stageTwo).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-2)
      (Get-Item -LiteralPath $stageThree).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-1)

      $otherOne = ('b' * 64)
      $otherTwo = ('c' * 64)
      foreach ($package in @($activeId, $otherOne, $otherTwo)) {
        New-Item -ItemType Directory -Path (Join-Path $paths.Packages $package) | Out-Null
        Start-Sleep -Milliseconds 20
      }
      (Get-Item -LiteralPath (Join-Path $paths.Packages $otherOne)).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-2)
      (Get-Item -LiteralPath (Join-Path $paths.Packages $otherTwo)).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-1)
      $oldTempPackage = Join-Path $paths.Packages '.old.tmp'
      New-Item -ItemType Directory -Path $oldTempPackage | Out-Null
      Set-OldTimestamp -Path $oldTempPackage -Days 2

      Invoke-AiBrainRuntimeMaintenance -Config $config -Paths $paths
      Assert-False (Test-Path -LiteralPath $oldLog)
      Assert-True (Test-Path -LiteralPath $newLog)
      Assert-False (Test-Path -LiteralPath $oldCompleted)
      Assert-False (Test-Path -LiteralPath $journalPath)
      Assert-False (Test-Path -LiteralPath $backup)
      Assert-False (Test-Path -LiteralPath $stageOne)
      Assert-True (Test-Path -LiteralPath $stageTwo)
      Assert-True (Test-Path -LiteralPath $stageThree)
      Assert-True (Test-Path -LiteralPath (Join-Path $paths.Packages $activeId))
      Assert-False (Test-Path -LiteralPath (Join-Path $paths.Packages $otherOne))
      Assert-True (Test-Path -LiteralPath (Join-Path $paths.Packages $otherTwo))
      Assert-False (Test-Path -LiteralPath $oldTempPackage)
    }
  }

  if ($Suite -in @('All', 'Integration')) {
    Test-Case -Name 'hidden process receives BOM-free stdin and has no console window' -Action {
      $work = New-TestDirectory -Name 'hidden-process'
      $probe = Join-Path $script:FixtureRoot 'StdinProbe.ps1'
      $text = 'stdin-' + [char]0x3042
      $result = Invoke-AiBrainHiddenProcess `
        -CommandPath $probe `
        -StandardInput $text `
        -WorkingDirectory $work `
        -TimeoutSeconds 30 `
        -MaxCaptureBytes 65536
      Assert-Equal 0 ([int]$result.ExitCode)
      Assert-False ([bool]$result.TimedOut)
      Assert-True ([bool]$result.Drained)
      $value = ([string]$result.StdOut.Text) | ConvertFrom-Json -ErrorAction Stop
      Assert-Equal $text ([string]$value.text)
      Assert-False ([bool]$value.stdinHadBom)
      Assert-False ([bool]$value.hasConsoleWindow)
    }

    Test-Case -Name 'hidden process drains and bounds stdout and stderr' -Action {
      $work = New-TestDirectory -Name 'bounded-process'
      $probe = Join-Path $script:FixtureRoot 'StdinProbe.ps1'
      $result = Invoke-AiBrainHiddenProcess `
        -CommandPath $probe `
        -Arguments @('-StdOutBytes', '8192', '-StdErrBytes', '6144') `
        -WorkingDirectory $work `
        -TimeoutSeconds 30 `
        -MaxCaptureBytes 1024
      Assert-Equal 0 ([int]$result.ExitCode)
      Assert-True ([bool]$result.Drained)
      Assert-True ([bool]$result.StdOut.Truncated)
      Assert-True ([bool]$result.StdErr.Truncated)
      Assert-Equal ([long]8192) ([long]$result.StdOut.Bytes)
      Assert-Equal ([long]6144) ([long]$result.StdErr.Bytes)
    }

    Test-Case -Name 'hidden process timeout terminates its descendant tree' -Action {
      $work = New-TestDirectory -Name 'timeout-tree'
      $pidPath = Join-Path $work 'child.json'
      $childId = $null
      try {
        $result = Invoke-AiBrainHiddenProcess `
          -CommandPath $script:MockAgentExe `
          -Arguments @('--spawn-child-probe', $pidPath) `
          -WorkingDirectory $work `
          -TimeoutSeconds 1 `
          -MaxCaptureBytes 65536
        Assert-True ([bool]$result.TimedOut)
        Assert-True ([bool]$result.TreeTerminated)
        Assert-True (Test-Path -LiteralPath $pidPath -PathType Leaf)
        $childId = [int](Read-AiBrainJson -Path $pidPath).pid
        Assert-True (Wait-TestProcessGone -ProcessId $childId -TimeoutSeconds 5) 'Timed out descendant survived.'
      } finally {
        if ($null -ne $childId) { Stop-TestMockProcess -ProcessId ([int]$childId) }
      }
    }

    Test-Case -Name 'moved vault reports attention without mutating state or leaking paths' -Action {
      $fixture = New-OrchestratorFixture -Target claude -RequestOperation compile
      $stateHash = Get-AiBrainFileSha256 -Path $fixture.Paths.State
      $originalVault = [string]$fixture.Vault
      $movedName = (Split-Path -Leaf $originalVault) + '-moved'
      Rename-Item -LiteralPath $originalVault -NewName $movedName -ErrorAction Stop
      $movedConfig = Read-AiBrainJson -Path $fixture.Paths.Config
      Assert-Throws -Code 'VAULT_NOT_FOUND_OR_MOVED' -Action {
        Assert-AiBrainConfig -Config $movedConfig | Out-Null
      }
      $result = Invoke-TestManager -RuntimeRoot $fixture.Runtime -Action Status
      Assert-Equal 0 ([int]$result.ExitCode)
      Assert-True ([bool]$result.Envelope.success)
      $status = Get-TestManagerResult -Envelope $result.Envelope
      Assert-Equal 'attention' ([string]$status.status)
      Assert-True (@($status.issues) -contains 'VAULT_NOT_FOUND_OR_MOVED')
      Assert-True ([bool]$status.statePreserved)
      Assert-Equal $stateHash (Get-AiBrainFileSha256 -Path $fixture.Paths.State)
      Assert-True (Test-Path -LiteralPath $fixture.Paths.Attention -PathType Leaf)
      $attentionText = Read-AiBrainUtf8 -Path $fixture.Paths.Attention
      $attention = $attentionText | ConvertFrom-Json -ErrorAction Stop
      Assert-Equal 'attention' ([string]$attention.status)
      Assert-Equal 'VAULT_NOT_FOUND_OR_MOVED' ([string]$attention.code)
      Assert-Equal 'action,code,schemaVersion,status,updatedUtc' (
        @($attention.PSObject.Properties.Name | Sort-Object) -join ',')
      Assert-False $attentionText.Contains($originalVault)
      Assert-Equal $null (Test-AiBrainContainsSecret -Text $attentionText)
    }

    Test-Case -Name 'scheduled due work still claims one pending request in the same cycle' -Action {
      $fixture = New-OrchestratorFixture -Target claude -RequestOperation compile
      Write-AiBrainTextAtomic `
        -Path (Join-Path $fixture.Vault 'main\same-cycle.md') `
        -Text 'MOCK_WRITE'
      $state = Read-AiBrainState -Paths $fixture.Paths
      $state.lastCompileSlotUtc = $null
      $state.lastCompileInputFingerprint = Get-AiBrainManifestFingerprint -Manifest (
        Get-AiBrainVaultManifest -VaultPath $fixture.Vault)
      Set-AiBrainState -Paths $fixture.Paths -State $state
      $request = New-AiBrainRequest -Paths $fixture.Paths -Operation compile -Scope all
      Invoke-OrchestratorProcess -RuntimeRoot $fixture.Runtime
      $location = Get-AiBrainRequestLocation `
        -Paths $fixture.Paths `
        -RequestId ([string]$request.requestId)
      Assert-Equal 'completed' ([string]$location.Status)
      Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Vault 'wiki\generated.md') -PathType Leaf)
      $eventCodes = New-Object System.Collections.ArrayList
      foreach ($log in Get-ChildItem -LiteralPath $fixture.Paths.Logs -Filter '*.jsonl' -File | Sort-Object Name) {
        foreach ($line in Get-Content -LiteralPath $log.FullName) {
          if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void]$eventCodes.Add([string](($line | ConvertFrom-Json).eventCode))
          }
        }
      }
      $noChangeIndex = [array]::IndexOf([object[]]$eventCodes.ToArray(), 'COMPILE_NO_CHANGE')
      $appliedIndex = [array]::IndexOf([object[]]$eventCodes.ToArray(), 'COMPILE_APPLIED')
      Assert-True ($noChangeIndex -ge 0)
      Assert-True ($appliedIndex -gt $noChangeIndex)
    }

    Test-Case -Name 'source safety failure stops once and clears active request identity' -Action {
      $fixture = New-OrchestratorFixture -Target codex -RequestOperation compile
      Write-AiBrainTextAtomic `
        -Path (Join-Path $fixture.Vault 'main\protected.md') `
        -Text 'password=abcdefghijklmnopqrstuv'
      $fixture.Config.compileEnabled = $false
      $fixture.Config.lintEnabled = $false
      Write-AiBrainJsonAtomic -Path $fixture.Paths.Config -Value $fixture.Config
      $request = New-AiBrainRequest -Paths $fixture.Paths -Operation compile -Scope all
      $result = Invoke-OrchestratorProcessRaw -RuntimeRoot $fixture.Runtime
      Assert-Equal 1 ([int]$result.ExitCode)
      $state = Read-AiBrainState -Paths $fixture.Paths
      Assert-Equal 'attention' ([string]$state.status)
      Assert-Equal 'SOURCE_SECRET_DETECTED' ([string]$state.attentionCode)
      Assert-Equal 0 ([int]$state.sameFailureCount)
      Assert-Equal $null $state.runId
      Assert-Equal $null $state.activeRequestId
      Assert-Equal $null $state.child
      $location = Get-AiBrainRequestLocation `
        -Paths $fixture.Paths `
        -RequestId ([string]$request.requestId)
      Assert-Equal 'failed' ([string]$location.Status)
      Assert-Equal 'SOURCE_SECRET_DETECTED' ([string]$location.Request.resultCode)
      $report = Read-AiBrainUtf8 -Path (Join-Path $fixture.Vault 'wiki\_meta\sleep-report.md')
      Assert-True $report.Contains((Get-AiBrainMessage -Name action_source_safety))
      Assert-Equal $null (Test-AiBrainContainsSecret -Text $report)
    }

    Test-Case -Name 'Claude adapter skips scheduled no-change and applies manual request' -Action {
      if (-not (Test-Path -LiteralPath $script:MockAgentExe -PathType Leaf)) { throw 'MOCK_AGENT_NOT_BUILT' }
      $fixture = New-OrchestratorFixture -Target claude -RequestOperation compile
      Invoke-OrchestratorProcess -RuntimeRoot $fixture.Runtime
      $state = Read-AiBrainState -Paths $fixture.Paths
      Assert-True ($null -ne $state.lastCompileSlotUtc)
      Assert-Equal 0 (@(Get-ChildItem -LiteralPath $fixture.Runtime -Filter 'mock-agent-probe-*.json')).Count
      Write-AiBrainTextAtomic `
        -Path (Join-Path $fixture.Vault 'main\manual.md') `
        -Text 'MOCK_WRITE'
      $fixture.Config.compileEnabled = $false
      $fixture.Config.lintEnabled = $false
      Write-AiBrainJsonAtomic -Path $fixture.Paths.Config -Value $fixture.Config
      $request = New-AiBrainRequest -Paths $fixture.Paths -Operation compile -Scope all
      Invoke-OrchestratorProcess -RuntimeRoot $fixture.Runtime
      Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Vault 'wiki\generated.md') -PathType Leaf)
      Assert-Equal 'completed' ([string](Get-AiBrainRequestLocation `
        -Paths $fixture.Paths `
        -RequestId ([string]$request.requestId)).Status)
      $probes = @(Get-ChildItem -LiteralPath $fixture.Runtime -Filter 'mock-agent-probe-*.json')
      Assert-Equal 1 $probes.Count
      $probe = Read-AiBrainJson -Path $probes[0].FullName
      Assert-Equal 'claude' ([string]$probe.target)
      Assert-False ([bool]$probe.stdinHadBom)
      Assert-False ([bool]$probe.hasConsoleWindow)
    }

    Test-Case -Name 'Codex adapter skips scheduled no-change and applies manual request' -Action {
      if (-not (Test-Path -LiteralPath $script:MockAgentExe -PathType Leaf)) { throw 'MOCK_AGENT_NOT_BUILT' }
      $fixture = New-OrchestratorFixture -Target codex -RequestOperation lint
      Invoke-OrchestratorProcess -RuntimeRoot $fixture.Runtime
      $state = Read-AiBrainState -Paths $fixture.Paths
      Assert-True ($null -ne $state.lastCompileSlotUtc)
      Assert-Equal 0 (@(Get-ChildItem -LiteralPath $fixture.Runtime -Filter 'mock-agent-probe-*.json')).Count
      Write-AiBrainTextAtomic `
        -Path (Join-Path $fixture.Vault 'main\manual.md') `
        -Text 'MOCK_WRITE'
      $fixture.Config.compileEnabled = $false
      $fixture.Config.lintEnabled = $false
      Write-AiBrainJsonAtomic -Path $fixture.Paths.Config -Value $fixture.Config
      $request = New-AiBrainRequest -Paths $fixture.Paths -Operation lint -Scope all
      Invoke-OrchestratorProcess -RuntimeRoot $fixture.Runtime
      Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Vault 'wiki\generated-lint.md') -PathType Leaf)
      Assert-Equal 'completed' ([string](Get-AiBrainRequestLocation `
        -Paths $fixture.Paths `
        -RequestId ([string]$request.requestId)).Status)
      $probes = @(Get-ChildItem -LiteralPath $fixture.Runtime -Filter 'mock-agent-probe-*.json')
      Assert-Equal 1 $probes.Count
      $probe = Read-AiBrainJson -Path $probes[0].FullName
      Assert-Equal 'codex' ([string]$probe.target)
      Assert-Equal 'lint' ([string]$probe.operation)
      Assert-False ([bool]$probe.stdinHadBom)
      Assert-False ([bool]$probe.hasConsoleWindow)
    }

    Test-Case -Name 'bulk estimate approval is bounded to 24 hours and consumed once' -Action {
      $fixture = New-OrchestratorFixture -Target claude -RequestOperation compile
      Set-TestFixtureOff -Fixture $fixture
      Install-TestRuntimePackage -Fixture $fixture
      $fixture.Config.agentCapability = [pscustomobject]@{ verified = $true }
      Write-AiBrainJsonAtomic -Path $fixture.Paths.Config -Value $fixture.Config
      for ($index = 0; $index -lt 105; $index++) {
        Write-AiBrainTextAtomic `
          -Path (Join-Path $fixture.Vault ('main\source-{0:D3}.md' -f $index)) `
          -Text ('source-{0:D3}' -f $index)
      }
      $state = Read-AiBrainState -Paths $fixture.Paths
      $state.status = 'attention'
      $state.attentionCode = 'INITIAL_BULK_APPROVAL_REQUIRED'
      $state.attentionAction = 'approve bulk'
      $state.lastCompileSuccessUtc = $null
      Set-AiBrainState -Paths $fixture.Paths -State $state

      $statusResult = Invoke-TestManager -RuntimeRoot $fixture.Runtime -Action Status
      Assert-Equal 0 ([int]$statusResult.ExitCode) ('Status failed: ' + (Get-TestManagerError -Envelope $statusResult.Envelope))
      $status = Get-TestManagerResult -Envelope $statusResult.Envelope
      Assert-True ($null -ne $status.bulkEstimate) 'Status must include a bulk estimate.'
      Assert-Equal 105 ([int]$status.bulkEstimate.estimatedSourceFiles)
      Assert-Equal 100 ([int]$status.bulkEstimate.proposedMaxChangeFiles)
      Assert-True ([long]$status.bulkEstimate.proposedMaxChangeBytes -le 1073741824) 'Estimated byte approval must not exceed 1 GiB.'

      $beforeApproval = [DateTime]::UtcNow
      $approvalResult = Invoke-TestManager -RuntimeRoot $fixture.Runtime -Action ApproveBulk
      $afterApproval = [DateTime]::UtcNow
      Assert-Equal 0 ([int]$approvalResult.ExitCode) ('ApproveBulk failed: ' + (Get-TestManagerError -Envelope $approvalResult.Envelope))
      Assert-True ([bool]$approvalResult.Envelope.success) 'ApproveBulk must return a successful envelope.'
      $approvedConfig = Read-AiBrainJson -Path $fixture.Paths.Config
      Assert-False ([bool]$approvedConfig.bulkApproval.consumed)
      Assert-True ([int]$approvedConfig.bulkApproval.maxChangeFiles -le 100) 'Approved file cap must not exceed 100.'
      Assert-True ([long]$approvedConfig.bulkApproval.maxChangeBytes -le 1073741824) 'Approved byte cap must not exceed 1 GiB.'
      $expiry = [DateTimeOffset]::Parse([string]$approvedConfig.bulkApproval.expiresUtc).UtcDateTime
      Assert-True ($expiry -ge $beforeApproval.AddHours(24).AddSeconds(-2)) 'Bulk approval expires too early.'
      Assert-True ($expiry -le $afterApproval.AddHours(24).AddSeconds(2)) 'Bulk approval expires later than 24 hours.'

      $invalidApproval = Read-AiBrainJson -Path $fixture.Paths.Config
      $invalidApproval.bulkApproval.maxChangeFiles = 101
      Assert-Throws -Code 'CONFIG_BULK_APPROVAL_INVALID' -Action {
        Assert-AiBrainConfig -Config $invalidApproval | Out-Null
      }

      $firstRun = Invoke-TestManager `
        -RuntimeRoot $fixture.Runtime `
        -Action RunNow `
        -Operation compile `
        -Scope all
      Assert-Equal 0 ([int]$firstRun.ExitCode) ('First approved RunNow failed: {0}; {1}' -f
        [string]$firstRun.Envelope.error, (Get-TestRequestDiagnostic -Paths $fixture.Paths))
      $consumedConfig = Read-AiBrainJson -Path $fixture.Paths.Config
      Assert-True ([bool]$consumedConfig.bulkApproval.consumed) 'Bulk approval must be consumed by the first run.'
      Assert-True ($null -ne $consumedConfig.bulkApproval.consumedUtc) 'Consumed approval must record consumedUtc.'

      $secondRun = Invoke-TestManager `
        -RuntimeRoot $fixture.Runtime `
        -Action RunNow `
        -Operation compile `
        -Scope all
      Assert-Equal 1 ([int]$secondRun.ExitCode) ('Consumed approval must reject the next bulk run: {0}; {1}' -f
        [string]$secondRun.Envelope.error, (Get-TestRequestDiagnostic -Paths $fixture.Paths))
      $failedRequests = @(Get-ChildItem -LiteralPath $fixture.Paths.FailedRequests -Filter '*.json' -File)
      Assert-Equal 1 $failedRequests.Count 'Rejected bulk run must create one failed request.'
      $failedRequest = Read-AiBrainJson -Path $failedRequests[0].FullName
      Assert-Equal 'INITIAL_BULK_APPROVAL_REQUIRED' ([string]$failedRequest.resultCode)
    }

    Test-Case -Name 'corrupt and unknown state require explicit reset approval and create a backup' -Action {
      $fixture = New-OrchestratorFixture -Target claude -RequestOperation compile
      Set-TestFixtureOff -Fixture $fixture
      Install-TestRuntimePackage -Fixture $fixture
      $corruptText = '{not-json'
      Write-AiBrainTextAtomic -Path $fixture.Paths.State -Text $corruptText
      $corruptHash = Get-AiBrainFileSha256 -Path $fixture.Paths.State
      $statusResult = Invoke-TestManager -RuntimeRoot $fixture.Runtime -Action Status
      Assert-Equal 0 ([int]$statusResult.ExitCode) ('Corrupt-state Status failed: ' + (Get-TestManagerError -Envelope $statusResult.Envelope))
      $status = Get-TestManagerResult -Envelope $statusResult.Envelope
      Assert-Equal 'attention' ([string]$status.status)
      Assert-True ([bool]$status.statePreserved)
      Assert-True (@($status.issues) -contains 'JSON_INVALID')
      Assert-Equal $corruptHash (Get-AiBrainFileSha256 -Path $fixture.Paths.State)

      $resetResult = Invoke-TestManager `
        -RuntimeRoot $fixture.Runtime `
        -Action Doctor `
        -Repair `
        -ApproveStateReset
      Assert-Equal 0 ([int]$resetResult.ExitCode) ('Corrupt-state reset failed: ' + (Get-TestManagerError -Envelope $resetResult.Envelope))
      $doctor = Get-TestManagerResult -Envelope $resetResult.Envelope
      $backupPath = [string]$doctor.stateResetBackupPath
      Assert-True (Test-Path -LiteralPath $backupPath -PathType Leaf)
      Assert-True (Test-AiBrainPathWithin -Root $fixture.Paths.Migration -Candidate $backupPath)
      Assert-Equal $corruptText (Read-AiBrainUtf8 -Path $backupPath)
      $resetState = Read-AiBrainState -Paths $fixture.Paths
      Assert-Equal 'STATE_RESET_APPROVED' ([string]$resetState.lastRecoveryCode)

      $unknownFixture = New-OrchestratorFixture -Target claude -RequestOperation compile
      Set-TestFixtureOff -Fixture $unknownFixture
      Install-TestRuntimePackage -Fixture $unknownFixture
      $unknownState = [ordered]@{
        schemaVersion = 99
        status = 'ready'
        sameFailureCount = 0
      }
      Write-AiBrainJsonAtomic -Path $unknownFixture.Paths.State -Value $unknownState
      $unknownText = Read-AiBrainUtf8 -Path $unknownFixture.Paths.State
      $unknownHash = Get-AiBrainFileSha256 -Path $unknownFixture.Paths.State
      $unknownResult = Invoke-TestManager -RuntimeRoot $unknownFixture.Runtime -Action Status
      Assert-Equal 0 ([int]$unknownResult.ExitCode) ('Unknown-state Status failed: ' + (Get-TestManagerError -Envelope $unknownResult.Envelope))
      $unknownStatus = Get-TestManagerResult -Envelope $unknownResult.Envelope
      Assert-True (@($unknownStatus.issues) -contains 'STATE_SCHEMA_UNSUPPORTED')
      Assert-True ([bool]$unknownStatus.statePreserved)
      Assert-Equal $unknownHash (Get-AiBrainFileSha256 -Path $unknownFixture.Paths.State)

      $unknownResetResult = Invoke-TestManager `
        -RuntimeRoot $unknownFixture.Runtime `
        -Action Doctor `
        -Repair `
        -ApproveStateReset
      Assert-Equal 0 ([int]$unknownResetResult.ExitCode) ('Unknown-state reset failed: ' + (Get-TestManagerError -Envelope $unknownResetResult.Envelope))
      $unknownDoctor = Get-TestManagerResult -Envelope $unknownResetResult.Envelope
      $unknownBackupPath = [string]$unknownDoctor.stateResetBackupPath
      Assert-True (Test-Path -LiteralPath $unknownBackupPath -PathType Leaf)
      Assert-True (Test-AiBrainPathWithin -Root $unknownFixture.Paths.Migration -Candidate $unknownBackupPath)
      Assert-Equal $unknownText (Read-AiBrainUtf8 -Path $unknownBackupPath)
      $unknownResetState = Read-AiBrainState -Paths $unknownFixture.Paths
      Assert-Equal 'STATE_RESET_APPROVED' ([string]$unknownResetState.lastRecoveryCode)
    }

    Test-Case -Name 'manual RunNow works while off and launch failures become failed requests' -Action {
      $fixture = New-OrchestratorFixture -Target claude -RequestOperation compile
      Set-TestFixtureOff -Fixture $fixture
      Install-TestRuntimePackage -Fixture $fixture
      Write-AiBrainTextAtomic `
        -Path (Join-Path $fixture.Vault 'main\off-manual.md') `
        -Text 'MOCK_WRITE'
      $runResult = Invoke-TestManager `
        -RuntimeRoot $fixture.Runtime `
        -Action RunNow `
        -Operation compile `
        -Scope all
      Assert-Equal 0 ([int]$runResult.ExitCode) ('Off-mode RunNow failed: {0}; {1}' -f
        [string]$runResult.Envelope.error, (Get-TestRequestDiagnostic -Paths $fixture.Paths))
      Assert-True ([bool]$runResult.Envelope.success)
      Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Vault 'wiki\generated.md') -PathType Leaf)
      Assert-Equal 1 (@(Get-ChildItem -LiteralPath $fixture.Paths.CompletedRequests -Filter '*.json' -File)).Count
      Assert-Equal 'off' ([string](Read-AiBrainState -Paths $fixture.Paths).status)

      $failedFixture = New-OrchestratorFixture -Target claude -RequestOperation compile
      Set-TestFixtureOff -Fixture $failedFixture
      Install-TestRuntimePackage -Fixture $failedFixture
      Write-AiBrainTextAtomic -Path $failedFixture.Paths.Bootstrap -Text "exit 7`n"
      $failedRun = Invoke-TestManager `
        -RuntimeRoot $failedFixture.Runtime `
        -Action RunNow `
        -Operation compile `
        -Scope all
      Assert-Equal 1 ([int]$failedRun.ExitCode)
      Assert-False ([bool]$failedRun.Envelope.success)
      Assert-Equal 0 (@(Get-ChildItem -LiteralPath $failedFixture.Paths.PendingRequests -Filter '*.json' -File)).Count
      $failedFiles = @(Get-ChildItem -LiteralPath $failedFixture.Paths.FailedRequests -Filter '*.json' -File)
      Assert-Equal 1 $failedFiles.Count
      $failedRequest = Read-AiBrainJson -Path $failedFiles[0].FullName
      Assert-Equal 'failed' ([string]$failedRequest.status)
      Assert-Equal 'launch_failed' ([string]$failedRequest.resultCode)
    }

    Test-Case -Name 'Codex timeout terminates the mock agent descendant tree' -Action {
      if (-not (Test-Path -LiteralPath $script:MockAgentExe -PathType Leaf)) { throw 'MOCK_AGENT_NOT_BUILT' }
      $fixture = New-OrchestratorFixture -Target codex -RequestOperation compile
      $fixture.Config.limits.timeoutSeconds = 1
      $fixture.Config.compileEnabled = $false
      $fixture.Config.lintEnabled = $false
      Write-AiBrainJsonAtomic -Path $fixture.Paths.Config -Value $fixture.Config
      Write-AiBrainTextAtomic `
        -Path (Join-Path $fixture.Vault 'main\timeout.md') `
        -Text 'MOCK_TIMEOUT_CHILD'
      New-AiBrainRequest -Paths $fixture.Paths -Operation compile -Scope all | Out-Null
      $childId = $null
      try {
        $result = Invoke-OrchestratorProcessRaw -RuntimeRoot $fixture.Runtime
        Assert-Equal 1 ([int]$result.ExitCode)
        $pidPath = Join-Path $fixture.Runtime 'mock-agent-child.json'
        Assert-True (Test-Path -LiteralPath $pidPath -PathType Leaf)
        $childId = [int](Read-AiBrainJson -Path $pidPath).pid
        Assert-True (Wait-TestProcessGone -ProcessId $childId -TimeoutSeconds 5) 'Codex descendant survived timeout.'
      } finally {
        if ($null -ne $childId) { Stop-TestMockProcess -ProcessId ([int]$childId) }
      }
    }
  }

  Test-Case -Name 'test sources are ASCII-only UTF-8 without BOM' -Action {
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File) {
      $bytes = [IO.File]::ReadAllBytes($file.FullName)
      if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        throw ('TEST_FILE_HAS_BOM ' + $file.FullName)
      }
      foreach ($byte in $bytes) {
        if ($byte -gt 0x7f) { throw ('TEST_FILE_NOT_ASCII ' + $file.FullName) }
      }
    }
  }
} finally {
  foreach ($runtime in @($script:ExternalRuntimeRoots)) {
    if (Test-Path -LiteralPath $runtime) {
      Assert-ExternalRuntimeForDelete -Path $runtime
      Remove-Item -LiteralPath $runtime -Recurse -Force -ErrorAction Stop
    }
  }
  if (Test-Path -LiteralPath $script:TestRoot) {
    Assert-TestRootForDelete -Path $script:TestRoot
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction Stop
  }
}

[Console]::Out.WriteLine('')
[Console]::Out.WriteLine("Passed: $($script:Passed)")
[Console]::Out.WriteLine("Failed: $($script:Failed.Count)")
if ($script:Failed.Count -gt 0) {
  foreach ($failure in $script:Failed) {
    [Console]::Out.WriteLine('')
    [Console]::Out.WriteLine("[FAILURE] $($failure.Name)")
    [Console]::Out.WriteLine($failure.Message)
    if (-not [string]::IsNullOrWhiteSpace($failure.Position)) {
      [Console]::Out.WriteLine($failure.Position)
    }
  }
  exit 1
}
exit 0
