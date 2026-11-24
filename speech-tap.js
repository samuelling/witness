// Taps the raw voice for the subtitle recogniser: mixes to mono, resamples to
// 16 kHz, and posts 100 ms blocks to the page. Produces no sound of its own.

class SpeechTap extends AudioWorkletProcessor {
  constructor() {
    super();
    this.on = false;
    this.port.onmessage = e => { this.on = !!e.data.on; };
    this.step = sampleRate / 16000;      // input samples per output sample
    this.t = 0; this.prev = 0;
    this.block = new Float32Array(1600); this.n = 0;
    // Two-stage low-pass at 7 kHz so the downsampling doesn't alias.
    this.lp = [0.5412, 1.3066].map(q => {
      const w = 2 * Math.PI * Math.min(7000, sampleRate * 0.45) / sampleRate, a = Math.sin(w) / (2 * q), c = Math.cos(w), a0 = 1 + a;
      return { b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - a) / a0, z1: 0, z2: 0 };
    });
  }

  process(inputs) {
    const inp = inputs[0];
    if (!this.on || !inp.length) return true;
    const L = inp[0], R = inp[1] || L, n = L.length;
    for (let i = 0; i < n; i++) {
      let x = 0.5 * (L[i] + R[i]);
      for (const f of this.lp) { const y = f.b0 * x + f.z1; f.z1 = f.b1 * x - f.a1 * y + f.z2; f.z2 = f.b2 * x - f.a2 * y; x = y; }
      while (this.t <= 1) {
        this.block[this.n++] = this.prev + (x - this.prev) * this.t;
        if (this.n === this.block.length) { this.port.postMessage(this.block.slice()); this.n = 0; }
        this.t += this.step;
      }
      this.t -= 1; this.prev = x;
    }
    return true;
  }
}

registerProcessor('speech-tap', SpeechTap);
