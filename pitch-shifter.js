// Real-time pitch shifter (speed unchanged), in the style of the delay-line
// "harmonizer" boxes TV newsrooms used to disguise voices.
//
// Two read heads trail the write head through a ring buffer. Each head reads
// at `ratio` × speed, so its delay drifts; before a head runs out of room it
// is faded out, jumped back, and faded in again while the other head covers.
// The jump target is chosen by correlation so the two heads line up on the
// waveform (a "de-glitched" splice) instead of beating against each other.

class PitchShifter extends AudioWorkletProcessor {
  static get parameterDescriptors() {
    return [{ name: 'ratio', defaultValue: 0.75, minValue: 0.4, maxValue: 2.5, automationRate: 'k-rate' }];
  }

  constructor() {
    super();
    const sr = sampleRate;
    this.N = 1 << Math.ceil(Math.log2(sr * 0.5));
    this.mask = this.N - 1;
    this.bufL = new Float32Array(this.N);
    this.bufR = new Float32Array(this.N);
    this.bufM = new Float32Array(this.N);   // mono mix, used for splice search
    this.w = 0;                             // index of newest sample
    this.W = Math.round(sr * 0.060);        // delay sweep per cycle
    this.S = Math.round(sr * 0.014);        // splice search range (≥ one period at ~72 Hz)
    this.C = Math.round(sr * 0.020);        // correlation window
    this.dMin = 4;
    this.p = 0;                             // crossfade phase, 0..1
    this.dA = this.dMin;
    this.dB = this.dMin + this.W / 2;
  }

  // Pick a delay in [base, base+S] whose recent waveform best matches what
  // the other head (at delay dOther) is reading right now.
  splice(base, dOther) {
    const M = this.bufM, mask = this.mask, w = this.w, C = this.C;
    const o = w - Math.round(dOther);
    let best = base, bestScore = -Infinity;
    for (let c = base; c <= base + this.S; c += 2) {
      const k = w - c;
      let dot = 0, en = 1e-9;
      for (let j = 0; j < C; j += 4) {
        const a = M[(k - j) & mask];
        dot += a * M[(o - j) & mask];
        en += a * a;
      }
      const score = dot / Math.sqrt(en);
      if (score > bestScore) { bestScore = score; best = c; }
    }
    return best;
  }

  read(buf, d) {
    const pos = this.w - d;
    const i = Math.floor(pos);
    const f = pos - i;
    const a = buf[i & this.mask], b = buf[(i + 1) & this.mask];
    return a + (b - a) * f;
  }

  process(inputs, outputs, params) {
    const inp = inputs[0], out = outputs[0];
    const oL = out[0], oR = out[1] || out[0];
    const iL = inp[0], iR = inp[1] || inp[0];
    const n = oL.length;
    const ratio = params.ratio[0];
    const dr = 1 - ratio;                    // delay drift per sample
    const bypass = Math.abs(dr) < 1e-4;
    const dp = Math.abs(dr) / this.W;
    const base = dr > 0 ? this.dMin : this.dMin + this.W;
    const { bufL, bufR, bufM, mask } = this;

    for (let s = 0; s < n; s++) {
      const l = iL ? iL[s] : 0, r = iR ? iR[s] : 0;
      this.w = (this.w + 1) & mask;
      bufL[this.w] = l; bufR[this.w] = r; bufM[this.w] = 0.5 * (l + r);

      if (bypass) { oL[s] = l; if (oR !== oL) oR[s] = r; continue; }

      const prev = this.p;
      this.p += dp;
      if (this.p >= 1) { this.p -= 1; this.dA = this.splice(base, this.dB); }
      else if (prev < 0.5 && this.p >= 0.5) { this.dB = this.splice(base, this.dA); }

      const sn = Math.sin(Math.PI * this.p);
      const gA = sn * sn, gB = 1 - gA;
      oL[s] = gA * this.read(bufL, this.dA) + gB * this.read(bufL, this.dB);
      if (oR !== oL) oR[s] = gA * this.read(bufR, this.dA) + gB * this.read(bufR, this.dB);
      this.dA += dr; this.dB += dr;
    }
    return true;
  }
}

registerProcessor('pitch-shifter', PitchShifter);
