# Signal Sieve pixel-module contract

Pixel Watermark Lab includes two signed, model-free modules. Signal Sieve LSB
Forensics screens classic least-significant-bit carrier regularity and can clear
selected LSBs in a verified copy. Signal Sieve Spectral Carrier Lab high-pass
filters luminance, measures correlation and cross-tile coherence against a
bounded bank of spatial frequencies, and can suppress its strongest projection
in a verified copy. Neither module owns provider keys or models, so neither is a
SynthID or universal learned-watermark detector. Periodic natural texture,
resampling, dithering, and sensor artifacts can create false positives.

The Lab can also run an explicitly selected local detector or image regenerator
through the same contract. No third-party model or executable is bundled with
Signal Sieve; the two built-in helpers are open-source parts of the app and use
the contract to preserve the same staging and verification boundary.

## Module folder

The selected folder must contain `signalsieve-pixel-module.json` and a regular,
non-symlink executable below that same folder. Manifest schema version 1 is:

```json
{
  "schemaVersion": 1,
  "name": "Example detector",
  "version": "1.0.0",
  "executable": "bin/example-detector",
  "capabilities": ["score", "regenerate"],
  "license": "Apache-2.0",
  "homepage": "https://example.invalid/project"
}
```

Absolute executable paths and paths containing `..` are rejected. The module
must declare at least one supported capability.

## Score operation

Signal Sieve invokes:

```text
executable score --input /temporary/read-only-copy.png --json
```

The process must emit one UTF-8 JSON object to standard output:

```json
{
  "schemaVersion": 1,
  "detector": "example-v1",
  "score": 0.73,
  "threshold": 0.5,
  "label": "elevated"
}
```

`score` and an optional `threshold` must be finite values from 0 through 1.
Signal Sieve treats them as module claims, not as independent proof.

## Regenerate operation

Signal Sieve pre-creates a private temporary output and invokes:

```text
executable regenerate --input /temporary/read-only-copy.png \
  --output /temporary/generated.png --strength 0.250 --json
```

The module must write a valid image to `--output`, keep the original dimensions,
and exit successfully. Signal Sieve rejects an identical output, an oversized
output, changed dimensions, or any change to the original selected file. A
verified result is moved to a new user-selected destination and reanalyzed for
known metadata. If the module also supports `score`, the app requests before
and after scores.

## Bounds and trust

- Images are limited to 256 MiB, JSON output to 1 MiB, and execution to five
  minutes by default.
- Proxy variables are removed and common offline flags are set, but these are
  advisory. This is not an operating-system sandbox.
- The module runs with the user's authority. Review its source, license, model
  files, downloads, and privacy behavior before selecting it.
- Signal Sieve never passes the original path to the module and never permits a
  pixel operation to overwrite an existing destination.
