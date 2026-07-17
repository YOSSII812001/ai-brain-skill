if (-not (Get-Command Get-AiBrainProperty -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'AiBrain.Common.ps1')
}

function ConvertTo-AiBrainWindowsArgument {
  param([AllowEmptyString()][string]$Argument)
  if ($null -eq $Argument -or $Argument.Length -eq 0) { return '""' }
  if ($Argument -notmatch '[\s"]') { return $Argument }
  $builder = New-Object Text.StringBuilder
  [void]$builder.Append('"')
  $slashes = 0
  foreach ($character in $Argument.ToCharArray()) {
    if ($character -eq '\') {
      $slashes++
      continue
    }
    if ($character -eq '"') {
      if ($slashes -gt 0) { [void]$builder.Append(('\' * ($slashes * 2))) }
      [void]$builder.Append('\"')
      $slashes = 0
      continue
    }
    if ($slashes -gt 0) {
      [void]$builder.Append(('\' * $slashes))
      $slashes = 0
    }
    [void]$builder.Append($character)
  }
  if ($slashes -gt 0) { [void]$builder.Append(('\' * ($slashes * 2))) }
  [void]$builder.Append('"')
  return $builder.ToString()
}

function ConvertTo-AiBrainWindowsCommandLine {
  param([string[]]$Arguments)
  return (($Arguments | ForEach-Object { ConvertTo-AiBrainWindowsArgument -Argument $_ }) -join ' ')
}

function Test-AiBrainCmdMetacharacter {
  param([AllowEmptyString()][string]$Text)
  return $Text -match '[%&|^!()]'
}

function Get-AiBrainProcessAdapter {
  param(
    [Parameter(Mandatory = $true)][string]$CommandPath,
    [string[]]$Arguments = @()
  )
  $command = Get-AiBrainCanonicalPath -Path $CommandPath -MustExist -AllowFile
  $extension = [IO.Path]::GetExtension($command).ToLowerInvariant()
  if ($extension -eq '.exe') {
    return [pscustomobject]@{
      FileName = $command
      ArgumentString = ConvertTo-AiBrainWindowsCommandLine -Arguments $Arguments
    }
  }
  if ($extension -eq '.ps1') {
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return [pscustomobject]@{
      FileName = $powershell
      ArgumentString = ConvertTo-AiBrainWindowsCommandLine -Arguments (@(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $command
      ) + $Arguments)
    }
  }
  if ($extension -in @('.cmd', '.bat')) {
    if (Test-AiBrainCmdMetacharacter -Text $command) { throw "CMD_METACHARACTER_REJECTED" }
    foreach ($argument in $Arguments) {
      if (Test-AiBrainCmdMetacharacter -Text $argument) { throw "CMD_METACHARACTER_REJECTED" }
    }
    $comspec = [Environment]::GetEnvironmentVariable('ComSpec')
    if ([string]::IsNullOrWhiteSpace($comspec)) {
      $comspec = Join-Path $env:SystemRoot 'System32\cmd.exe'
    }
    $inner = ConvertTo-AiBrainWindowsCommandLine -Arguments (@($command) + $Arguments)
    return [pscustomobject]@{
      FileName = $comspec
      ArgumentString = '/d /s /c "' + $inner + '"'
    }
  }
  throw "PROCESS_ADAPTER_UNSUPPORTED"
}

function Initialize-AiBrainProcessHost {
  if ($null -ne ('AiBrain.ProcessHost' -as [type])) { return }
  Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace AiBrain {
  public sealed class Capture {
    public string Text;
    public long Bytes;
    public bool Truncated;
  }

  public sealed class ProcessResult {
    public int? ExitCode;
    public bool TimedOut;
    public bool Drained;
    public bool TreeTerminated;
    public int ProcessId;
    public DateTime StartTimeUtc;
    public Capture StdOut;
    public Capture StdErr;
  }

  public static class ProcessHost {
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
      public long PerProcessUserTimeLimit;
      public long PerJobUserTimeLimit;
      public uint LimitFlags;
      public UIntPtr MinimumWorkingSetSize;
      public UIntPtr MaximumWorkingSetSize;
      public uint ActiveProcessLimit;
      public UIntPtr Affinity;
      public uint PriorityClass;
      public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS {
      public ulong ReadOperationCount;
      public ulong WriteOperationCount;
      public ulong OtherOperationCount;
      public ulong ReadTransferCount;
      public ulong WriteTransferCount;
      public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
      public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
      public IO_COUNTERS IoInfo;
      public UIntPtr ProcessMemoryLimit;
      public UIntPtr JobMemoryLimit;
      public UIntPtr PeakProcessMemoryUsed;
      public UIntPtr PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION {
      public long TotalUserTime;
      public long TotalKernelTime;
      public long ThisPeriodTotalUserTime;
      public long ThisPeriodTotalKernelTime;
      public uint TotalPageFaultCount;
      public uint TotalProcesses;
      public uint ActiveProcesses;
      public uint TotalTerminatedProcesses;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateJobObject(IntPtr job, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool QueryInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length, IntPtr returnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    static IntPtr CreateKillJob() {
      IntPtr job = CreateJobObject(IntPtr.Zero, null);
      if (job == IntPtr.Zero) throw new InvalidOperationException("JOB_CREATE_FAILED");
      var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
      info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
      int size = Marshal.SizeOf(info);
      IntPtr pointer = Marshal.AllocHGlobal(size);
      try {
        Marshal.StructureToPtr(info, pointer, false);
        if (!SetInformationJobObject(job, 9, pointer, (uint)size)) {
          throw new InvalidOperationException("JOB_CONFIG_FAILED");
        }
        return job;
      } catch {
        CloseHandle(job);
        throw;
      } finally {
        Marshal.FreeHGlobal(pointer);
      }
    }

    static async Task<Capture> Drain(StreamReader reader, int maxBytes) {
      char[] buffer = new char[4096];
      var builder = new StringBuilder();
      long total = 0;
      long captured = 0;
      bool truncated = false;
      while (true) {
        int read = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
        if (read == 0) break;
        string chunk = new string(buffer, 0, read);
        int bytes = Encoding.UTF8.GetByteCount(chunk);
        total += bytes;
        if (!truncated && captured + bytes <= maxBytes) {
          builder.Append(chunk);
          captured += bytes;
        } else {
          truncated = true;
        }
      }
      return new Capture { Text = builder.ToString(), Bytes = total, Truncated = truncated };
    }

    static string EncodeUtf8(string value) {
      return Convert.ToBase64String(Encoding.UTF8.GetBytes(value ?? String.Empty));
    }

    static ProcessStartInfo BuildGateStartInfo(ProcessStartInfo target, string gateName, string inputPath) {
      string shell = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.Windows),
        @"System32\WindowsPowerShell\v1.0\powershell.exe"
      );
      if (!File.Exists(shell)) throw new InvalidOperationException("PROCESS_GATE_SHELL_MISSING");
      string gateScript = @"
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$utf8=New-Object Text.UTF8Encoding($false)
[Console]::InputEncoding=$utf8
[Console]::OutputEncoding=$utf8
try {
  $gate=[Threading.EventWaitHandle]::OpenExisting($env:AIBRAIN_GATE_NAME)
  try {
    if (-not $gate.WaitOne(30000)) { exit 124 }
  } finally {
    $gate.Dispose()
  }
  $decode={ param($value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) }
  $child=New-Object Diagnostics.ProcessStartInfo
  $child.FileName=& $decode $env:AIBRAIN_GATE_FILE
  $child.Arguments=& $decode $env:AIBRAIN_GATE_ARGS
  $child.WorkingDirectory=& $decode $env:AIBRAIN_GATE_CWD
  $child.UseShellExecute=$false
  $child.CreateNoWindow=$true
  $child.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $child.RedirectStandardInput=$true
  foreach ($name in @('AIBRAIN_GATE_NAME','AIBRAIN_GATE_FILE','AIBRAIN_GATE_ARGS','AIBRAIN_GATE_CWD','AIBRAIN_GATE_INPUT')) {
    [void]$child.EnvironmentVariables.Remove($name)
  }
  $process=New-Object Diagnostics.Process
  $process.StartInfo=$child
  if (-not $process.Start()) { exit 125 }
  $inputBytes=[IO.File]::ReadAllBytes($env:AIBRAIN_GATE_INPUT)
  $write=$process.StandardInput.BaseStream.WriteAsync($inputBytes,0,$inputBytes.Length)
  [void]$write.GetAwaiter().GetResult()
  $process.StandardInput.BaseStream.Flush()
  $process.StandardInput.BaseStream.Close()
  $process.WaitForExit()
  exit $process.ExitCode
} catch {
  [Console]::Error.WriteLine('PROCESS_GATE_FAILED')
  exit 125
}
";
      string encodedScript = Convert.ToBase64String(Encoding.Unicode.GetBytes(gateScript));
      var gate = new ProcessStartInfo();
      gate.FileName = shell;
      gate.Arguments = "-NoLogo -NoProfile -NonInteractive -InputFormat Text -OutputFormat Text -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand " + encodedScript;
      gate.WorkingDirectory = target.WorkingDirectory;
      gate.UseShellExecute = false;
      gate.CreateNoWindow = true;
      gate.WindowStyle = ProcessWindowStyle.Hidden;
      gate.RedirectStandardInput = false;
      gate.RedirectStandardOutput = true;
      gate.RedirectStandardError = true;
      gate.StandardOutputEncoding = new UTF8Encoding(false);
      gate.StandardErrorEncoding = new UTF8Encoding(false);
      gate.EnvironmentVariables.Clear();
      foreach (string name in target.EnvironmentVariables.Keys) {
        gate.EnvironmentVariables[name] = target.EnvironmentVariables[name];
      }
      gate.EnvironmentVariables["AIBRAIN_GATE_NAME"] = gateName;
      gate.EnvironmentVariables["AIBRAIN_GATE_FILE"] = EncodeUtf8(target.FileName);
      gate.EnvironmentVariables["AIBRAIN_GATE_ARGS"] = EncodeUtf8(target.Arguments);
      gate.EnvironmentVariables["AIBRAIN_GATE_CWD"] = EncodeUtf8(target.WorkingDirectory);
      gate.EnvironmentVariables["AIBRAIN_GATE_INPUT"] = inputPath;
      return gate;
    }

    static bool StopAndVerifyJob(IntPtr job, int waitMilliseconds) {
      if (job == IntPtr.Zero) return false;
      if (!TerminateJobObject(job, 1)) return false;
      int size = Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
      IntPtr pointer = Marshal.AllocHGlobal(size);
      try {
        Stopwatch wait = Stopwatch.StartNew();
        while (wait.ElapsedMilliseconds <= waitMilliseconds) {
          if (!QueryInformationJobObject(job, 1, pointer, (uint)size, IntPtr.Zero)) return false;
          var info = (JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)Marshal.PtrToStructure(
            pointer,
            typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)
          );
          if (info.ActiveProcesses == 0) return true;
          Thread.Sleep(25);
        }
        return false;
      } finally {
        Marshal.FreeHGlobal(pointer);
      }
    }

    public static ProcessResult Run(ProcessStartInfo targetStartInfo, string input, int timeoutMilliseconds, int maxBytes) {
      string gateName = @"Local\AiBrainProcessGate-" + Guid.NewGuid().ToString("N");
      string inputPath = Path.Combine(
        targetStartInfo.WorkingDirectory,
        ".ai-brain-input-" + Guid.NewGuid().ToString("N") + ".tmp"
      );
      File.WriteAllBytes(inputPath, Encoding.UTF8.GetBytes(input ?? String.Empty));
      using (var gateSignal = new EventWaitHandle(false, EventResetMode.ManualReset, gateName))
      using (var process = new Process()) {
        process.StartInfo = BuildGateStartInfo(targetStartInfo, gateName, inputPath);
        IntPtr job = IntPtr.Zero;
        bool timedOut = false;
        bool treeTerminated = false;
        bool processStarted = false;
        int? exitCode = null;
        try {
          job = CreateKillJob();
          Encoding previousInputEncoding = Console.InputEncoding;
          try {
            Console.InputEncoding = new UTF8Encoding(false);
            if (!process.Start()) throw new InvalidOperationException("PROCESS_START_FAILED");
            processStarted = true;
          } finally {
            Console.InputEncoding = previousInputEncoding;
          }
          DateTime started = process.StartTime.ToUniversalTime();
          if (!AssignProcessToJobObject(job, process.Handle)) {
            throw new InvalidOperationException("JOB_ASSIGN_FAILED");
          }
          gateSignal.Set();
          Task<Capture> stdout = Drain(process.StandardOutput, maxBytes);
          Task<Capture> stderr = Drain(process.StandardError, maxBytes);
          if (process.WaitForExit(timeoutMilliseconds)) {
            exitCode = process.ExitCode;
          } else {
            timedOut = true;
          }
          treeTerminated = StopAndVerifyJob(job, 5000);
          bool rootExited = process.WaitForExit(5000);
          treeTerminated = treeTerminated && rootExited;
          if (!exitCode.HasValue && rootExited) exitCode = process.ExitCode;
          bool drained = Task.WaitAll(new Task[] { stdout, stderr }, 5000);
          return new ProcessResult {
            ExitCode = exitCode,
            TimedOut = timedOut,
            Drained = drained,
            TreeTerminated = treeTerminated,
            ProcessId = process.Id,
            StartTimeUtc = started,
            StdOut = drained ? stdout.Result : new Capture { Text = "", Bytes = 0, Truncated = true },
            StdErr = drained ? stderr.Result : new Capture { Text = "", Bytes = 0, Truncated = true }
          };
        } catch {
          if (job != IntPtr.Zero) {
            StopAndVerifyJob(job, 5000);
            try { process.WaitForExit(5000); } catch { }
          } else if (processStarted) {
            try { if (!process.HasExited) process.Kill(); } catch { }
            try { process.WaitForExit(5000); } catch { }
          }
          throw;
        } finally {
          if (job != IntPtr.Zero) {
            CloseHandle(job);
            job = IntPtr.Zero;
          }
          try { if (File.Exists(inputPath)) File.Delete(inputPath); } catch { }
        }
      }
    }
  }
}
'@
}

function Get-AiBrainChildEnvironment {
  param([hashtable]$Additional = @{})
  $allowed = @(
    'SystemRoot', 'WINDIR', 'ComSpec', 'PATHEXT', 'TEMP', 'TMP', 'USERPROFILE', 'HOME',
    'HOMEDRIVE', 'HOMEPATH', 'APPDATA', 'LOCALAPPDATA', 'PROGRAMDATA', 'ProgramFiles',
    'ProgramFiles(x86)', 'CommonProgramFiles', 'CommonProgramFiles(x86)', 'PATH',
    'OS', 'USERNAME', 'USERDOMAIN', 'USERDOMAIN_ROAMINGPROFILE', 'COMPUTERNAME',
    'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_IDENTIFIER',
    'PROCESSOR_LEVEL', 'PROCESSOR_REVISION', 'CODEX_HOME', 'CLAUDE_CONFIG_DIR'
  )
  $result = @{}
  foreach ($name in $allowed) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) { $result[$name] = $value }
  }
  foreach ($name in $Additional.Keys) {
    if ([string]$name -match '(?i)(KEY|TOKEN|SECRET|PASSWORD)' -or [string]$name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
      throw "CHILD_ENVIRONMENT_REJECTED"
    }
    $result[[string]$name] = [string]$Additional[$name]
  }
  return $result
}

function Invoke-AiBrainHiddenProcess {
  param(
    [Parameter(Mandatory = $true)][string]$CommandPath,
    [string[]]$Arguments = @(),
    [AllowEmptyString()][string]$StandardInput = '',
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [int]$TimeoutSeconds = 900,
    [int]$MaxCaptureBytes = 1048576,
    [hashtable]$Environment = @{}
  )
  if ($TimeoutSeconds -lt 1 -or $MaxCaptureBytes -lt 1024) { throw "PROCESS_LIMIT_INVALID" }
  $adapter = Get-AiBrainProcessAdapter -CommandPath $CommandPath -Arguments $Arguments
  $work = Get-AiBrainCanonicalPath -Path $WorkingDirectory -MustExist
  $start = New-Object Diagnostics.ProcessStartInfo
  $start.FileName = $adapter.FileName
  $start.Arguments = $adapter.ArgumentString
  $start.WorkingDirectory = $work
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $start.RedirectStandardInput = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.StandardOutputEncoding = $script:AiBrainUtf8NoBom
  $start.StandardErrorEncoding = $script:AiBrainUtf8NoBom
  $start.EnvironmentVariables.Clear()
  $childEnvironment = Get-AiBrainChildEnvironment -Additional $Environment
  foreach ($name in $childEnvironment.Keys) {
    $start.EnvironmentVariables[[string]$name] = [string]$childEnvironment[$name]
  }
  Initialize-AiBrainProcessHost
  return [AiBrain.ProcessHost]::Run($start, $StandardInput, ($TimeoutSeconds * 1000), $MaxCaptureBytes)
}

function New-AiBrainEmptyJsonFile {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Content = '{}'
  )
  $path = Join-Path $Directory $Name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Write-AiBrainTextAtomic -Path $path -Text ($Content + "`n")
  }
  return $path
}

function New-AiBrainOutputSchema {
  param(
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation
  )
  $schema = [ordered]@{
    type = 'object'
    additionalProperties = $false
    required = @('schemaVersion', 'operation', 'changes')
    properties = [ordered]@{
      schemaVersion = [ordered]@{ type = 'string'; enum = @('ai-brain-change-set-v1') }
      operation = [ordered]@{ type = 'string'; enum = @($Operation) }
      changes = [ordered]@{
        type = 'array'
        maxItems = 100
        items = [ordered]@{
          type = 'object'
          additionalProperties = $false
          required = @('path', 'action', 'content')
          properties = [ordered]@{
            path = [ordered]@{ type = 'string'; minLength = 1 }
            action = [ordered]@{ type = 'string'; enum = @('write', 'delete') }
            content = [ordered]@{ type = @('string', 'null') }
          }
        }
      }
    }
  }
  $path = Join-Path $RunDirectory 'change-set.schema.json'
  Write-AiBrainJsonAtomic -Path $path -Value $schema
  return [pscustomobject]@{ Path = $path; Text = (Read-AiBrainUtf8 -Path $path).Trim() }
}

function New-AiBrainAgentInvocation {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('compile', 'lint')][string]$Operation
  )
  $target = [string]$Config.target
  $schema = New-AiBrainOutputSchema -RunDirectory $RunDirectory -Operation $Operation
  if ($target -eq 'claude') {
    $emptyMcp = New-AiBrainEmptyJsonFile -Directory $RunDirectory -Name 'empty-mcp.json' -Content '{"mcpServers":{}}'
    $emptySettings = New-AiBrainEmptyJsonFile -Directory $RunDirectory -Name 'empty-settings.json'
    return [pscustomobject]@{
      CommandPath = [string]$Config.agentExecutable
      Arguments = @(
        '--print',
        '--tools', '',
        '--strict-mcp-config',
        '--mcp-config', $emptyMcp,
        '--settings', $emptySettings,
        '--setting-sources', '',
        '--no-session-persistence',
        '--output-format', 'json',
        '--json-schema', $schema.Text,
        '--permission-mode', 'manual'
      )
      FinalPath = $null
    }
  }
  if ($target -eq 'codex') {
    $finalPath = Join-Path $RunDirectory 'agent-final.txt'
    return [pscustomobject]@{
      CommandPath = [string]$Config.agentExecutable
      Arguments = @(
        'exec', '--strict-config', '--ephemeral', '--skip-git-repo-check', '--ignore-user-config',
        '--ignore-rules',
        '--disable', 'plugins', '--disable', 'apps', '--disable', 'memories', '--disable', 'hooks',
        '--disable', 'browser_use', '--disable', 'browser_use_external', '--disable', 'browser_use_full_cdp_access',
        '--disable', 'in_app_browser', '--disable', 'computer_use', '--disable', 'image_generation',
        '--disable', 'shell_tool', '--disable', 'unified_exec', '--disable', 'multi_agent',
        '--disable', 'multi_agent_v2', '--disable', 'code_mode_host', '--disable', 'goals',
        '--disable', 'tool_call_mcp_elicitation', '--disable', 'tool_suggest',
        '--disable', 'workspace_dependencies', '--disable', 'remote_plugin',
        '-c', 'skills.include_instructions=false',
        '-c', 'project_doc_max_bytes=0',
        '-c', 'include_apps_instructions=false',
        '-c', 'include_environment_context=false',
        '-c', 'approval_policy=never',
        '-c', 'shell_environment_policy.inherit=none',
        '-c', 'web_search=disabled',
        '--sandbox', 'read-only',
        '--cd', $RunDirectory,
        '--output-schema', $schema.Path,
        '--output-last-message', $finalPath,
        '-'
      )
      FinalPath = $finalPath
    }
  }
  throw "TARGET_INVALID"
}

function Get-AiBrainAgentFinalText {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex')][string]$Target,
    [Parameter(Mandatory = $true)][object]$ProcessResult,
    [string]$FinalPath
  )
  if ($ProcessResult.TimedOut) { throw "AGENT_TIMEOUT" }
  if (-not $ProcessResult.TreeTerminated) { throw "AGENT_TREE_UNCONFIRMED" }
  if (-not $ProcessResult.Drained) { throw "AGENT_STREAM_UNDRAINED" }
  if ($ProcessResult.StdOut.Truncated -or $ProcessResult.StdErr.Truncated) { throw "AGENT_OUTPUT_TRUNCATED" }
  if ($null -eq $ProcessResult.ExitCode -or [int]$ProcessResult.ExitCode -ne 0) {
    $diagnosticText = [string]$ProcessResult.StdOut.Text + "`n" + [string]$ProcessResult.StdErr.Text
    if ([regex]::IsMatch($diagnosticText, '(?i)(unauthorized|forbidden|authentication|not logged in|\b401\b|\b403\b)')) {
      throw "AGENT_AUTH_REQUIRED"
    }
    if ([regex]::IsMatch($diagnosticText, '(?i)(network is unreachable|connection (?:failed|refused|timed out)|dns|name resolution|econnrefused|enotfound)')) {
      throw "NETWORK_UNAVAILABLE"
    }
    throw "AGENT_EXIT_NONZERO"
  }
  if ($Target -eq 'claude') {
    try {
      $outer = ([string]$ProcessResult.StdOut.Text) | ConvertFrom-Json -ErrorAction Stop
    } catch {
      throw "AGENT_RESPONSE_INVALID"
    }
    if ([string](Get-AiBrainProperty -Object $outer -Name 'type' -Default '') -ne 'result' -or
        [string](Get-AiBrainProperty -Object $outer -Name 'subtype' -Default '') -ne 'success' -or
        [bool](Get-AiBrainProperty -Object $outer -Name 'is_error' -Default $true)) {
      throw "AGENT_RESPONSE_INVALID"
    }
    $structured = Get-AiBrainProperty -Object $outer -Name 'structured_output' -Default $null
    if ($null -eq $structured) { throw "AGENT_RESPONSE_MISSING_RESULT" }
    return ($structured | ConvertTo-Json -Compress -Depth 100)
  }
  if ([string]::IsNullOrWhiteSpace($FinalPath) -or -not (Test-Path -LiteralPath $FinalPath -PathType Leaf)) {
    throw "AGENT_RESPONSE_MISSING_RESULT"
  }
  return Read-AiBrainUtf8 -Path $FinalPath
}

function Test-AiBrainAgentCapability {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$ScratchDirectory
  )
  $target = [string]$Config.target
  $command = [string]$Config.agentExecutable
  $version = Invoke-AiBrainHiddenProcess -CommandPath $command -Arguments @('--version') -WorkingDirectory $ScratchDirectory -TimeoutSeconds 30 -MaxCaptureBytes 262144
  if ($version.TimedOut -or $version.ExitCode -ne 0 -or $version.StdOut.Truncated) { throw "AGENT_CAPABILITY_VERSION_FAILED" }
  $helpArguments = $(if ($target -eq 'codex') { @('exec', '--help') } else { @('--help') })
  $help = Invoke-AiBrainHiddenProcess -CommandPath $command -Arguments $helpArguments -WorkingDirectory $ScratchDirectory -TimeoutSeconds 30 -MaxCaptureBytes 1048576
  if ($help.TimedOut -or $help.ExitCode -ne 0 -or $help.StdOut.Truncated) { throw "AGENT_CAPABILITY_HELP_FAILED" }
  $helpText = [string]$help.StdOut.Text + [string]$help.StdErr.Text
  $required = $(if ($target -eq 'claude') {
    @('--print', '--tools', '--strict-mcp-config', '--no-session-persistence', '--output-format', '--json-schema')
  } else {
    @('--strict-config', '--ephemeral', '--ignore-user-config', '--ignore-rules', '--sandbox', '--output-schema', '--output-last-message')
  })
  foreach ($token in $required) {
    if (-not $helpText.Contains($token)) { throw "AGENT_CAPABILITY_FLAG_MISSING" }
  }
  $featureHash = $null
  if ($target -eq 'codex') {
    $features = Invoke-AiBrainHiddenProcess -CommandPath $command -Arguments @('features', 'list') -WorkingDirectory $ScratchDirectory -TimeoutSeconds 30 -MaxCaptureBytes 1048576
    if ($features.TimedOut -or $features.ExitCode -ne 0 -or $features.StdOut.Truncated) { throw "AGENT_CAPABILITY_FEATURES_FAILED" }
    $featureText = [string]$features.StdOut.Text + [string]$features.StdErr.Text
    foreach ($feature in @(
      'apps', 'browser_use', 'computer_use', 'hooks', 'image_generation', 'in_app_browser',
      'memories', 'multi_agent', 'plugins', 'shell_tool', 'tool_suggest', 'workspace_dependencies'
    )) {
      if ($featureText -notmatch "(?m)^$([regex]::Escape($feature))\s+") { throw "AGENT_CAPABILITY_FEATURE_MISSING" }
    }
    $featureHash = Get-AiBrainStringSha256 -Text $featureText
  }
  return [ordered]@{
    verified = $true
    verifiedUtc = [DateTime]::UtcNow.ToString('o')
    versionHash = Get-AiBrainStringSha256 -Text ([string]$version.StdOut.Text)
    helpHash = Get-AiBrainStringSha256 -Text $helpText
    featureHash = $featureHash
  }
}

function Test-AiBrainAgentAuthentication {
  param(
    [Parameter(Mandatory = $true)][object]$Config,
    [Parameter(Mandatory = $true)][string]$ScratchDirectory
  )
  $arguments = $(if ([string]$Config.target -eq 'claude') { @('auth', 'status') } else { @('login', 'status') })
  $result = Invoke-AiBrainHiddenProcess `
    -CommandPath ([string]$Config.agentExecutable) `
    -Arguments $arguments `
    -WorkingDirectory $ScratchDirectory `
    -TimeoutSeconds 30 `
    -MaxCaptureBytes 262144
  if ($result.TimedOut -or $result.ExitCode -ne 0 -or $result.StdOut.Truncated -or $result.StdErr.Truncated) {
    throw "AGENT_AUTH_REQUIRED"
  }
  if ([string]$Config.target -eq 'claude') {
    try {
      $status = ([string]$result.StdOut.Text) | ConvertFrom-Json -ErrorAction Stop
    } catch {
      throw "AGENT_AUTH_REQUIRED"
    }
    if (-not [bool](Get-AiBrainProperty $status 'loggedIn' $false)) { throw "AGENT_AUTH_REQUIRED" }
  }
  return $true
}
