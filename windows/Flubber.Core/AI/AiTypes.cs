namespace Flubber.Core.AI;

/// <summary>Serializable skin (to persist the AI-generated skin).</summary>
public sealed class SkinSpec
{
    public string Name { get; set; } = "";
    public string Body { get; set; } = "";   // hex "#RRGGBB"
    public string Dark { get; set; } = "";
    public string Light { get; set; } = "";
    public string Shine { get; set; } = "";
}

// MARK: - Types for function calling

public sealed record ToolCall(string Id, string Name, string Arguments);

public sealed record LLMResult(string? Content, IReadOnlyList<ToolCall> ToolCalls);

/// <summary>Tool definition. Parameters is the JSON schema (nested dictionary).</summary>
public sealed record ToolDef(string Name, string Description, IReadOnlyDictionary<string, object?> Parameters);

/// <summary>Normalized message, provider-independent.</summary>
public sealed class AIMessage
{
    public string Role { get; set; } = "user";   // system | user | assistant | tool
    public string Content { get; set; } = "";
    public List<ToolCall> ToolCalls { get; set; } = new();   // for assistant
    public string? ToolCallId { get; set; }                  // for tool (result)
    public string? ImageBase64 { get; set; }                 // attached screenshot (JPEG base64), for user

    public AIMessage() { }
    public AIMessage(string role, string content) { Role = role; Content = content; }
}
