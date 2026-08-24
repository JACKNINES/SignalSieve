# Optional local rewriting with Ollama

Signal Sieve can ask an already-installed Ollama model to rewrite prose. Ollama
is optional: text inspection, Safe Clean, Strict Clean, Active Guard, Vaccine,
metadata cleaning, OCR, and pixel forensics continue to work without it.

Signal Sieve never installs Ollama, downloads a model, or starts a remote
service automatically. Generation is pinned to Ollama's loopback endpoint at
`http://127.0.0.1:11434/api/chat`.

## Recommended model for this Mac

`qwen3.5:4b` is the practical default for the current Apple-silicon Mac. The
installed copy occupies approximately 3.4 GB. It is small enough for local
rewriting while still following the preservation prompt reasonably well.

Larger models can improve writing quality but use more unified memory, take
longer to load, and may make the rest of the system less responsive. Signal
Sieve does not select or download a larger model automatically.

## Install and start Ollama

1. Install Ollama from [ollama.com/download](https://ollama.com/download) or
   another source you trust.
2. Open `Ollama.app`. Alternatively, advanced users can start its local service:

   ```sh
   ollama serve
   ```

3. In a separate Terminal window, install the model explicitly:

   ```sh
   ollama pull qwen3.5:4b
   ```

4. Confirm that the service and model are available:

   ```sh
   ollama --version
   ollama list
   ```

Downloading a model is an Ollama network operation initiated by the user. Once
the model is installed, Signal Sieve's rewrite request remains on loopback.

## Use it in Signal Sieve

1. Paste prose into **Input**.
2. Select the **Analyze** toolbar section.
3. Open **Rewrite Integrity**.
4. Confirm that `qwen3.5:4b` appears under **Installed model**. Use **Refresh
   Installed Models** if Ollama was started after opening the sheet.
5. Choose **Substantial paraphrase** or **Natural voice variation**.
6. Select **Rewrite Locally**.
7. Read the generated **Result** and review the integrity cards before copying
   or using it.

The two styles change only the prompt:

- **Substantial paraphrase** requests broader changes to vocabulary, syntax,
  clause order, transitions, and sentence boundaries.
- **Natural voice variation** requests less formulaic phrasing and more varied
  cadence while retaining precision.

Signal Sieve asks the model to preserve language, meaning, names, numbers,
dates, URLs, quotations, and paragraph order. This is an instruction, not a
guarantee. Rewrite Integrity therefore compares the output again and reports
exact additions or removals of protected values.

## Repeatable integration test

The optional smoke test compiles the current Signal Sieve core and performs one
real rewrite through `LocalRewriteEngine`:

```sh
./ollama-smoke-test.sh
```

To test another installed model, pass its exact name:

```sh
./ollama-smoke-test.sh llama3.2:3b
```

The test fails if:

- Ollama or the requested model is unavailable;
- the model name is unsafe or not installed;
- the request times out or returns malformed/empty output;
- the model returns the input unchanged;
- model/style identity is lost;
- actionable hidden Unicode appears in the generated text; or
- an integrity rejection lacks supporting evidence.

The synthetic fixture contains a date, percentage, URL, and quotation. If the
model preserves them exactly, the test prints `PASS: exact protected values
preserved`. If the model changes one, the test prints `REJECTED SAFELY` with
only the affected categories and still succeeds because Signal Sieve enforced
the intended boundary. It never treats that rejected candidate as acceptable
prose.

The summary prints sizes and measurements, not the generated prose. This avoids
placing model output into CI logs.

This smoke test is intentionally separate from `quality-gate.sh`, because
Ollama is optional and release verification must pass on systems without a
model. The deterministic unit and restriction tests for the adapter still run
inside the normal quality gate.

## Safety and privacy boundaries

- Maximum input: 12,000 Swift characters.
- Request timeout: at most 180 seconds.
- Maximum accepted generated text: 2 MiB.
- Model context requested by Signal Sieve: 4,096 tokens.
- Source code is rejected; use Code Guard and project tests instead.
- Missing models are reported and never downloaded automatically.
- The request uses Apple's `/usr/bin/curl` without a shell and with proxy
  variables removed.
- The only accepted endpoint is the numeric loopback address
  `127.0.0.1:11434`.
- Temporary request output is deleted after the process completes.
- The model remains a separate local process and its output is untrusted.

A local model can introduce its own vocabulary, cadence, factual errors, and
statistical signature. Signal Sieve does not describe its output as anonymous,
neutral, semantically verified, or guaranteed to remove a watermark.

## Troubleshooting

### Ollama is installed, but the service is unavailable

Open `Ollama.app`, then run:

```sh
ollama list
```

If that command cannot reach `127.0.0.1:11434`, Signal Sieve cannot reach it
either. Do not start a second `ollama serve` process if the application already
owns the port.

### No installed model appears

Run `ollama list`. Model names must match exactly, including a tag such as
`:4b`. Signal Sieve never pulls the missing model for you.

### The rewrite times out

Try a shorter input, close memory-intensive applications, or select a smaller
installed model. Signal Sieve caps the request at 180 seconds and leaves Result
unchanged after a timeout.

### Protected values changed

Do not use the candidate until every reported number, date, URL, and quotation
has been checked against Input. A clean exact-value comparison still requires a
full human reading because semantic equivalence is not testable locally.

### Source code is rejected

This is deliberate. Model-based rewriting can silently alter identifiers,
literals, comments, syntax, or security behavior. Use **Code Guard**, Vaccine,
compiler diagnostics, and tests for code.
