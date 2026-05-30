import Foundation

// ============================================================================
// Loc.swift — idioma de la app (interfaz + prompts + respuestas).
// Por defecto sigue al sistema; se puede forzar a "es" o "en" y cambia al vuelo.
// ============================================================================

enum Lang { case es, en }

enum Loc {
    /// nil = seguir al sistema; "es"/"en" = forzado por el usuario.
    static var override: String?

    static var lang: Lang {
        if let o = override { return o == "en" ? .en : .es }
        let sys = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return sys.hasPrefix("es") ? .es : .en
    }

    /// Devuelve la cadena en el idioma actual.
    static func t(_ es: String, _ en: String) -> String { lang == .es ? es : en }

    static var isES: Bool { lang == .es }
    static var name: String { lang == .es ? "Español" : "English" }
}
