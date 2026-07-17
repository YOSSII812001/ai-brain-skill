[CmdletBinding()]
param(
  [int]$StdOutBytes = 0,
  [int]$StdErrBytes = 0,
  [int]$SleepMilliseconds = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
[Console]::OutputEncoding = $utf8

if ($SleepMilliseconds -gt 0) {
  Start-Sleep -Milliseconds $SleepMilliseconds
}

$inputStream = [Console]::OpenStandardInput()
$memory = New-Object IO.MemoryStream
try {
  $inputStream.CopyTo($memory)
  $bytes = $memory.ToArray()
} finally {
  $memory.Dispose()
  $inputStream.Dispose()
}

$hasBom = $bytes.Length -ge 3 -and
  $bytes[0] -eq 0xef -and
  $bytes[1] -eq 0xbb -and
  $bytes[2] -eq 0xbf
$text = $utf8.GetString($bytes)

if ($StdOutBytes -gt 0 -or $StdErrBytes -gt 0) {
  if ($StdOutBytes -gt 0) {
    [Console]::Out.Write(('O' * $StdOutBytes))
  }
  if ($StdErrBytes -gt 0) {
    [Console]::Error.Write(('E' * $StdErrBytes))
  }
  exit 0
}

if ($null -eq ('AiBrainTest.NativeWindow' -as [type])) {
  Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace AiBrainTest {
  public static class NativeWindow {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
  }
}
'@
}

$result = [ordered]@{
  byteCount = $bytes.Length
  stdinHadBom = $hasBom
  text = $text
  hasConsoleWindow = ([AiBrainTest.NativeWindow]::GetConsoleWindow() -ne [IntPtr]::Zero)
}
[Console]::Out.Write(($result | ConvertTo-Json -Compress))
