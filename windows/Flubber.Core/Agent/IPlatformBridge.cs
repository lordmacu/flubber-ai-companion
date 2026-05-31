namespace Flubber.Core.Agent;

/// <summary>
/// Bridge to the Windows layer (UI + native APIs). The (portable) Agent calls
/// these methods for the tools that depend on the OS: screen capture,
/// pet control, browser, open/run, reminders and confirmations.
/// The WPF app implements this interface.
/// </summary>
public interface IPlatformBridge
{
    PetStats Stats { get; }

    /// <summary>Capture. appHint null/"" = full screen; otherwise, tries that app/window.
    /// Returns (jpegBase64, thumbnailPath) or (null, null) if it failed/no permission.</summary>
    Task<(string? Base64, string? Path)> CaptureScreenAsync(string? appHint);

    /// <summary>Shows the capture thumbnail in the chat.</summary>
    void AttachShot(string path);

    /// <summary>Controls the pet: bailar|rodar|pasear|feliz|dormir|color|skin. Returns a message.</summary>
    string ControlSlime(string accion, string tema);

    Task<string> BrowserGetUrlAsync();
    Task<string> BrowserRunJsAsync(string js);

    Task<string> OpenTargetAsync(string target);
    Task<string> RunCommandAsync(string cmd);

    void ScheduleReminder(string text, double seconds);

    /// <summary>Asks the user for confirmation. Returns (approved, "always allow").</summary>
    Task<(bool Ok, bool Always)> ConfirmAsync(string title, string detail);

    // --- Listening / transcription (on Windows: microphone via native dictation) ---
    Task<string> StartMicAsync();        // starts transcribing the microphone
    Task<string> StopMicAsync();         // stops transcribing
    string MeetingTranscript { get; }    // accumulated text (to summarize)
}
