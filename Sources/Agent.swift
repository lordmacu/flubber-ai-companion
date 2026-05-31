import Cocoa
import UserNotifications

// ============================================================================
// Agent.swift — the slime as an AGENT: function-calling loop with MiniMax and
// the tool catalog (web search, page reading, weather, time,
// reminders, self-control, opening things, running commands).
// "Outward" actions (open / run) ask the user for confirmation.
// ============================================================================

final class Agent {
    weak var view: PetView?
    let client: AIBackend
    var messages: [AIMessage] = []
    private var iterations = 0
    private let maxIterations = 6

    var onStep: ((String) -> Void)?
    var onToken: ((String) -> Void)?     // streaming text (token by token)
    // (title, detail, callback(approved, always)) — provided by the UI to confirm.
    var confirm: ((String, String, @escaping (Bool, Bool) -> Void) -> Void)?

    func allowed(_ cat: String) -> Bool {
        guard let c = view?.client?.config else { return false }
        switch cat { case "browser": return c.allowBrowser == true
                     case "command": return c.allowCommand == true
                     case "open": return c.allowOpen == true; default: return false }
    }
    func setAllowed(_ cat: String) {
        guard let v = view, var c = v.client?.config else { return }
        switch cat { case "browser": c.allowBrowser = true
                     case "command": c.allowCommand = true
                     case "open": c.allowOpen = true; default: break }
        v.client?.config = c; c.save()
    }

    init(view: PetView, client: AIBackend) { self.view = view; self.client = client }

    // MARK: Loop

    func run(_ userText: String, image: String? = nil, onStep: @escaping (String) -> Void,
             onToken: @escaping (String) -> Void = { _ in }, completion: @escaping (String) -> Void) {
        self.onStep = onStep
        self.onToken = onToken
        let sys = Personality.agentSystem(view?.stats ?? PetStats())
        if messages.isEmpty { messages = [AIMessage(role: "system", content: sys)] }
        else { messages[0] = AIMessage(role: "system", content: sys) }    // refresh state
        messages.append(AIMessage(role: "user", content: userText, imageBase64: image))
        iterations = 0
        step(completion)
    }

    private func step(_ completion: @escaping (String) -> Void) {
        iterations += 1
        if iterations > maxIterations { completion("Uff, me enredé demasiado 😵 ¿lo intentamos de otra forma?"); return }
        client.completeStream(messages: messages, tools: Agent.tools, maxTokens: 2000,
                              onDelta: { [weak self] chunk in self?.onToken?(chunk) }) { [weak self] result in
            guard let self = self else { return }
            guard let result = result else { completion("Uy, no pude responder 😵‍💫"); return }

            if result.toolCalls.isEmpty {
                let text = Agent.cleanFinal(result.content ?? "")
                self.messages.append(AIMessage(role: "assistant", content: result.content ?? text))
                completion(text.isEmpty ? "🟢" : text)
                return
            }
            // record the assistant message with its tool_calls and execute them
            self.messages.append(AIMessage(role: "assistant", content: result.content ?? "", toolCalls: result.toolCalls))
            self.executeAll(result.toolCalls, index: 0) { self.step(completion) }
        }
    }

    private func executeAll(_ calls: [ToolCall], index: Int, done: @escaping () -> Void) {
        if index >= calls.count { done(); return }
        let call = calls[index]
        onStep?(Agent.stepLabel(call))
        execute(call) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.messages.append(AIMessage(role: "tool", content: result, toolCallId: call.id))
                self.executeAll(calls, index: index + 1, done: done)
            }
        }
    }

    // MARK: Tool dispatch

    private func execute(_ call: ToolCall, completion: @escaping (String) -> Void) {
        let args = Agent.parseArgs(call.arguments)
        switch call.name {
        case "buscar_web":   client.webSearch(args["query"] as? String ?? "", completion: completion)
        case "leer_pagina":  WebTools.fetch(args["url"] as? String ?? "", completion)
        case "clima":        WebTools.weather(args["lugar"] as? String ?? "", completion)
        case "fecha_hora":   completion(Agent.datetime())
        case "ver_pantalla":
            let q = (args["pregunta"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Describe qué se ve en esta pantalla."
            let appHint = args["app"] as? String
            let win = view?.window
            ScreenCapture.grab(appHint: appHint, excluding: win) { [weak self] b64, path in
                guard let self = self else { return }
                if let path = path { self.view?.attachShot(path) }      // thumbnail in the chat
                guard let b64 = b64 else {
                    completion("No pude ver la pantalla: activa Grabación de pantalla para Flubber en Ajustes (te lo abrí) y REINICIA la app."); return
                }
                self.client.vision(prompt: q, imageBase64: b64) { desc in
                    completion(desc ?? "Capturé la pantalla pero no pude analizarla.")
                }
            }
        case "recordatorio": self.scheduleReminder(args, completion)
        case "controlar_slime":
            DispatchQueue.main.async { completion(self.controlSlime(args)) }
        case "navegador_url": BrowserTools.getURL(completion)
        case "navegador_js":
            let js = args["codigo"] as? String ?? ""
            guard !js.isEmpty else { completion("No hay código."); return }
            gate("browser", Loc.t("Ejecutar en el navegador", "Run in the browser"), js,
                 { BrowserTools.runJS(js, completion) },
                 { completion(Loc.t("El usuario rechazó la acción.", "User rejected the action.")) })
        case "abrir":        self.confirmOpen(args, completion)
        case "ejecutar_comando": self.confirmRun(args, completion)
        case "escuchar_reunion":
            if #available(macOS 13.0, *) {
                let l = MeetingListener.shared
                if l.isListening { completion(Loc.t("Ya estoy escuchando 🎧", "Already listening 🎧")); return }
                l.start { ok, err in
                    DispatchQueue.main.async {
                        self.view?.listening = ok
                        completion(ok ? Loc.t("Empecé a escuchar la reunión 🎧", "Started listening to the meeting 🎧")
                                      : (err ?? Loc.t("No pude escuchar.", "Couldn't listen.")))
                    }
                }
            } else { completion(Loc.t("La escucha requiere macOS 13+.", "Listening requires macOS 13+.")) }
        case "detener_escucha":
            if #available(macOS 13.0, *) {
                MeetingListener.shared.stop()
                DispatchQueue.main.async { self.view?.listening = false; self.view?.micOn = false }
                completion(Loc.t("Dejé de escuchar 👂", "Stopped listening 👂"))
            } else { completion("ok") }
        case "usar_microfono":
            if #available(macOS 13.0, *) {
                let l = MeetingListener.shared
                if l.micOn { completion(Loc.t("El micrófono ya está activo 🎤", "Mic already on 🎤")); return }
                l.startMic { ok, err in
                    DispatchQueue.main.async {
                        self.view?.micOn = ok
                        completion(ok ? Loc.t("Activé tu micrófono 🎤", "Turned on your mic 🎤")
                                      : (err ?? Loc.t("No pude usar el micrófono.", "Couldn't use the mic.")))
                    }
                }
            } else { completion(Loc.t("El micrófono requiere macOS 13+.", "Mic requires macOS 13+.")) }
        case "apagar_microfono":
            if #available(macOS 13.0, *) {
                MeetingListener.shared.stopMic()
                DispatchQueue.main.async { self.view?.micOn = false }
                completion(Loc.t("Apagué el micrófono 🎤", "Mic off 🎤"))
            } else { completion("ok") }
        case "resumen_reunion":
            if #available(macOS 13.0, *) {
                let t = MeetingListener.shared.fullText
                completion(t.isEmpty
                    ? Loc.t("No hay nada transcrito aún. Activa la escucha primero.", "Nothing transcribed yet. Start listening first.")
                    : Loc.t("Transcripción de la reunión:\n", "Meeting transcript:\n") + t)
            } else { completion("") }
        default: completion("Herramienta desconocida.")
        }
    }

    // MARK: Local tools

    private func scheduleReminder(_ args: [String: Any], _ completion: @escaping (String) -> Void) {
        let texto = args["texto"] as? String ?? "recordatorio"
        let secs = (args["segundos"] as? NSNumber)?.doubleValue
            ?? Double(args["segundos"] as? String ?? "") ?? 60
        DispatchQueue.main.async {
            Timer.scheduledTimer(withTimeInterval: max(1, secs), repeats: false) { _ in
                let c = UNMutableNotificationContent()
                c.title = "⏰ Flubber"; c.body = texto; c.sound = .default
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            }
            completion("Recordatorio puesto en \(Int(secs)) s: \(texto)")
        }
    }

    private func controlSlime(_ args: [String: Any]) -> String {   // always call on the main thread
        guard let view = view else { return "No pude controlarme." }
        let accion = (args["accion"] as? String ?? "").lowercased()
        let tema = (args["tema"] as? String ?? args["color"] as? String ?? "").lowercased()
        switch accion {
        case "bailar": view.enter(.dancing); return "¡A bailar! 💃"
        case "rodar":  view.enter(.rolling); return "¡Rodando! 🤸"
        case "pasear": if let s = NSScreen.main { view.startWalking(in: s) }; return "Me voy a pasear 🚶"
        case "feliz":  view.enter(.happy); return "¡Yupi! 😄"
        case "dormir": view.stats.isAsleep = true; view.enter(.sleeping); return "Zzz 😴"
        case "color":
            let names = ["verde", "azul", "morado", "rosa"]
            if let i = names.firstIndex(where: { tema.contains($0) }) { Pal.index = i; view.stats.skinIndex = i }
            else { Pal.index = (Pal.index + 1) % Pal.skins.count }
            return "Nuevo color 🎨"
        case "skin":
            guard !tema.isEmpty else { return "¿De qué tema quieres el skin?" }
            view.client?.chat(system: "Eres un diseñador de paletas. Responde SOLO con JSON.",
                              history: [], user: Personality.skinPrompt(theme: tema), maxTokens: 800) { reply in
                if let r = reply, let spec = Personality.parseSkin(r) { view.applyAISkin(spec) }
            }
            return "Generando un skin de \(tema)… ✨"
        default: return "No conozco esa acción."
        }
    }

    private func confirmOpen(_ args: [String: Any], _ completion: @escaping (String) -> Void) {
        let target = args["objetivo"] as? String ?? args["url"] as? String ?? ""
        guard !target.isEmpty else { completion("No me dijiste qué abrir."); return }
        gate("open", Loc.t("Abrir", "Open"), target, {
            if let url = URL(string: target.contains("://") ? target : "https://\(target)"),
               target.contains(".") || target.contains("://") { NSWorkspace.shared.open(url) }
            else { NSWorkspace.shared.launchApplication(target) }
            completion("Abierto: \(target)")
        }, { completion(Loc.t("El usuario rechazó abrir \(target).", "User rejected opening \(target).")) })
    }

    private func confirmRun(_ args: [String: Any], _ completion: @escaping (String) -> Void) {
        let cmd = args["comando"] as? String ?? ""
        guard !cmd.isEmpty else { completion("No hay comando."); return }
        gate("command", Loc.t("Ejecutar comando", "Run command"), cmd, {
            DispatchQueue.global().async {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-lc", cmd]
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                var out = ""
                do { try p.run(); p.waitUntilExit()
                    out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                } catch { out = "Error: \(error.localizedDescription)" }
                if out.count > 2000 { out = String(out.prefix(2000)) + "…" }
                completion("Salida:\n\(out.isEmpty ? "(sin salida)" : out)")
            }
        }, { completion(Loc.t("El usuario rechazó el comando.", "User rejected the command.")) })
    }

    /// Asks for confirmation unless the category is already set to "always allow".
    private func gate(_ cat: String, _ title: String, _ detail: String, _ proceed: @escaping () -> Void, _ reject: @escaping () -> Void) {
        if allowed(cat) { proceed(); return }
        DispatchQueue.main.async {
            guard let confirm = self.confirm else { reject(); return }
            confirm(title, detail) { ok, always in
                if always { self.setAllowed(cat) }
                ok ? proceed() : reject()
            }
        }
    }

    // MARK: Helpers

    static func parseArgs(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
    }

    static func datetime() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE d 'de' MMMM 'de' yyyy, HH:mm"
        return f.string(from: Date())
    }

    static func cleanFinal(_ raw: String) -> String {
        var s = raw
        if let r = s.range(of: "</think>", options: [.caseInsensitive, .backwards]) { s = String(s[r.upperBound...]) }
        s = s.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stepLabel(_ c: ToolCall) -> String {
        let a = parseArgs(c.arguments)
        switch c.name {
        case "buscar_web":   return Loc.t("🔎 buscando: ", "🔎 searching: ") + (a["query"] as? String ?? "")
        case "leer_pagina":  return Loc.t("📄 leyendo: ", "📄 reading: ") + (a["url"] as? String ?? "")
        case "clima":        return Loc.t("🌡️ clima de ", "🌡️ weather in ") + (a["lugar"] as? String ?? "")
        case "fecha_hora":   return Loc.t("🕐 mirando la hora", "🕐 checking the time")
        case "ver_pantalla":
            let app = a["app"] as? String
            if app?.isEmpty == false { return Loc.t("👁️ mirando ", "👁️ looking at ") + app! }
            return Loc.t("👁️ mirando tu pantalla", "👁️ looking at your screen")
        case "recordatorio": return Loc.t("⏰ poniendo un recordatorio", "⏰ setting a reminder")
        case "controlar_slime": return "🎨 \(a["accion"] as? String ?? "")"
        case "navegador_url": return Loc.t("🌐 leyendo el navegador", "🌐 reading the browser")
        case "navegador_js":  return Loc.t("🌐 controlando el navegador", "🌐 controlling the browser")
        case "abrir":        return Loc.t("🔗 quiere abrir ", "🔗 wants to open ") + (a["objetivo"] as? String ?? a["url"] as? String ?? "")
        case "ejecutar_comando": return Loc.t("💻 quiere ejecutar un comando", "💻 wants to run a command")
        case "escuchar_reunion": return Loc.t("🎧 escuchando la reunión", "🎧 listening to the meeting")
        case "detener_escucha":  return Loc.t("⏹️ dejando de escuchar", "⏹️ stopping listening")
        case "usar_microfono":   return Loc.t("🎤 activando tu micrófono", "🎤 turning on your mic")
        case "apagar_microfono": return Loc.t("🎤 apagando el micrófono", "🎤 turning off the mic")
        case "resumen_reunion":  return Loc.t("📝 resumiendo la reunión", "📝 summarizing the meeting")
        default: return "🔧 \(c.name)"
        }
    }

    // MARK: Tool definitions (OpenAI schema)

    static func fn(_ name: String, _ desc: String, _ props: [String: Any], _ required: [String]) -> ToolDef {
        ToolDef(name: name, description: desc,
                parameters: ["type": "object", "properties": props, "required": required])
    }
    static let str: [String: Any] = ["type": "string"]

    static let tools: [ToolDef] = [
        fn("buscar_web", "Busca en internet (DuckDuckGo) y devuelve resultados con título, fragmento y URL.",
           ["query": ["type": "string", "description": "qué buscar"]], ["query"]),
        fn("leer_pagina", "Descarga una página web y devuelve su texto.",
           ["url": ["type": "string", "description": "URL completa"]], ["url"]),
        fn("clima", "Consulta el clima actual de un lugar.",
           ["lugar": ["type": "string", "description": "ciudad o lugar"]], ["lugar"]),
        fn("fecha_hora", "Devuelve la fecha y hora actuales.", [:], []),
        fn("recordatorio", "Programa un recordatorio (notificación) tras unos segundos.",
           ["texto": str, "segundos": ["type": "number"]], ["texto", "segundos"]),
        fn("controlar_slime", "Controla a la mascota: bailar, rodar, pasear, feliz, dormir, color o skin.",
           ["accion": ["type": "string", "description": "bailar|rodar|pasear|feliz|dormir|color|skin"],
            "tema": ["type": "string", "description": "color o tema del skin (opcional)"]], ["accion"]),
        fn("ver_pantalla", "Toma una captura de la pantalla del usuario y la analiza. Úsala cuando pregunten qué ven, un error en pantalla, etc. Si mencionan una app concreta (el navegador, Code, Figma…), pásala en 'app' para capturar SOLO esa ventana; si no, captura toda la pantalla.",
           ["pregunta": ["type": "string", "description": "qué quieres saber de la pantalla (opcional)"],
            "app": ["type": "string", "description": "app/ventana a capturar, ej. 'navegador', 'Safari', 'Code' (opcional; vacío = toda la pantalla)"]], []),
        fn("navegador_url", "Devuelve la URL y el título de la pestaña activa del navegador.", [:], []),
        fn("navegador_js", "Ejecuta JavaScript en la pestaña activa del navegador (Chrome/Safari/Brave/Edge/Arc) para leer o manipular la página: extraer texto, hacer clic, llenar formularios, navegar (location.href=...), hacer scroll, etc. Devuelve lo que retorne el JS. Pide confirmación.",
           ["codigo": ["type": "string", "description": "código JavaScript para la pestaña activa (ej. document.body.innerText)"]], ["codigo"]),
        fn("abrir", "Abre una URL en el navegador o una app (pide confirmación al usuario).",
           ["objetivo": ["type": "string", "description": "URL o nombre de app"]], ["objetivo"]),
        fn("ejecutar_comando", "Ejecuta un comando de shell en el Mac (pide confirmación al usuario).",
           ["comando": ["type": "string", "description": "comando zsh"]], ["comando"]),
        fn("escuchar_reunion", "Empieza a escuchar el audio del sistema (la reunión de Meet/Teams/Zoom) y a transcribirlo EN EL DISPOSITIVO. Úsala cuando el usuario diga 'escucha la conversación/la reunión'.", [:], []),
        fn("detener_escucha", "Deja de escuchar la reunión.", [:], []),
        fn("usar_microfono", "Activa el MICRÓFONO para que tu propia voz también entre en la transcripción de la reunión. Úsala si el usuario dice 'usa el micrófono' o 'incluye mi voz'.", [:], []),
        fn("apagar_microfono", "Apaga el micrófono (deja de transcribir tu voz).", [:], []),
        fn("resumen_reunion", "Devuelve la transcripción acumulada de la reunión para que la resumas. Úsala cuando pidan un resumen de lo que se ha hablado.", [:], []),
    ]
}

// MARK: - Screen capture (so the slime can "see")

enum ScreenCapture {
    static var shotsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlimePet/shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Finds the id of the frontmost window matching `hint` (app name or "browser").
    static func windowID(matching hint: String) -> CGWindowID? {
        let h = hint.lowercased()
        guard !h.isEmpty else { return nil }
        let browsers = ["safari", "chrome", "google chrome", "arc", "firefox", "edge", "microsoft edge", "brave", "opera", "vivaldi", "dia", "comet"]
        let wantBrowser = h.contains("navegad") || h.contains("browser")
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {   // comes front to back
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let owner = (w[kCGWindowOwnerName as String] as? String)?.lowercased(),
                  let num = w[kCGWindowNumber as String] as? CGWindowID, owner.lowercased() != "flubber" else { continue }
            if let b = w[kCGWindowBounds as String] as? [String: Any], let hgt = b["Height"] as? CGFloat, hgt < 80 { continue }
            let match = wantBrowser ? browsers.contains(where: { owner.contains($0) }) : (owner.contains(h) || h.contains(owner))
            if match { return num }
        }
        return nil
    }

    /// Capture. If `appHint` matches an app, captures ONLY that window; otherwise the whole screen.
    /// We don't hide the slime's window (sharingType=.none already excludes it) → no flicker.
    /// Do we actually have Screen Recording permission? (not what Settings "says")
    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    static func grab(appHint: String? = nil, excluding window: NSWindow? = nil, completion: @escaping (String?, String?) -> Void) {
        // Check the permission FOR REAL; if missing, request it and open the right panel.
        let pre = CGPreflightScreenCaptureAccess()
        Log.write("📸 grab(appHint=\(appHint ?? "nil")) — CGPreflightScreenCaptureAccess=\(pre)")
        if !pre {
            DispatchQueue.main.async {
                let granted = CGRequestScreenCaptureAccess()
                Log.write("🔐 No screen permission → CGRequestScreenCaptureAccess=\(granted). Opening Settings panel.")
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(u)
                }
                completion(nil, nil)
            }
            return
        }
        let targetID = appHint.flatMap { windowID(matching: $0) }
        Log.write("📸 Permission OK. Capturing \(targetID != nil ? "window id=\(targetID!)" : "full screen").")
        DispatchQueue.global().async {
            let path = shotsDir.appendingPathComponent(UUID().uuidString + ".jpg").path
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            if let id = targetID { p.arguments = ["-x", "-o", "-t", "jpg", "-l", String(id), path] }
            else { p.arguments = ["-x", "-t", "jpg", path] }
            var ok = true
            do { try p.run(); p.waitUntilExit() } catch { ok = false }
            let exists = FileManager.default.fileExists(atPath: path)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
            let b64 = ok ? NSImage(contentsOfFile: path).flatMap { encode($0, maxW: 1000) } : nil
            Log.write("📸 screencapture ok=\(ok) file=\(exists) bytes=\(bytes ?? 0) b64=\(b64 != nil ? "yes(\(b64!.count))" : "no")")
            DispatchQueue.main.async { completion(b64, ok ? path : nil) }
        }
    }
    private static func encode(_ img: NSImage, maxW: CGFloat) -> String? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        let scale = min(1, maxW / max(1, w))
        let nw = max(1, Int(w * scale)), nh = max(1, Int(h * scale))
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: nw, pixelsHigh: nh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        rep.draw(in: NSRect(x: 0, y: 0, width: nw, height: nh))
        NSGraphicsContext.restoreGraphicsState()
        // JPEG with compression: much smaller payload than PNG
        return out.representation(using: .jpeg, properties: [.compressionFactor: 0.55])?.base64EncodedString()
    }
}

// MARK: - Browser control (AppleScript: read URL, run JS in the active tab)

enum BrowserTools {
    static let names = ["safari", "google chrome", "chrome", "brave browser", "brave",
                        "microsoft edge", "edge", "arc", "opera", "vivaldi", "dia", "comet"]

    static func frontName() -> String? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {   // front to back
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let owner = w[kCGWindowOwnerName as String] as? String else { continue }
            let lo = owner.lowercased()
            if names.contains(where: { lo.contains($0) }) { return owner }
        }
        return nil
    }

    static func isSafari(_ name: String) -> Bool { name.lowercased().contains("safari") }
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    static func runOsa(_ script: String) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { return "error: \(error.localizedDescription)" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func getURL(_ completion: @escaping (String) -> Void) {
        DispatchQueue.global().async {
            guard let n = frontName() else { completion("No hay navegador abierto."); return }
            let s = isSafari(n)
                ? "tell application \"\(n)\" to return (URL of current tab of front window) & \"\n\" & (name of current tab of front window)"
                : "tell application \"\(n)\" to return (URL of active tab of front window) & \"\n\" & (title of active tab of front window)"
            completion("[\(n)]\n" + runOsa(s))
        }
    }

    static func runJS(_ js: String, _ completion: @escaping (String) -> Void) {
        DispatchQueue.global().async {
            guard let n = frontName() else { completion("No hay navegador abierto."); return }
            let e = esc(js)
            let s = isSafari(n)
                ? "tell application \"\(n)\" to do JavaScript \"\(e)\" in current tab of front window"
                : "tell application \"\(n)\" to execute active tab of front window javascript \"\(e)\""
            var out = runOsa(s)
            if out.count > 2500 { out = String(out.prefix(2500)) + "…" }
            completion(out.isEmpty ? "(hecho)" : out)
        }
    }
}

// MARK: - Network tools (DuckDuckGo / fetch / weather)

enum WebTools {
    static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func get(_ urlStr: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlStr) else { completion(nil); return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            completion(data.flatMap { String(data: $0, encoding: .utf8) })
        }.resume()
    }

    static func search(_ query: String, _ completion: @escaping (String) -> Void) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        get("https://html.duckduckgo.com/html/?q=\(q)") { html in
            guard let html = html else { completion("No pude buscar (sin conexión)."); return }
            let titles = matches(in: html, pattern: "class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
            let snippets = matches(in: html, pattern: "class=\"result__snippet\"[^>]*>(.*?)</a>")
            if titles.isEmpty { completion("No encontré resultados."); return }
            var out = ""
            for (i, t) in titles.prefix(5).enumerated() {
                let title = strip(t.count > 1 ? t[1] : "")
                let url = decodeDDG(t.count > 0 ? t[0] : "")
                let snip = i < snippets.count ? strip(snippets[i].count > 0 ? snippets[i][0] : "") : ""
                out += "\(i + 1). \(title)\n   \(snip)\n   \(url)\n"
            }
            completion(out)
        }
    }

    static func fetch(_ urlStr: String, _ completion: @escaping (String) -> Void) {
        get(urlStr) { html in
            guard let html = html else { completion("No pude leer la página."); return }
            var text = strip(html)
            if text.count > 3000 { text = String(text.prefix(3000)) + "…(recortado)" }
            completion(text)
        }
    }

    static func weather(_ place: String, _ completion: @escaping (String) -> Void) {
        let p = place.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        get("https://wttr.in/\(p)?format=3&lang=es") { line in
            completion(line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No pude consultar el clima.")
        }
    }

    // --- parsing utilities ---
    static func matches(in text: String, pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { i in m.range(at: i).location != NSNotFound ? ns.substring(with: m.range(at: i)) : "" }
        }
    }

    static func strip(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let ents = ["&amp;": "&", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (k, v) in ents { t = t.replacingOccurrences(of: k, with: v) }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeDDG(_ href: String) -> String {
        // DDG links come as //duckduckgo.com/l/?uddg=<url-encoded>&...
        if let r = href.range(of: "uddg=") {
            let after = String(href[r.upperBound...])
            let enc = after.components(separatedBy: "&").first ?? after
            return enc.removingPercentEncoding ?? href
        }
        return href.hasPrefix("//") ? "https:" + href : href
    }
}
