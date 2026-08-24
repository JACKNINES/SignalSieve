# Signal Sieve advanced roadmap

This document records acceptance criteria for capabilities that extend the
native desktop privacy boundary. A larger feature list is not sufficient: every
cleaner or learned-watermark module must preserve the source, bound untrusted
input, and produce evidence that can be rechecked.

## Strict format expansion

The implementation order is based on deterministic parsing complexity and the
ability to verify that visible or functional content survived:

1. WebP, GIF, BMP, SVG, HTML, and Markdown.
2. HEIC/HEIF, AVIF, and TIFF/BigTIFF.
3. EPUB and recursively embedded media.

Every format must satisfy the same transaction contract:

- Treat byte signatures as authoritative and report extension mismatches.
- Parse with explicit byte, entry-count, expansion-ratio, and nesting limits.
- Never overwrite the source or an existing destination.
- Reject symlink destinations and signed, encrypted, malformed, or
  parser-recovery structures that cannot be rewritten safely.
- Write to a private staged file, close it, reopen it, and reanalyze it.
- Verify that the source hash did not change during the operation.
- Verify format-specific content invariants before offering the copy.
- Report residual metadata and unsupported structures without claiming erasure.

Examples of required invariants include GIF frame count and loop behavior,
WebP canvas and animation timing, TIFF dimensions/pages/strip coverage, SVG
render bounds, HTML visible text and link targets, Markdown body bytes outside
selected front-matter keys, and EPUB spine/order/encryption preservation.

## Controlled watermark harness

A harness is a laboratory, not a detector for arbitrary vendor content. It
creates known positive and negative samples with a specific algorithm,
configuration, and key; runs a transformation; then invokes the same compatible
detector before and after. Its purposes are regression testing, calibration,
false-positive measurement, and honest evidence about supported schemes.

The harness must keep vendor-specific and universal claims separate. Clearing a
known KGW, Tree-Ring, or test SynthID-class fixture does not prove that a private
provider detector will fail on unrelated content.

## Learned pixel-watermark program

To exceed a collection of external scripts, Signal Sieve will optimize for
measured safety and evidence:

1. Build versioned positive, negative, and difficult-control corpora for at
   least two licensed learned-watermark families.
2. Add signed detector adapters with pinned model hashes and fully offline
   execution after explicit installation.
3. Compare at least two removal strategies, including conservative
   regeneration and a non-generative baseline.
4. Record compatible-detector scores before and after without treating them as
   universal provider verdicts.
5. Measure content preservation: dimensions, alpha, color, OCR text, perceptual
   similarity, edge/texture drift, and optional face/identity-sensitive review.
6. Reject results that change dimensions, exceed drift budgets, fail decoding,
   retain unsafe metadata, or modify the source.
7. Publish per-scheme false-positive, false-negative, removal-success, runtime,
   memory, and quality-drift results.

Heavy learned models remain optional modules. The native M2/8-GB application
must stay responsive and useful without them; modules that need more memory or
licensed research weights belong in an explicit advanced lab.

## API and containers

Signal Sieve does not need a public HTTP service for its consumer desktop path.
The native app remains the security and UX boundary. A narrow local CLI or
versioned IPC adapter is preferable for Shortcuts, tests, editor integrations,
and enterprise automation because it avoids exposing a listening service.

Containers are useful only for reproducible research dependencies such as
watermark harnesses and large Python/PyTorch stacks. They are not required to
run the app and should never become a dependency of Active Guard, deterministic
text cleaning, or verified metadata copies.

Implemented boundary: the optional Community Engines adapter can call an
independently installed `watermarks-remover` core service on fixed numeric
loopback. It follows the service's published health, capabilities, inspect, and
clean contract, sends text only after an explicit action, bounds all traffic,
and performs native post-analysis. The app does not own the service lifecycle
or inherit its detector claims. Future adapters must use the same capability,
version, trust-disclosure, and post-verification rules; arbitrary configurable
HTTP endpoints remain out of scope.

## Headless Vaccine and SARIF

The next automation boundary should reuse `VaccineEngine`; it should not create
a second scanner with different rules. A supported command-line target must:

- scan without launching AppKit or SwiftUI;
- remain report-only unless an explicit mutation flag is supplied;
- produce deterministic human-readable, JSON, and SARIF 2.1.0 output;
- map every result to a stable rule ID, severity, relative file URI, line,
  column, message, and partial fingerprint;
- exclude raw source fragments from SARIF by default;
- use documented exit codes for clean, policy-finding, usage-error, and
  internal-error outcomes;
- honor `.signalsieveignore`, file-size limits, symlink exclusions, and the same
  self-vaccination block as the desktop app;
- keep output on disk unless the user or CI workflow explicitly uploads it; and
- pass schema validation, golden-file determinism tests, path-redaction tests,
  and GitHub Code Scanning ingestion tests before being advertised.

SARIF is an interchange format, not an upload mechanism. Signal Sieve should
never require a GitHub account or network connection to generate it.
