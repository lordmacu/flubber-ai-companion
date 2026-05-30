namespace Flubber.Core.AI;

/// <summary>Backend de IA (común a MiniMax/Claude y OpenAI/DeepSeek). Puerto async de AIBackend.</summary>
public interface IAIBackend
{
    AIConfig Config { get; set; }
    bool IsConfigured { get; }

    Task<string?> ChatAsync(string system, IReadOnlyList<(string Role, string Content)> history, string? user, int maxTokens);
    Task<LLMResult?> CompleteAsync(IReadOnlyList<AIMessage> messages, IReadOnlyList<ToolDef>? tools, int maxTokens);
    Task<LLMResult?> CompleteStreamAsync(IReadOnlyList<AIMessage> messages, IReadOnlyList<ToolDef>? tools, int maxTokens, Action<string> onDelta);
    Task<string?> VisionAsync(string prompt, string imageBase64);
    Task<string> WebSearchAsync(string query);
    Task<(bool Ok, string Message)> TestAsync();
}

public static class BackendFactory
{
    // claude/minimax → formato Anthropic Messages; openai/deepseek → OpenAI Chat Completions.
    public static IAIBackend Make(AIConfig config) => config.Provider switch
    {
        "openai" or "deepseek" => new OpenAIBackend(config),
        _ => new AnthropicBackend(config),
    };
}
