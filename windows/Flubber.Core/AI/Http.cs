using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Flubber.Core.Util;

namespace Flubber.Core.AI;

/// <summary>Cliente HTTP compartido + utilidades JSON/SSE para los backends.</summary>
internal static class Http
{
    public static readonly HttpClient Client = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };  // timeout por petición vía CTS
        return c;
    }

    public static StringContent JsonBody(object body) =>
        new(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

    /// <summary>POST simple. Devuelve (status, body). body vacío en error de red.</summary>
    public static async Task<(int Status, string Body)> PostAsync(
        string url, IEnumerable<(string, string)> headers, object body, TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = JsonBody(body) };
            foreach (var (k, v) in headers) req.Headers.TryAddWithoutValidation(k, v);
            using var resp = await Client.SendAsync(req, cts.Token).ConfigureAwait(false);
            var text = await resp.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false);
            return ((int)resp.StatusCode, text);
        }
        catch (Exception e)
        {
            Log.Write($"HTTP error {url}: {e.Message}");
            return (-1, "");
        }
    }

    /// <summary>GET texto (con User-Agent). null en error.</summary>
    public static async Task<string?> GetAsync(string url, string userAgent, TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.UserAgent.ParseAdd(userAgent);
            using var resp = await Client.SendAsync(req, cts.Token).ConfigureAwait(false);
            return await resp.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false);
        }
        catch { return null; }
    }

    /// <summary>POST con respuesta en streaming SSE: invoca onLine por cada línea (sin el \n).</summary>
    public static async Task StreamPostAsync(
        string url, IEnumerable<(string, string)> headers, object body, TimeSpan timeout, Action<string> onLine)
    {
        using var cts = new CancellationTokenSource(timeout);
        using var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = JsonBody(body) };
        foreach (var (k, v) in headers) req.Headers.TryAddWithoutValidation(k, v);
        using var resp = await Client.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token).ConfigureAwait(false);
        await using var stream = await resp.Content.ReadAsStreamAsync(cts.Token).ConfigureAwait(false);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        string? line;
        while ((line = await reader.ReadLineAsync(cts.Token).ConfigureAwait(false)) != null)
            onLine(line);
    }
}

/// <summary>Helpers de serialización (equivalentes a jsonString/jsonObject de Swift).</summary>
internal static class Json
{
    public static string Stringify(object obj)
    {
        try { return JsonSerializer.Serialize(obj); } catch { return "{}"; }
    }

    public static Dictionary<string, object?> ParseObject(string s)
    {
        try
        {
            var doc = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(s);
            if (doc == null) return new();
            return doc.ToDictionary(kv => kv.Key, kv => (object?)kv.Value);
        }
        catch { return new(); }
    }
}
