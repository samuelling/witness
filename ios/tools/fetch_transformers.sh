#!/bin/sh
# Puts the subtitle engine's code in vendor/transformers/ so the iPhone/iPad app can bundle it
# instead of fetching code from a CDN at run time (App Store guideline 2.5.2). The website keeps
# loading the same pinned files from jsDelivr.
#
# These files stay out of git: GitHub's secret scanner mistakes a string inside
# transformers.min.js for an API key. Run this once per checkout before building the app;
# the Xcode build stops with a reminder if they are missing. Every file is checked against
# a pinned SHA-256.
set -eu
cd "$(dirname "$0")/../.."
DIR=vendor/transformers
mkdir -p "$DIR"
TF=https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.2/dist
ORT=https://cdn.jsdelivr.net/npm/onnxruntime-web@1.31.0-dev.20260914-8d85527a0/dist   # the build transformers 4.3.2 asks for
fetch() {   # url, sha256
  out="$DIR/$(basename "$1")"
  if [ -f "$out" ] && [ "$(shasum -a 256 "$out" | cut -d' ' -f1)" = "$2" ]; then echo "ok      $out"; return; fi
  if [ -f "$out" ] && [ -n "${3:-}" ] && [ "$(shasum -a 256 "$out" | cut -d' ' -f1)" = "$3" ]; then echo "ok      $out (patched)"; return; fi
  curl -fsSL "$1" -o "$out.part"
  got=$(shasum -a 256 "$out.part" | cut -d' ' -f1)
  [ "$got" = "$2" ] || { rm -f "$out.part"; echo "error: $1 has SHA-256 $got, expected $2" >&2; exit 1; }
  mv "$out.part" "$out"; echo "fetched $out"
}
fetch "$TF/transformers.min.js"                     8b5a3171f8876bab2b1820a7d65eb87628e3d30bb5ea85b9dd398e76eb34decb
fetch "$ORT/ort-wasm-simd-threaded.asyncify.mjs"    0966b6105cd936744498aa60df7a22cbd47af3374dbc64a9ab561c08a71e3611 7b103b427a98939e43258204d3961031d8b339a51ec17ec679a9bb68430c13f2
fetch "$ORT/ort-wasm-simd-threaded.asyncify.wasm"   49871f5a4409519797e127440868a6d1923339d9185907f301a5b2a1d90af082

# iOS WebKit can't reserve a 4 GB shared WebAssembly memory ("RangeError: Out of memory"), which is
# what this runtime build asks for. Moonshine needs far less, so cap it at 1 GB in the bundled copy.
# (The .wasm itself is unchanged: a smaller maximum still satisfies its memory import.)
MJS="$DIR/ort-wasm-simd-threaded.asyncify.mjs"
if grep -q 'maximum:65536,shared:!0' "$MJS"; then
  sed 's/maximum:65536,shared:!0/maximum:16384,shared:!0/' "$MJS" > "$MJS.part" && mv "$MJS.part" "$MJS"
  echo "patched $MJS (wasm memory maximum 4 GB -> 1 GB)"
fi
grep -q 'maximum:16384,shared:!0' "$MJS" || { echo "error: could not cap the wasm memory in $MJS" >&2; exit 1; }
