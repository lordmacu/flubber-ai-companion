using System.Text.Json;
using Flubber.Core.Platform;

namespace Flubber.Core;

// ============================================================================
// Multiple conversations with the slime, persisted. Port of Conversations.swift.
// ============================================================================

public sealed class Msg
{
    public string Role { get; set; } = "user";   // "user" | "assistant"
    public string Content { get; set; } = "";
    public string? ImagePath { get; set; }        // attached screenshot (clickable thumbnail)
    public string? FilePath { get; set; }         // clickable attached file (.txt transcript)
}

public sealed class Conversation
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = "Nueva conversación";
    public List<Msg> Messages { get; set; } = new();

    public static Conversation New() => new()
    {
        Id = Guid.NewGuid().ToString(),
        Title = "Nueva conversación",
        Messages = new(),
    };
}

public sealed class ConversationStore
{
    public List<Conversation> Conversations { get; set; } = new();

    public static ConversationStore Load()
    {
        try
        {
            if (System.IO.File.Exists(Paths.ConversationsJson))
            {
                var json = System.IO.File.ReadAllText(Paths.ConversationsJson);
                var s = JsonSerializer.Deserialize<ConversationStore>(json);
                if (s != null) return s;
            }
        }
        catch { /* ignore */ }
        return new ConversationStore();
    }

    public void Save()
    {
        try { System.IO.File.WriteAllText(Paths.ConversationsJson, JsonSerializer.Serialize(this)); }
        catch { /* ignore */ }
    }
}
