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
5. Run `./test-swift-testing-local.sh` before each push. Also run `swift test`
   with a complete Xcode installation when available, or `./check.sh` for the
   full Command Line Tools path described in the README.

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

## Publishing a release

Maintainers publish releases from an existing version tag. The tag must match
`CFBundleShortVersionString` in `Packaging/Info.plist`; the current version is
`0.12.0`, so its tag is `v0.12.0`.

1. Commit and push the intended release state to `main`, then wait for CI to
   pass.
2. Create and push an annotated tag:

   ```sh
   git tag -a v0.12.0 -m "Signal Sieve v0.12.0"
   git push origin v0.12.0
   ```

3. The tag-only Release workflow rebuilds pinned dependencies, runs all Swift
   tests and `quality-gate.sh`, packages the verified app, and publishes the ZIP
   plus its SHA-256 checksum. A failed check prevents publication.

Do not move or reuse a published version tag. Increment the app version and
build number before the next release.

## License of contributions

Unless a separate written agreement says otherwise, every contribution is
submitted under the Mozilla Public License 2.0, the same license that governs
the repository. By submitting a contribution, you represent that you have the
right to license it on those terms. Copyright ownership is not transferred.

Do not submit code copied from an incompatible source. A future request for
different commercial or relicensing rights would require a separate, explicit
agreement and is never implied by opening a pull request.
