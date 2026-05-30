import Foundation
import AVFoundation
import Speech
import ScreenCaptureKit

// ============================================================================
// MeetingListener — transcribe ON-DEVICE (Speech.framework) dos fuentes de audio
// INDEPENDIENTES que comparten un mismo reconocedor:
//   • 👂 audio del SISTEMA (lo que oyes en Meet/Teams/Zoom) vía ScreenCaptureKit.
//   • 🎤 MICRÓFONO (tu voz) vía AVAudioEngine.
// Cada una se enciende/apaga por separado. El transcript acumulado lo resume el agente.
// macOS 13+.
//
// Nota legal: grabar/transcribir una reunión puede requerir el consentimiento de
// los participantes. La UI debe advertirlo; la responsabilidad es del usuario.
// ============================================================================

@available(macOS 13.0, *)
final class MeetingListener: NSObject, SCStreamDelegate, SCStreamOutput {

    static let shared = MeetingListener()

    // Estado por fuente (los dos iconos los reflejan).
    private(set) var systemOn = false      // 👂 audio del sistema
    private(set) var micOn = false         // 🎤 micrófono

    private(set) var transcript = ""
    private var partial = ""

    /// Compat: "isListening" = la escucha del SISTEMA (👂 / la reunión). El mic es aparte.
    var isListening: Bool { systemOn }

    /// Alias de compatibilidad para el flujo de reunión existente (= audio del sistema).
    func start(completion: @escaping (Bool, String?) -> Void) { startSystem(completion: completion) }

    // Pipeline de reconocimiento (compartido por ambas fuentes).
    private var pipelineActive = false
    private let appendLock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var rotateTimer: Timer?

    // Fuente: sistema (ScreenCaptureKit).
    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "co.cristiangarcia.flubber.audio")
    private var sysConverter: AVAudioConverter?

    // Fuente: micrófono (AVAudioEngine).
    private var engine: AVAudioEngine?
    private var micConverter: AVAudioConverter?

    // El reconocedor quiere mono/16kHz; ambas fuentes se convierten a este formato.
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!

    /// Texto completo (segmentos finales + lo que se está reconociendo ahora).
    var fullText: String {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        return (transcript + (p.isEmpty ? "" : p)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Pipeline de reconocimiento

    /// Pide permiso de Speech y arranca el reconocedor si no estaba activo.
    private func ensurePipeline(_ completion: @escaping (Bool, String?) -> Void) {
        if pipelineActive { completion(true, nil); return }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    completion(false, Loc.t("Falta permiso de reconocimiento de voz (Ajustes → Privacidad).",
                                            "Missing speech-recognition permission (Settings → Privacy)."))
                    return
                }
                let id = Loc.isES ? "es-ES" : "en-US"
                self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: id)) ?? SFSpeechRecognizer()
                guard let rec = self.recognizer, rec.isAvailable else {
                    completion(false, Loc.t("Reconocimiento de voz no disponible.", "Speech recognition unavailable."))
                    return
                }
                self.startChunk()
                self.pipelineActive = true
                self.rotateTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in self?.rotateChunk() }
                Log.write("🎧 pipeline ON locale=\(id) onDevice=\(rec.supportsOnDeviceRecognition)")
                completion(true, nil)
            }
        }
    }

    private func teardownIfIdle() {
        guard !systemOn, !micOn, pipelineActive else { return }
        pipelineActive = false
        rotateTimer?.invalidate(); rotateTimer = nil
        appendLock.lock(); request?.endAudio(); appendLock.unlock()
        task?.finish()
        request = nil; task = nil
        Log.write("🎧 pipeline OFF — transcript=\(fullText.count) chars")
    }

    private func startChunk() {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
        appendLock.lock(); request = req; appendLock.unlock()
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.partial = result.bestTranscription.formattedString
                if result.isFinal {
                    let seg = self.partial.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seg.isEmpty { self.transcript += seg + " " }
                    self.partial = ""
                }
            }
            if error != nil, self.pipelineActive { self.startChunk() }   // expiró → reanuda
        }
    }

    private func rotateChunk() {
        guard pipelineActive else { return }
        appendLock.lock(); request?.endAudio(); appendLock.unlock()
        startChunk()
    }

    private func append(_ buf: AVAudioPCMBuffer) {
        appendLock.lock(); request?.append(buf); appendLock.unlock()
    }

    /// Convierte un buffer a 16kHz mono (un convertidor por fuente para no recrearlo).
    private func convert(_ input: AVAudioPCMBuffer, _ conv: inout AVAudioConverter?) -> AVAudioPCMBuffer? {
        if conv == nil || conv?.inputFormat != input.format { conv = AVAudioConverter(from: input.format, to: targetFormat) }
        guard let c = conv else { return nil }
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let cap = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        c.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return input
        }
        return (err == nil && out.frameLength > 0) ? out : nil
    }

    // MARK: - 👂 Fuente: audio del sistema (ScreenCaptureKit)

    func startSystem(completion: @escaping (Bool, String?) -> Void) {
        guard !systemOn else { completion(true, nil); return }
        ensurePipeline { ok, err in
            guard ok else { completion(false, err); return }
            Task { await self.beginSystemCapture(completion: completion) }
        }
    }

    @MainActor
    private func beginSystemCapture(completion: @escaping (Bool, String?) -> Void) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                completion(false, Loc.t("No encontré la pantalla para capturar audio.", "No display found for audio capture.")); return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000; config.channelCount = 2
            config.width = 2; config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 6)
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)
            try await s.startCapture()
            self.stream = s
            self.systemOn = true
            Log.write("🎧 sistema ON (48kHz/2ch)")
            completion(true, nil)
        } catch {
            Log.write("🎧 ERROR sistema: \(error.localizedDescription)")
            teardownIfIdle()
            completion(false, Loc.t("No pude capturar el audio del sistema: ", "Couldn't capture system audio: ") + error.localizedDescription)
        }
    }

    func stopSystem() {
        guard systemOn else { return }
        systemOn = false
        if let s = stream { Task { try? await s.stopCapture() } }
        stream = nil
        teardownIfIdle()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, systemOn, sampleBuffer.isValid else { return }
        guard let pcm = MeetingListener.pcmBuffer(from: sampleBuffer),
              let mono = convert(pcm, &sysConverter) else { return }
        append(mono)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.stopSystem() }
    }

    // MARK: - 🎤 Fuente: micrófono (AVAudioEngine)

    func startMic(completion: @escaping (Bool, String?) -> Void) {
        guard !micOn else { completion(true, nil); return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                guard granted else {
                    completion(false, Loc.t("Falta permiso de micrófono (Ajustes → Privacidad).",
                                            "Missing microphone permission (Settings → Privacy).")); return
                }
                self.ensurePipeline { ok, err in
                    guard ok else { completion(false, err); return }
                    do {
                        let engine = AVAudioEngine()
                        let input = engine.inputNode
                        let fmt = input.outputFormat(forBus: 0)
                        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
                            guard let self = self, self.micOn else { return }
                            if let mono = self.convert(buf, &self.micConverter) { self.append(mono) }
                        }
                        engine.prepare()
                        try engine.start()
                        self.engine = engine
                        self.micOn = true
                        Log.write("🎤 micrófono ON (\(Int(fmt.sampleRate))Hz ch=\(fmt.channelCount))")
                        completion(true, nil)
                    } catch {
                        Log.write("🎤 ERROR micrófono: \(error.localizedDescription)")
                        self.teardownIfIdle()
                        completion(false, Loc.t("No pude abrir el micrófono: ", "Couldn't open the mic: ") + error.localizedDescription)
                    }
                }
            }
        }
    }

    func stopMic() {
        guard micOn else { return }
        micOn = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        teardownIfIdle()
    }

    // MARK: - Compat / utilidades

    func stop() { stopSystem(); stopMic() }          // apaga todo

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }
}
