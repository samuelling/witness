// Subtitle recogniser. Runs the Moonshine speech-to-text model on this device
// (WebGPU if the browser has it, otherwise WebAssembly) via Transformers.js.
// Audio comes in as 16 kHz mono Float32Array; text goes back. Nothing is sent
// anywhere: the only network traffic is the one-time model download (and, on the website,
// the library itself).

// Transformers.js 4.3.2 and the ONNX runtime build it uses. The website loads them from the
// jsDelivr CDN; the iPhone/iPad app bundles the same pinned files in vendor/transformers/
// (see ios/tools/fetch_transformers.sh), so the app downloads no code, only the model.
const CDN = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.2/dist/transformers.min.js';
const BUNDLED = new URL('./vendor/transformers/', import.meta.url).href;
let lib = null, libFrom = null;
async function library(bundled) {
  if (lib) return lib;
  if (bundled) {
    lib = await import(BUNDLED + 'transformers.min.js');
    lib.env.backends.onnx.wasm.wasmPaths = BUNDLED;     // the runtime's .mjs and .wasm sit next to it
    libFrom = 'bundled';
  } else {
    lib = await import(CDN);
    libFrom = 'cdn';
  }
  return lib;
}

// With a GPU: Moonshine Base (about 155 MB). Without one everything runs on a single CPU thread,
// so use Moonshine Tiny (about 50 MB): roughly twice as fast and far lighter on memory.
const SETUP = {
  webgpu: { model: 'onnx-community/moonshine-base-ONNX', mb: 155, dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' } },
  wasm: { model: 'onnx-community/moonshine-tiny-ONNX', mb: 51, dtype: { encoder_model: 'fp32', decoder_model_merged: 'q8' } },
};
let transcriber = null, device = 'wasm';

async function load(prefer, bundled) {
  const { pipeline } = await library(bundled);
  // Use the GPU only if it is a real one: a software-emulated adapter is far slower than WebAssembly.
  // (?stt=wasm or ?stt=webgpu on the page address forces one or the other.)
  device = 'wasm';
  if (prefer === 'webgpu') device = 'webgpu';
  else if (prefer !== 'wasm') {
    try {
      const adapter = navigator.gpu && await navigator.gpu.requestAdapter();
      if (adapter && !(adapter.isFallbackAdapter || adapter.info?.isFallbackAdapter)) device = 'webgpu';
    } catch {}
  }
  const make = async dev => {
    postMessage({ type: 'device', device: dev, mb: SETUP[dev].mb });
    // Add up the two model files actually being fetched. (The library's own running total also
    // counts a file it never downloads, so it stalls short of 100%.)
    const files = {}; let last = -1;
    const progress_callback = p => {
      if (!/\.onnx$/.test(p.file || '')) return;
      if (p.status === 'progress' && p.total) files[p.file] = [p.loaded, p.total];
      else if (p.status === 'done' && files[p.file]) files[p.file][0] = files[p.file][1];
      else return;
      let loaded = 0, total = 0;
      for (const [l, t] of Object.values(files)) { loaded += l; total += t; }
      if (Object.keys(files).length < 2) total = Math.max(total, SETUP[dev].mb * 1e6);    // the second file hasn't started yet
      const pct = Math.floor(loaded / total * 100);
      if (pct !== last) { last = pct; postMessage({ type: 'progress', pct, mb: SETUP[dev].mb }); }
    };
    const t = await pipeline('automatic-speech-recognition', SETUP[dev].model, { device: dev, dtype: SETUP[dev].dtype, progress_callback });
    postMessage({ type: 'warming', device: dev });
    await t(new Float32Array(16000), { max_new_tokens: 4 });      // compile shaders / warm up
    return t;
  };
  try { transcriber = await make(device); }
  catch (e) {
    if (device !== 'webgpu') throw e;
    console.warn('WebGPU speech model failed, falling back to WebAssembly', e);
    device = 'wasm'; transcriber = await make('wasm');
  }
  postMessage({ type: 'ready', device });
}

// Anything that goes wrong outside a try block still reaches the page.
addEventListener('unhandledrejection', e => postMessage({ type: 'error', message: String(e.reason?.message || e.reason) }));

onmessage = async e => {
  const m = e.data;
  if (m.type === 'load') {
    load(m.prefer, m.bundled).catch(err => postMessage({ type: 'error', message: String(err?.message || err) }));
  } else if (m.type === 'probe') {
    // Self-check for the app: can the library load (from where), without fetching a model?
    library(m.bundled).then(() => postMessage({ type: 'probe', from: libFrom }), err => postMessage({ type: 'probe', from: 'error: ' + (err?.message || err) }));
  } else if (m.type === 'run') {
    let text = '';
    try {
      // Cap the output length to what could plausibly be said in this much audio;
      // without a cap the model can loop on noise.
      const max_new_tokens = Math.max(6, Math.ceil(m.audio.length / 16000 * 6.5));
      ({ text } = await transcriber(m.audio, { max_new_tokens }));
    } catch (err) { console.warn(err); }
    postMessage({ type: 'result', id: m.id, utt: m.utt, final: m.final, text: (text || '').trim() });
  }
};
