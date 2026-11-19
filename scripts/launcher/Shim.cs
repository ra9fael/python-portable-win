using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

// Path-relative replacement for pip/uv console-script launchers.
// A copy named <tool>.exe sits in python\Scripts and reads <tool>.entry side by side.
internal static class Program
{
    private static int Main(string[] args)
    {
        try
        {
            string self = Path.GetFullPath(Environment.GetCommandLineArgs()[0]);
            string dir = Path.GetDirectoryName(self);
            string stem = Path.GetFileNameWithoutExtension(self);

            string module = stem;
            string func = "main";
            bool gui = false;

            string entryFile = Path.Combine(dir, stem + ".entry");
            if (File.Exists(entryFile))
            {
                Dictionary<string, string> entry = Load(entryFile);
                string value;
                if (entry.TryGetValue("module", out value) && value.Length > 0)
                {
                    module = value;
                }
                if (entry.TryGetValue("func", out value) && value.Length > 0)
                {
                    func = value;
                }
                if (entry.TryGetValue("gui", out value))
                {
                    gui = value.Equals("true", StringComparison.OrdinalIgnoreCase);
                }
            }

            string pythonDir = Path.GetDirectoryName(dir);
            string pythonExe = Path.Combine(pythonDir, gui ? "pythonw.exe" : "python.exe");
            if (!File.Exists(pythonExe))
            {
                pythonExe = Path.Combine(pythonDir, "python.exe");
            }
            if (!File.Exists(pythonExe))
            {
                Console.Error.WriteLine("[shim] Python not found: " + pythonExe);
                return 2;
            }

            StringBuilder code = new StringBuilder();
            code.Append("import sys, importlib\n");
            code.Append("m = importlib.import_module(").Append(PyQuote(module)).Append(")\n");
            code.Append("f = m\n");
            code.Append("for p in ").Append(PyQuote(func)).Append(".split('.'):\n");
            code.Append("    f = getattr(f, p)\n");
            code.Append("sys.exit(f())\n");

            StringBuilder command = new StringBuilder();
            command.Append("-c ").Append(Quote(code.ToString()));
            foreach (string arg in args)
            {
                command.Append(' ').Append(Quote(arg));
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = pythonExe;
            psi.Arguments = command.ToString();
            psi.UseShellExecute = false;
            psi.CreateNoWindow = gui;
            psi.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";

            Process process = Process.Start(psi);
            if (process == null)
            {
                Console.Error.WriteLine("[shim] Failed to start " + psi.FileName);
                return 2;
            }

            using (process)
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("[shim] " + ex.Message);
            return 1;
        }
    }

    private static Dictionary<string, string> Load(string path)
    {
        Dictionary<string, string> map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string raw in File.ReadAllLines(path))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line[0] == '#' || line[0] == ';')
            {
                continue;
            }
            int eq = line.IndexOf('=');
            if (eq <= 0)
            {
                continue;
            }
            map[line.Substring(0, eq).Trim().ToLowerInvariant()] = line.Substring(eq + 1).Trim();
        }
        return map;
    }

    private static string PyQuote(string value)
    {
        return "'" + value.Replace("\\", "\\\\").Replace("'", "\\'") + "'";
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
