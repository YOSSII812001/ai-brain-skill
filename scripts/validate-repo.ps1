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
  $readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw
  $countMatch = [regex]::Match($readme, '(\d+)\s+micro-reference files')
  if (-not $countMatch.Success) {
    Add-Failure 'README does not declare the micro-reference file count.'
  } elseif ([int]$countMatch.Groups[1].Value -ne $referenceCount) {
    Add-Failure "README reference count is $($countMatch.Groups[1].Value), actual is $referenceCount."
  }

  $commandCount = (Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'commands') -Filter 'wiki-*.md' -File).Count
  if ($commandCount -ne 6) {
    Add-Failure "Expected 6 wiki command files, found $commandCount."
  }

  $forbidden = @(
    ('/c/Users/zooyo/Downloads/Obsid' + 'ian/' + 'Obsidian.com'),
    ('Downloads/Obsid' + 'ian/' + 'Obsidian.com'),
    ('karpa' + 'borern')
  )
  foreach ($file in Get-SourceFiles -Root $RepoRoot) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($needle in $forbidden) {
      if ($text.Contains($needle)) {
        Add-Failure "Forbidden string '$needle' found in $($file.FullName)"
      }
    }
  }

  $placeholderForbiddenFiles = @('SKILL.md', 'skill\SKILL.md')
  foreach ($relative in $placeholderForbiddenFiles) {
    $path = Join-Path $RepoRoot $relative
    $text = Get-Content -LiteralPath $path -Raw
    if ($text -match '<YOUR_VAULT_NAME>') {
      Add-Failure "Legacy placeholder <YOUR_VAULT_NAME> must not appear in $relative"
    }
  }

  $scriptFiles = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -Filter '*.ps1' -File
  foreach ($script in $scriptFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
      Add-Failure "PowerShell parse error in $($script.Name): $($errors[0].Message)"
    }
  }

  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.github\workflows\validate.yml'))) {
    Add-Failure 'Missing .github/workflows/validate.yml'
  }

  $markdownFiles = Get-SourceFiles -Root $RepoRoot | Where-Object { $_.Extension -eq '.md' }
  foreach ($file in $markdownFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
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
