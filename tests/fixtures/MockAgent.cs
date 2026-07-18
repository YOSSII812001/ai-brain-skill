using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Text.RegularExpressions;

internal static class MockAgent
{
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    private static string EscapeJson(string value)
    {
        if (value == null)
        {
            return "null";
        }

        StringBuilder builder = new StringBuilder();
        builder.Append('"');
        foreach (char character in value)
        {
            switch (character)
            {
                case '"':
                    builder.Append("\\\"");
                    break;
                case '\\':
                    builder.Append("\\\\");
                    break;
                case '\b':
                    builder.Append("\\b");
                    break;
                case '\f':
                    builder.Append("\\f");
                    break;
                case '\n':
                    builder.Append("\\n");
                    break;
                case '\r':
                    builder.Append("\\r");
                    break;
                case '\t':
                    builder.Append("\\t");
                    break;
                default:
                    if (character < 0x20)
                    {
                        builder.Append("\\u");
                        builder.Append(((int)character).ToString("x4"));
                    }
                    else
                    {
                        builder.Append(character);
                    }
                    break;
            }
        }
        builder.Append('"');
        return builder.ToString();
    }

    private static string ReadStandardInput(out bool hadBom)
    {
        using (Stream input = Console.OpenStandardInput())
        using (MemoryStream memory = new MemoryStream())
        {
            input.CopyTo(memory);
            byte[] bytes = memory.ToArray();
            hadBom = bytes.Length >= 3 &&
                bytes[0] == 0xef &&
                bytes[1] == 0xbb &&
                bytes[2] == 0xbf;
            return new UTF8Encoding(false, true).GetString(bytes);
        }
    }

    private static string FindArgument(string[] args, string name)
    {
        for (int index = 0; index + 1 < args.Length; index++)
        {
            if (String.Equals(args[index], name, StringComparison.Ordinal))
            {
                return args[index + 1];
            }
        }
        return null;
    }

    private static bool HasArgument(string[] args, string value)
    {
        foreach (string argument in args)
        {
            if (String.Equals(argument, value, StringComparison.Ordinal))
            {
                return true;
            }
        }
        return false;
    }

    private static string GetOperation(string prompt)
    {
        Match match = Regex.Match(
            prompt,
            "\"operation\"\\s*:\\s*\"(compile|lint)\"",
            RegexOptions.CultureInvariant);
        return match.Success ? match.Groups[1].Value : "compile";
    }

    private static string GetPromptField(string prompt, string name, string fallback)
    {
        Match match = Regex.Match(
            prompt,
            "\"" + Regex.Escape(name) + "\"\\s*:\\s*\"([^\"]*)\"",
            RegexOptions.CultureInvariant);
        return match.Success ? match.Groups[1].Value : fallback;
    }

    private static string GetSha256(string value)
    {
        byte[] bytes = new UTF8Encoding(false).GetBytes(value);
        using (SHA256 sha = SHA256.Create())
        {
            byte[] hash = sha.ComputeHash(bytes);
            StringBuilder builder = new StringBuilder(hash.Length * 2);
            foreach (byte item in hash)
            {
                builder.Append(item.ToString("x2"));
            }
            return builder.ToString();
        }
    }

    private static string NewWriteChangeSet(
        string operation,
        string path,
        string title,
        string type)
    {
        string content =
            "---\n" +
            "title: " + title + "\n" +
            "date_modified: 2026-07-17\n" +
            "type: " + type + "\n" +
            "status: complete\n" +
            "---\n" +
            "# " + title + "\n";
        return "{\"schemaVersion\":\"ai-brain-change-set-v1\",\"operation\":" +
            EscapeJson(operation) +
            ",\"changes\":[{\"path\":" + EscapeJson(path) +
            ",\"action\":\"write\",\"content\":" + EscapeJson(content) + "}]}";
    }

    private static string GetChangeSet(string prompt, string operation)
    {
        if (prompt.IndexOf("MOCK_RESERVED_PATH", StringComparison.Ordinal) >= 0)
        {
            return NewWriteChangeSet(operation, "wiki/index.md", "Reserved", "index");
        }
        if (prompt.IndexOf("MOCK_CONFLICT", StringComparison.Ordinal) >= 0)
        {
            return NewWriteChangeSet(operation, "wiki/conflict.md", "Conflict", "synthesis");
        }
        if (prompt.IndexOf("MOCK_NEW_CONFLICT", StringComparison.Ordinal) >= 0)
        {
            string chunkKey = GetPromptField(prompt, "chunkKey", "root");
            return NewWriteChangeSet(
                operation,
                "wiki/new-conflict.md",
                "New Conflict " + chunkKey,
                "synthesis");
        }
        if (prompt.IndexOf("MOCK_EXISTING_CONFLICT", StringComparison.Ordinal) >= 0)
        {
            return NewWriteChangeSet(operation, "wiki/concepts/topic.md", "Existing Conflict", "concept");
        }
        if (prompt.IndexOf("MOCK_WRITE", StringComparison.Ordinal) < 0)
        {
            return "{\"schemaVersion\":\"ai-brain-change-set-v1\",\"operation\":" +
                EscapeJson(operation) + ",\"changes\":[]}";
        }

        string title = operation == "lint" ? "Generated Lint" : "Generated";
        string path = operation == "lint" ? "wiki/concepts/topic.md" : "wiki/generated.md";
        return NewWriteChangeSet(operation, path, title, "synthesis");
    }

    private static string FindRuntimeRoot()
    {
        DirectoryInfo current = new DirectoryInfo(Environment.CurrentDirectory);
        while (current != null)
        {
            if (File.Exists(Path.Combine(current.FullName, "config.json")))
            {
                return current.FullName;
            }
            current = current.Parent;
        }
        return Environment.CurrentDirectory;
    }

    private static int GetNextCallNumber(string runtimeRoot)
    {
        string path = Path.Combine(runtimeRoot, "mock-agent-call-count.txt");
        int current = 0;
        if (File.Exists(path))
        {
            Int32.TryParse(File.ReadAllText(path).Trim(), out current);
        }
        current++;
        File.WriteAllText(path, current.ToString() + "\n", new UTF8Encoding(false));
        return current;
    }

    private static void WriteProbe(
        string runtimeRoot,
        string[] args,
        string prompt,
        string operation,
        bool hadBom,
        bool isCodex,
        int callNumber)
    {
        string path = Path.Combine(
            runtimeRoot,
            "mock-agent-probe-" + Guid.NewGuid().ToString("N") + ".json");
        string json =
            "{" +
            "\"operation\":" + EscapeJson(operation) + "," +
            "\"target\":" + EscapeJson(isCodex ? "codex" : "claude") + "," +
            "\"stdinHadBom\":" + (hadBom ? "true" : "false") + "," +
            "\"hasConsoleWindow\":" + (GetConsoleWindow() == IntPtr.Zero ? "false" : "true") + "," +
            "\"mode\":" + EscapeJson(GetPromptField(prompt, "mode", "worker")) + "," +
            "\"chunkKey\":" + EscapeJson(GetPromptField(prompt, "chunkKey", "root")) + "," +
            "\"promptBytes\":" + new UTF8Encoding(false).GetByteCount(prompt).ToString() + "," +
            "\"promptSha256\":" + EscapeJson(GetSha256(prompt)) + "," +
            "\"containsSecretSentinel\":" +
                (prompt.IndexOf("TOP_SECRET_SENTINEL_123", StringComparison.Ordinal) >= 0 ? "true" : "false") + "," +
            "\"containsNewConflict\":" +
                (prompt.IndexOf("MOCK_NEW_CONFLICT", StringComparison.Ordinal) >= 0 ? "true" : "false") + "," +
            "\"callNumber\":" + callNumber.ToString() + "," +
            "\"argumentCount\":" + args.Length.ToString() +
            "}\n";
        File.WriteAllText(path, json, new UTF8Encoding(false));
    }

    private static int SpawnSleepingChild(string pidPath)
    {
        ProcessStartInfo start = new ProcessStartInfo();
        start.FileName = Assembly.GetEntryAssembly().Location;
        start.Arguments = "--child-sleep";
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.WindowStyle = ProcessWindowStyle.Hidden;
        Process child = Process.Start(start);
        File.WriteAllText(
            pidPath,
            "{\"pid\":" + child.Id.ToString() + "}\n",
            new UTF8Encoding(false));
        return child.Id;
    }

    private static void WriteHelp(bool codex)
    {
        if (codex)
        {
            Console.Out.WriteLine(
                "--strict-config --ephemeral --ignore-user-config --ignore-rules " +
                "--sandbox --output-schema --output-last-message");
        }
        else
        {
            Console.Out.WriteLine(
                "--print --tools --strict-mcp-config --no-session-persistence " +
                "--output-format --json-schema");
        }
    }

    private static void WriteFeatures()
    {
        string[] features = new string[]
        {
            "apps",
            "browser_use",
            "computer_use",
            "hooks",
            "image_generation",
            "in_app_browser",
            "memories",
            "multi_agent",
            "plugins",
            "shell_tool",
            "tool_suggest",
            "workspace_dependencies"
        };
        foreach (string feature in features)
        {
            Console.Out.WriteLine(feature + " disabled");
        }
    }

    public static int Main(string[] args)
    {
        Console.InputEncoding = new UTF8Encoding(false, true);
        Console.OutputEncoding = new UTF8Encoding(false);

        if (HasArgument(args, "--child-sleep"))
        {
            Thread.Sleep(120000);
            return 0;
        }
        string childProbe = FindArgument(args, "--spawn-child-probe");
        if (!String.IsNullOrWhiteSpace(childProbe))
        {
            SpawnSleepingChild(childProbe);
            Thread.Sleep(120000);
            return 0;
        }
        if (HasArgument(args, "--version"))
        {
            Console.Out.WriteLine("mock-agent 1.0.0");
            return 0;
        }
        if (HasArgument(args, "--help"))
        {
            WriteHelp(args.Length > 0 && args[0] == "exec");
            return 0;
        }
        if (args.Length >= 2 && args[0] == "features" && args[1] == "list")
        {
            WriteFeatures();
            return 0;
        }
        if (args.Length >= 2 && args[0] == "auth" && args[1] == "status")
        {
            Console.Out.WriteLine("{\"loggedIn\":true}");
            return 0;
        }
        if (args.Length >= 2 && args[0] == "login" && args[1] == "status")
        {
            Console.Out.WriteLine("Logged in");
            return 0;
        }
        if (HasArgument(args, "--window-probe"))
        {
            Console.Out.WriteLine(
                "{\"hasConsoleWindow\":" +
                (GetConsoleWindow() == IntPtr.Zero ? "false" : "true") +
                "}");
            return 0;
        }
        bool hadBom;
        string prompt = ReadStandardInput(out hadBom);
        string operation = GetOperation(prompt);
        bool isCodex = args.Length > 0 && args[0] == "exec";
        string runtimeRoot = FindRuntimeRoot();
        int callNumber = GetNextCallNumber(runtimeRoot);
        if (prompt.IndexOf("MOCK_TIMEOUT_CHILD", StringComparison.Ordinal) >= 0)
        {
            string childPath = Path.Combine(
                runtimeRoot,
                "mock-agent-child.json");
            SpawnSleepingChild(childPath);
            Thread.Sleep(120000);
            return 0;
        }
        WriteProbe(runtimeRoot, args, prompt, operation, hadBom, isCodex, callNumber);
        string failOnSecond = Path.Combine(runtimeRoot, "mock-agent-fail-on-call-2.flag");
        string failCompleted = Path.Combine(runtimeRoot, "mock-agent-fail-on-call-2.done");
        if (callNumber == 2 && File.Exists(failOnSecond) && !File.Exists(failCompleted))
        {
            File.WriteAllText(failCompleted, "done\n", new UTF8Encoding(false));
            Console.Error.WriteLine("mock fail once");
            return 9;
        }
        string changeSet = GetChangeSet(prompt, operation);

        if (isCodex)
        {
            string outputPath = FindArgument(args, "--output-last-message");
            if (String.IsNullOrWhiteSpace(outputPath))
            {
                Console.Error.WriteLine("missing --output-last-message");
                return 3;
            }
            File.WriteAllText(outputPath, changeSet + "\n", new UTF8Encoding(false));
        }
        else
        {
            Console.Out.WriteLine(
                "{\"type\":\"result\",\"subtype\":\"success\"," +
                "\"is_error\":false,\"structured_output\":" +
                changeSet + "}");
        }
        return 0;
    }
}
