using System.Text.Json;
using System.Text.Json.Serialization;
using Flubber.Core.Platform;

namespace Flubber.Core.AI;

/// <summary>
/// Configuración de IA + ajustes no sensibles. Puerto de AIConfig (MiniMax.swift).
/// En Windows la clave se guarda en config.json (en macOS estaba en Keychain).
/// </summary>
public sealed class AIConfig
{
    public string Provider { get; set; } = "minimax";   // "minimax" | "claude" | "openai" | "deepseek"

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

    public string? Lang { get; set; }   // null=sistema, "es", "en"

    // "permitir siempre" por categoría
    public bool? AllowBrowser { get; set; }
    public bool? AllowCommand { get; set; }
    public bool? AllowOpen { get; set; }

    // Ocultar la ventana en capturas/grabaciones (habilitado por defecto).
    public bool? HideFromCapture { get; set; }

    public SkinSpec? CustomSkin { get; set; }

    [JsonIgnore] public bool HideFromCaptureValue => HideFromCapture ?? true;

    [JsonIgnore] public string ClaudeKeyValue => ClaudeKey ?? "";
    [JsonIgnore] public string ClaudeModelValue => !string.IsNullOrEmpty(ClaudeModel) ? ClaudeModel! : "claude-haiku-4-5-20251001";
    [JsonIgnore] public string OpenaiKeyValue => OpenaiKey ?? "";
    [JsonIgnore] public string OpenaiModelValue => !string.IsNullOrEmpty(OpenaiModel) ? OpenaiModel! : "gpt-4o";
    [JsonIgnore] public string DeepseekKeyValue => DeepseekKey ?? "";
    [JsonIgnore] public string DeepseekModelValue => !string.IsNullOrEmpty(DeepseekModel) ? DeepseekModel! : "deepseek-chat";

    [JsonIgnore]
    public bool IsConfigured
    {
        get
        {
            var k = Provider switch
            {
                "claude" => ClaudeKeyValue,
                "openai" => OpenaiKeyValue,
                "deepseek" => DeepseekKeyValue,
                _ => ApiKey,
            };
            return !string.IsNullOrWhiteSpace(k);
        }
    }

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    public static AIConfig Load()
    {
        try
        {
            if (System.IO.File.Exists(Paths.ConfigJson))
            {
                var json = System.IO.File.ReadAllText(Paths.ConfigJson);
                var c = JsonSerializer.Deserialize<AIConfig>(json);
                if (c != null) return c;
            }
        }
        catch { /* ignore */ }
        return new AIConfig();
    }

    public void Save()
    {
        try { System.IO.File.WriteAllText(Paths.ConfigJson, JsonSerializer.Serialize(this, JsonOpts)); }
        catch { /* ignore */ }
    }
}
