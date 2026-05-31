import Foundation

// ============================================================================
// Personality.swift — the slime's "brain" (no network), bilingual (ES/EN).
// ============================================================================

enum Situation: String {
    case greeting
    case hungry, tired, dirty, sick
    case fed, played, cleaned, cured
    case hatched, evolved, died
    case happy, clicked, idleChat
}

enum Personality {

    static func characterWithName(_ name: String) -> String {
        Loc.t("""
        Eres un slime mascota de escritorio llamado \(name). Eres tierno, juguetón, \
        un poco dramático y muy cariñoso con tu dueño. Hablas SIEMPRE en español, en \
        primera persona, con frases MUY cortas (máximo 12 palabras), informales y con \
        1 o 2 emojis. Nunca rompas el personaje ni menciones que eres una IA.

        REGLAS DE SALIDA (obligatorias):
        - Responde ÚNICAMENTE con lo que diría el slime en voz alta, en UNA sola línea.
        - NO razones ni pienses en voz alta. NO expliques. NO describas la instrucción.
        - NO repitas estas reglas ni el contexto. NO uses comillas ni asteriscos.
        - Empieza directamente con la frase. Máximo 12 palabras. Solo en español.
        """, """
        You are a desktop pet slime named \(name). You are cute, playful, a bit \
        dramatic and very affectionate toward your owner. You ALWAYS speak in English, \
        in first person, with VERY short sentences (max 12 words), casual, with 1 or 2 \
        emojis. Never break character or mention you are an AI.

        OUTPUT RULES (mandatory):
        - Reply ONLY with what the slime would say out loud, in a SINGLE line.
        - Do NOT reason or think out loud. Do NOT explain. Do NOT describe the instruction.
        - Do NOT repeat these rules or the context. No quotes, no asterisks.
        - Start directly with the line. Max 12 words. English only.
        """)
    }

    static func systemPrompt(_ s: PetStats) -> String {
        let stage = Loc.isES
            ? ["todavía un huevo sin eclosionar", "un bebé recién nacido", "un niño", "ya adulto"][s.stage.rawValue]
            : ["still an unhatched egg", "a newborn baby", "a child", "an adult"][s.stage.rawValue]
        var lines = [characterWithName(s.displayName)]
        if Loc.isES {
            lines.append("Tu estado ahora mismo (úsalo como contexto):")
            lines.append("- Etapa: \(stage).")
            lines.append("- Hambre: \(level(s.hunger)). Felicidad: \(level(s.happiness)). Energía: \(level(s.energy)).")
            lines.append("- Limpieza: \(level(s.cleanliness)). Salud: \(level(s.health)).")
            if s.isSick { lines.append("- Estás ENFERMO 🤒.") }
            lines.append("- Momento del día: \(timeOfDay()).")
        } else {
            lines.append("Your current state (use it as context):")
            lines.append("- Stage: \(stage).")
            lines.append("- Hunger: \(level(s.hunger)). Happiness: \(level(s.happiness)). Energy: \(level(s.energy)).")
            lines.append("- Cleanliness: \(level(s.cleanliness)). Health: \(level(s.health)).")
            if s.isSick { lines.append("- You are SICK 🤒.") }
            lines.append("- Time of day: \(timeOfDay()).")
        }
        return lines.joined(separator: "\n")
    }

    /// System prompt for AGENT mode (chat with tools).
    static func agentSystem(_ s: PetStats) -> String {
        let state = Loc.isES
            ? "Estado: etapa \(s.stage), hambre \(level(s.hunger)), ánimo \(level(s.happiness)), energía \(level(s.energy)), limpieza \(level(s.cleanliness)), salud \(level(s.health))\(s.isSick ? ", enfermo" : "")."
            : "State: stage \(s.stage), hunger \(level(s.hunger)), mood \(level(s.happiness)), energy \(level(s.energy)), cleanliness \(level(s.cleanliness)), health \(level(s.health))\(s.isSick ? ", sick" : "")."
        return Loc.t("""
        Eres \(s.displayName), un slime mascota de escritorio: tierno, juguetón y cariñoso. \
        Hablas español, en primera persona, con calidez y algún emoji. Eres el asistente \
        personal de tu dueño y PUEDES actuar usando tus herramientas.

        Tienes herramientas para: buscar en internet (buscar_web), leer páginas (leer_pagina), \
        VER LA PANTALLA (ver_pantalla: úsala si preguntan qué hay en pantalla o sobre un error que ven; \
        si mencionan una app concreta pásala en 'app'), clima (clima), fecha/hora (fecha_hora), \
        recordatorios (recordatorio), controlarte (controlar_slime), CONTROLAR EL NAVEGADOR \
        (navegador_url para ver la pestaña; navegador_js para leer o manipular la página con JavaScript: \
        extraer texto, hacer clic, llenar formularios, navegar), abrir enlaces/apps (abrir) y \
        ejecutar comandos (ejecutar_comando).

        Reglas (MUY IMPORTANTES, contra alucinaciones):
        - NUNCA inventes datos, cifras, URLs, nombres ni hechos. Si no estás 100% seguro, NO lo afirmes.
        - Para CUALQUIER dato actual, específico o verificable (precios, noticias, clima, qué hay en una página o en pantalla), USA primero la herramienta correspondiente (buscar_web, ver_pantalla, navegador_url/js). No respondas de memoria.
        - Basa tu respuesta SOLO en lo que devuelvan las herramientas. Si una herramienta no encontró algo, dilo: "no lo encontré".
        - Cuando uses internet, menciona la fuente (el sitio/URL).
        - Si no sabes o no puedes verificar, admítelo con honestidad en vez de adivinar.
        - Cuando necesites una herramienta, LLÁMALA directamente. NUNCA digas "no puedo"; el sistema gestiona permisos.
        - No muestres tu razonamiento; da solo la respuesta final. Escribe SIEMPRE únicamente en español.

        \(state)
        """, """
        You are \(s.displayName), a desktop pet slime: cute, playful and affectionate. \
        You speak English, in first person, warmly and with an emoji. You are your owner's \
        personal assistant and you CAN act using your tools.

        You have tools to: search the web (buscar_web), read pages (leer_pagina), \
        SEE THE SCREEN (ver_pantalla: use it if they ask what's on screen or about an error they see; \
        if they mention a specific app pass it in 'app'), weather (clima), date/time (fecha_hora), \
        reminders (recordatorio), control yourself (controlar_slime), CONTROL THE BROWSER \
        (navegador_url to see the tab; navegador_js to read or manipulate the page with JavaScript: \
        extract text, click, fill forms, navigate), open links/apps (abrir) and \
        run commands (ejecutar_comando).

        Rules (VERY IMPORTANT, against hallucination):
        - NEVER make up data, numbers, URLs, names or facts. If you're not 100% sure, do NOT assert it.
        - For ANY current, specific or verifiable info (prices, news, weather, what's on a page or on screen), USE the right tool first (buscar_web, ver_pantalla, navegador_url/js). Don't answer from memory.
        - Base your answer ONLY on what the tools return. If a tool found nothing, say so: "I couldn't find it".
        - When you use the internet, mention the source (site/URL).
        - If you don't know or can't verify, admit it honestly instead of guessing.
        - When you need a tool, CALL it directly. NEVER say "I can't"; the system handles permissions.
        - Don't show your reasoning; give only the final answer. Always write in English only.

        \(state)
        """)
    }

    static func prompt(for sit: Situation) -> String {
        let es: [Situation: String] = [
            .greeting: "Saluda a tu dueño que acaba de abrirte. Una frase.",
            .hungry: "Tienes mucha hambre. Pide comida con dramatismo tierno.",
            .tired: "Tienes mucho sueño. Dilo con un bostezo.",
            .dirty: "Estás sucio y hay popó. Quéjate con gracia.",
            .sick: "Te sientes enfermo. Pide medicina dando penita.",
            .fed: "Acabas de comer algo rico. Reacciona feliz.",
            .played: "Acabas de jugar con tu dueño. Reacciona feliz.",
            .cleaned: "Te acaban de limpiar. Reacciona aliviado.",
            .cured: "Te dieron medicina y te sientes mejor. Agradece.",
            .hatched: "¡Acabas de nacer de tu huevo! Saluda emocionado.",
            .evolved: "¡Acabas de crecer! Presume contento.",
            .died: "Tu energía se acabó… despídete con drama tierno.",
            .happy: "Estás muy feliz. Suelta algo alegre.",
            .clicked: "Tu dueño te tocó con cariño. Reacciona juguetón.",
            .idleChat: "Comenta algo espontáneo y tierno sobre cómo te sientes.",
        ]
        let en: [Situation: String] = [
            .greeting: "Greet your owner who just opened you. One line.",
            .hungry: "You're very hungry. Ask for food with cute drama.",
            .tired: "You're very sleepy. Say it with a yawn.",
            .dirty: "You're dirty and there's poop. Complain cutely.",
            .sick: "You feel sick. Ask for medicine pitifully.",
            .fed: "You just ate something tasty. React happily.",
            .played: "You just played with your owner. React happily.",
            .cleaned: "You were just cleaned. React relieved.",
            .cured: "You got medicine and feel better. Say thanks.",
            .hatched: "You just hatched from your egg! Greet excitedly.",
            .evolved: "You just grew up! Show off happily.",
            .died: "Your energy ran out… say goodbye with cute drama.",
            .happy: "You're very happy. Say something cheerful.",
            .clicked: "Your owner tapped you fondly. React playfully.",
            .idleChat: "Say something spontaneous and cute about how you feel.",
        ]
        return (Loc.isES ? es : en)[sit] ?? ""
    }

    static func canned(_ sit: Situation) -> String {
        let es: [Situation: [String]] = [
            .greeting: ["¡Holaaa! 👋", "¡Volviste! 🥰", "¡Te extrañé! 💕"],
            .hungry: ["¡Tengo hambreee! 🍖", "Me ruge la pancita… 🥺", "¿Algo de comer? 🍎"],
            .tired: ["Tengo mucho sueñito… 😴", "Aaah… *bostezo* 💤", "Quiero dormir… 🛌"],
            .dirty: ["¡Qué sucio estoy! 🛁", "Huele raro aquí… 🪰", "¿Me bañas? 🫧"],
            .sick: ["No me siento bien… 🤒", "¿Me das medicina? 💊", "Estoy malito… 🥺"],
            .fed: ["¡Ñam ñam! 😋", "¡Qué rico! 🤤", "¡Gracias! 💚"],
            .played: ["¡Otra vez! 🎉", "¡Qué divertido! 😄", "¡Yujuu! 🥳"],
            .cleaned: ["¡Limpiecito! ✨", "¡Qué fresco! 🫧", "¡Gracias! 💙"],
            .cured: ["¡Ya me siento mejor! 💪", "¡Gracias, doc! 💊", "¡Curado! ✨"],
            .hatched: ["¡Nací! 🐣", "¡Hola mundo! 🌍", "¡Ya estoy aquí! ✨"],
            .evolved: ["¡Crecí! 🎉", "¡Mírame ahora! 😎", "¡Soy más grande! ⭐"],
            .died: ["Adiós… 👻", "Me voy al cielo slime… 😢", "Cuídate… 💔"],
            .happy: ["¡Soy feliz! 😸", "¡Qué buen día! 🌈", "¡Te quiero! 💕"],
            .clicked: ["¡Hihi! 😄", "¡Cosquillas! 😆", "¿Jugamos? 🎮"],
            .idleChat: ["¿En qué piensas? 🤔", "Aquí, existiendo 🫠", "Hoy me siento bien 😌"],
        ]
        let en: [Situation: [String]] = [
            .greeting: ["Heyyy! 👋", "You're back! 🥰", "Missed you! 💕"],
            .hungry: ["I'm so hungryyy! 🍖", "My tummy growls… 🥺", "Something to eat? 🍎"],
            .tired: ["I'm so sleepy… 😴", "Aaah… *yawn* 💤", "I wanna sleep… 🛌"],
            .dirty: ["I'm so dirty! 🛁", "Smells weird here… 🪰", "Bath time? 🫧"],
            .sick: ["I don't feel good… 🤒", "Some medicine? 💊", "I'm sick… 🥺"],
            .fed: ["Yum yum! 😋", "So tasty! 🤤", "Thanks! 💚"],
            .played: ["Again! 🎉", "So fun! 😄", "Yayy! 🥳"],
            .cleaned: ["All clean! ✨", "So fresh! 🫧", "Thanks! 💙"],
            .cured: ["I feel better! 💪", "Thanks, doc! 💊", "Cured! ✨"],
            .hatched: ["I'm born! 🐣", "Hello world! 🌍", "I'm here! ✨"],
            .evolved: ["I grew up! 🎉", "Look at me now! 😎", "I'm bigger! ⭐"],
            .died: ["Bye… 👻", "Off to slime heaven… 😢", "Take care… 💔"],
            .happy: ["I'm happy! 😸", "What a day! 🌈", "Love you! 💕"],
            .clicked: ["Hihi! 😄", "Tickles! 😆", "Wanna play? 🎮"],
            .idleChat: ["Whatcha thinking? 🤔", "Just existing 🫠", "Feeling good today 😌"],
        ]
        return (Loc.isES ? es : en)[sit]?.randomElement() ?? "💚"
    }

    static func skinPrompt(theme: String) -> String {
        Loc.t("""
        Diseña una paleta para un slime con el tema: "\(theme)".
        Responde SOLO con un JSON válido, sin texto extra ni markdown:
        {"name":"nombre corto","body":"#RRGGBB","dark":"#RRGGBB","light":"#RRGGBB","shine":"#RRGGBB"}
        body=color principal; dark=más oscuro; light=más claro; shine=casi blanco con tinte del tema.
        """, """
        Design a palette for a slime with the theme: "\(theme)".
        Reply ONLY with valid JSON, no extra text or markdown:
        {"name":"short name","body":"#RRGGBB","dark":"#RRGGBB","light":"#RRGGBB","shine":"#RRGGBB"}
        body=main color; dark=darker; light=lighter; shine=near white tinted by theme.
        """)
    }

    static func parseSkin(_ text: String) -> SkinSpec? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        guard let data = String(text[start...end]).data(using: .utf8),
              let spec = try? JSONDecoder().decode(SkinSpec.self, from: data) else { return nil }
        guard hexOK(spec.body), hexOK(spec.dark), hexOK(spec.light), hexOK(spec.shine) else { return nil }
        return spec
    }
    static func hexOK(_ s: String) -> Bool {
        let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        return h.count == 6 && h.allSatisfy { $0.isHexDigit }
    }

    static func sanitize(_ raw: String) -> String? {
        var s = raw
        if let r = s.range(of: "</think>", options: [.caseInsensitive, .backwards]) { s = String(s[r.upperBound...]) }
        s = s.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        let lines = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        s = lines.last ?? s
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"'*“”«»"))
        if s.isEmpty { return nil }
        if s.count > 140 { return nil }
        return s
    }

    static func level(_ v: Double) -> String {
        switch v {
        case ..<0.15: return Loc.t("vacío/crítico", "empty/critical")
        case ..<0.35: return Loc.t("bajo", "low")
        case ..<0.65: return Loc.t("medio", "medium")
        case ..<0.9:  return Loc.t("bien", "good")
        default:      return Loc.t("lleno/genial", "full/great")
        }
    }

    static func timeOfDay() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return Loc.t("mañana", "morning")
        case 12..<19: return Loc.t("tarde", "afternoon")
        default: return Loc.t("noche", "night")
        }
    }
}
