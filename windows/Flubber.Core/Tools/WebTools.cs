using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using Flubber.Core.AI;

namespace Flubber.Core.Tools;

/// <summary>Herramientas de red portables (DuckDuckGo / fetch / clima). Puerto de WebTools.swift.</summary>
public static class WebTools
{
    private const string Ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";

    private static Task<string?> GetAsync(string url) => Http.GetAsync(url, Ua, TimeSpan.FromSeconds(20));

    public static async Task<string> SearchAsync(string query)
    {
        var q = Uri.EscapeDataString(query);
        var html = await GetAsync($"https://html.duckduckgo.com/html/?q={q}").ConfigureAwait(false);
        if (html == null) return "No pude buscar (sin conexión).";
        var titles = Matches(html, "class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>");
        var snippets = Matches(html, "class=\"result__snippet\"[^>]*>(.*?)</a>");
        if (titles.Count == 0) return "No encontré resultados.";
        var sb = new StringBuilder();
        for (var i = 0; i < Math.Min(5, titles.Count); i++)
        {
            var title = Strip(titles[i].Count > 1 ? titles[i][1] : "");
            var url = DecodeDdg(titles[i].Count > 0 ? titles[i][0] : "");
            var snip = i < snippets.Count ? Strip(snippets[i].Count > 0 ? snippets[i][0] : "") : "";
            sb.Append($"{i + 1}. {title}\n   {snip}\n   {url}\n");
        }
        return sb.ToString();
    }

    public static async Task<string> FetchAsync(string url)
    {
        var html = await GetAsync(url).ConfigureAwait(false);
        if (html == null) return "No pude leer la página.";
        var text = Strip(html);
        if (text.Length > 3000) text = text[..3000] + "…(recortado)";
        return text;
    }

    public static async Task<string> WeatherAsync(string place)
    {
        var p = Uri.EscapeDataString(place);
        var line = await GetAsync($"https://wttr.in/{p}?format=3&lang=es").ConfigureAwait(false);
        return line?.Trim() ?? "No pude consultar el clima.";
    }

    // --- utilidades de parseo ---
    private static List<List<string>> Matches(string text, string pattern)
    {
        var re = new Regex(pattern, RegexOptions.Singleline | RegexOptions.IgnoreCase);
        var result = new List<List<string>>();
        foreach (Match m in re.Matches(text))
        {
            var groups = new List<string>();
            for (var i = 1; i < m.Groups.Count; i++) groups.Add(m.Groups[i].Success ? m.Groups[i].Value : "");
            result.Add(groups);
        }
        return result;
    }

    public static string Strip(string s)
    {
        var t = Regex.Replace(s, "<script[^>]*>.*?</script>", " ", RegexOptions.Singleline | RegexOptions.IgnoreCase);
        t = Regex.Replace(t, "<style[^>]*>.*?</style>", " ", RegexOptions.Singleline | RegexOptions.IgnoreCase);
        t = Regex.Replace(t, "<[^>]+>", " ");
        t = HttpUtility.HtmlDecode(t);
        t = Regex.Replace(t, "\\s+", " ");
        return t.Trim();
    }

    private static string DecodeDdg(string href)
    {
        // //duckduckgo.com/l/?uddg=<url-encoded>&...
        var idx = href.IndexOf("uddg=", StringComparison.Ordinal);
        if (idx >= 0)
        {
            var after = href[(idx + 5)..];
            var enc = after.Split('&')[0];
            return Uri.UnescapeDataString(enc);
        }
        return href.StartsWith("//") ? "https:" + href : href;
    }
}
