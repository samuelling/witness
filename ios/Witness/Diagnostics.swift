import Foundation
import WebKit

/// A self-check used by the automated simulator run (launch argument `-WitnessDiag YES`): once the page
/// has loaded, ask it what works in here and write the answers to Documents/diag.json. Never runs otherwise.
enum Diagnostics {
    private static var started = false

    static func runIfAsked(in webView: WKWebView) {
        guard UserDefaults.standard.bool(forKey: "WitnessDiag"), !started else { return }
        started = true
        let js = """
        const out = { secureContext: isSecureContext, getUserMedia: !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia),
          mediaRecorder: typeof MediaRecorder, mp4: typeof MediaRecorder === 'function' && MediaRecorder.isTypeSupported('video/mp4;codecs=avc1.42E01E,mp4a.40.2'),
          webgpu: !!navigator.gpu, appFlag: window.WITNESS_APP || null, bridge: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.witness) };
        try { const ac = new (window.AudioContext || window.webkitAudioContext)();
          await Promise.all(['pitch-shifter', 'vocoder', 'speech-tap'].map(m => ac.audioWorklet.addModule('./' + m + '.js')));
          new AudioWorkletNode(ac, 'vocoder'); out.audioWorklets = 'ok'; ac.close(); } catch (e) { out.audioWorklets = String(e); }
        out.subtitleWorker = await new Promise(ok => { try { const w = new Worker('./captions-worker.js', { type: 'module' });
          w.onerror = e => ok('error: ' + (e.message || 'failed to load'));
          w.onmessage = e => { if (e.data.type === 'probe') { w.terminate(); ok('library ' + e.data.from); } };
          w.postMessage({ type: 'probe', bundled: true });
          setTimeout(() => { w.terminate(); ok('no answer after 20 s'); }, 20000); } catch (e) { ok(String(e)); } });
        for (let i = 0; i < 90 && !(document.documentElement.dataset.faces && document.documentElement.dataset.outline); i++) await new Promise(r => setTimeout(r, 500));
        out.faceDetector = document.documentElement.dataset.faces || 'not loaded after 45 s';
        out.personOutline = document.documentElement.dataset.outline || 'not loaded after 45 s';
        out.startScreen = !document.getElementById('start').hidden;
        return JSON.stringify(out);
        """
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            let text: String
            switch result {
            case .success(let v): text = (v as? String) ?? "{\"error\":\"no result\"}"
            case .failure(let e): text = "{\"error\":\"\(String(describing: e).replacingOccurrences(of: "\"", with: "'"))\"}"
            }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? text.write(to: dir.appendingPathComponent("diag.json"), atomically: true, encoding: .utf8)
            print("[Witness diag] \(text)")
        }
    }
}
