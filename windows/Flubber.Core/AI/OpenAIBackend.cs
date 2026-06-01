using System.Text.Json;
using Flubber.Core.Tools;
using Flubber.Core.Util;

namespace Flubber.Core.AI;

/// <summary>OpenAI (ChatGPT) and DeepSeek — OpenAI Chat Completions format. Port of OpenAIBackend.swift.</summary>
public sealed class OpenAIBackend : IAIBackend
{
    public AIConfig Config { get; set; }
    public OpenAIBackend(AIConfig config) { Config = config; }

    private bool IsOpenAI => Config.Provider == "openai";
    private bool IsOpenRouter => Config.Provider == "openrouter";
    private bool IsKilo => Config.Provider == "kilo";
    private string Base => Config.Provider switch
    {
        "openai" => "https://api.openai.com/v1",
        "openrouter" => "https://openrouter.ai/api/v1",
        "kilo" => "https://api.kilo.ai/api/gateway",
        _ => "https://api.deepseek.com",   // deepseek
    };
    private string Key => Config.Provider switch
    {
        "openai" => Config.OpenaiKeyValue,
        "openrouter" => Config.OpenrouterKeyValue,
        "kilo" => Config.KiloKeyValue,   // may be empty → anonymous
        _ => Config.DeepseekKeyValue,
    };
    private string Model => Config.Provider switch
    {
        "openai" => Config.OpenaiModelValue,
        "openrouter" => Config.OpenrouterModelValue,
        "kilo" => Config.KiloModelValue,
        _ => Config.DeepseekModelValue,
    };
    private string Name => Config.Provider switch
    {
        "openai" => "OpenAI",
        "openrouter" => "OpenRouter",
        "kilo" => "Kilo",
        _ => "DeepSeek",
    };
    private string ChatURL => Base + "/chat/completions";
    // Kilo's free tier works anonymously (no key); the others require one.
    public bool IsConfigured => IsKilo || !string.IsNullOrWhiteSpace(Key);
    // OpenAI deprecated max_tokens → max_completion_tokens; DeepSeek/OpenRouter/Kilo use the standard max_tokens.
    private string TokenParam => IsOpenAI ? "max_completion_tokens" : "max_tokens";

    private IEnumerable<(string, string)> Headers()
    {
        var h = new List<(string, string)>();
        if (!string.IsNullOrWhiteSpace(Key)) h.Add(("Authorization", "Bearer " + Key));   // Kilo anonymous has no key
        if (IsOpenRouter)
        {
            // Optional headers so the app is identified on OpenRouter's leaderboard.
            h.Add(("HTTP-Referer", "https://github.com/lordmacu/SlimePet"));
            h.Add(("X-Title", "Flubber"));
        }
        return h;
    }

    private List<object> OaiMessages(IReadOnlyList<AIMessage> messages)
    {
        var msgs = new List<object>();
        foreach (var m in messages)
        {
            if (m.Role == "assistant" && m.ToolCalls.Count > 0)
                msgs.Add(new Dictionary<string, object?>
                {
                    ["role"] = "assistant", ["content"] = m.Content,
                    ["tool_calls"] = m.ToolCalls.Select(tc => (object)new Dictionary<string, object?>
                    {
                        ["id"] = tc.Id, ["type"] = "function",
                        ["function"] = new Dictionary<string, object?> { ["name"] = tc.Name, ["arguments"] = tc.Arguments },
                    }).ToList(),
                });
            else if (m.Role == "tool")
                msgs.Add(new Dictionary<string, object?> { ["role"] = "tool", ["tool_call_id"] = m.ToolCallId ?? "", ["content"] = m.Content });
            else if (m.Role == "user" && m.ImageBase64 is { } img)
                msgs.Add(new Dictionary<string, object?>
                {
                    ["role"] = "user",
                    ["content"] = new List<object>
                    {
                        new Dictionary<string, object?> { ["type"] = "text", ["text"] = m.Content },
                        new Dictionary<string, object?> { ["type"] = "image_url", ["image_url"] = new Dictionary<string, object?> { ["url"] = $"data:image/jpeg;base64,{img}" } },
                    },
                });
            else
                msgs.Add(new Dictionary<string, object?> { ["role"] = m.Role, ["content"] = m.Content });
        }
        return msgs;
    }

    private Dictionary<string, object?> Body(IReadOnlyList<AIMessage> messages, IReadOnlyList<ToolDef>? tools, int maxTokens, bool stream)
    {
        var b = new Dictionary<string, object?>
        {
            ["model"] = Model, ["messages"] = OaiMessages(messages), [TokenParam] = maxTokens, ["temperature"] = 0.3,
        };
        if (stream) b["stream"] = true;
        if (tools is { Count: > 0 })
        {
            b["tools"] = tools.Select(t => (object)new Dictionary<string, object?>
            {
                ["type"] = "function",
                ["function"] = new Dictionary<string, object?> { ["name"] = t.Name, ["description"] = t.Description, ["parameters"] = t.Parameters },
            }).ToList();
            b["tool_choice"] = "auto";
        }
        return b;
    }

    private async Task<string?> PostAsync(object body, TimeSpan timeout)
    {
        if (!IsConfigured) return null;
        Log.Write($"→ {Name} POST {ChatURL} model={Model}");
        var (status, text) = await Http.PostAsync(ChatURL, Headers(), body, timeout).ConfigureAwait(false);
        Log.Write($"← {Name} HTTP {status} {Trunc(text, 300)}");
        return status == -1 ? null : text;
    }

    public async Task<string?> ChatAsync(string system, IReadOnlyList<(string Role, string Content)> history, string? user, int maxTokens)
    {
        var msgs = new List<object> { new Dictionary<string, object?> { ["role"] = "system", ["content"] = system } };
        foreach (var (r, c) in history) msgs.Add(new Dictionary<string, object?> { ["role"] = r, ["content"] = c });
        if (user != null) msgs.Add(new Dictionary<string, object?> { ["role"] = "user", ["content"] = user });
        var body = new Dictionary<string, object?> { ["model"] = Model, ["messages"] = msgs, [TokenParam] = maxTokens, ["temperature"] = 1.0 };
        var text = await PostAsync(body, TimeSpan.FromSeconds(20)).ConfigureAwait(false);
        return text == null ? null : ParseText(text);
    }

    public async Task<LLMResult?> CompleteAsync(IReadOnlyList<AIMessage> messages, IReadOnlyList<ToolDef>? tools, int maxTokens)
    {
        var text = await PostAsync(Body(messages, tools, maxTokens, false), TimeSpan.FromSeconds(60)).ConfigureAwait(false);
        return text == null ? null : ParseResult(text);
    }

    public async Task<LLMResult?> CompleteStreamAsync(IReadOnlyList<AIMessage> messages, IReadOnlyList<ToolDef>? tools, int maxTokens, Action<string> onDelta)
    {
        if (!IsConfigured) return null;
        var text = "";
        var toolAcc = new SortedDictionary<int, (string Id, string Name, string Args)>();
        Log.Write($"→ STREAM {Name} model={Model}");
        try
        {
            await Http.StreamPostAsync(ChatURL, Headers(), Body(messages, tools, maxTokens, true), TimeSpan.FromSeconds(120), line =>
            {
                if (line.EndsWith("\r")) line = line[..^1];
                if (!line.StartsWith("data:")) return;
                var payload = line[5..].Trim();
                if (payload == "[DONE]") return;
                if (payload.Length == 0) return;
                JsonElement obj;
                try { obj = JsonDocument.Parse(payload).RootElement; } catch { return; }
                if (!obj.TryGetProperty("choices", out var choices) || choices.ValueKind != JsonValueKind.Array || choices.GetArrayLength() == 0) return;
                var first = choices[0];
                if (!first.TryGetProperty("delta", out var delta)) return;
                if (delta.TryGetProperty("content", out var cEl) && cEl.ValueKind == JsonValueKind.String && cEl.GetString() is { Length: > 0 } c)
                { text += c; onDelta(c); }
                if (delta.TryGetProperty("tool_calls", out var tcs) && tcs.ValueKind == JsonValueKind.Array)
                {
                    foreach (var tc in tcs.EnumerateArray())
                    {
                        var idx = tc.TryGetProperty("index", out var iEl) ? iEl.GetInt32() : 0;
                        if (!toolAcc.ContainsKey(idx)) toolAcc[idx] = ("", "", "");
                        var cur = toolAcc[idx];
                        if (tc.TryGetProperty("id", out var idEl) && idEl.ValueKind == JsonValueKind.String) cur.Id = idEl.GetString() ?? "";
                        if (tc.TryGetProperty("function", out var fn))
                        {
                            if (fn.TryGetProperty("name", out var nEl) && nEl.ValueKind == JsonValueKind.String) cur.Name += nEl.GetString() ?? "";
                            if (fn.TryGetProperty("arguments", out var aEl) && aEl.ValueKind == JsonValueKind.String) cur.Args += aEl.GetString() ?? "";
                        }
                        toolAcc[idx] = cur;
                    }
                }
            }).ConfigureAwait(false);
        }
        catch (Exception e) { Log.Write($"STREAM error {e.Message}"); return null; }

        var calls = toolAcc.Values.Select(v => new ToolCall(v.Id, v.Name, string.IsNullOrEmpty(v.Args) ? "{}" : v.Args)).ToList();
        return new LLMResult(text.Length == 0 ? null : text, calls);
    }

    public async Task<string?> VisionAsync(string prompt, string imageBase64)
    {
        if (!IsConfigured || !(IsOpenAI || IsOpenRouter || IsKilo)) return null;   // DeepSeek has no vision; OpenRouter/Kilo depend on the model
        var body = new Dictionary<string, object?>
        {
            ["model"] = Model, [TokenParam] = 1024, ["temperature"] = 0.2,
            ["messages"] = new List<object> { new Dictionary<string, object?>
            {
                ["role"] = "user",
                ["content"] = new List<object>
                {
                    new Dictionary<string, object?> { ["type"] = "text", ["text"] = prompt },
                    new Dictionary<string, object?> { ["type"] = "image_url", ["image_url"] = new Dictionary<string, object?> { ["url"] = $"data:image/jpeg;base64,{imageBase64}" } },
                },
            } },
        };
        var text = await PostAsync(body, TimeSpan.FromSeconds(60)).ConfigureAwait(false);
        return text == null ? null : ParseText(text);
    }

    public Task<string> WebSearchAsync(string query) => WebTools.SearchAsync(query);

    public async Task<(bool Ok, string Message)> TestAsync()
    {
        if (!IsConfigured) return (false, "Falta la clave.");
        var body = new Dictionary<string, object?>
        {
            ["model"] = Model, ["messages"] = new List<object> { new Dictionary<string, object?> { ["role"] = "user", ["content"] = "ping" } }, [TokenParam] = 8,
        };
        var (status, text) = await Http.PostAsync(ChatURL, Headers(), body, TimeSpan.FromSeconds(20)).ConfigureAwait(false);
        if (status == -1) return (false, "Red: error.");
        var snip = Trunc(text, 220);
        if (status == 200 && ParseText(text) is { Length: > 0 } t) return (true, $"Conexión exitosa ✅ ({t})");
        return (false, $"HTTP {status}: {snip}");
    }

    public static string? ParseText(string body)
    {
        try
        {
            var root = JsonDocument.Parse(body).RootElement;
            if (root.TryGetProperty("choices", out var ch) && ch.ValueKind == JsonValueKind.Array && ch.GetArrayLength() > 0)
            {
                var f = ch[0];
                if (f.TryGetProperty("message", out var msg) && msg.TryGetProperty("content", out var c) && c.ValueKind == JsonValueKind.String)
                    return (c.GetString() ?? "").Trim();
            }
        }
        catch { /* ignore */ }
        return null;
    }

    public static LLMResult? ParseResult(string body)
    {
        try
        {
            var root = JsonDocument.Parse(body).RootElement;
            if (!root.TryGetProperty("choices", out var ch) || ch.ValueKind != JsonValueKind.Array || ch.GetArrayLength() == 0) return null;
            var msg = ch[0].TryGetProperty("message", out var m) ? m : default;
            if (msg.ValueKind != JsonValueKind.Object) return null;
            var calls = new List<ToolCall>();
            if (msg.TryGetProperty("tool_calls", out var tcs) && tcs.ValueKind == JsonValueKind.Array)
            {
                foreach (var tc in tcs.EnumerateArray())
                {
                    if (!tc.TryGetProperty("function", out var fn)) continue;
                    calls.Add(new ToolCall(
                        tc.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? "" : "",
                        fn.TryGetProperty("name", out var nEl) ? nEl.GetString() ?? "" : "",
                        fn.TryGetProperty("arguments", out var aEl) ? aEl.GetString() ?? "{}" : "{}"));
                }
            }
            var content = msg.TryGetProperty("content", out var cEl) && cEl.ValueKind == JsonValueKind.String ? cEl.GetString() : null;
            return new LLMResult(content, calls);
        }
        catch { return null; }
    }

    private static string Trunc(string s, int n) => s.Length <= n ? s : s[..n];
}
