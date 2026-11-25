import Foundation
import WebKit

/// A self-check used by the automated simulator run (launch argument `-WitnessDiag YES`): once the page
/// has loaded, ask it what works in here and write the answers to Documents/diag.json. Never runs otherwise.
enum Diagnostics {
    private static var started = false

    static func runIfAsked(in webView: WKWebView) {
        if UserDefaults.standard.bool(forKey: "WitnessDiagSubs") { runSubtitleCheck(in: webView); return }
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

    /// Launch argument `-WitnessDiagSubs YES`: load the speech model in the subtitle worker the way
    /// the page does (GPU first, then CPU), log every stage with its time, transcribe one second of
    /// silence, and write Documents/subs.json. Takes minutes (it downloads the models).
    private static func runSubtitleCheck(in webView: WKWebView) {
        guard !started else { return }
        started = true
        let js = """
        const t0 = performance.now(), log = [];
        const note = (s) => log.push(Math.round((performance.now() - t0) / 100) / 10 + 's ' + s);
        note('gpu adapter: ' + await (async () => { try { const a = navigator.gpu && await navigator.gpu.requestAdapter(); return a ? ('yes' + (a.isFallbackAdapter || a.info?.isFallbackAdapter ? ' (fallback)' : '')) : 'none'; } catch (e) { return String(e); } })());
        note('crossOriginIsolated ' + crossOriginIsolated + ', cores ' + navigator.hardwareConcurrency);
        note('shared wasm memory: ' + [65536, 32768, 16384, 8192].map(mx => { try { new WebAssembly.Memory({ initial: 256, maximum: mx, shared: true }); return mx / 16 + ' MB ok'; } catch (e) { return mx / 16 + ' MB ' + e.name; } }).join(', '));
        const tryOne = (prefer) => new Promise(done => {
          const w = new Worker('./captions-worker.js', { type: 'module' });
          let lastPct = -1;
          const end = (r) => { clearTimeout(timer); w.terminate(); note(prefer + ': ' + r); done(r); };
          const timer = setTimeout(() => end('TIMEOUT'), 300000);
          w.onerror = e => end('worker error ' + (e.message || ''));
          w.onmessage = e => { const m = e.data;
            if (m.type === 'progress') { if (m.pct >= lastPct + 25 || m.pct === 100) { lastPct = m.pct; note(prefer + ' download ' + m.pct + '%'); } }
            else if (m.type === 'warming') note(prefer + ' warming up');
            else if (m.type === 'ready') { note(prefer + ' ready on ' + m.device); w.postMessage({ type: 'run', id: 1, audio: new Float32Array(16000) }); }
            else if (m.type === 'result') end('ok, transcribed ' + JSON.stringify(m.text));
            else if (m.type === 'error') end('error ' + m.message); };
          w.postMessage({ type: 'load', prefer, bundled: !!window.WITNESS_APP });
        });
        await tryOne('webgpu');
        await tryOne('wasm');
        return JSON.stringify(log);
        """
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            let text: String
            switch result {
            case .success(let v): text = (v as? String) ?? "[\"no result\"]"
            case .failure(let e): text = "[\"error: \(String(describing: e).replacingOccurrences(of: "\"", with: "'"))\"]"
            }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? text.write(to: dir.appendingPathComponent("subs.json"), atomically: true, encoding: .utf8)
            print("[Witness subs] \(text)")
        }
    }
}
