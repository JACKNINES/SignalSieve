# Documentation screenshot policy

README screenshots must be reproducible, privacy-safe views of the actual
Signal Sieve application.

## Capture requirements

- Keep the application language set to English.
- Use synthetic text and reserved example domains such as `example.com`,
  `example.org`, and `.test`.
- Do not show real names, accounts, organizations, messages, browsing history,
  source applications, or third-party brand examples.
- Move or remove the mouse pointer before accepting a capture.
- Capture the full relevant window without clipped headings, controls, status
  text, or report cards.
- Store PNG assets at a minimum width of 1,400 pixels. The main overview should
  be at least 2,400 pixels wide.
- Preserve the real interface. Do not generate, reconstruct, or creatively
  alter application text or controls.

## Current fixtures

- `signal-sieve-mark.png`: the white Signal Sieve mark on a transparent
  1,024-by-1,024 canvas, used as the README brand image without an app-icon
  tile or screenshot background.
- `signal-sieve-overview.png`: neutral project note containing U+200B and
  U+202E plus a reserved-domain URL.
- `signal-sieve-active-guard.png`: persistent high-risk Unicode alert after
  Safe Clean reanalysis.
- `signal-sieve-link-report.png`: removed tracking parameters and preserved
  functional parameters across reserved example domains.

When a screen changes materially, replace its image and verify the dimensions,
language, example content, cursor absence, and README alternative text before
committing.
