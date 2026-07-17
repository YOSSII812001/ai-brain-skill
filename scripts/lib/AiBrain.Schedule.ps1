if (-not (Get-Command Get-AiBrainProperty -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Common.ps1')
}

function ConvertTo-AiBrainUtcDateTime {
  param([Parameter(Mandatory = $true)][datetime]$Value)
  if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
  return $Value.ToUniversalTime()
}

function Get-AiBrainCompileSlot {
  param([Parameter(Mandatory = $true)][datetime]$NowUtc, [int]$IntervalHours = 4)
  if ($IntervalHours -lt 1 -or $IntervalHours -gt 168) { throw "COMPILE_INTERVAL_INVALID" }
  $utc = ConvertTo-AiBrainUtcDateTime -Value $NowUtc
  $epoch = [DateTime]::SpecifyKind([datetime]'2000-01-01T00:00:00', [DateTimeKind]::Utc)
  $slotTicks = [TimeSpan]::FromHours($IntervalHours).Ticks
  $elapsedTicks = ($utc - $epoch).Ticks
  $index = [Math]::Floor($elapsedTicks / [double]$slotTicks)
  $slotUtc = $epoch.AddTicks([long]($index * $slotTicks))
  return [pscustomobject]@{
    Id = $slotUtc.ToString('o')
    Utc = $slotUtc
    NextUtc = $slotUtc.AddHours($IntervalHours)
  }
}

function ConvertTo-AiBrainLintUtc {
  param(
    [Parameter(Mandatory = $true)][datetime]$LocalUnspecified,
    [Parameter(Mandatory = $true)][TimeZoneInfo]$TimeZone
  )
  $candidate = [DateTime]::SpecifyKind($LocalUnspecified, [DateTimeKind]::Unspecified)
  while ($TimeZone.IsInvalidTime($candidate)) {
    $candidate = $candidate.AddMinutes(1)
  }
  if ($TimeZone.IsAmbiguousTime($candidate)) {
    $offsets = $TimeZone.GetAmbiguousTimeOffsets($candidate) | Sort-Object Ticks
    $offset = $offsets[0]
    return (New-Object DateTimeOffset -ArgumentList @($candidate, $offset)).UtcDateTime
  }
  return [TimeZoneInfo]::ConvertTimeToUtc($candidate, $TimeZone)
}

function Get-AiBrainLintSlot {
  param(
    [Parameter(Mandatory = $true)][datetime]$NowUtc,
    [Parameter(Mandatory = $true)][string]$LocalTime,
    [Parameter(Mandatory = $true)][string]$TimeZoneId
  )
  if ($LocalTime -notmatch '^(?<hour>[01]\d|2[0-3]):(?<minute>[0-5]\d)$') { throw "LINT_TIME_INVALID" }
  $zone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
  $utc = ConvertTo-AiBrainUtcDateTime -Value $NowUtc
  $localNow = [TimeZoneInfo]::ConvertTimeFromUtc($utc, $zone)
  $localCandidate = $localNow.Date.AddHours([int]$Matches.hour).AddMinutes([int]$Matches.minute)
  $candidateUtc = ConvertTo-AiBrainLintUtc -LocalUnspecified $localCandidate -TimeZone $zone
  if ($candidateUtc -gt $utc) {
    $localCandidate = $localCandidate.AddDays(-1)
    $candidateUtc = ConvertTo-AiBrainLintUtc -LocalUnspecified $localCandidate -TimeZone $zone
  }
  $nextLocal = $localCandidate.AddDays(1)
  $nextUtc = ConvertTo-AiBrainLintUtc -LocalUnspecified $nextLocal -TimeZone $zone
  return [pscustomobject]@{
    Id = ('{0}|{1}' -f $localCandidate.ToString('yyyy-MM-ddTHH:mm'), $TimeZoneId)
    Utc = $candidateUtc
    NextUtc = $nextUtc
  }
}

function Get-AiBrainDueOperations {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$State,
    [datetime]$NowUtc = [DateTime]::UtcNow
  )
  $compile = Get-AiBrainCompileSlot -NowUtc $NowUtc -IntervalHours ([int]$Config.compileIntervalHours)
  $lint = Get-AiBrainLintSlot -NowUtc $NowUtc -LocalTime ([string]$Config.lintLocalTime) -TimeZoneId ([string]$Config.timeZoneId)
  $compileEnabled = [bool](Get-AiBrainProperty $Config 'compileEnabled' $true)
  $lintEnabled = [bool](Get-AiBrainProperty $Config 'lintEnabled' $true)
  $State.nextCompileUtc = $(if ($compileEnabled) { $compile.NextUtc.ToString('o') } else { $null })
  $State.nextLintUtc = $(if ($lintEnabled) { $lint.NextUtc.ToString('o') } else { $null })
  $operations = New-Object System.Collections.ArrayList
  if ($compileEnabled -and [string]$State.lastCompileSlotUtc -ne $compile.Id) {
    [void]$operations.Add([pscustomobject]@{ operation = 'compile'; scope = 'all'; slotId = $compile.Id; slotUtc = $compile.Utc })
  }
  if ($lintEnabled -and [string]$State.lastLintSlotId -ne $lint.Id) {
    [void]$operations.Add([pscustomobject]@{ operation = 'lint'; scope = 'all'; slotId = $lint.Id; slotUtc = $lint.Utc })
  }
  return @($operations)
}

function Complete-AiBrainOperationSlot {
  param(
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$SlotId,
    [datetime]$CompletedUtc = [DateTime]::UtcNow
  )
  if ($Operation -eq 'compile') {
    $State.lastCompileSlotUtc = $SlotId
    $State.lastCompileSuccessUtc = $CompletedUtc.ToUniversalTime().ToString('o')
  } else {
    $State.lastLintSlotId = $SlotId
    $State.lastLintSuccessUtc = $CompletedUtc.ToUniversalTime().ToString('o')
  }
}
