using System.IO;
using System.Net.Http;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Flubber.Core;
using Flubber.Core.Util;

namespace Flubber.App.Platform;

/// <summary>
/// Control del navegador por Chrome DevTools Protocol (Chrome/Edge/Brave).
/// Reemplazo de los Apple Events de macOS: lee la pestaña activa y ejecuta JS.
/// Requiere que el navegador se haya abierto con --remote-debugging-port=9222.
/// </summary>
public static class BrowserCdp
{
    private const string Base = "http://127.0.0.1:9222";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(4) };

    private static async Task<JsonElement[]?> ListTargetsAsync()
    {
        try
        {
            var s = await Http.GetStringAsync(Base + "/json/list").ConfigureAwait(false);
            return JsonSerializer.Deserialize<JsonElement[]>(s);
        }
        catch { return null; }
    }

    private static JsonElement? ActivePage(JsonElement[] targets)
    {
        foreach (var t in targets)
        {
            if (!t.TryGetProperty("type", out var ty) || ty.GetString() != "page") continue;
            var url = t.TryGetProperty("url", out var u) ? u.GetString() ?? "" : "";
            if (!url.StartsWith("devtools://") && !url.StartsWith("chrome://") && !url.StartsWith("edge://"))
                return t;
        }
        foreach (var t in targets)
            if (t.TryGetProperty("type", out var ty) && ty.GetString() == "page") return t;
        return null;
    }

    public static async Task<string> GetUrlAsync()
    {
        var targets = await ListTargetsAsync().ConfigureAwait(false);
        if (targets == null) return NotAvailable();
        if (ActivePage(targets) is not { } page) return Loc.T("No hay pestaña activa.", "No active tab.");
        var url = page.TryGetProperty("url", out var u) ? u.GetString() ?? "" : "";
        var title = page.TryGetProperty("title", out var t) ? t.GetString() ?? "" : "";
        return $"{url}\n{title}";
    }

    public static async Task<string> RunJsAsync(string js)
    {
        var targets = await ListTargetsAsync().ConfigureAwait(false);
        if (targets == null) return NotAvailable();
        if (ActivePage(targets) is not { } page ||
            !page.TryGetProperty("webSocketDebuggerUrl", out var wsEl) || wsEl.GetString() is not { Length: > 0 } ws)
            return Loc.T("No hay pestaña activa.", "No active tab.");

        try
        {
            using var sock = new ClientWebSocket();
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            await sock.ConnectAsync(new Uri(ws), cts.Token).ConfigureAwait(false);

            var msg = JsonSerializer.Serialize(new
            {
                id = 1,
                method = "Runtime.evaluate",
                @params = new { expression = js, returnByValue = true, awaitPromise = true, userGesture = true },
            });
            await sock.SendAsync(Encoding.UTF8.GetBytes(msg), WebSocketMessageType.Text, true, cts.Token).ConfigureAwait(false);

            var buf = new byte[65536];
            for (var i = 0; i < 30; i++)
            {
                using var ms = new MemoryStream();
                WebSocketReceiveResult r;
                do
                {
                    r = await sock.ReceiveAsync(new ArraySegment<byte>(buf), cts.Token).ConfigureAwait(false);
                    ms.Write(buf, 0, r.Count);
                } while (!r.EndOfMessage);

                var doc = JsonDocument.Parse(Encoding.UTF8.GetString(ms.ToArray())).RootElement;
                if (doc.TryGetProperty("id", out var idEl) && idEl.GetInt32() == 1)
                {
                    try { await sock.CloseAsync(WebSocketCloseStatus.NormalClosure, "", cts.Token).ConfigureAwait(false); } catch { }
                    return ParseEval(doc);
                }
            }
            return Loc.T("Sin respuesta del navegador.", "No response from browser.");
        }
        catch (Exception e)
        {
            Log.Write("cdp error: " + e.Message);
            return NotAvailable();
        }
    }

    private static string ParseEval(JsonElement doc)
    {
        if (doc.TryGetProperty("result", out var res))
        {
            if (res.TryGetProperty("exceptionDetails", out var ex))
                return "JS error: " + (ex.TryGetProperty("text", out var tx) ? tx.GetString() : "error");
            if (res.TryGetProperty("result", out var inner))
            {
                if (inner.TryGetProperty("value", out var val))
                {
                    var s = val.ValueKind == JsonValueKind.String ? val.GetString() ?? "" : val.GetRawText();
                    if (s.Length > 2500) s = s[..2500] + "…";
                    return string.IsNullOrEmpty(s) ? "(hecho)" : s;
                }
                if (inner.TryGetProperty("description", out var d)) return d.GetString() ?? "(hecho)";
            }
        }
        return "(hecho)";
    }

    private static string NotAvailable() => Loc.T(
        "No pude conectar al navegador. Ábrelo con depuración remota: cierra Chrome/Edge/Brave y láncialo con  --remote-debugging-port=9222.",
        "Couldn't connect to the browser. Open it with remote debugging: close Chrome/Edge/Brave and start it with  --remote-debugging-port=9222.");
}
