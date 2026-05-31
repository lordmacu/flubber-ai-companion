namespace Flubber.Core.Agent;

/// <summary>
/// Puente hacia la capa de Windows (UI + APIs nativas). El Agent (portable) llama
/// a estos métodos para las herramientas que dependen del SO: captura de pantalla,
/// control de la mascota, navegador, abrir/ejecutar, recordatorios y confirmaciones.
/// La app WPF implementa esta interfaz.
/// </summary>
public interface IPlatformBridge
{
    PetStats Stats { get; }

    /// <summary>Captura. appHint null/"" = pantalla completa; si no, intenta esa app/ventana.
    /// Devuelve (jpegBase64, rutaThumbnail) o (null, null) si falló/sin permiso.</summary>
    Task<(string? Base64, string? Path)> CaptureScreenAsync(string? appHint);

    /// <summary>Muestra el thumbnail de la captura en el chat.</summary>
    void AttachShot(string path);

    /// <summary>Controla la mascota: bailar|rodar|pasear|feliz|dormir|color|skin. Devuelve mensaje.</summary>
    string ControlSlime(string accion, string tema);

    Task<string> BrowserGetUrlAsync();
    Task<string> BrowserRunJsAsync(string js);

    Task<string> OpenTargetAsync(string target);
    Task<string> RunCommandAsync(string cmd);

    void ScheduleReminder(string text, double seconds);

    /// <summary>Pide confirmación al usuario. Devuelve (aprobado, "permitir siempre").</summary>
    Task<(bool Ok, bool Always)> ConfirmAsync(string title, string detail);

    // --- Escucha / transcripción (en Windows: micrófono vía dictado nativo) ---
    Task<string> StartMicAsync();        // empieza a transcribir el micrófono
    Task<string> StopMicAsync();         // deja de transcribir
    string MeetingTranscript { get; }    // texto acumulado (para resumir)
}
