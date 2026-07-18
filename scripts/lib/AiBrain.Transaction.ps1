if (-not (Get-Command Get-AiBrainProperty -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Common.ps1')
}

function New-AiBrainRunDirectory {
  param([Parameter(Mandatory = $true)][object]$Paths, [Parameter(Mandatory = $true)][string]$RunId)
  if ($RunId -notmatch '^[a-f0-9]{32}$') { throw "RUN_ID_INVALID" }
  $directory = Join-Path $Paths.Staging $RunId
  if (Test-Path -LiteralPath $directory) { throw "RUN_DIRECTORY_ALREADY_EXISTS" }
  New-AiBrainDirectorySafe -Path $directory | Out-Null
  foreach ($layer in @('main', 'raw', 'wiki')) {
    New-AiBrainDirectorySafe -Path (Join-Path $directory $layer) | Out-Null
  }
  Assert-AiBrainNoReparsePath -Path $directory | Out-Null
  return $directory
}

function Read-AiBrainSourceUtf8 {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $offset = 0
  if ($bytes.Length -ge 3 -and
      $bytes[0] -eq 0xef -and
      $bytes[1] -eq 0xbb -and
      $bytes[2] -eq 0xbf) {
    $offset = 3
  }
  try {
    return $script:AiBrainUtf8NoBom.GetString($bytes, $offset, $bytes.Length - $offset)
  } catch {
    throw "SOURCE_ENCODING_INVALID"
  }
}

function New-AiBrainSourceBundle {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [string]$RunDirectory,
    [ValidateSet('compile', 'lint')][string]$Operation = 'compile',
    [switch]$NoStage
  )
  if (-not $NoStage -and [string]::IsNullOrWhiteSpace($RunDirectory)) {
    throw "STAGING_DIRECTORY_REQUIRED"
  }
  $vault = Get-AiBrainCanonicalPath -Path ([string]$Config.vaultPath) -MustExist
  $files = New-Object System.Collections.ArrayList
  $protectedWikiPaths = New-Object System.Collections.ArrayList
  [long]$totalBytes = 0
  [int]$excludedByName = 0
  [int]$excludedByContent = 0
  $layers = $(if ($Operation -eq 'lint') { @('wiki') } else { @('main', 'raw', 'wiki') })
  foreach ($layer in $layers) {
    $sourceLayer = Join-Path $vault $layer
    if (-not (Test-Path -LiteralPath $sourceLayer -PathType Container)) { continue }
    Assert-AiBrainNoReparsePath -Path $sourceLayer | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $sourceLayer -Recurse -File -Force -ErrorAction Stop | Sort-Object FullName) {
      Assert-AiBrainNoReparsePath -Path $file.FullName | Out-Null
      $relative = $file.FullName.Substring($vault.Length).TrimStart('\').Replace('\', '/')
      if ($relative -ieq 'wiki/_meta/sleep-report.md' -or $relative -match '(?i)^wiki/_meta/(?:\.lock|sleep-)') { continue }
      if ((Test-AiBrainDeniedFileName -Name $file.Name) -or
          $null -ne (Test-AiBrainContainsSecret -Text $relative)) {
        $excludedByName++
        if ($relative -like 'wiki/*') { [void]$protectedWikiPaths.Add($relative) }
        continue
      }
      if ($file.Extension.ToLowerInvariant() -notin $script:AiBrainTextExtensions) { continue }
      $content = Read-AiBrainSourceUtf8 -Path $file.FullName
      if ($null -ne (Test-AiBrainContainsSecret -Text $content)) {
        $excludedByContent++
        if ($relative -like 'wiki/*') { [void]$protectedWikiPaths.Add($relative) }
        continue
      }
      $bytes = $script:AiBrainUtf8NoBom.GetByteCount($content)
      $totalBytes += $bytes
      if (-not $NoStage) {
        $stagePath = Resolve-AiBrainChildPath -Root $RunDirectory -RelativePath $relative -AllowMissingLeaf
        Write-AiBrainTextAtomic -Path $stagePath -Text $content
      }
      [void]$files.Add([ordered]@{
        path = $relative
        sha256 = Get-AiBrainFileSha256 -Path $file.FullName
        bytes = [long]$bytes
        content = $content
      })
    }
  }
  return [ordered]@{
    schemaVersion = 1
    files = @($files)
    includedCount = $files.Count
    includedBytes = $totalBytes
    excludedCount = $excludedByName + $excludedByContent
    excludedByNameCount = $excludedByName
    excludedByContentCount = $excludedByContent
    detectorVersion = $script:AiBrainSecretDetectorVersion
    protectedWikiPaths = @($protectedWikiPaths)
  }
}

function New-AiBrainAgentPrompt {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][object]$SourceBundle,
    [ValidateSet('worker', 'finalizer')][string]$Mode = 'worker',
    [string]$ChunkKey = 'root',
    [string[]]$AllowedPaths = @(),
    [object[]]$ChangeSummary = @()
  )
  $instruction = $(if ($Mode -eq 'finalizer') {
    'Finalize the catalog after all worker chunks. Use the change summary to update only the allowed index or log paths.'
  } else {
    Get-AiBrainMessage -Name $(if ($Operation -eq 'compile') { 'compile_instruction' } else { 'lint_instruction' })
  })
  $promptFiles = New-Object System.Collections.ArrayList
  foreach ($file in @($SourceBundle.files)) {
    [void]$promptFiles.Add([ordered]@{
      path = [string]$file.path
      sha256 = [string]$file.sha256
      content = [string]$file.content
    })
  }
  $coordination = [ordered]@{
    mode = $Mode
    chunkKey = $ChunkKey
  }
  if ($Mode -eq 'worker') {
    $coordination.reservedPaths = @('wiki/index.md', 'wiki/log.md')
    $coordination.rule = 'Do not write or delete reserved paths. Only return changes directly justified by this input chunk.'
  } else {
    $coordination.allowedPaths = @($AllowedPaths)
    $coordination.changeSummary = @($ChangeSummary)
    $coordination.rule = 'Return changes only for allowedPaths. Do not recreate worker changes.'
  }
  $envelope = [ordered]@{
    operation = $Operation
    scope = $Scope
    instruction = $instruction.Trim()
    coordination = $coordination
    safety = @(
      (Get-AiBrainMessage -Name safety_bundle),
      (Get-AiBrainMessage -Name safety_tools),
      (Get-AiBrainMessage -Name safety_layers),
      (Get-AiBrainMessage -Name safety_json),
      'Every written Markdown file must include title, date_modified, type, and status in simple YAML frontmatter',
      'Use flat YAML scalar fields or inline [item, item] arrays; quote array items containing spaces or non-ASCII text',
      'Set content to null for delete actions'
    )
    outputSchema = [ordered]@{
      schemaVersion = 'ai-brain-change-set-v1'
      operation = $Operation
      changes = @(
        [ordered]@{
          path = 'wiki/example.md'
          action = Get-AiBrainMessage -Name schema_action
          content = Get-AiBrainMessage -Name schema_content
        }
      )
    }
    input = [ordered]@{
      schemaVersion = 1
      files = @($promptFiles)
    }
  }
  return ($envelope | ConvertTo-Json -Depth 50 -Compress)
}

function ConvertFrom-AiBrainChangeSet {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$ExpectedOperation
  )
  $trimmed = $Text.Trim()
  if (-not $trimmed.StartsWith('{') -or -not $trimmed.EndsWith('}')) { throw "CHANGE_SET_NOT_EXACT_JSON" }
  try {
    $changeSet = $trimmed | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "CHANGE_SET_INVALID_JSON"
  }
  $allowedTop = @('schemaVersion', 'operation', 'changes')
  foreach ($property in $changeSet.PSObject.Properties) {
    if ($property.Name -notin $allowedTop) { throw "CHANGE_SET_UNKNOWN_FIELD" }
  }
  if ([string]$changeSet.schemaVersion -ne 'ai-brain-change-set-v1') { throw "CHANGE_SET_SCHEMA_INVALID" }
  if ([string]$changeSet.operation -ne $ExpectedOperation) { throw "CHANGE_SET_OPERATION_MISMATCH" }
  if ($null -eq $changeSet.changes) { throw "CHANGE_SET_CHANGES_MISSING" }
  return $changeSet
}

function Test-AiBrainScopePath {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][string]$RelativePath
  )
  $path = $RelativePath.Replace('\', '/')
  if ($path -notmatch '(?i)^wiki/.+\.md$') { return $false }
  if ($path -in @('wiki/index.md', 'wiki/log.md')) { return $true }
  if ($Operation -eq 'compile') {
    if ($Scope -eq 'all') { return $true }
    if ($Scope -eq 'concepts') { return $path.StartsWith('wiki/concepts/', [StringComparison]::OrdinalIgnoreCase) }
    if ($Scope -eq 'sources') { return $path.StartsWith('wiki/sources/', [StringComparison]::OrdinalIgnoreCase) }
    if ($Scope.StartsWith('page:', [StringComparison]::OrdinalIgnoreCase)) {
      $page = $Scope.Substring(5).Replace('\', '/')
      if (-not $page.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase)) { $page += '.md' }
      if (-not $page.StartsWith('wiki/', [StringComparison]::OrdinalIgnoreCase)) { $page = 'wiki/' + $page.TrimStart('/') }
      return [string]::Equals($path, $page, [StringComparison]::OrdinalIgnoreCase)
    }
    return $false
  }
  return $Scope -in @('all', 'links', 'frontmatter', 'stale', 'naming')
}

function Get-AiBrainWikiPathSet {
  param([Parameter(Mandatory = $true)][string]$RunDirectory)
  $set = @{}
  $wiki = Join-Path $RunDirectory 'wiki'
  if (Test-Path -LiteralPath $wiki -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $wiki -Recurse -File -Filter '*.md') {
      $relative = $file.FullName.Substring($RunDirectory.Length).TrimStart('\').Replace('\', '/')
      $set[$relative.ToLowerInvariant()] = $true
      $set[[IO.Path]::GetFileNameWithoutExtension($relative).ToLowerInvariant()] = $true
    }
  }
  return $set
}

function Split-AiBrainFrontmatterInlineArray {
  param([Parameter(Mandatory = $true)][string]$Value)
  $trimmed = $Value.Trim()
  if (-not $trimmed.StartsWith('[') -or -not $trimmed.EndsWith(']')) {
    throw "FRONTMATTER_YAML_INVALID"
  }
  $body = $trimmed.Substring(1, $trimmed.Length - 2)
  if ([string]::IsNullOrWhiteSpace($body)) { return }
  $items = New-Object System.Collections.ArrayList
  $builder = New-Object System.Text.StringBuilder
  [char]$quote = [char]0
  $escaped = $false
  for ($index = 0; $index -lt $body.Length; $index++) {
    [char]$character = $body[$index]
    if ($quote -eq [char]0x22) {
      [void]$builder.Append($character)
      if ($escaped) {
        $escaped = $false
      } elseif ($character -eq [char]0x5c) {
        $escaped = $true
      } elseif ($character -eq [char]0x22) {
        $quote = [char]0
      }
      continue
    }
    if ($quote -eq [char]0x27) {
      [void]$builder.Append($character)
      if ($character -eq [char]0x27) {
        if ($index + 1 -lt $body.Length -and $body[$index + 1] -eq [char]0x27) {
          [void]$builder.Append($body[$index + 1])
          $index++
        } else {
          $quote = [char]0
        }
      }
      continue
    }
    if ($character -in @([char]0x22, [char]0x27)) {
      $quote = $character
      [void]$builder.Append($character)
      continue
    }
    if ($character -eq ',') {
      $item = $builder.ToString().Trim()
      if ([string]::IsNullOrWhiteSpace($item)) { throw "FRONTMATTER_YAML_INVALID" }
      [void]$items.Add($item)
      [void]$builder.Clear()
      continue
    }
    if ($character -in @('[', ']', '{', '}')) { throw "FRONTMATTER_YAML_INVALID" }
    [void]$builder.Append($character)
  }
  if ($quote -ne [char]0 -or $escaped) { throw "FRONTMATTER_YAML_INVALID" }
  $lastItem = $builder.ToString().Trim()
  if ([string]::IsNullOrWhiteSpace($lastItem)) { throw "FRONTMATTER_YAML_INVALID" }
  [void]$items.Add($lastItem)
  return @($items)
}

function ConvertFrom-AiBrainFrontmatterScalar {
  param([Parameter(Mandatory = $true)][string]$Value)
  $value = $Value.Trim()
  if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^[|>&*!@`{}#%]' -or
      $value -match '^[-?:](?:\s|$)' -or
      $value.IndexOf([char]0) -ge 0 -or $value -match '[\x01-\x08\x0B\x0C\x0E-\x1F]') {
    throw "FRONTMATTER_YAML_INVALID"
  }
  if ($value.StartsWith("'")) {
    if ($value -notmatch "^'(?:[^']|'')*'$") { throw "FRONTMATTER_YAML_INVALID" }
    return $value.Substring(1, $value.Length - 2).Replace("''", "'")
  }
  if ($value.StartsWith('"')) {
    if ($value -notmatch '^"(?:[^"\\]|\\["\\/bfnrt]|\\u[0-9A-Fa-f]{4})*"$') {
      throw "FRONTMATTER_YAML_INVALID"
    }
    try {
      return [string]($value | ConvertFrom-Json -ErrorAction Stop)
    } catch {
      throw "FRONTMATTER_YAML_INVALID"
    }
  }
  if ($value.StartsWith('[')) {
    foreach ($item in @(Split-AiBrainFrontmatterInlineArray -Value $value)) {
      [void](ConvertFrom-AiBrainFrontmatterScalar -Value ([string]$item))
    }
    return $value
  }
  if ($value.IndexOf("'") -ge 0 -or $value.IndexOf('"') -ge 0 -or
      $value.IndexOf('[') -ge 0 -or $value.IndexOf(']') -ge 0 -or
      $value.IndexOf('{') -ge 0 -or $value.IndexOf('}') -ge 0 -or
      $value -match ':\s' -or $value -match '\s#') {
    throw "FRONTMATTER_YAML_INVALID"
  }
  return $value
}

function Test-AiBrainFrontmatter {
  param([Parameter(Mandatory = $true)][string]$Content)
  $match = [regex]::Match($Content, '(?s)\A---\r?\n(?<yaml>.+?)\r?\n---\r?\n')
  if (-not $match.Success) { throw "MARKDOWN_FRONTMATTER_REQUIRED" }
  $values = @{}
  $lines = @($match.Groups['yaml'].Value -split '\r?\n')
  for ($index = 0; $index -lt $lines.Count; $index++) {
    $line = [string]$lines[$index]
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    if ($line -notmatch '^(?<key>[A-Za-z][A-Za-z0-9_-]*):[ \t]*(?<value>.*)$') {
      throw "FRONTMATTER_YAML_INVALID"
    }
    $key = $Matches.key.ToLowerInvariant()
    $rawValue = [string]$Matches.value
    if ($values.ContainsKey($key)) { throw "FRONTMATTER_DUPLICATE_KEY" }
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
      if ($key -in @('title', 'date_modified', 'type', 'status')) {
        throw "FRONTMATTER_YAML_INVALID"
      }
      $items = New-Object System.Collections.ArrayList
      while ($index + 1 -lt $lines.Count -and
          [string]$lines[$index + 1] -match '^[ \t]+-[ \t]+(?<item>.+)$') {
        $itemText = [string]$Matches.item
        if ($itemText.TrimStart().StartsWith('[')) { throw "FRONTMATTER_YAML_INVALID" }
        [void]$items.Add((ConvertFrom-AiBrainFrontmatterScalar -Value $itemText))
        $index++
      }
      if ($items.Count -eq 0) { throw "FRONTMATTER_YAML_INVALID" }
      $values[$key] = @($items)
      continue
    }
    $values[$key] = ConvertFrom-AiBrainFrontmatterScalar -Value $rawValue
  }
  foreach ($required in @('title', 'date_modified', 'type', 'status')) {
    if (-not $values.ContainsKey($required)) { throw "FRONTMATTER_REQUIRED_FIELD_MISSING" }
  }
  $parsedDate = [DateTime]::MinValue
  if (-not [DateTime]::TryParseExact(
      $values.date_modified,
      'yyyy-MM-dd',
      [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::None,
      [ref]$parsedDate
  )) { throw "FRONTMATTER_DATE_INVALID" }
  if ($values.type -notin @('concept', 'entity', 'source', 'synthesis', 'output', 'index', 'log')) {
    throw "FRONTMATTER_TYPE_INVALID"
  }
  if ($values.status -notin @('stub', 'draft', 'complete', 'stale')) { throw "FRONTMATTER_STATUS_INVALID" }
  return $true
}

function Resolve-AiBrainMarkdownLinkKey {
  param(
    [Parameter(Mandatory = $true)][string]$SourceRelativePath,
    [Parameter(Mandatory = $true)][string]$Target
  )
  $clean = [Uri]::UnescapeDataString($Target.Trim().Trim('<', '>').Replace('\', '/'))
  $sourceDirectory = [IO.Path]::GetDirectoryName($SourceRelativePath.Replace('/', '\')).Replace('\', '/')
  $combined = $(if ($clean.StartsWith('wiki/', [StringComparison]::OrdinalIgnoreCase)) { $clean } else { $sourceDirectory + '/' + $clean })
  $parts = @()
  foreach ($part in $combined.Split('/')) {
    if ([string]::IsNullOrWhiteSpace($part) -or $part -eq '.') { continue }
    if ($part -eq '..') {
      if ($parts.Count -eq 0) { throw "MARKDOWN_LINK_ESCAPES_WIKI" }
      $parts = @($parts | Select-Object -First ($parts.Count - 1))
      continue
    }
    $parts += $part
  }
  $key = ($parts -join '/').ToLowerInvariant()
  if (-not $key.StartsWith('wiki/', [StringComparison]::OrdinalIgnoreCase)) { throw "MARKDOWN_LINK_ESCAPES_WIKI" }
  return $key
}

function Test-AiBrainMarkdownLinks {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][string]$Content,
    [Parameter(Mandatory = $true)][hashtable]$KnownWikiPaths
  )
  if ($Content.IndexOf([char]0) -ge 0) { throw "MARKDOWN_NUL_NOT_ALLOWED" }
  foreach ($match in [regex]::Matches($Content, '\[\[([^\]|#]+)')) {
    $target = $match.Groups[1].Value.Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($target) -or [IO.Path]::IsPathRooted($target) -or $target.Contains('..')) {
      throw "WIKILINK_INVALID"
    }
    $key = $target.ToLowerInvariant()
    $fullKey = $key
    if (-not $fullKey.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase)) { $fullKey += '.md' }
    if (-not $fullKey.StartsWith('wiki/', [StringComparison]::OrdinalIgnoreCase)) {
      $fullKey = 'wiki/' + $fullKey.TrimStart('/')
    }
    if (-not $KnownWikiPaths.ContainsKey($key) -and
        -not $KnownWikiPaths.ContainsKey($fullKey) -and
        -not $KnownWikiPaths.ContainsKey([IO.Path]::GetFileNameWithoutExtension($key))) {
      throw "WIKILINK_TARGET_MISSING"
    }
  }
  foreach ($match in [regex]::Matches($Content, '\[[^\]]+\]\(([^)]+)\)')) {
    $target = (($match.Groups[1].Value -split '[#?]', 2)[0]).Trim()
    if ([string]::IsNullOrWhiteSpace($target) -or $target.StartsWith('#') -or $target -match '^[A-Za-z][A-Za-z0-9+.-]*:') { continue }
    if ([IO.Path]::IsPathRooted($target)) { throw "MARKDOWN_LINK_INVALID" }
    $linkKey = Resolve-AiBrainMarkdownLinkKey -SourceRelativePath $RelativePath -Target $target
    $candidateKeys = @($linkKey)
    if (-not [IO.Path]::HasExtension($linkKey)) { $candidateKeys += ($linkKey + '.md') }
    if (@($candidateKeys | Where-Object { $KnownWikiPaths.ContainsKey($_) }).Count -eq 0) {
      throw "MARKDOWN_LINK_TARGET_MISSING"
    }
  }
  if ($RelativePath -ieq 'wiki/index.md' -and $Content -notmatch '(?m)^#\s+\S+') { throw "INDEX_HEADING_REQUIRED" }
}

function Test-AiBrainMarkdownContent {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][string]$Content,
    [Parameter(Mandatory = $true)][hashtable]$KnownWikiPaths
  )
  Test-AiBrainFrontmatter -Content $Content | Out-Null
  Test-AiBrainMarkdownLinks -RelativePath $RelativePath -Content $Content -KnownWikiPaths $KnownWikiPaths
}

function Test-AiBrainChangeSet {
  param(
    [Parameter(Mandatory = $true)][object]$ChangeSet,
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [int]$ExistingWikiCount = 0,
    [string[]]$ProtectedWikiPaths = @()
  )
  $changes = @($ChangeSet.changes)
  $limits = $Config.limits
  [int]$fileLimit = [int]$limits.maxChangeFiles
  [long]$byteLimit = [long]$limits.maxChangeBytes
  $bulkApprovalActive = $false
  $bulkApproval = Get-AiBrainProperty $Config 'bulkApproval' $null
  if ($Operation -eq 'compile' -and $null -ne $bulkApproval -and
      -not [bool](Get-AiBrainProperty $bulkApproval 'consumed' $true)) {
    $expires = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse([string](Get-AiBrainProperty $bulkApproval 'expiresUtc' ''), [ref]$expires) -and
        $expires.UtcDateTime -gt [DateTime]::UtcNow) {
      $fileLimit = [int](Get-AiBrainProperty $bulkApproval 'maxChangeFiles' $fileLimit)
      $byteLimit = [long](Get-AiBrainProperty $bulkApproval 'maxChangeBytes' $byteLimit)
      $bulkApprovalActive = $true
    }
  }
  $ratioLimit = [Math]::Max(5, [Math]::Ceiling([Math]::Max(1, $ExistingWikiCount) * [double]$limits.maxChangeRatio))
  $effectiveFileLimit = $(if ($bulkApprovalActive) { $fileLimit } else { [Math]::Min($fileLimit, $ratioLimit) })
  if ($changes.Count -gt $effectiveFileLimit) {
    throw "CHANGE_SET_FILE_LIMIT_EXCEEDED"
  }
  $seen = @{}
  [long]$bytes = 0
  $known = Get-AiBrainWikiPathSet -RunDirectory $RunDirectory
  foreach ($protectedPath in $ProtectedWikiPaths) {
    $protectedKey = $protectedPath.Replace('\', '/').ToLowerInvariant()
    if ($protectedKey -notmatch '^wiki/.+\.md$') { continue }
    $known[$protectedKey] = $true
    $known[[IO.Path]::GetFileNameWithoutExtension($protectedKey)] = $true
  }
  foreach ($change in $changes) {
    $allowedFields = @('path', 'action', 'content')
    foreach ($property in $change.PSObject.Properties) {
      if ($property.Name -notin $allowedFields) { throw "CHANGE_SET_UNKNOWN_CHANGE_FIELD" }
    }
    $path = [string](Get-AiBrainProperty $change 'path' '')
    $action = [string](Get-AiBrainProperty $change 'action' '')
    if (-not (Test-AiBrainRelativePath -Path $path) -or -not (Test-AiBrainScopePath -Operation $Operation -Scope $Scope -RelativePath $path)) {
      throw "CHANGE_SET_PATH_OUT_OF_SCOPE"
    }
    $key = $path.Replace('\', '/').ToLowerInvariant()
    if ($seen.ContainsKey($key)) { throw "CHANGE_SET_DUPLICATE_PATH" }
    $seen[$key] = $true
    if ($action -notin @('write', 'delete')) { throw "CHANGE_SET_ACTION_INVALID" }
    if ($action -eq 'write') {
      $content = Get-AiBrainProperty $change 'content' $null
      if ($null -eq $content) { throw "CHANGE_SET_CONTENT_REQUIRED" }
      $text = [string]$content
      if ($null -ne (Test-AiBrainContainsSecret -Text $text)) { throw "CHANGE_SET_SECRET_DETECTED" }
      $bytes += $script:AiBrainUtf8NoBom.GetByteCount($text)
      $known[$key] = $true
      $known[[IO.Path]::GetFileNameWithoutExtension($key)] = $true
    } else {
      if ($null -ne (Get-AiBrainProperty $change 'content' $null)) { throw "CHANGE_SET_DELETE_CONTENT_NOT_ALLOWED" }
      $known.Remove($key)
      $known.Remove([IO.Path]::GetFileNameWithoutExtension($key))
    }
  }
  if ($bytes -gt $byteLimit) { throw "CHANGE_SET_BYTE_LIMIT_EXCEEDED" }
  if (-not $known.ContainsKey('wiki/index.md')) { throw "INDEX_REQUIRED" }
  $changeByPath = @{}
  foreach ($change in $changes) {
    $changeByPath[([string]$change.path).Replace('\', '/').ToLowerInvariant()] = $change
    if ([string]$change.action -eq 'write') {
      Test-AiBrainMarkdownContent -RelativePath ([string]$change.path) -Content ([string]$change.content) -KnownWikiPaths $known
    }
  }
  $wikiRoot = Join-Path $RunDirectory 'wiki'
  foreach ($file in Get-ChildItem -LiteralPath $wikiRoot -Recurse -File -Filter '*.md' -ErrorAction Stop) {
    $relative = $file.FullName.Substring($RunDirectory.Length).TrimStart('\').Replace('\', '/')
    $key = $relative.ToLowerInvariant()
    $change = $(if ($changeByPath.ContainsKey($key)) { $changeByPath[$key] } else { $null })
    if ($null -ne $change -and [string]$change.action -eq 'delete') { continue }
    $content = $(if ($null -ne $change) { [string]$change.content } else { Read-AiBrainUtf8 -Path $file.FullName })
    Test-AiBrainMarkdownLinks -RelativePath $relative -Content $content -KnownWikiPaths $known
  }
  return $true
}

function Materialize-AiBrainChangeSet {
  param(
    [Parameter(Mandatory = $true)][object]$ChangeSet,
    [Parameter(Mandatory = $true)][string]$RunDirectory
  )
  foreach ($change in @($ChangeSet.changes)) {
    $stagePath = Resolve-AiBrainChildPath -Root $RunDirectory -RelativePath ([string]$change.path) -AllowMissingLeaf
    if ([string]$change.action -eq 'write') {
      Write-AiBrainTextAtomic -Path $stagePath -Text ([string]$change.content)
      Set-AiBrainProperty -Object $change -Name 'stagedHash' -Value (Get-AiBrainFileSha256 -Path $stagePath)
    } elseif (Test-Path -LiteralPath $stagePath -PathType Leaf) {
      Remove-Item -LiteralPath $stagePath -Force -ErrorAction Stop
      Set-AiBrainProperty -Object $change -Name 'stagedHash' -Value $null
    }
  }
}

function Get-AiBrainManifestMap {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Manifest)
  $map = @{}
  foreach ($entry in $Manifest) { $map[[string]$entry.path.ToLowerInvariant()] = $entry }
  return $map
}

function Get-AiBrainExpectedManifestFingerprint {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$BaselineManifest,
    [Parameter(Mandatory = $true)][object]$ChangeSet,
    [Parameter(Mandatory = $true)][string]$RunDirectory
  )
  $map = @{}
  foreach ($entry in $BaselineManifest) {
    $map[[string]$entry.path.ToLowerInvariant()] = [ordered]@{
      path = [string]$entry.path
      size = [long]$entry.size
      sha256 = [string]$entry.sha256
    }
  }
  foreach ($change in @($ChangeSet.changes)) {
    $key = ([string]$change.path).Replace('\', '/').ToLowerInvariant()
    if ([string]$change.action -eq 'delete') {
      $map.Remove($key)
      continue
    }
    $stagePath = Resolve-AiBrainChildPath -Root $RunDirectory -RelativePath ([string]$change.path)
    $item = Get-Item -LiteralPath $stagePath -Force -ErrorAction Stop
    $map[$key] = [ordered]@{
      path = ([string]$change.path).Replace('\', '/')
      size = [long]$item.Length
      sha256 = [string]$change.stagedHash
    }
  }
  return Get-AiBrainManifestFingerprint -Manifest @($map.Values)
}

function Write-AiBrainBytesDurable {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
  $stream = New-Object IO.FileStream -ArgumentList @(
    $Path,
    [IO.FileMode]::CreateNew,
    [IO.FileAccess]::Write,
    [IO.FileShare]::None,
    4096,
    [IO.FileOptions]::WriteThrough
  )
  try {
    $stream.Write($Bytes, 0, $Bytes.Length)
    $stream.Flush($true)
  } finally {
    $stream.Dispose()
  }
}

function Invoke-AiBrainAtomicWriteFile {
  param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
    [AllowNull()][string]$ExpectedHash
  )
  $parent = Split-Path -Parent $TargetPath
  New-AiBrainDirectorySafe -Path $parent | Out-Null
  $exists = Test-Path -LiteralPath $TargetPath -PathType Leaf
  $actual = $(if ($exists) { Get-AiBrainFileSha256 -Path $TargetPath } else { $null })
  if ([string]$ExpectedHash -ne [string]$actual) { throw "EXTERNAL_EDIT_CONFLICT" }
  $temporary = Join-Path $parent ('.ai-brain-apply-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
  try {
    Write-AiBrainBytesDurable -Path $temporary -Bytes $Bytes
    $actualAgain = $(if (Test-Path -LiteralPath $TargetPath -PathType Leaf) { Get-AiBrainFileSha256 -Path $TargetPath } else { $null })
    if ([string]$ExpectedHash -ne [string]$actualAgain) { throw "EXTERNAL_EDIT_CONFLICT" }
    if (-not $exists) {
      [IO.File]::Move($temporary, $TargetPath)
    } else {
      Invoke-AiBrainFileReplace -SourcePath $temporary -TargetPath $TargetPath
    }
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
  }
}

function Write-AiBrainJournal {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Journal)
  Set-AiBrainProperty -Object $Journal -Name 'updatedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
  Write-AiBrainJsonAtomic -Path $Path -Value $Journal
}

function Invoke-AiBrainJournalRollback {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$JournalPath
  )
  $journal = Read-AiBrainJson -Path $JournalPath
  $journal.status = 'rolling_back'
  Write-AiBrainJournal -Path $JournalPath -Journal $journal
  $entries = @($journal.entries)
  [array]::Reverse($entries)
  foreach ($entry in $entries) {
    if ([bool](Get-AiBrainProperty $entry 'rolledBack' $false)) { continue }
    $target = Resolve-AiBrainChildPath -Root ([string]$Config.vaultPath) -RelativePath ([string]$entry.path) -AllowMissingLeaf
    $currentHash = $(if (Test-Path -LiteralPath $target -PathType Leaf) { Get-AiBrainFileSha256 -Path $target } else { $null })
    $beforeHash = Get-AiBrainProperty $entry 'beforeHash' $null
    $appliedHash = Get-AiBrainProperty $entry 'appliedHash' $null
    $stagedHash = Get-AiBrainProperty $entry 'stagedHash' $null
    $wasApplied = [bool](Get-AiBrainProperty $entry 'applied' $false)

    if ([string]$currentHash -eq [string]$beforeHash) {
      Set-AiBrainProperty -Object $entry -Name 'rolledBack' -Value $true
      Write-AiBrainJournal -Path $JournalPath -Journal $journal
      continue
    }
    if (-not $wasApplied) {
      if ([string]$entry.action -eq 'write' -and [string]$currentHash -eq [string]$stagedHash) {
        $wasApplied = $true
        $appliedHash = $stagedHash
      } elseif ([string]$entry.action -eq 'delete' -and [bool]$entry.existed -and $null -eq $currentHash) {
        $wasApplied = $true
        $appliedHash = $null
      }
    }
    if (-not $wasApplied -or [string]$currentHash -ne [string]$appliedHash) {
      $journal.status = 'conflict'
      Write-AiBrainJournal -Path $JournalPath -Journal $journal
      throw "ROLLBACK_EXTERNAL_EDIT_CONFLICT"
    }
    if ([bool]$entry.existed) {
      $backup = Resolve-AiBrainChildPath -Root $Paths.Backups -RelativePath ([string]$entry.backup) -AllowMissingLeaf
      Invoke-AiBrainAtomicWriteFile -TargetPath $target -Bytes ([IO.File]::ReadAllBytes($backup)) -ExpectedHash $currentHash
    } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
      Remove-Item -LiteralPath $target -Force -ErrorAction Stop
    }
    $restoredHash = $(if (Test-Path -LiteralPath $target -PathType Leaf) { Get-AiBrainFileSha256 -Path $target } else { $null })
    if ([string]$restoredHash -ne [string]$beforeHash) {
      $journal.status = 'conflict'
      Write-AiBrainJournal -Path $JournalPath -Journal $journal
      throw "ROLLBACK_VERIFY_FAILED"
    }
    Set-AiBrainProperty -Object $entry -Name 'rolledBack' -Value $true
    Write-AiBrainJournal -Path $JournalPath -Journal $journal
  }
  $baselineFingerprint = [string](Get-AiBrainProperty $journal 'baselineFingerprint' '')
  if (-not [string]::IsNullOrWhiteSpace($baselineFingerprint)) {
    $restoredFingerprint = Get-AiBrainManifestFingerprint (
      Get-AiBrainVaultManifest -VaultPath ([string]$Config.vaultPath))
    if ($restoredFingerprint -ne $baselineFingerprint) {
      $journal.status = 'conflict'
      Write-AiBrainJournal -Path $JournalPath -Journal $journal
      throw "ROLLBACK_VERIFY_FAILED"
    }
  }
  $journal.status = 'rolled_back'
  Write-AiBrainJournal -Path $JournalPath -Journal $journal
}

function Invoke-AiBrainWikiTransaction {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$ChangeSet,
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$BaselineManifest,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$Operation,
    [Parameter(Mandatory = $true)][string]$Scope,
    [string]$SlotId,
    [string]$RequestId,
    [string]$BatchId,
    [object[]]$CompileChunkFingerprints = @()
  )
  if (-not [string]::IsNullOrWhiteSpace($BatchId) -and $BatchId -notmatch '^[a-f0-9]{32}$') {
    throw "BATCH_ID_INVALID"
  }
  Assert-AiBrainFreeSpace -Config $Config -Paths $Paths | Out-Null
  $currentManifest = Get-AiBrainVaultManifest -VaultPath ([string]$Config.vaultPath)
  if ((Get-AiBrainManifestFingerprint $currentManifest) -ne (Get-AiBrainManifestFingerprint $BaselineManifest)) {
    throw "EXTERNAL_EDIT_CONFLICT"
  }
  $baseline = Get-AiBrainManifestMap -Manifest $BaselineManifest
  $backupRun = Join-Path $Paths.Backups $RunId
  if (Test-Path -LiteralPath $backupRun) { throw "BACKUP_RUN_ALREADY_EXISTS" }
  New-AiBrainDirectorySafe -Path $backupRun | Out-Null
  $entries = New-Object System.Collections.ArrayList
  foreach ($change in @($ChangeSet.changes)) {
    $relative = ([string]$change.path).Replace('\', '/')
    $key = $relative.ToLowerInvariant()
    $before = $(if ($baseline.ContainsKey($key)) { [string]$baseline[$key].sha256 } else { $null })
    $target = Resolve-AiBrainChildPath -Root ([string]$Config.vaultPath) -RelativePath $relative -AllowMissingLeaf
    $exists = Test-Path -LiteralPath $target -PathType Leaf
    $backupRelative = $null
    if ($exists) {
      $backupRelative = "$RunId/$relative"
      $backup = Resolve-AiBrainChildPath -Root $Paths.Backups -RelativePath $backupRelative -AllowMissingLeaf
      $backupParent = Split-Path -Parent $backup
      New-AiBrainDirectorySafe -Path $backupParent | Out-Null
      Copy-Item -LiteralPath $target -Destination $backup -ErrorAction Stop
      if ((Get-AiBrainFileSha256 $backup) -ne $before) { throw "BACKUP_HASH_MISMATCH" }
    }
    [void]$entries.Add([ordered]@{
      path = $relative
      action = [string]$change.action
      existed = $exists
      beforeHash = $before
      stagedHash = Get-AiBrainProperty $change 'stagedHash' $null
      backup = $backupRelative
      applied = $false
      appliedHash = $null
      rolledBack = $false
    })
  }
  $journal = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    requestId = $RequestId
    operation = $Operation
    scope = $Scope
    slotId = $SlotId
    batchId = $BatchId
    compileChunkFingerprints = @($CompileChunkFingerprints)
    status = 'prepared'
    createdUtc = [DateTime]::UtcNow.ToString('o')
    baselineFingerprint = Get-AiBrainManifestFingerprint -Manifest $BaselineManifest
    expectedFinalFingerprint = Get-AiBrainExpectedManifestFingerprint -BaselineManifest $BaselineManifest -ChangeSet $ChangeSet -RunDirectory $RunDirectory
    entries = @($entries)
  }
  $journalPath = Join-Path $Paths.Journals "$RunId.json"
  Write-AiBrainJournal -Path $journalPath -Journal $journal
  try {
    $journal.status = 'applying'
    Write-AiBrainJournal -Path $journalPath -Journal $journal
    for ($index = 0; $index -lt $journal.entries.Count; $index++) {
      $entry = $journal.entries[$index]
      $target = Resolve-AiBrainChildPath -Root ([string]$Config.vaultPath) -RelativePath ([string]$entry.path) -AllowMissingLeaf
      $currentHash = $(if (Test-Path -LiteralPath $target -PathType Leaf) { Get-AiBrainFileSha256 -Path $target } else { $null })
      if ([string]$currentHash -ne [string]$entry.beforeHash) { throw "EXTERNAL_EDIT_CONFLICT" }
      if ([string]$entry.action -eq 'write') {
        $stagePath = Resolve-AiBrainChildPath -Root $RunDirectory -RelativePath ([string]$entry.path)
        if ((Get-AiBrainFileSha256 -Path $stagePath) -ne [string]$entry.stagedHash) {
          throw "STAGING_INTEGRITY_FAILED"
        }
        $bytes = [IO.File]::ReadAllBytes($stagePath)
        Invoke-AiBrainAtomicWriteFile -TargetPath $target -Bytes $bytes -ExpectedHash $entry.beforeHash
        $entry.appliedHash = Get-AiBrainFileSha256 -Path $target
        if ([string]$entry.appliedHash -ne [string]$entry.stagedHash) { throw "APPLY_HASH_MISMATCH" }
      } else {
        if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force -ErrorAction Stop }
        $entry.appliedHash = $null
      }
      $entry.applied = $true
      Write-AiBrainJournal -Path $journalPath -Journal $journal
    }
    $journal.finalFingerprint = Get-AiBrainManifestFingerprint (Get-AiBrainVaultManifest -VaultPath ([string]$Config.vaultPath))
    if ([string]$journal.finalFingerprint -ne [string]$journal.expectedFinalFingerprint) {
      throw "EXTERNAL_EDIT_CONFLICT"
    }
    $journal.status = 'committed'
    Write-AiBrainJournal -Path $journalPath -Journal $journal
    return [pscustomobject]@{ JournalPath = $journalPath; Journal = $journal }
  } catch {
    Invoke-AiBrainJournalRollback -Config $Config -Paths $Paths -JournalPath $journalPath
    throw
  }
}

function Complete-AiBrainJournal {
  param([Parameter(Mandatory = $true)][string]$JournalPath)
  $journal = Read-AiBrainJson -Path $JournalPath
  if ([string]$journal.status -ne 'committed') { throw "JOURNAL_NOT_COMMITTED" }
  $journal.status = 'finalized'
  Write-AiBrainJournal -Path $JournalPath -Journal $journal
}

function Recover-AiBrainJournals {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths
  )
  $results = New-Object System.Collections.ArrayList
  foreach ($file in Get-ChildItem -LiteralPath $Paths.Journals -Filter '*.json' -File -ErrorAction SilentlyContinue) {
    $journal = Read-AiBrainJson -Path $file.FullName
    if ([string]$journal.status -in @('prepared', 'applying', 'rolling_back')) {
      Invoke-AiBrainJournalRollback -Config $Config -Paths $Paths -JournalPath $file.FullName
      [void]$results.Add([pscustomobject]@{ path = $file.FullName; action = 'rolled_back'; journal = $journal })
    } elseif ([string]$journal.status -eq 'conflict') {
      throw "ROLLBACK_EXTERNAL_EDIT_CONFLICT"
    } elseif ([string]$journal.status -eq 'committed') {
      [void]$results.Add([pscustomobject]@{ path = $file.FullName; action = 'finalize_state'; journal = $journal })
    }
  }
  return @($results)
}
