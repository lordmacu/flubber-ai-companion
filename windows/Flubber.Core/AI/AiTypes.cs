namespace Flubber.Core.AI;

/// <summary>Skin serializable (para persistir el skin generado por IA).</summary>
public sealed class SkinSpec
{
    public string Name { get; set; } = "";
    public string Body { get; set; } = "";   // hex "#RRGGBB"
    public string Dark { get; set; } = "";
    public string Light { get; set; } = "";
    public string Shine { get; set; } = "";
}

// MARK: - Tipos para function calling

public sealed record ToolCall(string Id, string Name, string Arguments);

public sealed record LLMResult(string? Content, IReadOnlyList<ToolCall> ToolCalls);

/// <summary>Definición de herramienta. Parameters es el JSON schema (dictionary anidado).</summary>
public sealed record ToolDef(string Name, string Description, IReadOnlyDictionary<string, object?> Parameters);

/// <summary>Mensaje normalizado, independiente del proveedor.</summary>
public sealed class AIMessage
{
    public string Role { get; set; } = "user";   // system | user | assistant | tool
    public string Content { get; set; } = "";
    public List<ToolCall> ToolCalls { get; set; } = new();   // para assistant
    public string? ToolCallId { get; set; }                  // para tool (resultado)
    public string? ImageBase64 { get; set; }                 // captura adjunta (JPEG base64), para user

    public AIMessage() { }
    public AIMessage(string role, string content) { Role = role; Content = content; }
}
