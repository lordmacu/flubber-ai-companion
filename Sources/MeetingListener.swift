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

    /// Texto completo (segmentos finales + lo que se está reconociendo ahora).
    var fullText: String {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        return (transcript + (p.isEmpty ? "" : p)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: arranque / parada

    func start(completion: @escaping (Bool, String?) -> Void) {
        guard !isListening else { completion(true, nil); return }
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
                Task { await self.beginCapture(completion: completion) }
            }
        }
    }

    @MainActor
    private func beginCapture(completion: @escaping (Bool, String?) -> Void) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
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

            startChunk()
            startedAt = Date()
            isListening = true
            rotateTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in self?.rotateChunk() }
            completion(true, nil)
        } catch {
            completion(false, Loc.t("No pude iniciar la captura de audio: ", "Couldn't start audio capture: ") + error.localizedDescription)
        }
    }

    func stop() {
        guard isListening else { return }
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
                if result.isFinal {
                    let seg = self.partial.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seg.isEmpty { self.transcript += seg + " " }
                    self.partial = ""
                }
            }
            if error != nil, self.isListening {
                // la petición terminó/expiró: arranca otra para seguir escuchando
                self.startChunk()
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
        if let pcm = MeetingListener.pcmBuffer(from: sampleBuffer) {
            request?.append(pcm)
        }
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
