# Security policy

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for the repository. If that
channel is not yet enabled, open a public issue containing only a request for a
private contact channel. Do not include private source text, complete tracked
URLs, tokens, signatures, personal rule files, or sensitive documents in a
public issue. Provide the smallest synthetic reproduction possible.

## Security boundaries

- Text processing, Code Guard, Binary Guard, Vaccine, and OCR are local.
- Surface Regularity is a local, deterministic stylometric triage screen. Its score is not a
  probability and must never be presented as confirmation of AI generation,
  authorship, or a provider-specific watermark. Provider-specific verification
  requires a compatible detector and validated parameters that Signal Sieve
  does not currently possess. Provider profiles must not infer an undisclosed
  mechanism.
- Copy History is session-only and held in process memory. It is capped at 50
  entries and 20,000 characters per entry; concealed, transient, and
  auto-generated pasteboard items are not stored. Source application names are
  best-effort observations of the foreground app, not authenticated provenance.
  Clean-result and original-restore actions are available only for history-
  eligible, untruncated automatic-cleaning entries, and they fail closed if the
  pasteboard change count or expected text no longer matches.
- Opening a finding in the browser is an explicit network boundary. Unicode
  queries contain element metadata only; Surface Regularity queries contain only
  the generic signal topic. Neither may contain the analyzed text.
- Private URL rules store domain and parameter names, never values or source
  URLs.
- Community packs are untrusted until both their signature and signer trust
  have been verified explicitly.
- Code Guard never executes, compiles, or automatically rewrites copied code.
  Sanitized output requires explicit review, and visually confusable
  identifiers remain unchanged because their intended spelling is unknowable.
- Automatic clipboard cleaning prepares and reanalyzes its candidate before
  writing. If a high-risk finding remains, the pasteboard is left unchanged and
  the item is treated as quarantined. If an original red finding is removed, the
  clean text may replace the clipboard, but the red source warning remains
  mandatory. Clean Receipts store only counts, severities, the selected
  protocol, skipped status, and bounded content-free reasons.
  A green receipt is limited to the supported cleaning analysis and is not a
  general safety or source-trust verdict. Automatic Visual Transfer follows the
  same reanalysis and quarantine decision, but its OCR output remains lossy and
  is not represented as a deterministic scalar-replacement count.
- Binary Guard never decodes or executes a detected payload. Encoded data is
  not inherently unsafe; the label describes its representation, not intent.
- Contextual Unicode classification is fail-safe rather than blanket removal.
  Default-ignorable characters are preserved by Safe Clean only when a bounded
  emoji, writing-system, glyph-variation, directional, orthographic, or notation
  context is recognized. Deprecated bidi controls, floating language tags,
  invisible operators, and controls outside their expected script remain
  actionable. Strict Clean intentionally removes functional invisible controls
  too and may alter rendering. See [UNICODE_SECURITY.md](UNICODE_SECURITY.md).
- Advanced Carrier Lab analyzes relationships across scalar sequences rather
  than treating one character as proof. Base-4 zero-width runs, mixed-space
  alphabets, trailing spaces/tabs, and recurring confusable letters require
  minimum carrier and context thresholds. Decoded payloads are bounded inert
  text. Automatic cleanup is limited to deterministic invisible or whitespace
  carriers; visible confusable letters remain review-only.
- Vaccine scans before writing, does not follow symbolic links, skips binary
  and oversized files, checks that each file is unchanged since the scan, and
  backs up every candidate before the first source file is rewritten. Only
  deterministic safe transformations are applied. Confusable identifiers and
  encoded payloads remain review-only. Supported metadata/provenance findings
  are included in the folder report but are never rewritten by Vaccine.
- Self-vaccination is rejected in the core engine as well as the interface;
  Signal Sieve's own security fixtures may intentionally contain attack data.
- Vaccine has no supported non-GUI CLI or SARIF output in this release. CI
  integration must not scrape the interface or treat an ad-hoc JSON conversion
  as the official Signal Sieve result format. A future exporter must keep file
  locations and bounded evidence separate from private source fragments.
- Invisible payload previews are decoded locally into display-only strings,
  capped in length, and never interpreted as commands or executed. A decoded
  fragment indicates a recognizable encoding, not malicious intent.
- Reveal never silently pads or repairs malformed binary channels. It may show
  an explicitly labeled, low- or medium-confidence probable equivalence when a
  bounded bitstream closely matches the local, auditable known-payload catalog.
  The app exposes the similarity and edit distance; this inference is not proof
  of the original bytes. Reveal never decrypts, decompresses, or executes it.
- Signature Hunt neutralizes only groups backed by deterministic safe Vaccine
  transformations. It creates backups before writing, verifies file
  fingerprints, preserves UTF encoding/endianness/BOM, and performs a fresh
  scan after changes. Review-only groups are never selected implicitly.
- `.signalsieveignore` is applied before a file is read. Use it for intentional
  security fixtures, generated snapshots, or private trees that should remain
  outside the analysis scope.
- Copyable findings reports visualize every detected invisible scalar as a
  `U+…` marker. The report formatter does not silently reproduce those scalars
  on the clipboard.
- File Provenance Inspector analysis is read-only and bounded. Cleanup is a
  separate, explicit operation that creates a new value. A recognized `caBX` or
  C2PA-labelled JUMBF structure establishes only that a container marker exists;
  it does not validate the signer, claim, trust chain, or asset binding. A
  missing embedded container does not rule out external manifests, soft
  bindings, or pixel/text marks. Generic JPEG APP11 data is not classified as
  C2PA without an identifying structure. Byte signatures take precedence over
  filename extensions and mismatches are reported. PDF headers found after
  leading wrapper data are reported as a container anomaly and refused for
  cleaning rather than silently normalized.
- Clipboard-image inspection verifies the pasteboard change count before an
  Active Guard action imports bytes. PNG/JPEG representations are kept intact;
  TIFF, HEIC, HEIF, or GIF inputs are decoded under pixel and byte limits and
  normalized locally to PNG. Transcoding cannot preserve source-container
  metadata, so the UI discloses that boundary instead of issuing a verdict.
- Fresh clipboard-image cleaning rebuilds a PNG from bounded decoded pixels and
  verifies that supported container findings are absent before offering it. It
  never mutates the source payload. Clipboard replacement checks the pasteboard
  change count, and saving refuses an existing destination. Regeneration does
  not remove or disprove watermark patterns carried by visible pixel values.
- Verified metadata cleaning supports bounded PNG, JPEG, WebP, AVIF/HEIC, BMP,
  GIF, TIFF, PDF, DOCX, XLSX, PPTX, EPUB, and ODT structures. It always targets
  a new path and verifies both the unchanged source and the reanalyzed result.
  DOCX `customXml` is preserved because removing it can break bound content.
  TIFF pointer graphs are refused when metadata payloads cannot be proven
  disjoint from pixels. PDF cleaning uses a pinned qpdf helper and verifies
  structural invariants plus the reanalyzed copy; signed, encrypted, or
  parser-recovery PDFs are refused. Signed document packages are refused. This
  is not a cryptographic erasure guarantee.
- Rewrite Integrity checks exact protected-value differences but cannot prove
  semantic equivalence. Optional local Ollama output remains untrusted prose,
  source code is blocked, and lexical divergence is never interpreted as proof
  that a watermark was removed. Ollama is never required for deterministic
  inspection or cleaning. A local rewrite may replace the source's statistical
  pattern with the selected model's own token and style bias, so the app does
  not describe model output as neutral, anonymous, or watermark-free.
  Generation is pinned to `http://127.0.0.1:11434/api/chat` and delegated to
  Apple's fixed-path `/usr/bin/curl` process with a bounded request, response,
  context, and timeout. Proxy variables are removed, no configurable remote
  endpoint is accepted, and Signal Sieve contains no general-purpose
  in-process network client.
  The optional `ollama-smoke-test.sh` exercises this same core path and prints
  measurements rather than generated prose. It is deliberately excluded from
  the mandatory release gate so builds do not acquire a model dependency.
- Pixel Watermark Lab validates module paths, input/output bounds, dimensions,
  and source immutability. Its built-in LSB and spectral modules are heuristics
  that can confuse natural sensor noise, periodic texture, resampling, or
  dithering with a carrier and do not detect learned provider schemes. External
  modules are not an operating-system sandbox. A selected
  third-party executable can ignore offline environment flags and must be
  trusted independently from Signal Sieve.
- Community Engines is an explicit third-party execution boundary. The first
  adapter accepts only `http://127.0.0.1:8765`, uses the documented
  `watermarks-remover` health, capabilities, inspect, and clean routes, removes
  proxy variables, bounds request/response sizes and time, and never invokes a
  shell. Opening the panel sends only a health request; selected text is sent
  to the local process only after an inspect or clean action. Loopback prevents
  remote routing but does not sandbox that process. Signal Sieve never installs,
  launches, or updates it, and reanalyzes returned text before offering Result.
  See [COMMUNITY_ENGINES.md](COMMUNITY_ENGINES.md).
- The release quality gate scans both in-process networking APIs and
  network-capable subprocess executables. Only the fixed `/usr/bin/curl`
  bridges in `LocalRewriteEngine.swift` and `CommunityWatermarkService.swift`
  are allowlisted, and their numeric loopback endpoint literals are checked.
  Adding another networking tool, a shell subprocess, or changing either
  endpoint fails the release gate until the boundary is reviewed explicitly.

SignalSieve reduces known text and URL tracking signals. It does not guarantee
that arbitrary statistical or linguistic watermarks can be detected or
removed.
Code Guard detects common source-code Unicode hazards; it is not a substitute
for compiler warnings, code review, dependency auditing, or sandboxing.
Its language label is based on syntax evidence and must not be treated as a
security boundary or a guarantee that a snippet can be compiled safely.
Vaccine is not a malware scanner, dependency auditor, compiler, or substitute
for version control. Backups may contain sensitive source and are stored only
in the user's local Application Support directory.
