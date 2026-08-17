# Contributing to SignalSieve

SignalSieve accepts focused changes that preserve its local-first privacy model.
Please keep analysis deterministic where possible and treat every input string
as private data.

## Before opening a change

1. Keep core behavior in `Sources/SignalSieveCore` and UI state in
   `Sources/SignalSieve`.
2. Add or update a focused test for every behavior change and regression fix.
3. Preserve functional URL parameters unless there is strong evidence that a
   parameter is tracking-only for the scoped domain.
4. Never log, upload, persist, or place processed text into a diagnostic URL.
5. Run `swift test` with a complete Xcode installation, or `./check.sh` on the
   Command Line Tools setup described in the README.

## Rule changes

Document why a URL parameter is tracking-only and scope uncertain rules to a
domain. A valid community-pack signature proves integrity, not trust. New
signers must never become trusted silently.

## Test layers

- Unit tests cover Unicode inspection, cleaning, patterns, URL rules,
  persistence, signature verification, and Watermark Probe calibration
  boundaries. A long answer alone must never be a positive watermark signal.
- Apple Vision tests are integration tests because they exercise an operating
  system framework and OCR resources.
- UI changes must at minimum compile with warnings treated as errors and be
  checked manually for keyboard and accessibility labels.

## License of contributions

Unless a separate written agreement says otherwise, every contribution is
submitted under the Mozilla Public License 2.0, the same license that governs
the repository. By submitting a contribution, you represent that you have the
right to license it on those terms. Copyright ownership is not transferred.

Do not submit code copied from an incompatible source. A future request for
different commercial or relicensing rights would require a separate, explicit
agreement and is never implied by opening a pull request.
