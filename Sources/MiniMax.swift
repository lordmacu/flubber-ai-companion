import Foundation
import Security

// MARK: - Log a archivo (~/Library/Application Support/SlimePet/slimepet.log)

enum Log {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlimePet", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("slimepet.log")
    }
    static func write(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(s)\n"
        FileHandle.standardError.write(Data(line.utf8))
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}

// ============================================================================
// MiniMax.swift — configuración + cliente de red (LLM chat).
// La CLAVE API se guarda en el Keychain de macOS (cifrado por el sistema).
// Los ajustes no sensibles (modelo, URL, skin) van en config.json.
// Las llamadas usan callbacks en el hilo principal, sin bloquear la animación.
// ============================================================================

// MARK: - Keychain (lugar seguro para la clave)

enum Keychain {
    static let service = "co.cristiangarcia.slimepet"
    static let account = "minimax-api-key"

    static func set(_ value: String) {
        delete()
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Skin serializable (para persistir el skin generado por IA)

struct SkinSpec: Codable {
    var name: String
    var body: String     // hex "#RRGGBB"
    var dark: String
    var light: String
    var shine: String
}

// MARK: - Configuración

struct AIConfig: Codable {
    var provider: String = "minimax"          // "minimax" | "claude"
    // MiniMax
    var apiKey: String = ""
    var model: String = "MiniMax-M2.5"
    var baseURL: String = "https://api.minimax.io/v1"
    // Claude (Anthropic)
    var claudeKey: String? = nil
    var claudeModel: String? = nil            // p.ej. "claude-sonnet-4-6"
    // OpenAI (ChatGPT)
    var openaiKey: String? = nil
    var openaiModel: String? = nil
    // DeepSeek
    var deepseekKey: String? = nil
    var deepseekModel: String? = nil
    var lang: String? = nil                   // nil=sistema, "es", "en"
    // "permitir siempre" por categoría (no volver a preguntar)
    var allowBrowser: Bool? = nil
    var allowCommand: Bool? = nil
    var allowOpen: Bool? = nil
    // común
    var customSkin: SkinSpec? = nil

    var claudeKeyValue: String { claudeKey ?? "" }
    var claudeModelValue: String { (claudeModel?.isEmpty == false) ? claudeModel! : "claude-haiku-4-5-20251001" }
    var openaiKeyValue: String { openaiKey ?? "" }
    var openaiModelValue: String { (openaiModel?.isEmpty == false) ? openaiModel! : "gpt-4o" }
    var deepseekKeyValue: String { deepseekKey ?? "" }
    var deepseekModelValue: String { (deepseekModel?.isEmpty == false) ? deepseekModel! : "deepseek-chat" }

    var isConfigured: Bool {
        let k: String
        switch provider {
        case "claude": k = claudeKeyValue
        case "openai": k = openaiKeyValue
        case "deepseek": k = deepseekKeyValue
        default: k = apiKey                  // minimax
        }
        return !k.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlimePet", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }

    static func load() -> AIConfig {
        var c = AIConfig()
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            c = decoded
        }
        // migración: si quedó una clave del Keychain de versiones anteriores, úsala
        if c.apiKey.isEmpty, let legacy = Keychain.get(), !legacy.isEmpty {
            c.apiKey = legacy
            c.save()
            Keychain.delete()
        }
        return c
    }

    /// Guarda en un archivo local protegido (solo el usuario puede leerlo).
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: AIConfig.fileURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AIConfig.fileURL.path)
    }
}

// MARK: - Tipos para function calling

struct ToolCall { let id: String; let name: String; let arguments: String }
struct LLMResult { let content: String?; let toolCalls: [ToolCall] }
struct ToolDef { let name: String; let description: String; let parameters: [String: Any] }

/// Mensaje normalizado, independiente del proveedor.
struct AIMessage {
    var role: String                 // system | user | assistant | tool
    var content: String
    var toolCalls: [ToolCall] = []   // para assistant
    var toolCallId: String? = nil    // para tool (resultado)
    var imageBase64: String? = nil   // captura de pantalla adjunta (PNG base64), para user
}

// MARK: - Backend (protocolo común a MiniMax y Claude)

protocol AIBackend: AnyObject {
    var config: AIConfig { get set }
    var isConfigured: Bool { get }
    func chat(system: String, history: [(String, String)], user: String?, maxTokens: Int, completion: @escaping (String?) -> Void)
    func complete(messages: [AIMessage], tools: [ToolDef]?, maxTokens: Int, completion: @escaping (LLMResult?) -> Void)
    func completeStream(messages: [AIMessage], tools: [ToolDef]?, maxTokens: Int, onDelta: @escaping (String) -> Void, completion: @escaping (LLMResult?) -> Void)
    func vision(prompt: String, imageBase64: String, completion: @escaping (String?) -> Void)
    func webSearch(_ query: String, completion: @escaping (String) -> Void)
    func test(completion: @escaping (Bool, String) -> Void)
}

// Enruta al backend según el proveedor:
//  - claude / minimax → formato Anthropic Messages
//  - openai / deepseek → formato OpenAI Chat Completions
func makeBackend(_ config: AIConfig) -> AIBackend {
    switch config.provider {
    case "openai", "deepseek": return OpenAIBackend(config: config)
    default: return AnthropicBackend(config: config)   // claude, minimax
    }
}

// MARK: - Parser SSE para streaming real (formato Anthropic Messages)

final class StreamSession: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    private var text = ""
    private var tools: [Int: (id: String, name: String, json: String)] = [:]
    private let onDelta: (String) -> Void
    private let onDone: (LLMResult?) -> Void
    private var session: URLSession?
    private var finished = false

    init(onDelta: @escaping (String) -> Void, onDone: @escaping (LLMResult?) -> Void) {
        self.onDelta = onDelta; self.onDone = onDone
    }
    func start(_ request: URLRequest) {
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session?.dataTask(with: request).resume()
    }
    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let r = buffer.firstRange(of: Data([0x0a])) {
            let line = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<r.upperBound)
            handle(String(data: line, encoding: .utf8) ?? "")
        }
    }
    private func handle(_ raw: String) {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let d = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "content_block_start":
            if let idx = obj["index"] as? Int, let cb = obj["content_block"] as? [String: Any],
               cb["type"] as? String == "tool_use" {
                tools[idx] = (cb["id"] as? String ?? "", cb["name"] as? String ?? "", "")
            }
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any] {
                if let t = delta["text"] as? String { text += t; onDelta(t) }
                else if let pj = delta["partial_json"] as? String, let idx = obj["index"] as? Int {
                    tools[idx]?.json += pj
                }
            }
        case "message_stop": finishOnce()
        default: break
        }
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil, !finished { finished = true; Log.write("STREAM error"); onDone(nil) }
        else { finishOnce() }
        session?.finishTasksAndInvalidate()
    }
    private func finishOnce() {
        guard !finished else { return }; finished = true
        let calls = tools.sorted { $0.key < $1.key }.map {
            ToolCall(id: $0.value.id, name: $0.value.name, arguments: $0.value.json.isEmpty ? "{}" : $0.value.json)
        }
        onDone(LLMResult(content: text.isEmpty ? nil : text, toolCalls: calls))
    }
}

func jsonString(_ obj: Any) -> String {
    if let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) { return s }
    return "{}"
}
func jsonObject(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
}

// MARK: - OpenAI / DeepSeek (formato OpenAI Chat Completions)

final class OpenAIBackend: AIBackend {
    var config: AIConfig
    init(config: AIConfig) { self.config = config }

    var isOpenAI: Bool { config.provider == "openai" }
    var base: String { isOpenAI ? "https://api.openai.com/v1" : "https://api.deepseek.com" }
    var key: String { isOpenAI ? config.openaiKeyValue : config.deepseekKeyValue }
    var model: String { isOpenAI ? config.openaiModelValue : config.deepseekModelValue }
    var name: String { isOpenAI ? "OpenAI" : "DeepSeek" }
    var chatURL: String { base + "/chat/completions" }
    var isConfigured: Bool { !key.trimmingCharacters(in: .whitespaces).isEmpty }

    private func makeRequest(_ body: [String: Any], timeout: TimeInterval) -> URLRequest? {
        guard isConfigured, let url = URL(string: chatURL),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.httpBody = payload
        return req
    }
    private func post(_ body: [String: Any], timeout: TimeInterval, completion: @escaping (Data?) -> Void) {
        guard let req = makeRequest(body, timeout: timeout) else { completion(nil); return }
        Log.write("→ \(name) POST \(chatURL) model=\(model)")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if let err = err { Log.write("← \(name) ERROR \(err.localizedDescription)") }
            else { Log.write("← \(name) HTTP \(code) \(String((data.flatMap { String(data: $0, encoding: .utf8) } ?? "").prefix(300)))") }
            completion(err == nil ? data : nil)
        }.resume()
    }

    private func oaiMessages(_ messages: [AIMessage]) -> [[String: Any]] {
        var msgs: [[String: Any]] = []
        for m in messages {
            if m.role == "assistant", !m.toolCalls.isEmpty {
                msgs.append(["role": "assistant", "content": m.content,
                             "tool_calls": m.toolCalls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]] }])
            } else if m.role == "tool" {
                msgs.append(["role": "tool", "tool_call_id": m.toolCallId ?? "", "content": m.content])
            } else if m.role == "user", let img = m.imageBase64 {
                msgs.append(["role": "user", "content": [
                    ["type": "text", "text": m.content],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(img)"]]]])
            } else {
                msgs.append(["role": m.role, "content": m.content])
            }
        }
        return msgs
    }
    private func body(_ messages: [AIMessage], _ tools: [ToolDef]?, _ maxTokens: Int, stream: Bool) -> [String: Any] {
        var b: [String: Any] = ["model": model, "messages": oaiMessages(messages), "max_tokens": maxTokens, "temperature": 0.3]
        if stream { b["stream"] = true }
        if let tools = tools, !tools.isEmpty {
            b["tools"] = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
            b["tool_choice"] = "auto"
        }
        return b
    }

    func chat(system: String, history: [(String, String)] = [], user: String? = nil,
              maxTokens: Int = 120, completion: @escaping (String?) -> Void) {
        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for (r, c) in history { msgs.append(["role": r, "content": c]) }
        if let user { msgs.append(["role": "user", "content": user]) }
        post(["model": model, "messages": msgs, "max_tokens": maxTokens, "temperature": 1.0], timeout: 20) { data in
            DispatchQueue.main.async { completion(data.flatMap { Self.parseText($0) }) }
        }
    }
    func complete(messages: [AIMessage], tools: [ToolDef]?, maxTokens: Int = 800, completion: @escaping (LLMResult?) -> Void) {
        post(body(messages, tools, maxTokens, stream: false), timeout: 60) { data in
            DispatchQueue.main.async { completion(data.flatMap { Self.parseResult($0) }) }
        }
    }
    func completeStream(messages: [AIMessage], tools: [ToolDef]?, maxTokens: Int = 2000,
                        onDelta: @escaping (String) -> Void, completion: @escaping (LLMResult?) -> Void) {
        guard let req = makeRequest(body(messages, tools, maxTokens, stream: true), timeout: 120) else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        Log.write("→ STREAM \(name) model=\(model)")
        OpenAIStreamSession(onDelta: onDelta, onDone: completion).start(req)
    }
    func vision(prompt: String, imageBase64: String, completion: @escaping (String?) -> Void) {
        func done(_ s: String?) { DispatchQueue.main.async { completion(s) } }
        guard isConfigured, isOpenAI else { done(nil); return }   // DeepSeek no tiene visión
        let b: [String: Any] = ["model": model, "max_tokens": 1024, "temperature": 0.2, "messages": [[
            "role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]]]]]]
        post(b, timeout: 60) { data in done(data.flatMap { Self.parseText($0) }) }
    }
    func webSearch(_ query: String, completion: @escaping (String) -> Void) { WebTools.search(query, completion) }

    func test(completion: @escaping (Bool, String) -> Void) {
        guard let req = makeRequest(["model": model, "messages": [["role": "user", "content": "ping"]], "max_tokens": 8], timeout: 20) else {
            DispatchQueue.main.async { completion(false, "Falta la clave.") }; return
        }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(false, "Red: \(err.localizedDescription)"); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let snip = String((data.flatMap { String(data: $0, encoding: .utf8) } ?? "").prefix(220))
                if code == 200, let t = data.flatMap({ Self.parseText($0) }), !t.isEmpty { completion(true, "Conexión exitosa ✅ (\(t))") }
                else { completion(false, "HTTP \(code): \(snip)") }
            }
        }.resume()
    }

    static func parseText(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ch = json["choices"] as? [[String: Any]], let f = ch.first else { return nil }
        if let msg = f["message"] as? [String: Any], let s = msg["content"] as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    static func parseResult(_ data: Data) -> LLMResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ch = json["choices"] as? [[String: Any]], let f = ch.first,
              let msg = f["message"] as? [String: Any] else { return nil }
        var calls: [ToolCall] = []
        if let tcs = msg["tool_calls"] as? [[String: Any]] {
            for tc in tcs where tc["function"] != nil {
                let fn = tc["function"] as! [String: Any]
                calls.append(ToolCall(id: tc["id"] as? String ?? "", name: fn["name"] as? String ?? "",
                                      arguments: fn["arguments"] as? String ?? "{}"))
            }
        }
        return LLMResult(content: msg["content"] as? String, toolCalls: calls)
    }
}

// MARK: - Parser SSE para OpenAI / DeepSeek

final class OpenAIStreamSession: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    private var text = ""
    private var tools: [Int: (id: String, name: String, args: String)] = [:]
    private let onDelta: (String) -> Void
    private let onDone: (LLMResult?) -> Void
    private var session: URLSession?
    private var finished = false

    init(onDelta: @escaping (String) -> Void, onDone: @escaping (LLMResult?) -> Void) {
        self.onDelta = onDelta; self.onDone = onDone
    }
    func start(_ request: URLRequest) {
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session?.dataTask(with: request).resume()
    }
    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let r = buffer.firstRange(of: Data([0x0a])) {
            let line = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<r.upperBound)
            handle(String(data: line, encoding: .utf8) ?? "")
        }
    }
    private func handle(_ raw: String) {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { finishOnce(); return }
        guard let d = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let delta = first["delta"] as? [String: Any] else { return }
        if let c = delta["content"] as? String, !c.isEmpty { text += c; onDelta(c) }
        if let tcs = delta["tool_calls"] as? [[String: Any]] {
            for tc in tcs {
                let idx = tc["index"] as? Int ?? 0
                if tools[idx] == nil { tools[idx] = ("", "", "") }
                if let id = tc["id"] as? String { tools[idx]?.id = id }
                if let fn = tc["function"] as? [String: Any] {
                    if let n = fn["name"] as? String { tools[idx]?.name += n }
                    if let a = fn["arguments"] as? String { tools[idx]?.args += a }
                }
            }
        }
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil, !finished { finished = true; Log.write("STREAM error"); onDone(nil) }
        else { finishOnce() }
        session?.finishTasksAndInvalidate()
    }
    private func finishOnce() {
        guard !finished else { return }; finished = true
        let calls = tools.sorted { $0.key < $1.key }.map {
            ToolCall(id: $0.value.id, name: $0.value.name, arguments: $0.value.args.isEmpty ? "{}" : $0.value.args)
        }
        onDone(LLMResult(content: text.isEmpty ? nil : text, toolCalls: calls))
    }
}

// MARK: - Claude / Anthropic Messages API

final class AnthropicBackend: AIBackend {
    var config: AIConfig
    init(config: AIConfig) { self.config = config }

    var isClaude: Bool { config.provider == "claude" }
    var endpoint: String { isClaude ? "https://api.anthropic.com/v1/messages" : "https://api.minimax.io/anthropic/v1/messages" }
    var key: String { isClaude ? config.claudeKeyValue : config.apiKey }
    var model: String { isClaude ? config.claudeModelValue : config.model }
    var isConfigured: Bool { !key.trimmingCharacters(in: .whitespaces).isEmpty }

    private func post(_ body: [String: Any], timeout: TimeInterval, completion: @escaping (Data?) -> Void) {
        guard isConfigured, let url = URL(string: endpoint),
              let payload = try? JSONSerialization.data(withJSONObject: body) else {
            Log.write("post: sin clave o config inválida (provider=\(config.provider))"); completion(nil); return
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = payload
        Log.write("→ \(isClaude ? "Claude" : "MiniMax") POST \(endpoint) model=\(model) keyLen=\(key.count)")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if let err = err { Log.write("← ERROR \(err.localizedDescription)") }
            else { Log.write("← HTTP \(code) \(String((data.flatMap { String(data: $0, encoding: .utf8) } ?? "").prefix(400)))") }
            completion(err == nil ? data : nil)
        }.resume()
    }

    func chat(system: String, history: [(String, String)] = [], user: String? = nil,
              maxTokens: Int = 120, completion: @escaping (String?) -> Void) {
        var msgs: [[String: Any]] = []
        for (r, c) in history { msgs.append(["role": r == "assistant" ? "assistant" : "user", "content": c]) }
        if let user { msgs.append(["role": "user", "content": user]) }
        if msgs.isEmpty { msgs = [["role": "user", "content": " "]] }
        post(["model": model, "max_tokens": maxTokens, "system": system, "messages": msgs], timeout: 20) { data in
            DispatchQueue.main.async { completion(data.flatMap { Self.parse($0).content }) }
        }
    }

    /// Construye el body Anthropic (mensajes, system, tools, temperatura).
    private func anthropicBody(_ messages: [AIMessage], _ tools: [ToolDef]?, _ maxTokens: Int, stream: Bool) -> [String: Any] {
        var system = ""
        var msgs: [[String: Any]] = []
        var pending: [[String: Any]] = []
        func flush() { if !pending.isEmpty { msgs.append(["role": "user", "content": pending]); pending = [] } }
        for m in messages {
            switch m.role {
            case "system": system += (system.isEmpty ? "" : "\n") + m.content
            case "tool": pending.append(["type": "tool_result", "tool_use_id": m.toolCallId ?? "", "content": m.content])
            case "assistant":
                flush()
                var blocks: [[String: Any]] = []
                if !m.content.isEmpty { blocks.append(["type": "text", "text": m.content]) }
                for tc in m.toolCalls { blocks.append(["type": "tool_use", "id": tc.id, "name": tc.name, "input": jsonObject(tc.arguments)]) }
                msgs.append(["role": "assistant", "content": blocks.isEmpty ? [["type": "text", "text": " "]] : blocks])
            default:
                flush()
                if let img = m.imageBase64 {
                    msgs.append(["role": "user", "content": [
                        ["type": "text", "text": m.content],
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": img]]]])
                } else { msgs.append(["role": "user", "content": m.content]) }
            }
        }
        flush()
        var body: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system,
                                   "messages": msgs, "temperature": 0.3]
        if stream { body["stream"] = true }
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] }
        }
        return body
    }

    func complete(messages: [AIMessage], tools: [ToolDef]?, maxTokens: Int = 800,
                  completion: @escaping (LLMResult?) -> Void) {
        post(anthropicBody(messages, tools, maxTokens, stream: false), timeout: 60) { data in
            DispatchQueue.main.async { completion(data.map { Self.parse($0) }) }
        }
    }

    func completeStream(messages: [AIMessage], tools: [ToolDef]?, maxTokens: Int = 2000,
                        onDelta: @escaping (String) -> Void, completion: @escaping (LLMResult?) -> Void) {
        guard isConfigured, let url = URL(string: endpoint),
              let payload = try? JSONSerialization.data(withJSONObject: anthropicBody(messages, tools, maxTokens, stream: true)) else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = payload
        Log.write("→ STREAM \(isClaude ? "Claude" : "MiniMax") model=\(model)")
        StreamSession(onDelta: onDelta, onDone: completion).start(req)
    }

    /// Visión: Claude usa la Messages API con imagen; MiniMax usa /v1/coding_plan/vlm.
    func vision(prompt: String, imageBase64: String, completion: @escaping (String?) -> Void) {
        func done(_ s: String?) { DispatchQueue.main.async { completion(s) } }
        guard isConfigured else { done(nil); return }

        if isClaude {
            let body: [String: Any] = ["model": model, "max_tokens": 1024, "temperature": 0.2, "messages": [[
                "role": "user", "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": imageBase64]],
                ]]]]
            post(body, timeout: 60) { data in done(data.flatMap { Self.parse($0).content }) }
            return
        }
        // MiniMax VLM
        guard let url = URL(string: "https://api.minimax.io/v1/coding_plan/vlm"),
              let payload = try? JSONSerialization.data(withJSONObject:
                ["prompt": prompt, "image_url": "data:image/jpeg;base64,\(imageBase64)"]) else { done(nil); return }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.httpBody = payload
        Log.write("→ MiniMax VLM /v1/coding_plan/vlm")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            Log.write("← VLM HTTP \(code) \(String((data.flatMap { String(data: $0, encoding: .utf8) } ?? "").prefix(300)))")
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let c = json["content"] as? String, !c.isEmpty { done(c) } else { done(nil) }
        }.resume()
    }

    /// Búsqueda web: MiniMax usa /v1/coding_plan/search; Claude cae a DuckDuckGo.
    func webSearch(_ query: String, completion: @escaping (String) -> Void) {
        func done(_ s: String) { DispatchQueue.main.async { completion(s) } }
        if isClaude { WebTools.search(query) { done($0) }; return }
        guard isConfigured, let url = URL(string: "https://api.minimax.io/v1/coding_plan/search"),
              let payload = try? JSONSerialization.data(withJSONObject: ["q": query]) else {
            WebTools.search(query) { done($0) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.httpBody = payload
        Log.write("→ MiniMax SEARCH q=\(query)")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            Log.write("← SEARCH HTTP \(code) \(String((data.flatMap { String(data: $0, encoding: .utf8) } ?? "").prefix(160)))")
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let organic = json["organic"] as? [[String: Any]], !organic.isEmpty {
                var out = ""
                for (i, r) in organic.prefix(6).enumerated() {
                    out += "\(i + 1). \(r["title"] as? String ?? "")\n   \(r["snippet"] as? String ?? "")\n   \(r["link"] as? String ?? "")\n"
                }
                done(out)
            } else {
                WebTools.search(query) { done($0) }   // respaldo
            }
        }.resume()
    }

    func test(completion: @escaping (Bool, String) -> Void) {
        guard isConfigured else { DispatchQueue.main.async { completion(false, "Falta la clave del proveedor.") }; return }
        guard let url = URL(string: endpoint),
              let payload = try? JSONSerialization.data(withJSONObject:
                ["model": model, "max_tokens": 1024, "system": "Responde solo: ok",
                 "messages": [["role": "user", "content": "ping"]]]) else {
            DispatchQueue.main.async { completion(false, "Configuración inválida.") }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = payload
        Log.write("TEST → \(isClaude ? "Claude" : "MiniMax") \(endpoint) model=\(model) keyLen=\(key.count)")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { Log.write("TEST ← ERROR \(err.localizedDescription)"); completion(false, "Error de red: \(err.localizedDescription)"); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let snip = String(body.prefix(220))
                Log.write("TEST ← HTTP \(code) \(snip)")
                if code == 200 {
                    let t = data.map { Self.parse($0).content ?? "" } ?? ""
                    completion(!t.isEmpty, t.isEmpty ? "HTTP 200 pero sin texto. \(snip)" : "Conexión exitosa ✅ (\(t))")
                } else {
                    completion(false, "HTTP \(code) en \(self.endpoint)\n\(snip)")
                }
            }
        }.resume()
    }

    static func parse(_ data: Data) -> LLMResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else { return LLMResult(content: nil, toolCalls: []) }
        var text = ""; var calls: [ToolCall] = []
        for b in blocks {
            switch b["type"] as? String {
            case "text": text += (b["text"] as? String ?? "")
            case "tool_use":
                calls.append(ToolCall(id: b["id"] as? String ?? "", name: b["name"] as? String ?? "",
                                      arguments: jsonString(b["input"] ?? [:])))
            default: break
            }
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMResult(content: t.isEmpty ? nil : t, toolCalls: calls)
    }
}
