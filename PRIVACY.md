# SignalSieve privacy model

SignalSieve is designed around local processing and data minimization.

## Text content

- Text inspection, Code Guard, cleaning, Pattern Memory, Surface Regularity,
  Rewrite Integrity, file-provenance inspection, and OCR run locally.
- Contextual Unicode analysis keeps functional emoji composition, script
  shaping, orthographic controls, glyph variation, notation layout, and bounded
  bidirectional marks distinguishable from actionable hidden-text findings.
  The analyzer operates on Unicode scalar values and neighboring context in
  memory; it does not query a remote Unicode service.
- Advanced Carrier Lab performs bounded relational analysis locally. Decoded
  carrier content remains in the current view and is not saved or submitted to
  a provider.
- Pattern Memory keeps up to ten raw samples in process memory only.
- Pattern Memory samples are discarded when the application exits or the user
  chooses **Clear Session Memory**.
- While **Active Guard** is enabled and SignalSieve is running, the app checks
  the macOS pasteboard locally for newly copied content. It ignores the clipboard
  contents that existed before monitoring began.
- Active Guard maintains only the bounded, in-memory Session Copy History.
  Substantial text samples may also enter the session-only Pattern Memory
  described above. Both disappear when the app exits.
- For images, files, HTML, and rich text, Active Guard classifies the declared
  pasteboard type identifiers. It does not retain image bytes, file bytes,
  metadata values, or non-text clipboard payloads in Copy History. When the user
  explicitly chooses **Inspect Copied Image** or **Paste Image**, one bounded
  image representation is held only in the inspector's memory and released when
  that sheet closes. PNG/JPEG bytes are inspected as copied; other supported
  raster representations are normalized locally to PNG and are never uploaded.
  An explicit **Create Fresh Clean Image** action decodes the visible pixels into
  a new in-memory PNG, reanalyzes it, and can place that verified copy on the
  clipboard or save it to a user-selected path. Signal Sieve does not retain the
  generated image after the inspector closes.
- The File Provenance Inspector uses bounded reads and bounded archive-entry
  extraction for a file chosen explicitly by the user. It reports container
  names and structural markers, not private metadata values. Supported PNG,
  JPEG, WebP, AVIF/HEIC, BMP, GIF, TIFF, PDF, DOCX, XLSX, PPTX, EPUB, and ODT
  cleaning always creates and reanalyzes a new file; the source is never
  overwritten. Signed document packages and signed, encrypted, or structurally
  damaged PDFs are refused.
- Rewrite Integrity receives only the existing in-memory Input and Result and
  stores no comparison after the app exits. Optional rewriting invokes only an
  already-installed Ollama command and pins its API host to loopback; Signal
  Sieve never downloads a missing model automatically. The optional integration
  smoke test uses fixed synthetic prose and logs measurements rather than the
  generated text.
- Automatic link cleaning replaces clipboard text only when a known tracking
  parameter was removed and the clipboard still contains the text that was
  analyzed. This prevents a delayed action from overwriting a newer copy.
- Automatic link cleaning is skipped when Code Guard recognizes source code.
  Code Guard output is produced only after an explicit review action, and
  confusable identifiers are never rewritten automatically.
- Active Guard, each warning category, and automatic link cleaning are
  controlled independently from the app. Preferences are stored locally; copied
  text is not included in those preferences.
- The selected interface language is stored as a short local preference (`en`,
  `es`, or `nb`) and contains no processed text.
- The packaged app migrates only the known protection and language preferences
  from the earlier executable build. It never migrates clipboard contents or
  Pattern Memory samples.

## Private link rules

- Private rules contain a normalized domain and query-parameter name only.
- Full URLs, parameter values, and source text are never written to the rule
  file.
- Rules are stored at
  `~/Library/Application Support/SignalSieve/private-url-rules.json`.
- On first launch after the rename, existing TextScrub rules are copied into
  the SignalSieve location. The legacy file is left untouched.
- Private rules are not included in community updates and are not synced.

## Network boundaries

- Native cleaning and analysis make no network requests. Optional local
  integrations are separate, explicit boundaries described below.
- Clicking a Unicode or Code Guard finding explicitly opens a DuckDuckGo query
  in the user's browser. The query contains only the Unicode code, name, and
  category—never the copied text, source code, or identifier.
- Clicking a Surface Regularity signal opens a generic research query for that
  metric. The query never contains words or fragments from the analyzed text.
- Opening official provider documentation is an explicit browser action. No
  analyzed text, filename, metadata value, or provider-detection result is
  appended to that URL.
- Automatic community-rule downloads are disabled until a trusted signer and
  transparent update source are configured.
- Community Engines checks only `http://127.0.0.1:8765/health` when its panel
  opens. It sends the current text to that local process only after the user
  chooses inspect or clean. Signal Sieve accepts no configurable remote host,
  strips proxy variables, does not follow a community-engine update feed, and
  never starts or downloads the external project. The independently installed
  service can still read the text explicitly sent to it and must be trusted as
  a separate local process. See [COMMUNITY_ENGINES.md](COMMUNITY_ENGINES.md).
- Vaccine does not currently export SARIF or run as a supported headless CLI.
  Consequently, no scan report is uploaded automatically. A future CI exporter
  must be opt-in and disclose that uploading SARIF shares file paths, locations,
  rule identifiers, and messages with the selected CI provider.
- Pixel Watermark Lab bundles model-free LSB and spectral-carrier modules that
  run as signed local helpers without network code. Inputs are staged as temporary
  copies and outputs must be new files. Optional third-party modules remain an
  explicit trust boundary: offline environment flags are advisory and an
  external executable can ignore them.

## Community signatures

A valid signature proves that a rule pack was not changed after a particular
key signed it. It does not prove that the signer is trustworthy. SignalSieve must
show the signer fingerprint and require explicit trust before applying future
community updates.
