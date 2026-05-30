import Foundation

// ============================================================================
// Conversations.swift — varias conversaciones con el slime, persistidas.
// ============================================================================

struct Msg: Codable {
    var role: String           // "user" | "assistant"
    var content: String
    var imagePath: String? = nil   // captura adjunta (thumbnail clicable)
}

struct Conversation: Codable {
    var id: String
    var title: String
    var messages: [Msg]

    static func new() -> Conversation {
        Conversation(id: UUID().uuidString, title: "Nueva conversación", messages: [])
    }
}

struct ConversationStore: Codable {
    var conversations: [Conversation] = []

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlimePet", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("conversations.json")
    }

    static func load() -> ConversationStore {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(ConversationStore.self, from: data) else {
            return ConversationStore()
        }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: ConversationStore.fileURL) }
    }
}
