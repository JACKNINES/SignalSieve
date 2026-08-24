# Signal Sieve statistical text-detector contract

Surface Regularity is keyless triage. It cannot confirm a token-sampling
watermark. Signal Sieve therefore supports explicitly selected local detector
modules for schemes such as KGW, SynthID-Text, and keyed-Gumbel/EXP.

The module folder contains a regular, non-symlink executable and
`signalsieve-text-watermark-module.json`:

```json
{
  "schemaVersion": 1,
  "name": "Local MarkLLM KGW detector",
  "version": "1.0.0",
  "executable": "bin/detect-kgw",
  "schemes": ["KGW"],
  "verificationMode": "same-configuration",
  "requiresSecretKey": true,
  "license": "Apache-2.0",
  "homepage": "https://github.com/THU-BPM/MarkLLM"
}
```

Signal Sieve invokes:

```text
executable detect --input /private/temporary/input.txt --json
```

The only accepted stdout is a bounded JSON object:

```json
{
  "schemaVersion": 1,
  "detector": "markllm-kgw",
  "scheme": "KGW",
  "statistic": 4.2,
  "threshold": 3.0,
  "pValue": 0.0002,
  "detected": true,
  "tokenCount": 180,
  "note": "Same key, tokenizer, vocabulary, and seeding configuration"
}
```

The reported scheme must be advertised by the manifest. Numeric values must be
finite, a p-value must lie in 0...1, text is limited to 1 MiB, stdout to 64 KiB,
and runtime to two minutes. The source text is copied to a temporary mode-0400
file and deleted after the run. Proxy variables are removed and offline flags
are set, but an external process is not an operating-system sandbox.

Verification modes:

- `same-configuration`: valid only with matching tokenizer, vocabulary, key,
  seeding, and algorithm parameters. This is the correct label for typical
  MarkLLM research harnesses.
- `provider-compatible`: use only when compatibility with a deployed provider
  detector is independently documented.
- `research-heuristic`: an experimental score without a matching watermark
  configuration.

Never label a negative result “watermark free.” Short text, paraphrasing,
tokenizer drift, unknown keys, or a different deployed configuration can all
produce false negatives. MarkLLM is an appropriate Apache-2.0 adapter base; no
third-party code or model is bundled with Signal Sieve.
