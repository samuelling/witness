// Channel vocoder voice mask.
//
// The voice is split into bands and only each band's loudness over time is
// kept. Those loudness curves then shape the same bands of a synthetic
// carrier: a fixed-pitch sawtooth buzz, with hiss mixed in (more of it in the
// top bands, so "s" and "sh" survive). The words come through; the speaker's
// own pitch and melody are thrown away, which a pitch shift alone doesn't do.

const NB = 18, F_LO = 110, F_HI = 7600, Q = 4.2;

class Vocoder extends AudioWorkletProcessor {
  static get parameterDescriptors() {
    return [
      { name: 'on', defaultValue: 0, minValue: 0, maxValue: 1, automationRate: 'k-rate' },
      { name: 'freq', defaultValue: 98, minValue: 30, maxValue: 400, automationRate: 'k-rate' },
      { name: 'breath', defaultValue: 0.15, minValue: 0, maxValue: 1, automationRate: 'k-rate' },
    ];
  }

  constructor() {
    super();
    const sr = sampleRate;
    this.fc = new Float32Array(NB); this.b0 = new Float32Array(NB); this.a1 = new Float32Array(NB); this.a2 = new Float32Array(NB);
    this.bw = new Float32Array(NB);       // noise-equivalent bandwidth of the two-stage filter, Hz
    this.hiss = new Float32Array(NB);     // how much hiss this band always gets
    for (let b = 0; b < NB; b++) {
      const fc = F_LO * (F_HI / F_LO) ** (b / (NB - 1));
      const w = 2 * Math.PI * fc / sr, alpha = Math.sin(w) / (2 * Q), a0 = 1 + alpha;
      this.fc[b] = fc; this.b0[b] = alpha / a0; this.a1[b] = -2 * Math.cos(w) / a0; this.a2[b] = (1 - alpha) / a0;
      this.bw[b] = Math.PI / 4 * fc / Q;
      const t = Math.min(1, Math.max(0, (fc - 2200) / (5500 - 2200)));
      this.hiss[b] = 0.75 * t * t * (3 - 2 * t);
    }
    // Filter state: two cascaded band-passes each for analysis (voice) and synthesis (carrier).
    this.za = new Float64Array(NB * 4); this.zs = new Float64Array(NB * 4);
    this.env = new Float32Array(NB); this.env2 = new Float32Array(NB);
    this.gSaw = new Float32Array(NB); this.gNoise = new Float32Array(NB);
    this.att = 1 - Math.exp(-1 / (0.003 * sr)); this.rel = 1 - Math.exp(-1 / (0.020 * sr));
    this.sm = 1 - Math.exp(-1 / (0.006 * sr));   // second smoothing pass: irons out the speaker's pitch pulses
    this.phase = 0; this.f = 98; this.seed = 22222;
  }

  process(inputs, outputs, params) {
    const out = outputs[0], oL = out[0], oR = out[1] || out[0], n = oL.length;
    if (params.on[0] < 0.5) return true;                       // idle: emit silence, cost nothing
    const inp = inputs[0], iL = inp[0], iR = inp[1] || inp[0];
    const sr = sampleRate, breath = params.breath[0];
    this.f += (params.freq[0] - this.f) * 0.2;
    const f0 = this.f, dt = f0 / sr;
    const { b0, a1, a2, za, zs, env, env2, gSaw, gNoise, att, rel, sm } = this;

    // Give every band a carrier of equal power, so the voice's envelopes alone set the spectrum.
    for (let b = 0; b < NB; b++) {
      const nm = breath + (1 - breath) * this.hiss[b];
      const pSaw = 2 * this.bw[b] * f0 / (Math.PI * Math.PI * this.fc[b] * this.fc[b]);
      const pNoise = 2 * this.bw[b] / (3 * sr);
      gSaw[b] = Math.sqrt((1 - nm) / pSaw); gNoise[b] = Math.sqrt(nm / pNoise);
    }

    for (let s = 0; s < n; s++) {
      const x = iL ? 0.5 * (iL[s] + iR[s]) : 0;

      // band-limited sawtooth
      let ph = this.phase + dt; if (ph >= 1) ph -= 1; this.phase = ph;
      let saw = 2 * ph - 1;
      if (ph < dt) { const t = ph / dt; saw -= t + t - t * t - 1; }
      else if (ph > 1 - dt) { const t = (ph - 1) / dt; saw -= t * t + t + t + 1; }
      this.seed = (this.seed * 1664525 + 1013904223) >>> 0;
      const noise = this.seed / 2147483648 - 1;

      let y = 0;
      for (let b = 0, k = 0; b < NB; b++, k += 4) {
        const B = b0[b], A1 = a1[b], A2 = a2[b];
        // voice → band → loudness
        let v = B * x + za[k]; za[k] = za[k + 1] - A1 * v; za[k + 1] = -B * x - A2 * v;
        let u = B * v + za[k + 2]; za[k + 2] = za[k + 3] - A1 * u; za[k + 3] = -B * v - A2 * u;
        u = u < 0 ? -u : u;
        env[b] += (u - env[b]) * (u > env[b] ? att : rel);
        env2[b] += (env[b] - env2[b]) * sm;
        // carrier → same band → scaled by that loudness
        const c = saw * gSaw[b] + noise * gNoise[b];
        v = B * c + zs[k]; zs[k] = zs[k + 1] - A1 * v; zs[k + 1] = -B * c - A2 * v;
        u = B * v + zs[k + 2]; zs[k + 2] = zs[k + 3] - A1 * u; zs[k + 3] = -B * v - A2 * u;
        y += u * env2[b];
      }
      y = Math.tanh(1.3 * y);
      oL[s] = y; if (oR !== oL) oR[s] = y;
    }
    return true;
  }
}

registerProcessor('vocoder', Vocoder);
