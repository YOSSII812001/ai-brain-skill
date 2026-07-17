using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
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

    private static string GetChangeSet(string prompt, string operation)
    {
        if (prompt.IndexOf("MOCK_WRITE", StringComparison.Ordinal) < 0)
        {
            return "{\"schemaVersion\":\"ai-brain-change-set-v1\",\"operation\":" +
                EscapeJson(operation) + ",\"changes\":[]}";
        }

        string leaf = operation == "lint" ? "generated-lint.md" : "generated.md";
        string title = operation == "lint" ? "Generated Lint" : "Generated";
        string content =
            "---\n" +
            "title: " + title + "\n" +
            "date_modified: 2026-07-17\n" +
            "type: synthesis\n" +
            "status: complete\n" +
            "---\n" +
            "# " + title + "\n";
        return "{\"schemaVersion\":\"ai-brain-change-set-v1\",\"operation\":" +
            EscapeJson(operation) +
            ",\"changes\":[{\"path\":\"wiki/" + leaf +
            "\",\"action\":\"write\",\"content\":" + EscapeJson(content) + "}]}";
    }

    private static string FindRuntimeRoot()
    {
        DirectoryInfo run = new DirectoryInfo(Environment.CurrentDirectory);
        if (run.Parent == null || run.Parent.Parent == null)
        {
            return Environment.CurrentDirectory;
        }
        return run.Parent.Parent.FullName;
    }

    private static void WriteProbe(
        string runtimeRoot,
        string[] args,
        string operation,
        bool hadBom,
        bool isCodex)
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
        if (prompt.IndexOf("MOCK_TIMEOUT_CHILD", StringComparison.Ordinal) >= 0)
        {
            string childPath = Path.Combine(
                FindRuntimeRoot(),
                "mock-agent-child.json");
            SpawnSleepingChild(childPath);
            Thread.Sleep(120000);
            return 0;
        }
        WriteProbe(FindRuntimeRoot(), args, operation, hadBom, isCodex);
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
