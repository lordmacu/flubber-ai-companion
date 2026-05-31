using System.Text.Json;
using Flubber.Core.Tools;
using Flubber.Core.Util;

namespace Flubber.Core.AI;

/// <summary>Claude / Anthropic Messages API (and MiniMax, which is compatible). Port of AnthropicBackend.swift.</summary>
public sealed class AnthropicBackend : IAIBackend
{
    public AIConfig Config { get; set; }
    public AnthropicBackend(AIConfig config) { Config = config; }

    private bool IsClaude => Config.Provider == "claude";
    private string Endpoint => IsClaude
        ? "https://api.anthropic.com/v1/messages"
        : "https://api.minimax.io/anthropic/v1/messages";
    private string Key => IsClaude ? Config.ClaudeKeyValue : Config.ApiKey;
    private string Model => IsClaude ? Config.ClaudeModelValue : Config.Model;
    public bool IsConfigured => !string.IsNullOrWhiteSpace(Key);

    private IEnumerable<(string, string)> Headers() => new (string, string)[]
    {
        ("x-api-key", Key),
        ("Authorization", "Bearer " + Key),
        ("anthropic-version", "2023-06-01"),
    };

    private async Task<string?> PostAsync(object body, TimeSpan timeout)
    {
        if (!IsConfigured) { Log.Write($"post: no key (provider={Config.Provider})"); return null; }
        Log.Write($"→ {(IsClaude ? "Claude" : "MiniMax")} POST {Endpoint} model={Model} keyLen={Key.Length}");
        var (status, text) = await Http.PostAsync(Endpoint, Headers(), body, timeout).ConfigureAwait(false);
        Log.Write($"← HTTP {status} {Trunc(text, 400)}");
        return status >= 200 && status < 300 ? text : (status == -1 ? null : text);
    }

    public async Task<string?> ChatAsync(string system, IReadOnlyList<(string Role, string Content)> history, string? user, int maxTokens)
    {
        var msgs = new List<object>();
        foreach (var (r, c) in history) msgs.Add(new Dictionary<string, object?> { ["role"] = r == "assistant" ? "assistant" : "user", ["content"] = c });
        if (user != null) msgs.Add(new Dictionary<string, object?> { ["role"] = "user", ["content"] = user });
        if (msgs.Count == 0) msgs.Add(new Dictionary<string, object?> { ["role"] = "user", ["content"] = " " });
        var body = new Dictionary<string, object?> { ["model"] = Model, ["max_tokens"] = maxTokens, ["system"] = system, ["messages"] = msgs };
        var text = await PostAsync(body, TimeSpan.FromSeconds(20)).ConfigureAwait(false);
        return text == null ? null : Parse(text).Content;
    }

    private Dictionary<string, object?> AnthropicBody(IReadOnlyList<AIMessage> messages, IReadOnlyList<ToolDef>? tools, int maxTokens, bool stream)
    {
        var system = "";
        var msgs = new List<object>();
        var pending = new List<object>();
        void Flush() { if (pending.Count > 0) { msgs.Add(new Dictionary<string, object?> { ["role"] = "user", ["content"] = new List<object>(pending) }); pending.Clear(); } }

        foreach (var m in messages)
        {
            switch (m.Role)
            {
                case "system":
                    system += (system.Length == 0 ? "" : "\n") + m.Content;
                    break;
                case "tool":
                    pending.Add(new Dictionary<string, object?> { ["type"] = "tool_result", ["tool_use_id"] = m.ToolCallId ?? "", ["content"] = m.Content });
                    break;
                case "assistant":
                    Flush();
                    var blocks = new List<object>();
                    if (m.Content.Length > 0) blocks.Add(new Dictionary<string, object?> { ["type"] = "text", ["text"] = m.Content });
                    foreach (var tc in m.ToolCalls)
                        blocks.Add(new Dictionary<string, object?> { ["type"] = "tool_use", ["id"] = tc.Id, ["name"] = tc.Name, ["input"] = Json.ParseObject(tc.Arguments) });
                    msgs.Add(new Dictionary<string, object?> { ["role"] = "assistant", ["content"] = blocks.Count == 0 ? new List<object> { new Dictionary<string, object?> { ["type"] = "text", ["text"] = " " } } : blocks });
                    break;
                default:
                    Flush();
                    if (m.ImageBase64 is { } img)
                        msgs.Add(new Dictionary<string, object?>
                        {
                            ["role"] = "user",
                            ["content"] = new List<object>
                            {
                                new Dictionary<string, object?> { ["type"] = "text", ["text"] = m.Content },
                                new Dictionary<string, object?> { ["type"] = "image", ["source"] = new Dictionary<string, object?> { ["type"] = "base64", ["media_type"] = "image/jpeg", ["data"] = img } },
                            },
                        });
                    else
                        msgs.Add(new Dictionary<string, object?> { ["role"] = "user", ["content"] = m.Content });
                    break;
            }
        }
        Flush();

        var body = new Dictionary<string, object?> { ["model"] = Model, ["max_tokens"] = maxTokens, ["system"] = system, ["messages"] = msgs, ["temperature"] = 0.3 };
        if (stream) body["stream"] = true;
        if (tools is { Count: > 0 })
            body["tools"] = tools.Select(t => new Dictionary<string, object?> { ["name"] = t.Name, ["description"] = t.Description, ["input_schema"] = t.Parameters }).ToList<object>();
        return body;
    }

    public async Task<LLMResult?> CompleteAsync(IReadOnlyList<AIMessage> messages, IReadOnlyList<ToolDef>? tools, int maxTokens)
    {
        var text = await PostAsync(AnthropicBody(messages, tools, maxTokens, false), TimeSpan.FromSeconds(60)).ConfigureAwait(false);
        return text == null ? null : Parse(text);
    }

    public async Task<LLMResult?> CompleteStreamAsync(IReadOnlyList<AIMessage> messages, IReadOnlyList<ToolDef>? tools, int maxTokens, Action<string> onDelta)
    {
        if (!IsConfigured) return null;
        var text = "";
        var toolAcc = new SortedDictionary<int, (string Id, string Name, string Json)>();
        Log.Write($"→ STREAM {(IsClaude ? "Claude" : "MiniMax")} model={Model}");
        try
        {
            await Http.StreamPostAsync(Endpoint, Headers(), AnthropicBody(messages, tools, maxTokens, true), TimeSpan.FromSeconds(120), line =>
            {
                if (line.EndsWith("\r")) line = line[..^1];
                if (!line.StartsWith("data:")) return;
                var payload = line[5..].Trim();
                if (payload.Length == 0) return;
                JsonElement obj;
                try { obj = JsonDocument.Parse(payload).RootElement; } catch { return; }
                if (!obj.TryGetProperty("type", out var typeEl)) return;
                switch (typeEl.GetString())
                {
                    case "content_block_start":
                        if (obj.TryGetProperty("index", out var iEl) && obj.TryGetProperty("content_block", out var cb)
                            && cb.TryGetProperty("type", out var cbt) && cbt.GetString() == "tool_use")
                        {
                            var idx = iEl.GetInt32();
                            toolAcc[idx] = (
                                cb.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? "" : "",
                                cb.TryGetProperty("name", out var nEl) ? nEl.GetString() ?? "" : "",
                                "");
                        }
                        break;
                    case "content_block_delta":
                        if (obj.TryGetProperty("delta", out var delta))
                        {
                            if (delta.TryGetProperty("text", out var tEl) && tEl.ValueKind == JsonValueKind.String)
                            { var t = tEl.GetString() ?? ""; text += t; onDelta(t); }
                            else if (delta.TryGetProperty("partial_json", out var pj) && obj.TryGetProperty("index", out var iEl2))
                            {
                                var idx = iEl2.GetInt32();
                                if (toolAcc.TryGetValue(idx, out var cur))
                                    toolAcc[idx] = (cur.Id, cur.Name, cur.Json + (pj.GetString() ?? ""));
                            }
                        }
                        break;
                }
            }).ConfigureAwait(false);
        }
        catch (Exception e) { Log.Write($"STREAM error {e.Message}"); return null; }

        var calls = toolAcc.Values.Select(v => new ToolCall(v.Id, v.Name, string.IsNullOrEmpty(v.Json) ? "{}" : v.Json)).ToList();
        return new LLMResult(text.Length == 0 ? null : text, calls);
    }

    public async Task<string?> VisionAsync(string prompt, string imageBase64)
    {
        if (!IsConfigured) return null;
        if (IsClaude)
        {
            var body = new Dictionary<string, object?>
            {
                ["model"] = Model, ["max_tokens"] = 1024, ["temperature"] = 0.2,
                ["messages"] = new List<object> { new Dictionary<string, object?>
                {
                    ["role"] = "user",
                    ["content"] = new List<object>
                    {
                        new Dictionary<string, object?> { ["type"] = "text", ["text"] = prompt },
                        new Dictionary<string, object?> { ["type"] = "image", ["source"] = new Dictionary<string, object?> { ["type"] = "base64", ["media_type"] = "image/jpeg", ["data"] = imageBase64 } },
                    },
                } },
            };
            var text = await PostAsync(body, TimeSpan.FromSeconds(60)).ConfigureAwait(false);
            return text == null ? null : Parse(text).Content;
        }
        // MiniMax VLM
        var (status, resp) = await Http.PostAsync("https://api.minimax.io/v1/coding_plan/vlm",
            new (string, string)[] { ("Authorization", "Bearer " + Key) },
            new Dictionary<string, object?> { ["prompt"] = prompt, ["image_url"] = $"data:image/jpeg;base64,{imageBase64}" },
            TimeSpan.FromSeconds(60)).ConfigureAwait(false);
        Log.Write($"← VLM HTTP {status} {Trunc(resp, 300)}");
        try
        {
            var root = JsonDocument.Parse(resp).RootElement;
            if (root.TryGetProperty("content", out var c) && c.GetString() is { Length: > 0 } s) return s;
        }
        catch { /* ignore */ }
        return null;
    }

    public async Task<string> WebSearchAsync(string query)
    {
        if (IsClaude) return await WebTools.SearchAsync(query).ConfigureAwait(false);
        if (!IsConfigured) return await WebTools.SearchAsync(query).ConfigureAwait(false);
        Log.Write($"→ MiniMax SEARCH q={query}");
        var (status, resp) = await Http.PostAsync("https://api.minimax.io/v1/coding_plan/search",
            new (string, string)[] { ("Authorization", "Bearer " + Key) },
            new Dictionary<string, object?> { ["q"] = query }, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
        Log.Write($"← SEARCH HTTP {status} {Trunc(resp, 160)}");
        try
        {
            var root = JsonDocument.Parse(resp).RootElement;
            if (root.TryGetProperty("organic", out var organic) && organic.ValueKind == JsonValueKind.Array && organic.GetArrayLength() > 0)
            {
                var sb = new System.Text.StringBuilder();
                var i = 0;
                foreach (var r in organic.EnumerateArray().Take(6))
                {
                    i++;
                    sb.Append($"{i}. {Str(r, "title")}\n   {Str(r, "snippet")}\n   {Str(r, "link")}\n");
                }
                return sb.ToString();
            }
        }
        catch { /* ignore */ }
        return await WebTools.SearchAsync(query).ConfigureAwait(false);
    }

    public async Task<(bool Ok, string Message)> TestAsync()
    {
        if (!IsConfigured) return (false, "Falta la clave del proveedor.");
        var body = new Dictionary<string, object?>
        {
            ["model"] = Model, ["max_tokens"] = 1024, ["system"] = "Responde solo: ok",
            ["messages"] = new List<object> { new Dictionary<string, object?> { ["role"] = "user", ["content"] = "ping" } },
        };
        Log.Write($"TEST → {(IsClaude ? "Claude" : "MiniMax")} {Endpoint} model={Model} keyLen={Key.Length}");
        var (status, text) = await Http.PostAsync(Endpoint, Headers(), body, TimeSpan.FromSeconds(20)).ConfigureAwait(false);
        if (status == -1) return (false, "Error de red.");
        var snip = Trunc(text, 220);
        Log.Write($"TEST ← HTTP {status} {snip}");
        if (status == 200)
        {
            var t = Parse(text).Content ?? "";
            return (t.Length > 0, t.Length == 0 ? $"HTTP 200 pero sin texto. {snip}" : $"Conexión exitosa ✅ ({t})");
        }
        return (false, $"HTTP {status} en {Endpoint}\n{snip}");
    }

    public static LLMResult Parse(string body)
    {
        try
        {
            var root = JsonDocument.Parse(body).RootElement;
            if (!root.TryGetProperty("content", out var blocks) || blocks.ValueKind != JsonValueKind.Array)
                return new LLMResult(null, Array.Empty<ToolCall>());
            var text = "";
            var calls = new List<ToolCall>();
            foreach (var b in blocks.EnumerateArray())
            {
                var type = b.TryGetProperty("type", out var tEl) ? tEl.GetString() : null;
                if (type == "text") text += b.TryGetProperty("text", out var txt) ? txt.GetString() ?? "" : "";
                else if (type == "tool_use")
                {
                    var input = b.TryGetProperty("input", out var inp) ? inp.GetRawText() : "{}";
                    calls.Add(new ToolCall(
                        b.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? "" : "",
                        b.TryGetProperty("name", out var nEl) ? nEl.GetString() ?? "" : "",
                        input));
                }
            }
            var t = text.Trim();
            return new LLMResult(t.Length == 0 ? null : t, calls);
        }
        catch { return new LLMResult(null, Array.Empty<ToolCall>()); }
    }

    private static string Str(JsonElement e, string key) => e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";
    private static string Trunc(string s, int n) => s.Length <= n ? s : s[..n];
}
