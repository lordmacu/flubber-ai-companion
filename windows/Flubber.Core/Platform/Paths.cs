namespace Flubber.Core.Platform;

/// <summary>
/// User data paths. On macOS it was ~/Library/Application Support/SlimePet;
/// on Windows we use %APPDATA%\SlimePet (Roaming).
/// </summary>
public static class Paths
{
    public static string AppDataDir
    {
        get
        {
            var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var dir = Path.Combine(baseDir, "SlimePet");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string File(string name) => Path.Combine(AppDataDir, name);

    public static string SubDir(string name)
    {
        var dir = Path.Combine(AppDataDir, name);
        Directory.CreateDirectory(dir);
        return dir;
    }

    public static string StateJson => File("state.json");
    public static string ConfigJson => File("config.json");
    public static string ConversationsJson => File("conversations.json");
    public static string LogFile => File("slimepet.log");
    public static string ShotsDir => SubDir("shots");
}
