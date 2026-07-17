[CmdletBinding()]
param(
  [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Add-Failure {
  param([string]$Message)
  [void]$failures.Add($Message)
}

function Get-SourceFiles {
  param([string]$Root)
  Get-ChildItem -LiteralPath $Root -Recurse -File |
    Where-Object {
      $_.FullName -notmatch '\\\.git\\' -and
      $_.FullName -notmatch '\\tasks\\'
    }
}

Push-Location $RepoRoot
try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\check-reference-parity.ps1')
  if ($LASTEXITCODE -ne 0) {
    Add-Failure 'Reference parity check failed.'
  }

  $referenceCount = (Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'skill\references') -Filter '*.md' -File).Count
  $readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw -Encoding UTF8
  $countMatch = [regex]::Match($readme, '(\d+)\s+micro-reference files')
  if (-not $countMatch.Success) {
    Add-Failure 'README does not declare the micro-reference file count.'
  } elseif ([int]$countMatch.Groups[1].Value -ne $referenceCount) {
    Add-Failure "README reference count is $($countMatch.Groups[1].Value), actual is $referenceCount."
  }

  $expectedCommands = @(
    'wiki-compile.md', 'wiki-ingest-inbox.md', 'wiki-ingest.md', 'wiki-init.md',
    'wiki-lint.md', 'wiki-query.md', 'wiki-sleep.md'
  )
  $actualCommands = @(
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'commands') -Filter 'wiki-*.md' -File |
      Select-Object -ExpandProperty Name |
      Sort-Object
  )
  if (($actualCommands -join '|') -ne (($expectedCommands | Sort-Object) -join '|')) {
    Add-Failure "Wiki command manifest differs. Expected: $($expectedCommands -join ', ')."
  }

  $forbidden = @(
    ('/c/Users/zooyo/Downloads/Obsid' + 'ian/' + 'Obsidian.com'),
    ('Downloads/Obsid' + 'ian/' + 'Obsidian.com'),
    ('karpa' + 'borern')
  )
  foreach ($file in Get-SourceFiles -Root $RepoRoot) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($needle in $forbidden) {
      if ($text.Contains($needle)) {
        Add-Failure "Forbidden string '$needle' found in $($file.FullName)"
      }
    }
  }

  $placeholderForbiddenFiles = @('SKILL.md', 'skill\SKILL.md')
  foreach ($relative in $placeholderForbiddenFiles) {
    $path = Join-Path $RepoRoot $relative
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($text -match '<YOUR_VAULT_NAME>') {
      Add-Failure "Legacy placeholder <YOUR_VAULT_NAME> must not appear in $relative"
    }
  }

  $scriptFiles = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -Recurse -Filter '*.ps1' -File
  foreach ($script in $scriptFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
      Add-Failure "PowerShell parse error in $($script.Name): $($errors[0].Message)"
    }
  }

  foreach ($relative in @(
    'tests\run-tests.ps1',
    'tests\fixtures\MockAgent.cs',
    'tests\fixtures\StdinProbe.ps1',
    'tests\fixtures\ManagerHarness.ps1'
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) {
      Add-Failure "Missing test file: $relative"
    }
  }

  foreach ($file in Get-SourceFiles -Root $RepoRoot | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.md', '.yml', '.yaml', '.json', '.cs') }) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
      Add-Failure "UTF-8 BOM is not allowed: $($file.FullName)"
    }
    try {
      [void](New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
    } catch {
      Add-Failure "File is not strict UTF-8: $($file.FullName)"
    }
  }

  if ((Get-FileHash -LiteralPath (Join-Path $RepoRoot 'SKILL.md') -Algorithm SHA256).Hash -ne
      (Get-FileHash -LiteralPath (Join-Path $RepoRoot 'skill\SKILL.md') -Algorithm SHA256).Hash) {
    Add-Failure 'Root and packaged SKILL.md files differ.'
  }
  if ((Get-FileHash -LiteralPath (Join-Path $RepoRoot 'vault\CLAUDE.md') -Algorithm SHA256).Hash -ne
      (Get-FileHash -LiteralPath (Join-Path $RepoRoot 'vault-CLAUDE-template.md') -Algorithm SHA256).Hash) {
    Add-Failure 'Vault schema templates differ.'
  }

  foreach ($relative in @(
    'scripts\ai-brain-sleep-bootstrap.ps1',
    'scripts\invoke-ai-brain-sleep.ps1',
    'scripts\manage-ai-brain-sleep.ps1',
    'scripts\lib\AiBrain.Common.ps1',
    'scripts\lib\AiBrain.Process.ps1',
    'scripts\lib\AiBrain.Requests.ps1',
    'scripts\lib\AiBrain.Schedule.ps1',
    'scripts\lib\AiBrain.Tasks.ps1',
    'scripts\lib\AiBrain.Transaction.ps1'
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) {
      Add-Failure "Missing sleep runtime package file: $relative"
    }
  }

  $vaultSchema = Get-Content -LiteralPath (Join-Path $RepoRoot 'vault\CLAUDE.md') -Raw -Encoding UTF8
  foreach ($placeholder in @('<AI_BRAIN_RUNTIME_ROOT>', '<AI_BRAIN_SCRIPT_PATH>')) {
    if (-not $vaultSchema.Contains($placeholder)) {
      Add-Failure "Vault schema is missing $placeholder"
    }
  }
  foreach ($command in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'commands') -Filter 'wiki-*.md' -File) {
    $commandText = Get-Content -LiteralPath $command.FullName -Raw -Encoding UTF8
    if ($commandText -match '<AI_BRAIN_RUNTIME_ROOT>|<YOUR_VAULT_NAME>') {
      Add-Failure "Global command contains a vault-specific placeholder: $($command.Name)"
    }
  }

  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.github\workflows\validate.yml'))) {
    Add-Failure 'Missing .github/workflows/validate.yml'
  }

  $markdownFiles = Get-SourceFiles -Root $RepoRoot | Where-Object { $_.Extension -eq '.md' }
  foreach ($file in $markdownFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $matches = [regex]::Matches($text, '\[[^\]]+\]\(([^)]+)\)')
    foreach ($match in $matches) {
      $link = $match.Groups[1].Value
      if ($link -match '^(https?|mailto):' -or $link.StartsWith('#')) {
        continue
      }
      $pathPart = ($link -split '#')[0]
      if ([string]::IsNullOrWhiteSpace($pathPart)) {
        continue
      }
      $candidate = Join-Path $file.DirectoryName ([uri]::UnescapeDataString($pathPart))
      if (-not (Test-Path -LiteralPath $candidate)) {
        Add-Failure "Broken internal link in $($file.FullName): $link"
      }
    }
  }
}
finally {
  Pop-Location
}

if ($failures.Count -gt 0) {
  Write-Host 'Validation failed:'
  $failures | ForEach-Object { Write-Host "- $_" }
  exit 1
}

Write-Host 'PASS repository validation'
