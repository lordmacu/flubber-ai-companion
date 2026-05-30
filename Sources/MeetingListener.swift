import Foundation
import AVFoundation
import Speech
import ScreenCaptureKit

// ============================================================================
// MeetingListener — escucha el AUDIO DEL SISTEMA (lo que oyes en una reunión de
// Meet/Teams/Zoom) con ScreenCaptureKit y lo transcribe ON-DEVICE con Speech.framework.
// Mantiene un transcript acumulado que el agente puede resumir. macOS 13+.
//
// Nota legal: grabar/transcribir una reunión puede requerir el consentimiento de
// los participantes. La UI debe advertirlo; la responsabilidad es del usuario.
// ============================================================================

@available(macOS 13.0, *)
final class MeetingListener: NSObject, SCStreamDelegate, SCStreamOutput {

    static let shared = MeetingListener()

    private(set) var isListening = false
    private(set) var transcript = ""
    private var partial = ""

    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "co.cristiangarcia.flubber.audio")
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var rotateTimer: Timer?
    private var startedAt = Date()
    private var audioBuffers = 0          // cuántos buffers de audio han llegado (diagnóstico)
    private var loggedFirstPartial = false

    // SFSpeechRecognizer necesita el audio en mono/16kHz; ScreenCaptureKit lo
    // entrega en 48kHz estéreo → convertimos cada buffer con AVAudioConverter.
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private var loggedConvErr = false

    /// Texto completo (segmentos finales + lo que se está reconociendo ahora).
    var fullText: String {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        return (transcript + (p.isEmpty ? "" : p)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: arranque / parada

    func start(completion: @escaping (Bool, String?) -> Void) {
        guard !isListening else { completion(true, nil); return }
        Log.write("🎧 listen.start — pidiendo permiso de Speech…")
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                Log.write("🎧 Speech auth status=\(status.rawValue) (3=authorized, 2=denied, 1=restricted, 0=notDetermined)")
                guard status == .authorized else {
                    completion(false, Loc.t("Falta permiso de reconocimiento de voz (Ajustes → Privacidad).",
                                            "Missing speech-recognition permission (Settings → Privacy)."))
                    return
                }
                let id = Loc.isES ? "es-ES" : "en-US"
                self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: id)) ?? SFSpeechRecognizer()
                guard let rec = self.recognizer, rec.isAvailable else {
                    Log.write("🎧 recognizer NO disponible (rec=\(self.recognizer != nil), available=\(self.recognizer?.isAvailable ?? false))")
                    completion(false, Loc.t("Reconocimiento de voz no disponible.", "Speech recognition unavailable."))
                    return
                }
                Log.write("🎧 recognizer OK locale=\(id) onDevice=\(rec.supportsOnDeviceRecognition)")
                Task { await self.beginCapture(completion: completion) }
            }
        }
    }

    @MainActor
    private func beginCapture(completion: @escaping (Bool, String?) -> Void) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            Log.write("🎧 SCShareableContent — displays=\(content.displays.count)")
            guard let display = content.displays.first else {
                Log.write("🎧 sin display para capturar audio")
                completion(false, Loc.t("No encontré la pantalla para capturar audio.", "No display found for audio capture."))
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true     // no capturar los sonidos del propio Flubber
            config.sampleRate = 48_000
            config.channelCount = 2
            // SCK exige algo de vídeo aunque solo queramos audio: lo dejamos mínimo.
            config.width = 2; config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 6)

            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)   // requerido por SCK; lo ignoramos
            try await s.startCapture()
            self.stream = s

            audioBuffers = 0
            loggedFirstPartial = false
            loggedConvErr = false
            converter = nil
            startChunk()
            startedAt = Date()
            isListening = true
            rotateTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in self?.rotateChunk() }
            Log.write("🎧 SCStream capturando audio ✅ (48kHz/2ch, excluye audio propio). Listening=true")
            completion(true, nil)
        } catch {
            Log.write("🎧 ERROR beginCapture: \(error.localizedDescription)")
            completion(false, Loc.t("No pude iniciar la captura de audio: ", "Couldn't start audio capture: ") + error.localizedDescription)
        }
    }

    func stop() {
        guard isListening else { return }
        Log.write("🎧 listen.stop — buffers de audio=\(audioBuffers), transcript=\(fullText.count) chars")
        isListening = false
        rotateTimer?.invalidate(); rotateTimer = nil
        request?.endAudio()
        task?.finish()
        request = nil; task = nil
        if let s = stream { Task { try? await s.stopCapture() } }
        stream = nil
    }

    // MARK: reconocimiento por bloques (Speech.framework limita la duración por petición)

    private func startChunk() {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
        request = req
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.partial = result.bestTranscription.formattedString
                if !self.loggedFirstPartial, !self.partial.isEmpty {
                    self.loggedFirstPartial = true
                    Log.write("🎧 primer parcial reconocido: \"\(self.partial.prefix(60))\"")
                }
                if result.isFinal {
                    let seg = self.partial.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seg.isEmpty { self.transcript += seg + " "; Log.write("🎧 segmento: \"\(seg.prefix(60))\"") }
                    self.partial = ""
                }
            }
            if let error = error {
                Log.write("🎧 recognitionTask error: \(error.localizedDescription)")
                if self.isListening {
                    // la petición terminó/expiró: arranca otra para seguir escuchando
                    self.startChunk()
                }
            }
        }
    }

    /// Cierra el bloque actual (vuelca su texto a `transcript`) y abre uno nuevo.
    private func rotateChunk() {
        guard isListening else { return }
        request?.endAudio()
        // el callback con isFinal volcará el texto; abrimos el nuevo bloque enseguida
        startChunk()
    }

    // MARK: salida de ScreenCaptureKit

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isListening, sampleBuffer.isValid else { return }
        guard let pcm = MeetingListener.pcmBuffer(from: sampleBuffer) else { return }
        audioBuffers += 1
        if audioBuffers == 1 {
            Log.write("🎧 primer buffer de audio ✅ formato origen: \(Int(pcm.format.sampleRate))Hz ch=\(pcm.format.channelCount) interleaved=\(pcm.format.isInterleaved)")
        }
        // Convierte a mono/16kHz antes de dárselo al reconocedor.
        guard let mono = convertToTarget(pcm) else { return }
        request?.append(mono)
        if audioBuffers % 250 == 0 { Log.write("🎧 audio buffers=\(audioBuffers), transcript=\(transcript.count) chars") }
    }

    /// Convierte un buffer (48kHz estéreo) al formato del reconocedor (16kHz mono).
    private func convertToTarget(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter == nil || converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: targetFormat)
        }
        guard let conv = converter else { return nil }
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let cap = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return input
        }
        if let err = err, !loggedConvErr {
            loggedConvErr = true
            Log.write("🎧 AVAudioConverter error: \(err.localizedDescription)")
        }
        if audioBuffers == 1 {
            Log.write("🎧 buffer convertido: frames=\(out.frameLength) → \(Int(targetFormat.sampleRate))Hz mono")
        }
        return out.frameLength > 0 ? out : nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.stop() }
    }

    /// Convierte un CMSampleBuffer de audio a AVAudioPCMBuffer (formato nativo del buffer).
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
