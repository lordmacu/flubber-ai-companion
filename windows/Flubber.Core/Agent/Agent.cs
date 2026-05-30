using System.Globalization;
using System.Text.Json;
using Flubber.Core.AI;
using Flubber.Core.Tools;

namespace Flubber.Core.Agent;

/// <summary>
/// El slime como AGENTE: bucle de function-calling + despacho de herramientas.
/// Puerto de Agent.swift. Las herramientas del SO van por <see cref="IPlatformBridge"/>.
/// </summary>
public sealed class Agent
{
    private readonly IAIBackend _client;
    private readonly IPlatformBridge _platform;
    private readonly List<AIMessage> _messages = new();
    private const int MaxIterations = 6;

    private Action<string> _onStep = _ => { };
    private Action<string> _onToken = _ => { };

    public Agent(IAIBackend client, IPlatformBridge platform)
    {
        _client = client;
        _platform = platform;
    }

    // MARK: permisos
    private bool Allowed(string cat) => cat switch
    {
        "browser" => _client.Config.AllowBrowser == true,
        "command" => _client.Config.AllowCommand == true,
        "open" => _client.Config.AllowOpen == true,
        _ => false,
    };
    private void SetAllowed(string cat)
    {
        switch (cat)
        {
            case "browser": _client.Config.AllowBrowser = true; break;
            case "command": _client.Config.AllowCommand = true; break;
            case "open": _client.Config.AllowOpen = true; break;
        }
        _client.Config.Save();
    }

    // MARK: bucle
    public async Task<string> RunAsync(string userText, string? image, Action<string> onStep, Action<string>? onToken = null)
    {
        _onStep = onStep;
        _onToken = onToken ?? (_ => { });
        var sys = Personality.AgentSystem(_platform.Stats);
        if (_messages.Count == 0) _messages.Add(new AIMessage("system", sys));
        else _messages[0] = new AIMessage("system", sys);   // refresca estado
        _messages.Add(new AIMessage { Role = "user", Content = userText, ImageBase64 = image });

        for (var iter = 1; iter <= MaxIterations; iter++)
        {
            var result = await _client.CompleteStreamAsync(_messages, AgentTools.All, 2000, chunk => _onToken(chunk)).ConfigureAwait(false);
            if (result == null) return "Uy, no pude responder 😵‍💫";

            if (result.ToolCalls.Count == 0)
            {
                var text = CleanFinal(result.Content ?? "");
                _messages.Add(new AIMessage("assistant", result.Content ?? text));
                return text.Length == 0 ? "🟢" : text;
            }

            _messages.Add(new AIMessage { Role = "assistant", Content = result.Content ?? "", ToolCalls = result.ToolCalls.ToList() });
            foreach (var call in result.ToolCalls)
            {
                _onStep(StepLabel(call));
                var toolResult = await ExecuteAsync(call).ConfigureAwait(false);
                _messages.Add(new AIMessage { Role = "tool", Content = toolResult, ToolCallId = call.Id });
            }
        }
        return "Uff, me enredé demasiado 😵 ¿lo intentamos de otra forma?";
    }

    // MARK: despacho de herramientas
    private async Task<string> ExecuteAsync(ToolCall call)
    {
        var args = new ToolArgs(call.Arguments);
        switch (call.Name)
        {
            case "buscar_web": return await _client.WebSearchAsync(args.Str("query")).ConfigureAwait(false);
            case "leer_pagina": return await WebTools.FetchAsync(args.Str("url")).ConfigureAwait(false);
            case "clima": return await WebTools.WeatherAsync(args.Str("lugar")).ConfigureAwait(false);
            case "fecha_hora": return Datetime();
            case "ver_pantalla":
            {
                var q = args.Str("pregunta");
                if (string.IsNullOrEmpty(q)) q = "Describe qué se ve en esta pantalla.";
                var appHint = args.Str("app");
                var (b64, path) = await _platform.CaptureScreenAsync(string.IsNullOrEmpty(appHint) ? null : appHint).ConfigureAwait(false);
                if (path != null) _platform.AttachShot(path);
                if (b64 == null) return "No pude ver la pantalla: revisa el permiso de captura y reinicia la app.";
                var desc = await _client.VisionAsync(q, b64).ConfigureAwait(false);
                return desc ?? "Capturé la pantalla pero no pude analizarla.";
            }
            case "recordatorio":
            {
                var texto = args.Str("texto");
                if (string.IsNullOrEmpty(texto)) texto = "recordatorio";
                var secs = args.Num("segundos") ?? 60;
                _platform.ScheduleReminder(texto, secs);
                return $"Recordatorio puesto en {(int)secs} s: {texto}";
            }
            case "controlar_slime": return _platform.ControlSlime(args.Str("accion"), !string.IsNullOrEmpty(args.Str("tema")) ? args.Str("tema") : args.Str("color"));
            case "navegador_url": return await _platform.BrowserGetUrlAsync().ConfigureAwait(false);
            case "navegador_js":
            {
                var js = args.Str("codigo");
                if (string.IsNullOrEmpty(js)) return "No hay código.";
                return await GateAsync("browser", Loc.T("Ejecutar en el navegador", "Run in the browser"), js,
                    () => _platform.BrowserRunJsAsync(js)).ConfigureAwait(false);
            }
            case "abrir":
            {
                var target = !string.IsNullOrEmpty(args.Str("objetivo")) ? args.Str("objetivo") : args.Str("url");
                if (string.IsNullOrEmpty(target)) return "No me dijiste qué abrir.";
                return await GateAsync("open", Loc.T("Abrir", "Open"), target,
                    () => _platform.OpenTargetAsync(target)).ConfigureAwait(false);
            }
            case "ejecutar_comando":
            {
                var cmd = args.Str("comando");
                if (string.IsNullOrEmpty(cmd)) return "No hay comando.";
                return await GateAsync("command", Loc.T("Ejecutar comando", "Run command"), cmd,
                    () => _platform.RunCommandAsync(cmd)).ConfigureAwait(false);
            }
            default: return "Herramienta desconocida.";
        }
    }

    /// <summary>Pide confirmación salvo que la categoría ya esté en "permitir siempre".</summary>
    private async Task<string> GateAsync(string cat, string title, string detail, Func<Task<string>> proceed)
    {
        if (Allowed(cat)) return await proceed().ConfigureAwait(false);
        var (ok, always) = await _platform.ConfirmAsync(title, detail).ConfigureAwait(false);
        if (always) SetAllowed(cat);
        return ok ? await proceed().ConfigureAwait(false) : Loc.T("El usuario rechazó la acción.", "User rejected the action.");
    }

    // MARK: helpers
    private static string Datetime() =>
        DateTime.Now.ToString("dddd d 'de' MMMM 'de' yyyy, HH:mm", new CultureInfo("es-ES"));

    public static string CleanFinal(string raw)
    {
        var s = raw;
        var idx = s.LastIndexOf("</think>", StringComparison.OrdinalIgnoreCase);
        if (idx >= 0) s = s[(idx + "</think>".Length)..];
        s = s.Replace("<think>", "", StringComparison.OrdinalIgnoreCase).Replace("</think>", "", StringComparison.OrdinalIgnoreCase);
        return s.Trim();
    }

    private static string StepLabel(ToolCall c)
    {
        var a = new ToolArgs(c.Arguments);
        return c.Name switch
        {
            "buscar_web" => Loc.T("🔎 buscando: ", "🔎 searching: ") + a.Str("query"),
            "leer_pagina" => Loc.T("📄 leyendo: ", "📄 reading: ") + a.Str("url"),
            "clima" => Loc.T("🌡️ clima de ", "🌡️ weather in ") + a.Str("lugar"),
            "fecha_hora" => Loc.T("🕐 mirando la hora", "🕐 checking the time"),
            "ver_pantalla" => string.IsNullOrEmpty(a.Str("app"))
                ? Loc.T("👁️ mirando tu pantalla", "👁️ looking at your screen")
                : Loc.T("👁️ mirando ", "👁️ looking at ") + a.Str("app"),
            "recordatorio" => Loc.T("⏰ poniendo un recordatorio", "⏰ setting a reminder"),
            "controlar_slime" => "🎨 " + a.Str("accion"),
            "navegador_url" => Loc.T("🌐 leyendo el navegador", "🌐 reading the browser"),
            "navegador_js" => Loc.T("🌐 controlando el navegador", "🌐 controlling the browser"),
            "abrir" => Loc.T("🔗 quiere abrir ", "🔗 wants to open ") + (!string.IsNullOrEmpty(a.Str("objetivo")) ? a.Str("objetivo") : a.Str("url")),
            "ejecutar_comando" => Loc.T("💻 quiere ejecutar un comando", "💻 wants to run a command"),
            _ => "🔧 " + c.Name,
        };
    }
}

/// <summary>Lectura cómoda de los argumentos JSON de una tool call.</summary>
internal readonly struct ToolArgs
{
    private readonly JsonElement _root;
    private readonly bool _ok;

    public ToolArgs(string json)
    {
        try { _root = JsonDocument.Parse(string.IsNullOrWhiteSpace(json) ? "{}" : json).RootElement; _ok = true; }
        catch { _root = default; _ok = false; }
    }

    public string Str(string key)
    {
        if (!_ok || !_root.TryGetProperty(key, out var v)) return "";
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString() ?? "",
            JsonValueKind.Number => v.ToString(),
            _ => "",
        };
    }

    public double? Num(string key)
    {
        if (!_ok || !_root.TryGetProperty(key, out var v)) return null;
        return v.ValueKind switch
        {
            JsonValueKind.Number => v.GetDouble(),
            JsonValueKind.String when double.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var d) => d,
            _ => null,
        };
    }
}
