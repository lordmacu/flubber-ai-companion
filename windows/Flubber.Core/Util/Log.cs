using Flubber.Core.Platform;

namespace Flubber.Core.Util;

/// <summary>Log a archivo (%APPDATA%\SlimePet\slimepet.log) + stderr.</summary>
public static class Log
{
    private static readonly object Gate = new();

    public static void Write(string s)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {s}\n";
        try { Console.Error.Write(line); } catch { /* ignore */ }
        lock (Gate)
        {
            try { System.IO.File.AppendAllText(Paths.LogFile, line); } catch { /* ignore */ }
        }
    }
}
