import AVFoundation
import Speech
import WebKit

/// Live subtitles in the app, using iOS's own speech recogniser on the device (no download, nothing
/// sent off the phone). The page already splits the microphone into phrases and resamples it to
/// 16 kHz mono for its subtitle engine; in the app it hands those phrases here instead.
///
/// Page → app (message handler "witness", type "stt"):
///   { op: "start" }                       ask permission, check on-device support, answer "ready" or "error"
///   { op: "begin", utt }                  a phrase starts
///   { op: "audio", utt, pcm }             100 ms of 16 kHz mono, little-endian Int16, base64
///   { op: "end", utt }                    the phrase is over: finish it
///   { op: "stop" }                        subtitles switched off
/// App → page: window.witnessNativeSpeech({ type: "ready" | "error" | "result", ... })
final class NativeSpeech {
    private weak var webView: WKWebView?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var utt = 0
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    init(webView: WKWebView?) { self.webView = webView }

    func handle(_ body: [String: Any]) {
        switch body["op"] as? String {
        case "start": start()
        case "begin": begin(utt: body["utt"] as? Int ?? 0)
        case "audio":
            if let b64 = body["pcm"] as? String, let data = Data(base64Encoded: b64), body["utt"] as? Int == utt { append(data) }
        case "end": if body["utt"] as? Int == utt { request?.endAudio() }
        case "stop": cancel()
        default: break
        }
    }

    // MARK: - setup

    private func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    let why = status == .denied || status == .restricted
                        ? "Speech recognition is turned off for Witness. Turn it on in Settings › Witness."
                        : "Speech recognition isn't available."
                    return self.send(["type": "error", "message": why])
                }
                // The phone's language if it can be recognised on the device, otherwise US English.
                let candidates = [SFSpeechRecognizer(), SFSpeechRecognizer(locale: Locale(identifier: "en-US"))]
                guard let r = candidates.compactMap({ $0 }).first(where: { $0.supportsOnDeviceRecognition && $0.isAvailable }) else {
                    return self.send(["type": "error", "message": "This device can't transcribe speech offline."])
                }
                self.recognizer = r
                self.send(["type": "ready", "device": "ios", "locale": r.locale.identifier])
            }
        }
    }

    // MARK: - phrases

    private func begin(utt: Int) {
        cancel()
        guard let recognizer else { return }
        self.utt = utt
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true          // never sent to Apple's servers
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if #available(iOS 16, *) { req.addsPunctuation = true }
        request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.send(["type": "result", "utt": utt, "final": result.isFinal,
                               "text": result.bestTranscription.formattedString])
                } else if error != nil {
                    // No speech recognised in this phrase (or it was cancelled): an empty final result.
                    self.send(["type": "result", "utt": utt, "final": true, "text": ""])
                }
            }
        }
    }

    private func append(_ data: Data) {
        guard let request else { return }
        let n = data.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]
        data.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self)
            for i in 0..<n { out[i] = Float(Int16(littleEndian: s[i])) / 32768 }
        }
        request.append(buf)
    }

    private func cancel() {
        task?.cancel(); task = nil
        request = nil
    }

    // MARK: - reply

    private func send(_ msg: [String: Any]) {
        guard let webView, let json = try? JSONSerialization.data(withJSONObject: msg),
              let s = String(data: json, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.witnessNativeSpeech && window.witnessNativeSpeech(\(s))")
    }
}
