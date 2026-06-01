using System.Text.Json;
using System.Text.Json.Serialization;
using Flubber.Core.Platform;

namespace Flubber.Core.AI;

/// <summary>
/// AI configuration + non-sensitive settings. Port of AIConfig (MiniMax.swift).
/// On Windows the key is stored in config.json (on macOS it was in the Keychain).
/// </summary>
public sealed class AIConfig
{
    public string Provider { get; set; } = "kilo";   // "kilo" | "minimax" | "claude" | "openai" | "deepseek" | "openrouter"

    // MiniMax
    public string ApiKey { get; set; } = "";
    public string Model { get; set; } = "MiniMax-M2.5";
    public string BaseURL { get; set; } = "https://api.minimax.io/v1";

    // Claude (Anthropic)
    public string? ClaudeKey { get; set; }
    public string? ClaudeModel { get; set; }

    // OpenAI (ChatGPT)
    public string? OpenaiKey { get; set; }
    public string? OpenaiModel { get; set; }

    // DeepSeek
    public string? DeepseekKey { get; set; }
    public string? DeepseekModel { get; set; }

    // OpenRouter (aggregator — OpenAI-compatible). Free models end in ":free".
    public string? OpenrouterKey { get; set; }
    public string? OpenrouterModel { get; set; }

    // Kilo Gateway (OpenAI-compatible). Free models work anonymously (no key); a key raises the limits.
    public string? KiloKey { get; set; }
    public string? KiloModel { get; set; }

    public string? Lang { get; set; }   // null=system, "es", "en"

    // "always allow" per category
    public bool? AllowBrowser { get; set; }
    public bool? AllowCommand { get; set; }
    public bool? AllowOpen { get; set; }

    // Hide the window from captures/recordings (enabled by default).
    public bool? HideFromCapture { get; set; }

    public SkinSpec? CustomSkin { get; set; }

    [JsonIgnore] public bool HideFromCaptureValue => HideFromCapture ?? true;

    [JsonIgnore] public string ClaudeKeyValue => ClaudeKey ?? "";
    [JsonIgnore] public string ClaudeModelValue => !string.IsNullOrEmpty(ClaudeModel) ? ClaudeModel! : "claude-haiku-4-5-20251001";
    [JsonIgnore] public string OpenaiKeyValue => OpenaiKey ?? "";
    [JsonIgnore] public string OpenaiModelValue => !string.IsNullOrEmpty(OpenaiModel) ? OpenaiModel! : "gpt-4o";
    [JsonIgnore] public string DeepseekKeyValue => DeepseekKey ?? "";
    [JsonIgnore] public string DeepseekModelValue => !string.IsNullOrEmpty(DeepseekModel) ? DeepseekModel! : "deepseek-chat";
    [JsonIgnore] public string OpenrouterKeyValue => OpenrouterKey ?? "";
    [JsonIgnore] public string OpenrouterModelValue => !string.IsNullOrEmpty(OpenrouterModel) ? OpenrouterModel! : "minimax/minimax-m2.5:free";
    [JsonIgnore] public string KiloKeyValue => KiloKey ?? "";
    [JsonIgnore] public string KiloModelValue => !string.IsNullOrEmpty(KiloModel) ? KiloModel! : "poolside/laguna-m.1:free";

    [JsonIgnore]
    public bool IsConfigured
    {
        get
        {
            if (Provider == "kilo") return true;   // Kilo Gateway: free anonymous tier works without a key
            var k = Provider switch
            {
                "claude" => ClaudeKeyValue,
                "openai" => OpenaiKeyValue,
                "deepseek" => DeepseekKeyValue,
                "openrouter" => OpenrouterKeyValue,
                _ => ApiKey,
            };
            return !string.IsNullOrWhiteSpace(k);
        }
    }

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    // Secret encryption hooks (filled in by the Windows layer with DPAPI).
    // If left null (e.g. on CI/non-Windows), the keys are stored in plain text.
    public static Func<string, string>? ProtectFn;
    public static Func<string, string>? UnprotectFn;

    private static string Enc(string s) => string.IsNullOrEmpty(s) ? s : (ProtectFn?.Invoke(s) ?? s);
    private static string? EncN(string? s) => string.IsNullOrEmpty(s) ? s : (ProtectFn?.Invoke(s!) ?? s);
    private static string Dec(string s) => string.IsNullOrEmpty(s) ? s : (UnprotectFn?.Invoke(s) ?? s);
    private static string? DecN(string? s) => string.IsNullOrEmpty(s) ? s : (UnprotectFn?.Invoke(s!) ?? s);

    public static AIConfig Load()
    {
        try
        {
            if (System.IO.File.Exists(Paths.ConfigJson))
            {
                var json = System.IO.File.ReadAllText(Paths.ConfigJson);
                var c = JsonSerializer.Deserialize<AIConfig>(json);
                if (c != null)
                {
                    // decrypt the keys (UnprotectFn returns the plain text if it already was — migration)
                    c.ApiKey = Dec(c.ApiKey);
                    c.ClaudeKey = DecN(c.ClaudeKey);
                    c.OpenaiKey = DecN(c.OpenaiKey);
                    c.DeepseekKey = DecN(c.DeepseekKey);
                    c.OpenrouterKey = DecN(c.OpenrouterKey);
                    c.KiloKey = DecN(c.KiloKey);
                    return c;
                }
            }
        }
        catch { /* ignore */ }
        return new AIConfig();
    }

    public void Save()
    {
        try
        {
            // encrypt the keys in a copy before writing (the in-memory instance stays in plain text)
            var clone = (AIConfig)MemberwiseClone();
            clone.ApiKey = Enc(ApiKey);
            clone.ClaudeKey = EncN(ClaudeKey);
            clone.OpenaiKey = EncN(OpenaiKey);
            clone.DeepseekKey = EncN(DeepseekKey);
            clone.OpenrouterKey = EncN(OpenrouterKey);
            clone.KiloKey = EncN(KiloKey);
            System.IO.File.WriteAllText(Paths.ConfigJson, JsonSerializer.Serialize(clone, JsonOpts));
        }
        catch { /* ignore */ }
    }
}
