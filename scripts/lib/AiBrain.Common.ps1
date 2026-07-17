Set-StrictMode -Version 2.0

$script:AiBrainUtf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
$script:AiBrainAllowedStatuses = @('off', 'ready', 'running', 'paused', 'attention')
$script:AiBrainTextExtensions = @('.md', '.txt', '.json', '.csv', '.yml', '.yaml')
$script:AiBrainMessages = @{
  action_doctor = '"wiki-sleep doctor \u3092\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  report_title_yaml = '"title: \"AI Brain \u7761\u7720\u30ec\u30dd\u30fc\u30c8\""'
  report_heading = '"# AI Brain \u7761\u7720\u30ec\u30dd\u30fc\u30c8"'
  report_status = '"- \u72b6\u614b: {0}"'
  report_last_success = '"- \u6700\u7d42\u6210\u529f: {0}"'
  report_last_compile = '"- \u6700\u7d42\u306e\u8a18\u61b6\u306e\u6574\u7406\uff08compile\uff09: {0}"'
  report_last_lint = '"- \u6700\u7d42\u306e\u8a18\u61b6\u306e\u5065\u5eb7\u8a3a\u65ad\uff08lint\uff09: {0}"'
  report_next_compile = '"- \u6b21\u56de\u306e\u8a18\u61b6\u306e\u6574\u7406\uff08compile\uff09: {0}"'
  report_next_lint = '"- \u6b21\u56de\u306e\u8a18\u61b6\u306e\u5065\u5eb7\u8a3a\u65ad\uff08lint\uff09: {0}"'
  report_heartbeat = '"- \u6700\u5f8c\u306e\u751f\u5b58\u78ba\u8a8d: {0}"'
  report_result = '"- \u76f4\u8fd1\u306e\u7d50\u679c: {0}"'
  report_recovery = '"- \u81ea\u52d5\u5fa9\u5143: {0}"'
  report_organized = '"- \u6574\u7406\u3057\u305f\u77e5\u8b58: {0}\u4ef6"'
  report_concepts = '"- \u65b0\u3057\u304f\u3064\u306a\u304c\u3063\u305f\u6982\u5ff5: {0}\u4ef6"'
  report_links = '"- \u4fee\u6b63\u3057\u305f\u30ea\u30f3\u30af: {0}\u30d5\u30a1\u30a4\u30eb"'
  report_metadata = '"- \u4fee\u6b63\u3057\u305f\u7ba1\u7406\u60c5\u5831: {0}\u30d5\u30a1\u30a4\u30eb"'
  report_skip = '"- \u30b9\u30ad\u30c3\u30d7\u7406\u7531: {0}"'
  result_none = '"\u307e\u3060\u7d50\u679c\u306f\u3042\u308a\u307e\u305b\u3093"'
  result_no_change = '"\u6574\u7406\u3059\u308b\u65b0\u3057\u3044\u5185\u5bb9\u306f\u3042\u308a\u307e\u305b\u3093"'
  result_clean = '"\u70b9\u691c\u6e08\u307f\u3067\u3059\u3002\u4fee\u6b63\u306f\u3042\u308a\u307e\u305b\u3093"'
  result_applied = '"{0}\u4ef6\u3092\u6574\u7406\u3057\u307e\u3057\u305f"'
  recovery_none = '"\u306a\u3057"'
  recovery_state = '"\u72b6\u614b\u30d5\u30a1\u30a4\u30eb\u3092\u81ea\u52d5\u5fa9\u5143\u3057\u307e\u3057\u305f"'
  recovery_rollback = '"\u4e2d\u65ad\u3057\u305f\u5909\u66f4\u3092\u81ea\u52d5\u7684\u306b\u5143\u306b\u623b\u3057\u307e\u3057\u305f"'
  report_never = '"\u672a\u5b9f\u884c"'
  report_disabled = '"\u7121\u52b9"'
  status_off = '"\u81ea\u52d5\u6574\u7406\u306f\u505c\u6b62\u4e2d\u3067\u3059"'
  status_ready = '"\u6b63\u5e38\u306b\u5f85\u6a5f\u3057\u3066\u3044\u307e\u3059"'
  status_running = '"\u73fe\u5728\u3001\u77e5\u8b58\u3092\u6574\u7406\u4e2d\u3067\u3059"'
  status_paused = '"\u540c\u3058\u5931\u6557\u304c\u7d9a\u3044\u305f\u305f\u3081\u3001\u5b89\u5168\u306b\u505c\u6b62\u3057\u307e\u3057\u305f"'
  status_attention = '"\u5229\u7528\u8005\u306e\u64cd\u4f5c\u304c1\u3064\u5fc5\u8981\u3067\u3059"'
  skip_none = '"\u306a\u3057"'
  skip_source_unchanged = '"\u65b0\u3057\u3044\u5185\u5bb9\u304c\u306a\u3044\u305f\u3081\u3001AI\u3092\u4f7f\u308f\u305a\u78ba\u8a8d\u3060\u3051\u884c\u3044\u307e\u3057\u305f"'
  report_next_action = '"## \u6b21\u306b\u884c\u3046\u64cd\u4f5c"'
  setup_intro = '"AI Brain\u306e\u300c\u7761\u7720\u30e2\u30fc\u30c9\u300d\u3092\u8a2d\u5b9a\u3057\u307e\u3059\u3002"'
  setup_compile_what = '"compile\uff08\u30b3\u30f3\u30d1\u30a4\u30eb\uff09\u306f\u3001\u4eba\u304c\u7720\u3063\u3066\u3044\u308b\u9593\u306b\u65e5\u4e2d\u306e\u8a18\u61b6\u3092\u6574\u7406\u3059\u308b\u4f5c\u696d\u3067\u3059\u3002"'
  setup_compile_when = '"\u5897\u3048\u305f\u30ce\u30fc\u30c8\u3092\u7d50\u3073\u76f4\u3057\u3001\u76ee\u6b21\u3092\u6574\u3048\u307e\u3059\u3002\u65e2\u5b9a\u3067\u306f4\u6642\u9593\u3054\u3068\u3067\u3059\u3002"'
  setup_lint_what = '"lint\uff08\u30ea\u30f3\u30c8\uff09\u306f\u3001\u4eba\u306e\u6bce\u65e5\u306e\u5065\u5eb7\u8a3a\u65ad\u3067\u3059\u3002"'
  setup_lint_when = '"\u30ea\u30f3\u30af\u5207\u308c\u3084\u66f8\u5f0f\u306e\u4e71\u308c\u3092\u70b9\u691c\u3057\u307e\u3059\u3002\u65e2\u5b9a\u3067\u306f\u6bce\u65e517:00\u3067\u3059\u3002"'
  setup_hidden = '"\u3069\u3061\u3089\u3082\u88cf\u5074\u3067\u52d5\u304d\u3001\u901a\u5e38\u306f\u30bf\u30fc\u30df\u30ca\u30eb\u3092\u8868\u793a\u3057\u307e\u305b\u3093\u3002"'
  setup_choice = '"[A] \u3053\u306e\u307e\u307e\u4f7f\u3046 / [C] \u6642\u9593\u3092\u5909\u3048\u308b / [D] \u7121\u52b9\u306b\u3059\u308b"'
  setup_hours = '"compile\u306e\u9593\u9694\uff08\u6642\u9593\u3002\u73fe\u5728 {0}\uff09"'
  setup_lint_time = '"lint\u306e\u6642\u523b\uff08HH:mm\u3002\u73fe\u5728 {0}\uff09"'
  compile_instruction = '"\u4eba\u9593\u304c\u7720\u3063\u3066\u3044\u308b\u9593\u306b\u8a18\u61b6\u3092\u6574\u7406\u3059\u308b\u3088\u3046\u306b\u3001main/raw/wiki\u306e\u60c5\u5831\u3092\u7d71\u5408\u3057\u3066\u304f\u3060\u3055\u3044\u3002\n\u65b0\u3057\u3044\u4e8b\u5b9f\u306e\u7d71\u5408\u3001stub\u306e\u6607\u683c\u3001wikilink\u306e\u88dc\u5f37\u3001wiki/index.md\u3068wiki/log.md\u306e\u66f4\u65b0\u3092\u884c\u3044\u307e\u3059\u3002"'
  lint_instruction = '"\u6bce\u65e5\u306e\u5065\u5eb7\u8a3a\u65ad\u306e\u3088\u3046\u306bwiki\u3092\u70b9\u691c\u3057\u3066\u304f\u3060\u3055\u3044\u3002\n\u58ca\u308c\u305f\u30ea\u30f3\u30af\u3001frontmatter\u3001\u53e4\u3044\u8a18\u8ff0\u3001\u547d\u540d\u3001\u5b64\u7acb\u30da\u30fc\u30b8\u3092\u70b9\u691c\u3057\u3001\u5fc5\u8981\u306a\u4fee\u6b63\u3068wiki/log.md\u306e\u66f4\u65b0\u3092\u884c\u3044\u307e\u3059\u3002"'
  safety_bundle = '"\u5165\u529bbundle\u4ee5\u5916\u3092\u8aad\u307e\u306a\u3044"'
  safety_tools = '"tool\u3001command\u3001network\u3001filesystem\u3092\u4f7f\u308f\u306a\u3044"'
  safety_layers = '"main\u3068raw\u306f\u5909\u66f4\u3057\u306a\u3044"'
  safety_json = '"\u51fa\u529b\u306fJSON object\u3060\u3051\u3067\u3001\u524d\u5f8c\u306b\u8aac\u660e\u3092\u66f8\u304b\u306a\u3044"'
  schema_action = '"write \u307e\u305f\u306f delete"'
  schema_content = '"write\u306e\u3068\u304d\u3060\u3051UTF-8 Markdown\u5168\u6587"'
  action_auth = '"AI\u30a8\u30fc\u30b8\u30a7\u30f3\u30c8\u3078\u518d\u30ed\u30b0\u30a4\u30f3\u3057\u3001wiki-sleep doctor \u3092\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_edit = '"\u7de8\u96c6\u4e2d\u306e\u30ce\u30fc\u30c8\u3092\u4fdd\u5b58\u3057\u3066\u304b\u3089 wiki-sleep doctor \u3092\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_admin = '"\u7ba1\u7406\u8005\u6a29\u9650\u3092\u78ba\u8a8d\u3057\u3066 wiki-sleep doctor \u3092\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_repair = '"wiki-sleep doctor --repair \u3092\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_bulk = '"\u521d\u56de\u306e\u5927\u91cf\u6574\u7406\u306e\u898b\u7a4d\u308a\u3092\u78ba\u8a8d\u3057\u3001wiki-sleep approve-bulk \u30921\u56de\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_state_reset = '"\u4fdd\u5b58\u3055\u308c\u305f\u72b6\u614b\u3092\u78ba\u8a8d\u3057\u3001wiki-sleep doctor --repair --approve-state-reset \u3092\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_vault = '"Obsidian vault\u304c\u79fb\u52d5\u307e\u305f\u306f\u524a\u9664\u3055\u308c\u3066\u3044\u307e\u3059\u3002vault\u3092\u5143\u306e\u5834\u6240\u3078\u623b\u3059\u304b\u3001wiki-sleep rebind \"<new-vault-path>\" \u30921\u56de\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_config_reset = '"\u73fe\u5728\u306e\u8a2d\u5b9a\u3092\u4fdd\u5b58\u3057\u305f\u307e\u307e\u3001wiki-sleep reconfigure --approve-config-reset \u3092\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_setup = '"wiki-sleep repair-installation \u30921\u56de\u5b9f\u884c\u3057\u3066\u304f\u3060\u3055\u3044"'
  action_source_safety = '"AI\u306b\u300c\u79d8\u5bc6\u60c5\u5831\u3092\u542b\u3080\u30ce\u30fc\u30c8\u3092\u6574\u7406\u5bfe\u8c61\u304b\u3089\u5916\u3057\u3066\u3001\u81ea\u52d5\u6574\u7406\u3092\u518d\u958b\u3057\u3066\u300d\u3068\u4f9d\u983c\u3057\u3066\u304f\u3060\u3055\u3044"'
  setup_bulk_estimate = '"\u521d\u56decompile\u306e\u5bfe\u8c61\u306f {0}\u30d5\u30a1\u30a4\u30eb\uff08{1}\u30d0\u30a4\u30c8\uff09\u3067\u3059\u3002\u6700\u5927{2}\u30d5\u30a1\u30a4\u30eb\u306ewiki\u5909\u66f4\u30921\u56de\u3060\u3051\u8a31\u53ef\u3057\u307e\u3059\u304b\uff1f"'
  setup_bulk_choice = '"[Y] \u8a31\u53ef\u3059\u308b / [N] \u4eca\u306f\u8a31\u53ef\u3057\u306a\u3044"'
}

function Get-AiBrainMessage {
  param([Parameter(Mandatory = $true)][string]$Name)
  if (-not $script:AiBrainMessages.ContainsKey($Name)) { throw "MESSAGE_NOT_FOUND" }
  return ([string]$script:AiBrainMessages[$Name] | ConvertFrom-Json -ErrorAction Stop)
}

function Get-AiBrainProperty {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) { return $Object[$Name] }
    return $Default
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Set-AiBrainProperty {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($Object -is [System.Collections.IDictionary]) {
    $Object[$Name] = $Value
    return
  }
  $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-AiBrainSha256Bytes {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-AiBrainStringSha256 {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
  return Get-AiBrainSha256Bytes -Bytes $script:AiBrainUtf8NoBom.GetBytes($Text)
}

function Get-AiBrainFileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Read-AiBrainUtf8 {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
    throw "UTF8_BOM_NOT_ALLOWED"
  }
  try {
    return $script:AiBrainUtf8NoBom.GetString($bytes)
  } catch {
    throw "INVALID_UTF8"
  }
}

function Write-AiBrainTextAtomic {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
  )
  $parent = Split-Path -Parent $Path
  if ([string]::IsNullOrWhiteSpace($parent)) { throw "ATOMIC_PARENT_MISSING" }
  New-AiBrainDirectorySafe -Path $parent | Out-Null
  $temporary = Join-Path $parent ('.ai-brain-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
  $bytes = $script:AiBrainUtf8NoBom.GetBytes($Text)
  $stream = $null
  try {
    $stream = New-Object IO.FileStream -ArgumentList @(
      $temporary,
      [IO.FileMode]::CreateNew,
      [IO.FileAccess]::Write,
      [IO.FileShare]::None,
      4096,
      [IO.FileOptions]::WriteThrough
    )
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
    $stream.Dispose()
    $stream = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
      Invoke-AiBrainFileReplace -SourcePath $temporary -TargetPath $Path
    } else {
      [IO.File]::Move($temporary, $Path)
    }
  } finally {
    if ($null -ne $stream) { $stream.Dispose() }
    if (Test-Path -LiteralPath $temporary) {
      Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
  }
}

function Invoke-AiBrainFileReplace {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$TargetPath
  )
  $parent = Split-Path -Parent $TargetPath
  $backup = Join-Path $parent ('.ai-brain-replace-{0}.bak' -f [Guid]::NewGuid().ToString('N'))
  try {
    # Windows PowerShell 5.1 rejects a null backup path for File.Replace.
    [IO.File]::Replace($SourcePath, $TargetPath, $backup, $true)
  } finally {
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
      Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    }
  }
}

function Read-AiBrainJson {
  param([Parameter(Mandatory = $true)][string]$Path, [switch]$Optional)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    if ($Optional) { return $null }
    throw "JSON_NOT_FOUND"
  }
  $text = Read-AiBrainUtf8 -Path $Path
  if ([string]::IsNullOrWhiteSpace($text)) { throw "JSON_EMPTY" }
  try {
    $command = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($command.Parameters.ContainsKey('DateKind')) {
      return $text | ConvertFrom-Json -DateKind String -ErrorAction Stop
    }
    return $text | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "JSON_INVALID"
  }
}

function Write-AiBrainJsonAtomic {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $json = $Value | ConvertTo-Json -Depth 40
  Write-AiBrainTextAtomic -Path $Path -Text ($json + "`n")
}

function Test-AiBrainUncOrDevicePath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return $Path.StartsWith('\\', [StringComparison]::Ordinal) -or
    $Path.StartsWith('\\?\', [StringComparison]::Ordinal) -or
    $Path.StartsWith('\\.\', [StringComparison]::Ordinal)
}

function Get-AiBrainCanonicalPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$MustExist,
    [switch]$AllowFile
  )
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "PATH_EMPTY" }
  if (Test-AiBrainUncOrDevicePath -Path $Path) { throw "NETWORK_OR_DEVICE_PATH_NOT_SUPPORTED" }
  $full = [IO.Path]::GetFullPath($Path)
  if ($MustExist) {
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (-not $AllowFile -and -not $item.PSIsContainer) { throw "PATH_NOT_DIRECTORY" }
    $full = $item.FullName
  }
  $root = [IO.Path]::GetPathRoot($full)
  if ([string]::IsNullOrWhiteSpace($root) -or (Test-AiBrainUncOrDevicePath -Path $root)) {
    throw "LOCAL_ABSOLUTE_PATH_REQUIRED"
  }
  if ($root -match '^[A-Za-z]:[\\/]$') {
    $drive = New-Object System.IO.DriveInfo -ArgumentList $root
    if ($drive.DriveType -eq [IO.DriveType]::Network) {
      throw "NETWORK_OR_DEVICE_PATH_NOT_SUPPORTED"
    }
  }
  if ($full.Length -gt $root.Length) { $full = $full.TrimEnd('\', '/') }
  return $full
}

function Assert-AiBrainNoReparsePath {
  param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissingLeaf)
  $full = Get-AiBrainCanonicalPath -Path $Path
  $cursor = $full
  if ($AllowMissingLeaf) {
    while (-not [string]::IsNullOrWhiteSpace($cursor) -and -not (Test-Path -LiteralPath $cursor)) {
      $parent = Split-Path -Parent $cursor
      if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
      $cursor = $parent
    }
  }
  while (-not [string]::IsNullOrWhiteSpace($cursor) -and (Test-Path -LiteralPath $cursor)) {
    $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "REPARSE_POINT_NOT_ALLOWED"
    }
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
    $cursor = $parent
  }
  return $full
}

function New-AiBrainDirectorySafe {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = Assert-AiBrainNoReparsePath -Path $Path -AllowMissingLeaf
  if (Test-Path -LiteralPath $full -PathType Container) {
    Assert-AiBrainNoReparsePath -Path $full | Out-Null
    return $full
  }
  if (Test-Path -LiteralPath $full) { throw "PATH_NOT_DIRECTORY" }

  $missing = New-Object System.Collections.ArrayList
  $cursor = $full
  while (-not (Test-Path -LiteralPath $cursor)) {
    [void]$missing.Add($cursor)
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) {
      throw "DIRECTORY_ANCESTOR_NOT_FOUND"
    }
    $cursor = $parent
  }
  Assert-AiBrainNoReparsePath -Path $cursor | Out-Null

  for ($index = $missing.Count - 1; $index -ge 0; $index--) {
    [IO.Directory]::CreateDirectory([string]$missing[$index]) | Out-Null
    Assert-AiBrainNoReparsePath -Path ([string]$missing[$index]) | Out-Null
  }
  return $full
}

function Test-AiBrainPathWithin {
  param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Candidate)
  $rootFull = (Get-AiBrainCanonicalPath -Path $Root).TrimEnd('\') + '\'
  $candidateFull = Get-AiBrainCanonicalPath -Path $Candidate
  return $candidateFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Test-AiBrainRelativePath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path.Contains(':')) { return $false }
  $normalized = $Path.Replace('/', '\')
  foreach ($component in $normalized.Split('\')) {
    if ($component -in @('', '.', '..')) { return $false }
    if ($component.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
  }
  return $true
}

function Resolve-AiBrainChildPath {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [switch]$AllowMissingLeaf
  )
  if (-not (Test-AiBrainRelativePath -Path $RelativePath)) { throw "RELATIVE_PATH_INVALID" }
  $rootFull = Get-AiBrainCanonicalPath -Path $Root
  $candidate = Get-AiBrainCanonicalPath -Path (Join-Path $rootFull $RelativePath)
  if (-not (Test-AiBrainPathWithin -Root $rootFull -Candidate $candidate)) { throw "PATH_ESCAPES_ROOT" }
  Assert-AiBrainNoReparsePath -Path $candidate -AllowMissingLeaf:$AllowMissingLeaf | Out-Null
  return $candidate
}

function Get-AiBrainVaultId {
  param([Parameter(Mandatory = $true)][string]$VaultPath)
  $canonical = Get-AiBrainCanonicalPath -Path $VaultPath -MustExist
  Assert-AiBrainNoReparsePath -Path $canonical | Out-Null
  return (Get-AiBrainStringSha256 -Text $canonical.ToUpperInvariant()).Substring(0, 16)
}

function Get-AiBrainExpectedRuntimeRoot {
  param([Parameter(Mandatory = $true)][string]$VaultId)
  $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  if ([string]::IsNullOrWhiteSpace($local)) { throw "LOCALAPPDATA_NOT_FOUND" }
  return Get-AiBrainCanonicalPath -Path (Join-Path (Join-Path $local 'ai-brain') $VaultId)
}

function Get-AiBrainRuntimePaths {
  param([Parameter(Mandatory = $true)][string]$RuntimeRoot)
  $root = Get-AiBrainCanonicalPath -Path $RuntimeRoot
  return [pscustomobject]@{
    Root = $root
    Config = Join-Path $root 'config.json'
    State = Join-Path $root 'state.json'
    Attention = Join-Path $root 'attention.json'
    ActivePackage = Join-Path $root 'active-package.json'
    Bootstrap = Join-Path $root 'bootstrap\ai-brain-sleep-bootstrap.ps1'
    Packages = Join-Path $root 'packages'
    Logs = Join-Path $root 'logs'
    Staging = Join-Path $root 'staging'
    Backups = Join-Path $root 'backups'
    Journals = Join-Path $root 'journals'
    Requests = Join-Path $root 'requests'
    PendingRequests = Join-Path $root 'requests\pending'
    ClaimedRequests = Join-Path $root 'requests\claimed'
    CompletedRequests = Join-Path $root 'requests\completed'
    FailedRequests = Join-Path $root 'requests\failed'
    Migration = Join-Path $root 'migration'
  }
}

function Initialize-AiBrainRuntimeDirectories {
  param([Parameter(Mandatory = $true)][object]$Paths)
  foreach ($path in @(
    $Paths.Root, $Paths.Packages, $Paths.Logs, $Paths.Staging, $Paths.Backups, $Paths.Journals,
    $Paths.PendingRequests, $Paths.ClaimedRequests, $Paths.CompletedRequests, $Paths.FailedRequests,
    $Paths.Migration, (Split-Path -Parent $Paths.Bootstrap)
  )) {
    New-AiBrainDirectorySafe -Path $path | Out-Null
  }
}

function New-AiBrainConfig {
  param(
    [Parameter(Mandatory = $true)][string]$VaultPath,
    [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex')][string]$Target,
    [Parameter(Mandatory = $true)][string]$AgentExecutable,
    [int]$CompileIntervalHours = 4,
    [string]$LintLocalTime = '17:00',
    [bool]$Enabled = $true,
    [string]$PackageId = ''
  )
  $canonicalVault = Get-AiBrainCanonicalPath -Path $VaultPath -MustExist
  $vaultId = Get-AiBrainVaultId -VaultPath $canonicalVault
  $runtimeRoot = Get-AiBrainExpectedRuntimeRoot -VaultId $vaultId
  return [ordered]@{
    schemaVersion = 1
    consentVersion = 1
    vaultId = $vaultId
    vaultPath = $canonicalVault
    runtimeRoot = $runtimeRoot
    target = $Target
    agentExecutable = (Get-AiBrainCanonicalPath -Path $AgentExecutable -MustExist -AllowFile)
    enabled = $Enabled
    compileEnabled = $true
    lintEnabled = $true
    compileIntervalHours = $CompileIntervalHours
    lintLocalTime = $LintLocalTime
    timeZoneId = [TimeZoneInfo]::Local.Id
    installedUtc = [DateTime]::UtcNow.ToString('o')
    taskPath = '\AI Brain\'
    taskName = "AI Brain Sleep $vaultId"
    packageId = $PackageId
    taskGeneration = [Guid]::NewGuid().ToString('N')
    managedTaskXmlHash = $null
    lastControlAction = 'setup'
    agentCapability = $null
    limits = [ordered]@{
      timeoutSeconds = 5400
      maxSourceFiles = 1000
      maxSourceBytes = 8388608
      maxChangeFiles = 100
      maxChangeRatio = 0.25
      maxChangeBytes = 10485760
      maxCaptureBytes = 12582912
      minFreeSpaceBytes = 104857600
      legacyWaitSeconds = 900
      requestWaitSeconds = 120
      retentionDays = 30
      retainedFailedRuns = 5
      retainedPackages = 3
    }
  }
}

function Assert-AiBrainConfig {
  param([Parameter(Mandatory = $true)][object]$Config)
  if ([int](Get-AiBrainProperty $Config 'schemaVersion' 0) -ne 1) { throw "CONFIG_SCHEMA_UNSUPPORTED" }
  if ([int](Get-AiBrainProperty $Config 'consentVersion' 0) -ne 1) { throw "CONSENT_REQUIRED" }
  $configuredVault = [string](Get-AiBrainProperty $Config 'vaultPath' '')
  if ([string]::IsNullOrWhiteSpace($configuredVault) -or
      -not (Test-Path -LiteralPath $configuredVault -PathType Container)) {
    throw "VAULT_NOT_FOUND_OR_MOVED"
  }
  $vault = Get-AiBrainCanonicalPath -Path $configuredVault -MustExist
  $vaultId = Get-AiBrainVaultId -VaultPath $vault
  if ($vaultId -ne [string]$Config.vaultId) { throw "VAULT_ID_MISMATCH" }
  $expectedRuntime = Get-AiBrainExpectedRuntimeRoot -VaultId $vaultId
  if (-not [string]::Equals($expectedRuntime, (Get-AiBrainCanonicalPath -Path ([string]$Config.runtimeRoot)), [StringComparison]::OrdinalIgnoreCase)) {
    throw "RUNTIME_ROOT_MISMATCH"
  }
  if ([string]$Config.target -notin @('claude', 'codex')) { throw "TARGET_INVALID" }
  if ((Get-AiBrainProperty $Config 'enabled' $null) -isnot [bool]) { throw "CONFIG_ENABLED_INVALID" }
  if ((Get-AiBrainProperty $Config 'compileEnabled' $null) -isnot [bool] -or
      (Get-AiBrainProperty $Config 'lintEnabled' $null) -isnot [bool]) { throw "CONFIG_OPERATION_ENABLED_INVALID" }
  if ([int]$Config.compileIntervalHours -lt 1 -or [int]$Config.compileIntervalHours -gt 168) { throw "COMPILE_INTERVAL_INVALID" }
  if ([string]$Config.lintLocalTime -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$') { throw "LINT_TIME_INVALID" }
  [void][TimeZoneInfo]::FindSystemTimeZoneById([string]$Config.timeZoneId)
  $installed = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse(
      [string](Get-AiBrainProperty $Config 'installedUtc' ''),
      [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::RoundtripKind,
      [ref]$installed
  )) { throw "CONFIG_INSTALLED_TIME_INVALID" }
  $agent = Get-AiBrainCanonicalPath -Path ([string]$Config.agentExecutable) -MustExist -AllowFile
  Assert-AiBrainNoReparsePath -Path $agent | Out-Null
  if ([IO.Path]::GetExtension($agent).ToLowerInvariant() -ne '.exe') { throw "DIRECT_AGENT_EXECUTABLE_REQUIRED" }
  if ([string]$Config.taskPath -ne '\AI Brain\') { throw "TASK_PATH_INVALID" }
  if ([string]$Config.taskName -ne "AI Brain Sleep $vaultId") { throw "TASK_NAME_INVALID" }
  if ([string]$Config.packageId -notmatch '^[a-f0-9]{64}$') { throw "PACKAGE_ID_INVALID" }
  if ([string]$Config.taskGeneration -notmatch '^[a-f0-9]{32}$') { throw "TASK_GENERATION_INVALID" }
  $limits = Get-AiBrainProperty $Config 'limits' $null
  if ($null -eq $limits) { throw "CONFIG_LIMITS_MISSING" }
  foreach ($limitName in @(
    'timeoutSeconds', 'maxSourceFiles', 'maxSourceBytes', 'maxChangeFiles', 'maxChangeBytes',
    'maxCaptureBytes', 'minFreeSpaceBytes', 'legacyWaitSeconds', 'requestWaitSeconds',
    'retentionDays', 'retainedFailedRuns', 'retainedPackages'
  )) {
    $value = [long](Get-AiBrainProperty $limits $limitName 0)
    if ($value -lt 1 -or $value -gt 1073741824) { throw "CONFIG_LIMIT_INVALID" }
  }
  $ratio = [double](Get-AiBrainProperty $limits 'maxChangeRatio' 0)
  if ($ratio -le 0 -or $ratio -gt 1) { throw "CONFIG_LIMIT_INVALID" }
  $bulkApproval = Get-AiBrainProperty $Config 'bulkApproval' $null
  if ($null -ne $bulkApproval) {
    if ((Get-AiBrainProperty $bulkApproval 'consumed' $null) -isnot [bool]) { throw "CONFIG_BULK_APPROVAL_INVALID" }
    $bulkFiles = [int](Get-AiBrainProperty $bulkApproval 'maxChangeFiles' 0)
    $bulkBytes = [long](Get-AiBrainProperty $bulkApproval 'maxChangeBytes' 0)
    if ($bulkFiles -lt [int]$limits.maxChangeFiles -or $bulkFiles -gt 100 -or
        $bulkBytes -lt [long]$limits.maxChangeBytes -or $bulkBytes -gt 1073741824) {
      throw "CONFIG_BULK_APPROVAL_INVALID"
    }
    $bulkExpiry = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string](Get-AiBrainProperty $bulkApproval 'expiresUtc' ''), [ref]$bulkExpiry)) {
      throw "CONFIG_BULK_APPROVAL_INVALID"
    }
  }
  return $true
}

function New-AiBrainState {
  param([bool]$Enabled)
  return [ordered]@{
    schemaVersion = 1
    status = $(if ($Enabled) { 'ready' } else { 'off' })
    runId = $null
    activeRequestId = $null
    child = $null
    lastHeartbeatUtc = $null
    lastCompileSlotUtc = $null
    lastLintSlotId = $null
    lastCompileSuccessUtc = $null
    lastLintSuccessUtc = $null
    lastCompileInputFingerprint = $null
    nextCompileUtc = $null
    nextLintUtc = $null
    failureSignature = $null
    sameFailureCount = 0
    attentionCode = $null
    attentionAction = $null
    packageId = $null
    taskGeneration = $null
    lastResultCode = $null
    lastResultOperation = $null
    lastChangeCount = 0
    lastNewConceptCount = 0
    lastLinkFixCount = 0
    lastMetadataFixCount = 0
    lastSkipReason = $null
    lastRecoveryCode = $null
    lastRollbackPerformed = $false
    lastRunCompletedUtc = $null
    updatedUtc = [DateTime]::UtcNow.ToString('o')
  }
}

function Assert-AiBrainState {
  param([Parameter(Mandatory = $true)][object]$State)
  if ([int](Get-AiBrainProperty $State 'schemaVersion' 0) -ne 1) { throw "STATE_SCHEMA_UNSUPPORTED" }
  if ([string]$State.status -notin $script:AiBrainAllowedStatuses) { throw "STATE_STATUS_INVALID" }
  if ([int](Get-AiBrainProperty $State 'sameFailureCount' -1) -lt 0) { throw "STATE_FAILURE_COUNT_INVALID" }
  foreach ($idName in @('runId', 'activeRequestId', 'taskGeneration')) {
    $value = [string](Get-AiBrainProperty $State $idName '')
    if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '^[a-f0-9]{32}$') { throw "STATE_ID_INVALID" }
  }
  $packageId = [string](Get-AiBrainProperty $State 'packageId' '')
  if (-not [string]::IsNullOrWhiteSpace($packageId) -and $packageId -notmatch '^[a-f0-9]{64}$') { throw "STATE_PACKAGE_ID_INVALID" }
  return $true
}

function Set-AiBrainState {
  param([Parameter(Mandatory = $true)][object]$Paths, [Parameter(Mandatory = $true)][object]$State)
  Set-AiBrainProperty -Object $State -Name 'updatedUtc' -Value ([DateTime]::UtcNow.ToString('o'))
  Assert-AiBrainState -State $State | Out-Null
  Write-AiBrainJsonAtomic -Path $Paths.State -Value $State
}

function Read-AiBrainState {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [object]$Config,
    [switch]$Repair
  )
  if (Test-Path -LiteralPath $Paths.State -PathType Leaf) {
    $state = Read-AiBrainJson -Path $Paths.State
    Assert-AiBrainState -State $state | Out-Null
    return $state
  }
  if (-not $Repair -or $null -eq $Config) { throw "STATE_NOT_FOUND" }
  $state = New-AiBrainState -Enabled ([bool]$Config.enabled)
  $state.packageId = [string]$Config.packageId
  $state.taskGeneration = [string]$Config.taskGeneration
  $state.lastHeartbeatUtc = [DateTime]::UtcNow.ToString('o')
  $state.lastCompileInputFingerprint = $null
  $state.lastResultCode = 'state_rebuilt'
  $state.lastRecoveryCode = 'STATE_REBUILT'
  $state.lastRunCompletedUtc = [DateTime]::UtcNow.ToString('o')
  Set-AiBrainState -Paths $Paths -State $state
  return $state
}

function Test-AiBrainContainsSecret {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
  $patterns = [ordered]@{
    private_key = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    openai_key = '\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b'
    github_token = '\bgh[pousr]_[A-Za-z0-9]{20,}\b'
    aws_key = '\bAKIA[0-9A-Z]{16}\b'
    assigned_secret = '(?i)\b(?:api[_-]?key|access[_-]?token|secret|password)\b\s*[:=]\s*[''"]?[A-Za-z0-9_./+=-]{16,}'
  }
  foreach ($entry in $patterns.GetEnumerator()) {
    if ([regex]::IsMatch($Text, [string]$entry.Value)) { return [string]$entry.Key }
  }
  return $null
}

function Test-AiBrainDeniedFileName {
  param([Parameter(Mandatory = $true)][string]$Name)
  $lower = $Name.ToLowerInvariant()
  return $lower -like '.env*' -or
    $lower -match '(credential|credentials|secret|private[-_ ]?key|id_rsa|id_ed25519)' -or
    [IO.Path]::GetExtension($lower) -in @('.pfx', '.p12', '.pem', '.key', '.kdbx')
}

function Get-AiBrainErrorCode {
  param([Parameter(Mandatory = $true)][object]$ErrorRecord)
  $message = [string](Get-AiBrainProperty -Object (Get-AiBrainProperty -Object $ErrorRecord -Name 'Exception' -Default $null) -Name 'Message' -Default '')
  if ($message -match '^[A-Z][A-Z0-9_]{2,}$') { return $message }
  $exception = Get-AiBrainProperty -Object $ErrorRecord -Name 'Exception' -Default $null
  $typeName = $(if ($null -ne $exception) { $exception.GetType().FullName } else { 'UnknownException' })
  $fullyQualifiedId = [string](Get-AiBrainProperty -Object $ErrorRecord -Name 'FullyQualifiedErrorId' -Default '')
  $stable = '{0}|{1}' -f $typeName, (($fullyQualifiedId -split ',', 2)[0])
  return 'UNEXPECTED_' + (Get-AiBrainStringSha256 -Text $stable).Substring(0, 12).ToUpperInvariant()
}

function Get-AiBrainVaultManifest {
  param([Parameter(Mandatory = $true)][string]$VaultPath, [switch]$TextOnly)
  $vault = Get-AiBrainCanonicalPath -Path $VaultPath -MustExist
  $entries = New-Object System.Collections.ArrayList
  foreach ($layer in @('main', 'raw', 'wiki')) {
    $layerPath = Join-Path $vault $layer
    if (-not (Test-Path -LiteralPath $layerPath -PathType Container)) { continue }
    Assert-AiBrainNoReparsePath -Path $layerPath | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $layerPath -Recurse -File -Force -ErrorAction Stop | Sort-Object FullName) {
      Assert-AiBrainNoReparsePath -Path $file.FullName | Out-Null
      $relative = $file.FullName.Substring($vault.Length).TrimStart('\').Replace('\', '/')
      if ($relative -ieq 'wiki/_meta/sleep-report.md' -or $relative -match '(?i)^wiki/_meta/(?:\.lock|sleep-)') { continue }
      if ($TextOnly -and $file.Extension.ToLowerInvariant() -notin $script:AiBrainTextExtensions) { continue }
      [void]$entries.Add([ordered]@{
        path = $relative
        size = [long]$file.Length
        sha256 = Get-AiBrainFileSha256 -Path $file.FullName
      })
    }
  }
  return ,([object[]]@($entries))
}

function Get-AiBrainManifestFingerprint {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Manifest)
  $lines = @(
    $Manifest |
      Sort-Object { [string](Get-AiBrainProperty -Object $_ -Name 'path' -Default '') } |
      ForEach-Object { '{0}|{1}|{2}' -f $_.path, $_.size, $_.sha256 }
  )
  return Get-AiBrainStringSha256 -Text (($lines -join "`n") + "`n")
}

function Assert-AiBrainFreeSpace {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths,
    [long]$SourceBytes = 0,
    [hashtable]$AvailableBytesByRoot = @{}
  )
  if ($SourceBytes -lt 0) { throw "DISK_SPACE_REQUIREMENT_INVALID" }
  [long]$margin = [long]$Config.limits.minFreeSpaceBytes
  [long]$runtimeRequired = $margin + $SourceBytes + ([long]$Config.limits.maxChangeBytes * 3) + [long]$Config.limits.maxCaptureBytes
  [long]$vaultRequired = $margin + ([long]$Config.limits.maxChangeBytes * 2)
  $requirements = @{}
  foreach ($entry in @(
    [pscustomobject]@{ path = [string]$Paths.Root; bytes = $runtimeRequired },
    [pscustomobject]@{ path = [string]$Config.vaultPath; bytes = $vaultRequired }
  )) {
    $root = [IO.Path]::GetPathRoot((Get-AiBrainCanonicalPath -Path ([string]$entry.path))).TrimEnd('\') + '\'
    if ($requirements.ContainsKey($root)) { $requirements[$root] = [long]$requirements[$root] + [long]$entry.bytes }
    else { $requirements[$root] = [long]$entry.bytes }
  }
  foreach ($root in $requirements.Keys) {
    [long]$available = 0
    if ($AvailableBytesByRoot.ContainsKey($root)) {
      $available = [long]$AvailableBytesByRoot[$root]
    } else {
      $drive = New-Object IO.DriveInfo -ArgumentList $root
      if (-not $drive.IsReady) { throw "DISK_NOT_READY" }
      $available = [long]$drive.AvailableFreeSpace
    }
    if ($available -lt [long]$requirements[$root]) { throw "DISK_SPACE_LOW" }
  }
  return $true
}

function Write-AiBrainLogEvent {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$EventCode,
    [ValidateSet('info', 'warning', 'attention', 'error')][string]$Level = 'info',
    [hashtable]$SafeData = @{}
  )
  $record = [ordered]@{
    timestampUtc = [DateTime]::UtcNow.ToString('o')
    level = $Level
    eventCode = $EventCode
    data = $SafeData
  }
  $line = ($record | ConvertTo-Json -Compress -Depth 8) + "`n"
  $logPath = Join-Path $Paths.Logs ('sleep-{0}.jsonl' -f [DateTime]::UtcNow.ToString('yyyy-MM-dd'))
  [IO.File]::AppendAllText($logPath, $line, $script:AiBrainUtf8NoBom)
}

function Write-AiBrainRuntimeAttention {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][string]$Action
  )
  $record = [ordered]@{
    schemaVersion = 1
    status = 'attention'
    code = $Code
    action = $Action
    updatedUtc = [DateTime]::UtcNow.ToString('o')
  }
  Write-AiBrainJsonAtomic -Path $Paths.Attention -Value $record
}

function Set-AiBrainAttention {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][string]$Action
  )
  $State.status = 'attention'
  $State.attentionCode = $Code
  $State.attentionAction = $Action
  $State.runId = $null
  $State.activeRequestId = $null
  $State.child = $null
  Set-AiBrainState -Paths $Paths -State $State
  Write-AiBrainLogEvent -Paths $Paths -EventCode $Code -Level attention
}

function Register-AiBrainFailure {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][string]$Code
  )
  $signature = Get-AiBrainStringSha256 -Text $Code
  if ([string]$State.failureSignature -eq $signature) {
    $State.sameFailureCount = [int]$State.sameFailureCount + 1
  } else {
    $State.failureSignature = $signature
    $State.sameFailureCount = 1
  }
  $State.status = $(if ([int]$State.sameFailureCount -ge 3) { 'paused' } else { 'ready' })
  $State.runId = $null
  $State.activeRequestId = $null
  $State.child = $null
  if ($State.status -eq 'paused') {
    $State.attentionCode = 'REPEATED_FAILURE_PAUSED'
    $State.attentionAction = Get-AiBrainMessage -Name action_doctor
  }
  Set-AiBrainState -Paths $Paths -State $State
  Write-AiBrainLogEvent -Paths $Paths -EventCode $Code -Level error -SafeData @{ sameFailureCount = [int]$State.sameFailureCount }
}

function Reset-AiBrainFailure {
  param([Parameter(Mandatory = $true)][object]$State)
  $State.failureSignature = $null
  $State.sameFailureCount = 0
  $State.attentionCode = $null
  $State.attentionAction = $null
}

function Clear-AiBrainAttentionIfCode {
  param(
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][string]$ExpectedCode,
    [Parameter(Mandatory = $true)][bool]$Enabled,
    [Parameter(Mandatory = $true)][string]$RecoveryCode
  )
  if ([string]$State.status -ne 'attention' -or [string]$State.attentionCode -ne $ExpectedCode) {
    return $false
  }
  $State.status = $(if ($Enabled) { 'ready' } else { 'off' })
  Reset-AiBrainFailure -State $State
  $State.runId = $null
  $State.activeRequestId = $null
  $State.child = $null
  $State.lastRecoveryCode = $RecoveryCode
  return $true
}

function Enter-AiBrainMutex {
  param([Parameter(Mandatory = $true)][string]$VaultId, [int]$TimeoutMilliseconds = 0)
  $name = "Global\AiBrainSleep-$VaultId"
  $mutex = New-Object Threading.Mutex($false, $name)
  try {
    $acquired = $mutex.WaitOne($TimeoutMilliseconds)
  } catch [Threading.AbandonedMutexException] {
    $acquired = $true
  } catch {
    $mutex.Dispose()
    throw
  }
  return [pscustomobject]@{ Name = $name; Mutex = $mutex; Acquired = $acquired }
}

function Exit-AiBrainMutex {
  param([object]$Lock)
  if ($null -eq $Lock) { return }
  try { if ($Lock.Acquired) { $Lock.Mutex.ReleaseMutex() } } catch {}
  try { $Lock.Mutex.Dispose() } catch {}
}

function Remove-AiBrainRuntimeItem {
  param(
    [Parameter(Mandatory = $true)][object]$Paths,
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Recurse
  )
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $root = Get-AiBrainCanonicalPath -Path $Paths.Root -MustExist
  $target = Get-AiBrainCanonicalPath -Path $Path -MustExist -AllowFile
  if ([string]::Equals($root, $target, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-AiBrainPathWithin -Root $root -Candidate $target)) {
    throw "RUNTIME_DELETE_GUARD_FAILED"
  }
  Assert-AiBrainNoReparsePath -Path $target | Out-Null
  Remove-Item -LiteralPath $target -Force -Recurse:$Recurse -ErrorAction Stop
}

function Invoke-AiBrainRuntimeMaintenance {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$Paths
  )
  $cutoff = [DateTime]::UtcNow.AddDays(-[int]$Config.limits.retentionDays)
  foreach ($root in @($Paths.Logs, $Paths.CompletedRequests, $Paths.FailedRequests)) {
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue) {
      if ($file.LastWriteTimeUtc -lt $cutoff) { Remove-AiBrainRuntimeItem -Paths $Paths -Path $file.FullName }
    }
  }

  $stagingDirectories = @(
    Get-ChildItem -LiteralPath $Paths.Staging -Directory -Force -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTimeUtc -Descending
  )
  for ($index = 0; $index -lt $stagingDirectories.Count; $index++) {
    if ($index -ge [int]$Config.limits.retainedFailedRuns -or $stagingDirectories[$index].LastWriteTimeUtc -lt $cutoff) {
      Remove-AiBrainRuntimeItem -Paths $Paths -Path $stagingDirectories[$index].FullName -Recurse
    }
  }

  foreach ($file in Get-ChildItem -LiteralPath $Paths.Journals -Filter '*.json' -File -Force -ErrorAction SilentlyContinue) {
    if ($file.LastWriteTimeUtc -ge $cutoff) { continue }
    $journal = Read-AiBrainJson -Path $file.FullName
    if ([string]$journal.status -notin @('finalized', 'rolled_back')) { continue }
    $runId = [string](Get-AiBrainProperty $journal 'runId' '')
    if ($runId -match '^[a-f0-9]{32}$') {
      $backup = Join-Path $Paths.Backups $runId
      if (Test-Path -LiteralPath $backup -PathType Container) { Remove-AiBrainRuntimeItem -Paths $Paths -Path $backup -Recurse }
    }
    Remove-AiBrainRuntimeItem -Paths $Paths -Path $file.FullName
  }

  $active = Read-AiBrainJson -Path $Paths.ActivePackage
  $activeId = [string]$active.packageId
  $packages = @(
    Get-ChildItem -LiteralPath $Paths.Packages -Directory -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^[a-f0-9]{64}$' } |
      Sort-Object LastWriteTimeUtc -Descending
  )
  $retained = @{}
  $retained[$activeId] = $true
  foreach ($package in $packages) {
    if ($retained.Count -lt [int]$Config.limits.retainedPackages) { $retained[$package.Name] = $true }
  }
  foreach ($package in $packages) {
    if (-not $retained.ContainsKey($package.Name)) { Remove-AiBrainRuntimeItem -Paths $Paths -Path $package.FullName -Recurse }
  }
  foreach ($temporary in Get-ChildItem -LiteralPath $Paths.Packages -Directory -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like '.*.tmp' -and $_.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-1) }) {
    Remove-AiBrainRuntimeItem -Paths $Paths -Path $temporary.FullName -Recurse
  }
}

function Write-AiBrainSleepReport {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][object]$State
  )
  $meta = Join-Path ([string]$Config.vaultPath) 'wiki\_meta'
  if (-not (Test-Path -LiteralPath $meta -PathType Container)) {
    New-Item -ItemType Directory -Path $meta -Force -ErrorAction Stop | Out-Null
  }
  Assert-AiBrainNoReparsePath -Path $meta | Out-Null
  $resultCode = [string](Get-AiBrainProperty $State 'lastResultCode' '')
  $changeCount = [int](Get-AiBrainProperty $State 'lastChangeCount' 0)
  $resultText = switch ($resultCode) {
    'no_change' { Get-AiBrainMessage -Name result_no_change; break }
    'clean' { Get-AiBrainMessage -Name result_clean; break }
    'applied' { (Get-AiBrainMessage -Name result_applied) -f $changeCount; break }
    'state_rebuilt' { Get-AiBrainMessage -Name recovery_state; break }
    default { Get-AiBrainMessage -Name result_none }
  }
  $recoveryCode = [string](Get-AiBrainProperty $State 'lastRecoveryCode' '')
  $recoveryText = $(if ([bool](Get-AiBrainProperty $State 'lastRollbackPerformed' $false)) {
    Get-AiBrainMessage -Name recovery_rollback
  } else { switch ($recoveryCode) {
    'STATE_REBUILT' { Get-AiBrainMessage -Name recovery_state; break }
    'JOURNAL_ROLLED_BACK' { Get-AiBrainMessage -Name recovery_rollback; break }
    default { Get-AiBrainMessage -Name recovery_none }
  }})
  $statusText = Get-AiBrainMessage -Name ('status_' + [string]$State.status)
  $successTimes = @(
    [string](Get-AiBrainProperty $State 'lastCompileSuccessUtc' ''),
    [string](Get-AiBrainProperty $State 'lastLintSuccessUtc' '')
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Descending
  $lastSuccess = $(if (@($successTimes).Count -gt 0) { [string]$successTimes[0] } else { Get-AiBrainMessage -Name report_never })
  $skipCode = [string](Get-AiBrainProperty $State 'lastSkipReason' '')
  $skipText = $(if ($skipCode -eq 'source_unchanged') {
    Get-AiBrainMessage -Name skip_source_unchanged
  } else {
    Get-AiBrainMessage -Name skip_none
  })
  $lines = @(
    '---',
    (Get-AiBrainMessage -Name report_title_yaml),
    ('date_modified: "{0}"' -f (Get-Date -Format 'yyyy-MM-dd')),
    'type: log',
    'status: complete',
    '---',
    (Get-AiBrainMessage -Name report_heading),
    '',
    ((Get-AiBrainMessage -Name report_status) -f $statusText),
    ((Get-AiBrainMessage -Name report_heartbeat) -f $(if ($State.lastHeartbeatUtc) { $State.lastHeartbeatUtc } else { Get-AiBrainMessage -Name report_never })),
    ((Get-AiBrainMessage -Name report_last_success) -f $lastSuccess),
    ((Get-AiBrainMessage -Name report_result) -f $resultText),
    ((Get-AiBrainMessage -Name report_organized) -f [int](Get-AiBrainProperty $State 'lastChangeCount' 0)),
    ((Get-AiBrainMessage -Name report_concepts) -f [int](Get-AiBrainProperty $State 'lastNewConceptCount' 0)),
    ((Get-AiBrainMessage -Name report_links) -f [int](Get-AiBrainProperty $State 'lastLinkFixCount' 0)),
    ((Get-AiBrainMessage -Name report_metadata) -f [int](Get-AiBrainProperty $State 'lastMetadataFixCount' 0)),
    ((Get-AiBrainMessage -Name report_skip) -f $skipText),
    ((Get-AiBrainMessage -Name report_recovery) -f $recoveryText),
    ((Get-AiBrainMessage -Name report_last_compile) -f $(if ($State.lastCompileSuccessUtc) { $State.lastCompileSuccessUtc } else { Get-AiBrainMessage -Name report_never })),
    ((Get-AiBrainMessage -Name report_last_lint) -f $(if ($State.lastLintSuccessUtc) { $State.lastLintSuccessUtc } else { Get-AiBrainMessage -Name report_never })),
    ((Get-AiBrainMessage -Name report_next_compile) -f $(if ($State.nextCompileUtc) { $State.nextCompileUtc } else { Get-AiBrainMessage -Name report_disabled })),
    ((Get-AiBrainMessage -Name report_next_lint) -f $(if ($State.nextLintUtc) { $State.nextLintUtc } else { Get-AiBrainMessage -Name report_disabled }))
  )
  if ($State.status -in @('paused', 'attention')) {
    $lines += ''
    $lines += (Get-AiBrainMessage -Name report_next_action)
    $lines += ('{0}' -f [string]$State.attentionAction)
  }
  Write-AiBrainTextAtomic -Path (Join-Path $meta 'sleep-report.md') -Text (($lines -join "`n") + "`n")
}
