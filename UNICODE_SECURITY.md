# Contextual Unicode security

Signal Sieve reports invisible and security-sensitive Unicode scalars without
assuming that every invisible character is malicious. Some are required for
emoji, writing systems, ideographic variants, bidirectional text, or specialist
notation. The same scalar outside a functional context can also carry hidden
data or change how text is displayed.

The implementation follows a bounded-context policy inspired by Unicode
[UTS #39](https://www.unicode.org/reports/tr39/): retain a default-ignorable
character only where its surrounding script or sequence provides a known
reason. This is a documented application profile, not a claim of complete
conformance to every Unicode security mechanism.

## Explicitly covered carriers

In addition to general Unicode categories, Signal Sieve has explicit handling
for:

- zero-width space, joiners, word joiner, soft hyphen, combining grapheme
  joiner, Mongolian vowel separator, and BOM-like `U+FEFF`;
- invisible mathematical operators `U+2061` through `U+2064`;
- directional marks, embeddings, overrides, isolates, and deprecated bidi
  controls `U+206A` through `U+206F`;
- Mongolian, BMP, and supplementary variation selectors;
- `U+E0001` and the Unicode tag payload range;
- Hangul fillers `U+115F`, `U+1160`, `U+3164`, and `U+FFA0`, plus Khmer
  invisible vowels;
- Arabic, Syriac, and Kaithi orthographic format controls;
- Egyptian Hieroglyph, Duployan, musical, and interlinear layout controls;
- reserved default-ignorables, all Unicode noncharacters, private-use scalars,
  unassigned scalars, and unusual whitespace.

Every finding retains its scalar and UTF-16 position, code point, category,
context, exact-evidence label, and risk tier. Copied reports replace the scalar
with a visible `U+…` marker.

## Relational covert channels

Some encodings are defined by a sequence rather than one suspicious scalar.
The Advanced Carrier Lab adds bounded, model-free detection for:

- four-symbol base-4 runs using `U+200B`, `U+200C`, `U+200D`, and `U+2060`;
- binary alphabets made from ASCII space and one unusual Unicode space;
- spaces and tabs at the ends of multiple lines; and
- recurring Cyrillic look-alikes embedded in predominantly Latin prose.

The report separates an exact decoded payload from a probable structure or a
heuristic cadence. It requires minimum carrier counts, mixed alphabet symbols,
and contextual thresholds rather than flagging one space, an indented line, or
ordinary emoji composition. Decoded output is bounded and displayed as inert
text; it is never executed.

Safe and Strict Clean already remove actionable zero-width symbols and replace
unusual Unicode spaces. When a trailing-whitespace channel is detected, both
modes additionally remove only the spaces and tabs at line endings and then
reanalyze the result. Visible confusable letters remain review-only because an
automatic replacement could change names, identifiers, or meaning.

| Carrier family | Native detection | Reveal | Safe Clean treatment |
| --- | --- | --- | --- |
| ZWNJ/ZWJ binary | Exact scalar run | Bytes, incomplete bits, qualified equivalence | Remove nonfunctional carriers |
| Four-symbol zero-width base 4 | Structured run | Printable UTF-8 when exact | Remove nonfunctional carriers |
| Unicode Tags | Exact scalar range | Tag payload | Remove nonfunctional tags |
| Variation-selector bytes | Context-aware selector run | Printable bytes when valid | Preserve functional glyph/emoji use; remove floating payloads |
| Mixed Unicode spaces | Binary relationship and cadence | Printable UTF-8 when exact | Replace unusual spaces with ASCII space |
| Trailing spaces/tabs | Multi-line binary relationship | Printable UTF-8 when exact | Strip line-ending carriers only after channel detection |
| Recurring Cyrillic look-alikes | Predominantly Latin context and cadence | Evidence and positions | Review only; never guess visible replacements |

## Context decisions

Safe Clean preserves a finding only when a supported functional context is
recognized:

| Sequence | Safe Clean decision |
| --- | --- |
| Emoji variation selector or emoji ZWJ sequence | Preserve |
| ZWJ/ZWNJ between compatible letters or marks in a supported joining script | Preserve |
| Standard CJK variation selector sequence | Preserve |
| Known subdivision-flag tag sequence | Preserve |
| Bounded implicit direction mark or balanced non-override bidi pair | Preserve |
| Script-appropriate Hangul/Khmer filler or Arabic/Syriac/Kaithi control | Preserve |
| Script/notation layout control next to its supported notation | Preserve |
| Floating selector, tag, filler, operator, deprecated bidi control, or layout control | Remove |

Explicit bidi overrides are never considered safe merely because a closing
control exists. Arbitrary emoji tag text is not accepted as a functional flag.
BMP variation selectors `U+FE00` through `U+FE0D` require an ideographic base;
`U+FE0E` and `U+FE0F` require an emoji base. This prevents a non-ASCII letter
alone from legitimizing a hidden selector.

Strict Clean removes functional invisible controls as well and applies
compatibility normalization. It is useful for aggressive canonicalization, but
it can change emoji presentation, orthography, or specialist notation.

## Regression policy

Every range expansion must include positive and negative fixtures:

1. a floating or payload-like carrier that remains actionable;
2. a legitimate contextual sequence that Safe Clean preserves;
3. a Safe Clean result proving the suspicious scalar was removed; and
4. a regression check for existing emoji, joining-script, bidi, tag, and CJK
   behavior.

Relational detectors additionally require a natural-text negative fixture, a
decodable positive fixture where applicable, and a post-cleaning assertion that
the supported carrier no longer survives.

The release quality gate type-checks the Swift Testing suite with warnings as
errors and runs a compiler-compatible local suite that includes these Unicode
boundaries. A new range is not considered supported until both paths pass.

## Limitations

Context detection reduces false positives; it cannot prove intent. Fonts,
renderers, normalization, language conventions, and future Unicode versions may
change how a sequence behaves. Signal Sieve does not claim exhaustive
confusable detection, language validation, or universal watermark removal.

For source code, Code Guard applies a stricter policy and leaves ambiguous
confusable identifiers unchanged for human review. Always combine these reports
with compiler diagnostics, code review, version control, and dependency
security tooling.

## References

- [Unicode UTS #39: Unicode Security Mechanisms](https://www.unicode.org/reports/tr39/)
- [Unicode UTS #55: Unicode Source Code Handling](https://www.unicode.org/reports/tr55/)
- [Unicode UAX #31: Unicode Identifiers and Syntax](https://www.unicode.org/reports/tr31/)
- [Unicode UTR #36 status and superseding guidance](https://www.unicode.org/reports/tr36/)
