# Changelog

All notable user-facing changes to Signal Sieve are recorded here.

## 0.12.0 — 2026-08-24

- Added automatic, reviewable Safe Clean output when Input changes, with an
  opt-out in Copying Settings.
- Added Automatic Visual Transfer with local OCR and protected-value safety
  gates.
- Made automatic Strict Clean flatten HTML and RTF clipboard representations
  even when visible text is unchanged.
- Expanded hidden-Unicode, contextual, statistical, link, code, scam, UUID,
  file-metadata, document-container, and pixel-forensics coverage.
- Added the local Swift Testing runner and hardened CI/quality restrictions.
- Added Apple-silicon ZIP and DMG releases with SHA-256 checksums and GitHub
  build-provenance attestations.

Signal Sieve 0.12.0 is ad-hoc signed and is not notarized with an Apple
Developer ID. See the README for the macOS first-launch procedure.
