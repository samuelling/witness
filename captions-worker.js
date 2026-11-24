// Subtitle recogniser. Runs the Moonshine speech-to-text model on this device
// (WebGPU if the browser has it, otherwise WebAssembly) via Transformers.js.
// Audio comes in as 16 kHz mono Float32Array; text goes back. Nothing is sent
// anywhere: the only network traffic is the one-time model download.

// Pinned release, loaded from the jsDelivr CDN (as is the ONNX runtime it pulls in).
import { pipeline } from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.2/dist/transformers.min.js';

const MODEL = 'onnx-community/moonshine-base-ONNX';
const DTYPE = {
  webgpu: { encoder_model: 'fp32', decoder_model_merged: 'q4' },
  wasm: { encoder_model: 'fp32', decoder_model_merged: 'q8' },
};
let transcriber = null, device = 'wasm';

async function load(prefer) {
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
  let last = -1;
  const progress_callback = p => {
    if (p.status !== 'progress_total' || !p.total) return;
    const pct = Math.floor(p.loaded / p.total * 100);
    if (pct !== last) { last = pct; postMessage({ type: 'progress', pct, total: p.total }); }
  };
  const make = async dev => {
    const t = await pipeline('automatic-speech-recognition', MODEL, { device: dev, dtype: DTYPE[dev], progress_callback });
    postMessage({ type: 'warming' });
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

onmessage = async e => {
  const m = e.data;
  if (m.type === 'load') {
    load(m.prefer).catch(err => postMessage({ type: 'error', message: String(err?.message || err) }));
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
