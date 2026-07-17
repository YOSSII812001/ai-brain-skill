if (-not (Get-Command Get-AiBrainProperty -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Common.ps1')
}
if (-not (Get-Command ConvertTo-AiBrainWindowsCommandLine -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Process.ps1')
}
if (-not (Get-Command Get-AiBrainCompileSlot -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Schedule.ps1')
}

function ConvertTo-AiBrainXmlText {
  param([AllowEmptyString()][string]$Text)
  return [Security.SecurityElement]::Escape($Text)
}

function ConvertTo-AiBrainPowerShellLiteralArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  return '"' + $Value.Replace('\', '\').Replace('"', '\"') + '"'
}

function Get-AiBrainTaskXmlHash {
  param([Parameter(Mandatory = $true)][string]$Xml)
  return Get-AiBrainStringSha256 -Text (($Xml -replace "`r`n", "`n") + "`n")
}

function Read-AiBrainVerifiedTaskXml {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ExpectedHash,
    [Parameter(Mandatory = $true)][string]$FailureCode
  )
  $xml = Read-AiBrainUtf8 -Path $Path
  if ([string]::IsNullOrWhiteSpace($ExpectedHash) -or
      (Get-AiBrainTaskXmlHash -Xml $xml) -ne $ExpectedHash) {
    throw $FailureCode
  }
  try {
    $document = New-Object Xml.XmlDocument
    $document.LoadXml($xml)
  } catch {
    throw $FailureCode
  }
  return $xml
}

function Get-AiBrainCommandLineOptionValue {
  param(
    [Parameter(Mandatory = $true)][string]$Arguments,
    [Parameter(Mandatory = $true)][string]$Name
  )
  $pattern = '(?i)(?:^|\s)-{0}(?:\s+|=)(?:"(?<double>[^"]+)"|''(?<single>[^'']+)''|(?<bare>\S+))' -f
    [regex]::Escape($Name)
  $match = [regex]::Match($Arguments, $pattern)
  if (-not $match.Success) { return $null }
  foreach ($groupName in @('double', 'single', 'bare')) {
    if ($match.Groups[$groupName].Success) { return [string]$match.Groups[$groupName].Value }
  }
  return $null
}

function Test-AiBrainLegacyTaskContract {
  param(
    [Parameter(Mandatory = $true)][string]$Xml,
    [Parameter(Mandatory = $true)][string]$ExpectedScriptPath,
    [Parameter(Mandatory = $true)][string]$ExpectedVaultPath,
    [Parameter(Mandatory = $true)][string]$CommandText,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$RegisteredVaultPaths
  )
  try { [xml]$document = $Xml } catch { return $false }
  $actions = @($document.SelectNodes('//*[local-name()="Actions"]/*[local-name()="Exec"]'))
  if ($actions.Count -ne 1) { return $false }
  $argumentsNode = $actions[0].SelectSingleNode('./*[local-name()="Arguments"]')
  if ($null -eq $argumentsNode) { return $false }
  $arguments = [string]$argumentsNode.InnerText

  $fileArgument = Get-AiBrainCommandLineOptionValue -Arguments $arguments -Name 'File'
  if ([string]::IsNullOrWhiteSpace($fileArgument)) { return $false }
  try {
    $actualScript = Get-AiBrainCanonicalPath -Path $fileArgument -MustExist -AllowFile
    $expectedScript = Get-AiBrainCanonicalPath -Path $ExpectedScriptPath -MustExist -AllowFile
  } catch {
    return $false
  }
  if (-not [string]::Equals($actualScript, $expectedScript, [StringComparison]::OrdinalIgnoreCase)) {
    return $false
  }

  $vaultArgument = Get-AiBrainCommandLineOptionValue -Arguments $arguments -Name 'VaultPath'
  if (-not [string]::IsNullOrWhiteSpace($vaultArgument)) {
    try {
      $actualVault = Get-AiBrainCanonicalPath -Path $vaultArgument -MustExist
      $expectedVault = Get-AiBrainCanonicalPath -Path $ExpectedVaultPath -MustExist
    } catch {
      return $false
    }
    return [string]::Equals($actualVault, $expectedVault, [StringComparison]::OrdinalIgnoreCase)
  }

  $labels = New-Object System.Collections.ArrayList
  foreach ($line in ($CommandText -split "`r?`n")) {
    $match = [regex]::Match($line, '^\s*[^:]+:\s*(.+?)\s*$')
    if (-not $match.Success) { continue }
    $value = $match.Groups[1].Value.Trim().Trim([char[]]@('"', "'", '`', ' '))
    if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$labels.Add($value) }
  }

  $candidates = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($label in @($labels)) {
    if ([IO.Path]::IsPathRooted([string]$label)) {
      try {
        [void]$candidates.Add((Get-AiBrainCanonicalPath -Path ([string]$label) -MustExist))
      } catch {
        return $false
      }
      continue
    }
    foreach ($registered in $RegisteredVaultPaths) {
      try {
        $canonical = Get-AiBrainCanonicalPath -Path $registered -MustExist
      } catch {
        continue
      }
      if ([string]::Equals((Split-Path -Leaf $canonical), [string]$label, [StringComparison]::OrdinalIgnoreCase)) {
        [void]$candidates.Add($canonical)
      }
    }
  }
  if ($candidates.Count -ne 1) { return $false }
  try { $expected = Get-AiBrainCanonicalPath -Path $ExpectedVaultPath -MustExist } catch { return $false }
  foreach ($candidate in $candidates) {
    return [string]::Equals($candidate, $expected, [StringComparison]::OrdinalIgnoreCase)
  }
  return $false
}

function Ensure-AiBrainTaskFolder {
  param([Parameter(Mandatory = $true)][string]$TaskPath)
  $segments = @($TaskPath.Trim('\').Split('\') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $service = New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $current = $service.GetFolder('\')
  foreach ($segment in $segments) {
    try {
      $current = $current.GetFolder($segment)
    } catch {
      $current = $current.CreateFolder($segment)
    }
  }
}

function Get-AiBrainTaskXml {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$BootstrapPath,
    [switch]$Preflight,
    [string]$PreflightToken
  )
  $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $arguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle', 'Hidden',
    '-ExecutionPolicy', 'Bypass',
    '-File', $BootstrapPath,
    '-RuntimeRoot', [string]$Config.runtimeRoot
  )
  if ($Preflight) {
    if ($PreflightToken -notmatch '^[a-f0-9]{32}$') { throw "PREFLIGHT_TOKEN_INVALID" }
    $arguments += @('-Preflight', '-PreflightToken', $PreflightToken)
  }
  $argumentText = ConvertTo-AiBrainWindowsCommandLine -Arguments $arguments
  $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $startCompile = (Get-AiBrainCompileSlot -NowUtc ([DateTime]::UtcNow) -IntervalHours ([int]$Config.compileIntervalHours)).NextUtc.ToString("yyyy-MM-ddTHH:mm:ss'Z'")
  $lintParts = ([string]$Config.lintLocalTime).Split(':')
  $lintStart = (Get-Date).Date.AddHours([int]$lintParts[0]).AddMinutes([int]$lintParts[1])
  if ($lintStart -le (Get-Date)) { $lintStart = $lintStart.AddDays(1) }
  $triggerXml = if ($Preflight) {
@"
    <TimeTrigger>
      <StartBoundary>$((Get-Date).AddDays(1).ToString('s'))</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
"@
  } else {
@"
    <TimeTrigger>
      <Repetition>
        <Interval>PT$([int]$Config.compileIntervalHours)H</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$startCompile</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
    <CalendarTrigger>
      <StartBoundary>$($lintStart.ToString('s'))</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
"@
  }
  $workingDirectory = ConvertTo-AiBrainXmlText -Text ([string]$Config.runtimeRoot)
  $commandXml = ConvertTo-AiBrainXmlText -Text $powershell
  $argumentsXml = ConvertTo-AiBrainXmlText -Text $argumentText
  $description = $(if ($Preflight) { 'AI Brain S4U permission preflight' } else { 'AI Brain sleep mode: compile every four hours and lint daily' })
  return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$(ConvertTo-AiBrainXmlText $description)</Description>
  </RegistrationInfo>
  <Triggers>
$triggerXml
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$userSid</UserId>
      <LogonType>S4U</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$commandXml</Command>
      <Arguments>$argumentsXml</Arguments>
      <WorkingDirectory>$workingDirectory</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
}

function Register-AiBrainTaskXml {
  param(
    [Parameter(Mandatory = $true)][string]$TaskPath,
    [Parameter(Mandatory = $true)][string]$TaskName,
    [Parameter(Mandatory = $true)][string]$Xml
  )
  Ensure-AiBrainTaskFolder -TaskPath $TaskPath
  Register-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Xml $Xml -Force -ErrorAction Stop | Out-Null
}

function Export-AiBrainTaskXml {
  param(
    [Parameter(Mandatory = $true)][string]$TaskPath,
    [Parameter(Mandatory = $true)][string]$TaskName
  )
  return Export-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
}

function Test-AiBrainTaskXmlContract {
  param(
    [Parameter(Mandatory = $true)][string]$Xml,
    [switch]$Preflight,
    [int]$CompileIntervalHours = 4,
    [string]$ExpectedBootstrapPath,
    [string]$ExpectedRuntimeRoot
  )
  try { [xml]$document = $Xml } catch { throw "TASK_XML_INVALID" }
  $namespace = New-Object Xml.XmlNamespaceManager($document.NameTable)
  $namespace.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
  function Get-NodeText([string]$XPath) {
    $node = $document.SelectSingleNode($XPath, $namespace)
    if ($null -eq $node) { return $null }
    return $node.InnerText
  }
  if ((Get-NodeText '//t:Principal/t:LogonType') -ne 'S4U') { throw "TASK_NOT_S4U" }
  if ((Get-NodeText '//t:Principal/t:RunLevel') -ne 'LeastPrivilege') { throw "TASK_NOT_LIMITED" }
  if ((Get-NodeText '//t:MultipleInstancesPolicy') -ne 'IgnoreNew') { throw "TASK_NOT_IGNORE_NEW" }
  if ((Get-NodeText '//t:StartWhenAvailable') -ne 'true') { throw "TASK_NOT_START_WHEN_AVAILABLE" }
  if ((Get-NodeText '//t:WakeToRun') -ne 'false') { throw "TASK_WAKE_ENABLED" }
  if ((Get-NodeText '//t:ExecutionTimeLimit') -ne 'PT0S') { throw "TASK_EXECUTION_LIMIT_ENABLED" }
  if ($null -ne $document.SelectSingleNode('//t:Repetition/t:Duration', $namespace)) { throw "TASK_REPETITION_EXPIRES" }
  if (-not $Preflight) {
    $timeTriggers = @($document.SelectNodes('//t:TimeTrigger', $namespace))
    $calendarTriggers = @($document.SelectNodes('//t:CalendarTrigger', $namespace))
    if ($timeTriggers.Count -ne 1 -or $calendarTriggers.Count -ne 1) { throw "TASK_TRIGGER_COUNT_INVALID" }
    if ((Get-NodeText '//t:TimeTrigger/t:Repetition/t:Interval') -ne "PT${CompileIntervalHours}H") {
      throw "TASK_COMPILE_INTERVAL_INVALID"
    }
    if ((Get-NodeText '//t:CalendarTrigger/t:ScheduleByDay/t:DaysInterval') -ne '1') {
      throw "TASK_LINT_INTERVAL_INVALID"
    }
  }
  $arguments = Get-NodeText '//t:Actions/t:Exec/t:Arguments'
  if ($null -ne (Test-AiBrainContainsSecret -Text $arguments) -or
      $arguments -match '(?i)(?:^|\s)["'']?--?(?:api[_-]?key|access[_-]?token|secret|password)(?:["'']?\s|=)') {
    throw "TASK_ARGUMENT_SECRET_FIELD"
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedBootstrapPath) -or
      -not [string]::IsNullOrWhiteSpace($ExpectedRuntimeRoot)) {
    if ([string]::IsNullOrWhiteSpace($ExpectedBootstrapPath) -or
        [string]::IsNullOrWhiteSpace($ExpectedRuntimeRoot)) {
      throw "TASK_ACTION_EXPECTATION_INCOMPLETE"
    }
    $expectedBootstrap = Get-AiBrainCanonicalPath -Path $ExpectedBootstrapPath
    $expectedRuntime = Get-AiBrainCanonicalPath -Path $ExpectedRuntimeRoot
    $expectedArguments = ConvertTo-AiBrainWindowsCommandLine -Arguments @(
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle', 'Hidden',
      '-ExecutionPolicy', 'Bypass',
      '-File', $expectedBootstrap,
      '-RuntimeRoot', $expectedRuntime
    )
    $expectedCommand = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not [string]::Equals(
        (Get-NodeText '//t:Actions/t:Exec/t:Command'),
        $expectedCommand,
        [StringComparison]::OrdinalIgnoreCase)) {
      throw "TASK_ACTION_COMMAND_INVALID"
    }
    if (-not [string]::Equals($arguments, $expectedArguments, [StringComparison]::Ordinal)) {
      throw "TASK_ACTION_ARGUMENTS_INVALID"
    }
    if (-not [string]::Equals(
        (Get-AiBrainCanonicalPath -Path (Get-NodeText '//t:Actions/t:Exec/t:WorkingDirectory')),
        $expectedRuntime,
        [StringComparison]::OrdinalIgnoreCase)) {
      throw "TASK_ACTION_WORKING_DIRECTORY_INVALID"
    }
  }
  return $true
}

function Test-AiBrainS4UPreflight {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$BootstrapPath,
    [int]$TimeoutSeconds = 90
  )
  $token = [Guid]::NewGuid().ToString('N')
  $taskName = "AI Brain S4U Preflight $token"
  $xml = Get-AiBrainTaskXml -Config $Config -BootstrapPath $BootstrapPath -Preflight -PreflightToken $token
  $resultPath = Join-Path $Paths.Migration "preflight-$token.json"
  try {
    Register-AiBrainTaskXml -TaskPath ([string]$Config.taskPath) -TaskName $taskName -Xml $xml
    $exported = Export-AiBrainTaskXml -TaskPath ([string]$Config.taskPath) -TaskName $taskName
    Test-AiBrainTaskXmlContract -Xml $exported -Preflight | Out-Null
    Start-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName $taskName -ErrorAction Stop
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
      $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName $taskName -ErrorAction Stop
      if ((Test-Path -LiteralPath $resultPath -PathType Leaf) -and [string]$task.State -ne 'Running') { break }
      Start-Sleep -Milliseconds 250
    }
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw "S4U_PREFLIGHT_TIMEOUT" }
    $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName $taskName -ErrorAction Stop
    if ([string]$task.State -eq 'Running') { throw "S4U_PREFLIGHT_TIMEOUT" }
    $result = Read-AiBrainJson -Path $resultPath
    if (-not [bool]$result.success -or [string]$result.token -ne $token) { throw "S4U_PREFLIGHT_RESULT_INVALID" }
    $info = Get-ScheduledTaskInfo -TaskPath ([string]$Config.taskPath) -TaskName $taskName -ErrorAction Stop
    if ([int]$info.LastTaskResult -ne 0) { throw "S4U_PREFLIGHT_TASK_FAILED" }
    return $true
  } finally {
    $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $task -and [string]$task.State -eq 'Running') {
      Stop-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName $taskName -ErrorAction SilentlyContinue
      $stopDeadline = [DateTime]::UtcNow.AddSeconds(10)
      do {
        Start-Sleep -Milliseconds 200
        $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName $taskName -ErrorAction SilentlyContinue
      } while ($null -ne $task -and [string]$task.State -eq 'Running' -and [DateTime]::UtcNow -lt $stopDeadline)
    }
    Unregister-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue }
  }
}

function Register-AiBrainSleepTask {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$BootstrapPath
  )
  $xml = Get-AiBrainTaskXml -Config $Config -BootstrapPath $BootstrapPath
  Register-AiBrainTaskXml -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -Xml $xml
  if (-not [bool]$Config.enabled) {
    Disable-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop | Out-Null
  }
  $exported = Export-AiBrainTaskXml -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName)
  Test-AiBrainTaskXmlContract `
    -Xml $exported `
    -CompileIntervalHours ([int]$Config.compileIntervalHours) `
    -ExpectedBootstrapPath $BootstrapPath `
    -ExpectedRuntimeRoot ([string]$Config.runtimeRoot) | Out-Null
  return [pscustomobject]@{
    Xml = $exported
    Hash = Get-AiBrainTaskXmlHash -Xml $exported
  }
}

function Get-AiBrainTaskStatus {
  param([Parameter(Mandatory = $true)][object]$Config)
  $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction SilentlyContinue
  if ($null -eq $task) { return [pscustomobject]@{ Exists = $false; State = 'Missing'; Enabled = $false; XmlHash = $null } }
  $xml = Export-AiBrainTaskXml -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName)
  return [pscustomobject]@{
    Exists = $true
    State = [string]$task.State
    Enabled = [string]$task.State -ne 'Disabled'
    XmlHash = Get-AiBrainTaskXmlHash -Xml $xml
  }
}

function Wait-AiBrainTaskRun {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [string]$PreviousHeartbeat,
    [int]$TimeoutSeconds = 120
  )
  Start-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName) -ErrorAction Stop
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
    $state = Read-AiBrainJson -Path $Paths.State -Optional
    if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.lastHeartbeatUtc) -and
        [string]$state.lastHeartbeatUtc -ne [string]$PreviousHeartbeat) {
      $task = Get-ScheduledTask -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName)
      if ([string]$task.State -ne 'Running') {
        $info = Get-ScheduledTaskInfo -TaskPath ([string]$Config.taskPath) -TaskName ([string]$Config.taskName)
        if ([int]$info.LastTaskResult -ne 0) { throw "SLEEP_TASK_TEST_FAILED" }
        return $true
      }
    }
  }
  throw "SLEEP_TASK_TEST_TIMEOUT"
}
