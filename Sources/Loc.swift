import Foundation

// ============================================================================
// Loc.swift — the app's language (interface + prompts + responses).
// Follows the system by default; can be forced to "es" or "en" and switches on the fly.
// ============================================================================

enum Lang { case es, en }

enum Loc {
    /// nil = follow the system; "es"/"en" = forced by the user.
    static var override: String?

    static var lang: Lang {
        if let o = override { return o == "en" ? .en : .es }
        let sys = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return sys.hasPrefix("es") ? .es : .en
    }

    /// Returns the string in the current language.
    static func t(_ es: String, _ en: String) -> String { lang == .es ? es : en }

    static var isES: Bool { lang == .es }
    static var name: String { lang == .es ? "Español" : "English" }
}
