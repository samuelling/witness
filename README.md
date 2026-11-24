# Witness

Pixelates faces and pitches the voice down, like a protected witness on the evening news.
Works on a live camera or on a video file, and saves the disguised result. Everything runs
in the browser; no video or audio leaves the device.

**Live:** https://linglab.org/witness/

## How it works

- **Face.** Two MediaPipe BlazeFace detectors (close-range and full-range) run on every frame.
  Each face is covered with a mosaic, a blur, a black bar over the eyes, or a full-body silhouette. The mosaic is
  snapped to a fixed grid so blocks don't crawl, and a face that the detector loses stays
  covered (and the cover widens) for 1.2 s. Until the detector has loaded, the whole frame is
  pixelated.
- **Scene.** A MediaPipe selfie segmenter finds the person's outline. Silhouette mode paints
  the whole person black (with a black oval over each detected face as a backstop); background
  blur keeps the person sharp over a heavily blurred room, and blurs everything if the outline
  isn't available. An optional lower-third caption is drawn into the picture.
- **Subtitles.** `speech-tap.js` resamples the undisguised voice to 16 kHz; the page splits it
  into phrases at pauses and `captions-worker.js` transcribes them with Moonshine through
  Transformers.js: Moonshine Base on WebGPU, or the smaller Moonshine Tiny on WebAssembly where
  there is no real GPU. A phrase in progress is
  re-read every ~0.6 s for a live preview. The model (about 155 MB, or 50 MB for Tiny) is downloaded from
  Hugging Face the first time subtitles are switched on and cached by the browser;
  Transformers.js 4.3.2 and its ONNX runtime come from jsDelivr. Audio never leaves the device. `?stt=wasm` or `?stt=webgpu`
  on the address forces a backend.
- **Voice.** `pitch-shifter.js` is an AudioWorklet delay-line pitch shifter: two read heads
  sweep a ring buffer and crossfade, with each splice aligned by correlation. Pitch drops
  (formants and all) while speed stays the same. Default is 5 semitones down.
  The alternative mask, `vocoder.js`, is an 18-band channel vocoder: the voice's per-band
  loudness shapes a fixed-pitch sawtooth buzz (plus hiss, up to a full whisper), so the
  speaker's own pitch and melody are discarded rather than shifted.
- **Recording.** The output canvas and the shifted audio are recorded with MediaRecorder
  (MP4 where the browser can encode H.264/AAC, otherwise WebM). A video file is exported by
  playing it through once in real time.

## Limits

This is a toy, not real anonymisation. A plain pitch shift can be undone by shifting it back (the vocoder is harder to undo, but keeps timing and accent),
and a detector can miss a face that is turned away, tiny, or partly covered. Recording pauses
if the tab is in the background.

## Files

- `index.html` – the app
- `pitch-shifter.js`, `vocoder.js` – the two voice-mask worklets
- `speech-tap.js`, `captions-worker.js` – subtitle audio tap and speech-to-text worker
- `vendor/` – `@mediapipe/tasks-vision` 1.2.3 (Apache-2.0) the BlazeFace and selfie-segmenter models
