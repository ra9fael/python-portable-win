using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

// Generic, path-relative launcher for the portable Python package.
// It reads app.ini next to itself and starts python\python.exe (or pythonw.exe).
internal static class Program
{
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("kernel32.dll")]
    private static extern uint GetConsoleProcessList(uint[] processes, uint count);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    private const int SW_HIDE = 0;

    private static string _root;
    private static bool _gui;

    private static int Main(string[] args)
    {
        _root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        Dictionary<string, string> config = Ini.Load(Path.Combine(_root, "app.ini"));
        _gui = Ini.Bool(config, "app", "gui", false);

        if (args.Length > 0 && (args[0] == "--help" || args[0] == "-h" || args[0] == "/?"))
        {
            Console.WriteLine("Usage: App.exe [--script file.py | --module name] [args...]");
            return 0;
        }

        try
        {
            return Run(args, config);
        }
        catch (Exception ex)
        {
            Fatal(ex.Message);
            return 1;
        }
    }

    private static int Run(string[] args, Dictionary<string, string> config)
    {
        string pythonExe = ResolvePython(config);
        if (pythonExe == null)
        {
            throw new FileNotFoundException("Python runtime not found under " + Path.Combine(_root, "python"));
        }

        RepairOnce(Path.Combine(_root, "python", "python.exe"));

        string module = Ini.Get(config, "app", "module", "");
        string script = null;
        List<string> passthrough = new List<string>();

        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            if (arg == "--module" && i + 1 < args.Length)
            {
                module = args[++i];
            }
            else if (arg == "--script" && i + 1 < args.Length)
            {
                script = args[++i];
            }
            else if (script == null && module.Length == 0 && arg.EndsWith(".py", StringComparison.OrdinalIgnoreCase))
            {
                script = arg;
            }
            else
            {
                passthrough.Add(arg);
            }
        }

        if (script == null && module.Length == 0)
        {
            throw new ArgumentException("No entry configured. Set [app] module in app.ini or pass --script file.py.");
        }

        StringBuilder childArgs = new StringBuilder();
        if (script != null)
        {
            string fullPath = Path.IsPathRooted(script) ? script : Path.Combine(_root, script);
            if (!File.Exists(fullPath))
            {
                throw new FileNotFoundException("Script not found: " + fullPath);
            }
            childArgs.Append(Quote(fullPath));
        }
        else
        {
            childArgs.Append("-m ").Append(Quote(module));
        }

        foreach (string arg in passthrough)
        {
            childArgs.Append(' ').Append(Quote(arg));
        }

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = pythonExe;
        psi.Arguments = childArgs.ToString();
        psi.WorkingDirectory = _root;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = _gui;
        psi.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
        psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";

        string appDir = Ini.Get(config, "app", "app_dir", "");
        string pythonPath = _root;
        if (appDir.Length > 0)
        {
            string resolved = Path.IsPathRooted(appDir) ? appDir : Path.Combine(_root, appDir);
            pythonPath = resolved + ";" + pythonPath;
        }
        psi.EnvironmentVariables["PYTHONPATH"] = pythonPath;

        ApplyTclTk(psi);

        if (_gui)
        {
            HideSoleConsole();
        }

        Process process = Process.Start(psi);
        if (process == null)
        {
            throw new InvalidOperationException("Failed to start " + psi.FileName);
        }

        using (process)
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string ResolvePython(Dictionary<string, string> config)
    {
        string configured = Ini.Get(config, "app", "python", "");
        if (configured.Length > 0)
        {
            string path = Path.IsPathRooted(configured) ? configured : Path.Combine(_root, configured);
            if (File.Exists(path))
            {
                return path;
            }
        }

        string pythonDir = Path.Combine(_root, "python");
        string[] names = _gui
            ? new string[] { "pythonw.exe", "python.exe" }
            : new string[] { "python.exe", "pythonw.exe" };

        foreach (string name in names)
        {
            string path = Path.Combine(pythonDir, name);
            if (File.Exists(path))
            {
                return path;
            }
        }
        return null;
    }

    private static void ApplyTclTk(ProcessStartInfo psi)
    {
        string tclRoot = Path.Combine(_root, "python", "tcl");
        if (!Directory.Exists(tclRoot))
        {
            return;
        }

        string tcl = FindLatest(tclRoot, "tcl8.*");
        string tk = FindLatest(tclRoot, "tk8.*");
        if (tcl != null)
        {
            psi.EnvironmentVariables["TCL_LIBRARY"] = tcl;
        }
        if (tk != null)
        {
            psi.EnvironmentVariables["TK_LIBRARY"] = tk;
        }
    }

    private static string FindLatest(string directory, string pattern)
    {
        string[] matches = Directory.GetDirectories(directory, pattern);
        if (matches.Length == 0)
        {
            return null;
        }
        Array.Sort(matches, StringComparer.OrdinalIgnoreCase);
        return matches[matches.Length - 1];
    }

    // Console-script shims embed absolute paths. Re-create them whenever the package moves.
    private static void RepairOnce(string pythonExe)
    {
        string marker = Path.Combine(_root, "python", ".portable_root");
        string previous = null;
        try
        {
            if (File.Exists(marker))
            {
                previous = File.ReadAllText(marker).Trim();
            }
        }
        catch
        {
        }

        if (previous == _root)
        {
            return;
        }

        string repairScript = Path.Combine(_root, "scripts", "repair.py");
        bool hasRepairScript = File.Exists(repairScript);
        if (hasRepairScript)
        {
            string runner = Path.Combine(_root, "python", "pythonw.exe");
            if (!File.Exists(runner))
            {
                runner = pythonExe;
            }

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = runner;
                psi.Arguments = Quote(repairScript) + " " + Quote(_root);
                psi.WorkingDirectory = _root;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
                using (Process process = Process.Start(psi))
                {
                    if (process != null)
                    {
                        process.WaitForExit(30000);
                        if (process.HasExited && process.ExitCode == 0)
                        {
                            // repair.py wrote the marker after rebuilding every shim
                            return;
                        }
                    }
                }
            }
            catch
            {
            }
        }

        if (!hasRepairScript)
        {
            try
            {
                File.WriteAllText(marker, _root);
            }
            catch
            {
            }
        }
    }

    private static void HideSoleConsole()
    {
        IntPtr hwnd = GetConsoleWindow();
        if (hwnd == IntPtr.Zero)
        {
            return;
        }

        uint[] processes = new uint[4];
        uint count = GetConsoleProcessList(processes, (uint)processes.Length);
        if (count <= 1)
        {
            ShowWindow(hwnd, SW_HIDE);
        }
    }

    private static void Fatal(string message)
    {
        Console.Error.WriteLine("[launcher] " + message);
        if (_gui)
        {
            try
            {
                MessageBox.Show(message, "Portable Launcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch
            {
            }
        }
    }

    private static string Quote(string value)
    {
        if (value.Length == 0)
        {
            return "\"\"";
        }
        if (value.IndexOfAny(new char[] { ' ', '\t', '\n', '\v', '"' }) < 0)
        {
            return value;
        }

        StringBuilder sb = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char c in value)
        {
            if (c == '\\')
            {
                backslashes++;
            }
            else if (c == '"')
            {
                sb.Append('\\', backslashes * 2 + 1);
                sb.Append('"');
                backslashes = 0;
            }
            else
            {
                sb.Append('\\', backslashes);
                sb.Append(c);
                backslashes = 0;
            }
        }
        sb.Append('\\', backslashes * 2);
        sb.Append('"');
        return sb.ToString();
    }
}

internal static class Ini
{
    public static Dictionary<string, string> Load(string path)
    {
        Dictionary<string, string> map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(path))
        {
            return map;
        }

        string section = "";
        foreach (string raw in File.ReadAllLines(path))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line[0] == '#' || line[0] == ';')
            {
                continue;
            }
            if (line[0] == '[' && line[line.Length - 1] == ']')
            {
                section = line.Substring(1, line.Length - 2).Trim().ToLowerInvariant();
                continue;
            }
            int eq = line.IndexOf('=');
            if (eq <= 0)
            {
                continue;
            }
            string key = line.Substring(0, eq).Trim().ToLowerInvariant();
            string value = line.Substring(eq + 1).Trim();
            map[section + "." + key] = value;
        }
        return map;
    }

    public static string Get(Dictionary<string, string> map, string section, string key, string fallback)
    {
        string value;
        return map.TryGetValue(section + "." + key, out value) ? value : fallback;
    }

    public static bool Bool(Dictionary<string, string> map, string section, string key, bool fallback)
    {
        string value = Get(map, section, key, fallback ? "true" : "false");
        return value.Equals("true", StringComparison.OrdinalIgnoreCase)
            || value == "1"
            || value.Equals("yes", StringComparison.OrdinalIgnoreCase);
    }
}
