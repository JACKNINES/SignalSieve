// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import SignalSieveCore

struct RevealView: View {
    @Environment(\.dismiss) private var dismiss

    let fragments: [RevealedInvisibleFragment]
    let language: AppLanguage
    let onCopy: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 460, idealHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.fill")
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("Reveal Hidden Content"))
                    .font(.title3.weight(.semibold))
                Text(localized("Decode known invisible encodings without executing their contents."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatted("%d revealed fragment(s)", fragments.count))
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.purple.opacity(0.10), in: Capsule())
        }
        .padding(16)
    }

    private var content: some View {
        Group {
            if fragments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(localized("Nothing to reveal"))
                        .font(.headline)
                    Text(localized("No supported invisible payload was found."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(fragments) { fragment in
                            fragmentCard(fragment)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fragmentCard(_ fragment: RevealedInvisibleFragment) -> some View {
        let color = presentationColor(fragment.presentation)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(
                    localized(fragment.presentation.rawValue),
                    systemImage: presentationIcon(fragment.presentation)
                )
                .font(.headline)
                .foregroundStyle(color)
                Spacer()
                Text(formatted(
                    "Line %d · column %d · %d invisible scalar(s)",
                    fragment.line,
                    fragment.column,
                    fragment.hiddenScalarCount
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if let binary = fragment.zeroWidthBinary {
                binaryDetails(binary)
                if let equivalence = binary.probableTextEquivalence {
                    probableEquivalence(equivalence)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(contentLabel(fragment.presentation))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(fragment.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }

            HStack {
                if fragment.presentation == .incompletePayload,
                   let binary = fragment.zeroWidthBinary {
                    Label(
                        formatted(
                            "Incomplete byte stream · %d bit(s) missing",
                            binary.missingBitCount
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                }
                Spacer()
                Button(localized("Copy Reveal"), systemImage: "doc.on.doc") {
                    onCopy(FindingReportFormatter.revealedFragment(fragment, language: language))
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.35), lineWidth: 1)
        }
    }

    private func binaryDetails(_ binary: ZeroWidthBinaryDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(binary.zeroCodePoint) = 0")
                Text("\(binary.oneCodePoint) = 1")
                Text(formatted("%d complete byte(s)", binary.completeByteCount))
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            Text(binary.bits + (binary.isPreviewTruncated ? "…" : ""))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }

    private func probableEquivalence(_ equivalence: ProbablePayloadEquivalence) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(localized("Probable detected equivalence"), systemImage: "text.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text("“\(equivalence.text)”")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)

            Text(equivalence.unicodeCodePoints.joined(separator: " "))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            Text(formatted(
                "%d character(s) · %@ · %d%% similarity · %d bit edits",
                equivalence.characterCount,
                localized(equivalence.confidence.rawValue),
                equivalence.similarityPercent,
                equivalence.bitEditDistance
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(localized("Approximate local catalog match; this is not an exact byte-for-byte decode."))
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.orange.opacity(0.28), lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack {
            Label(
                localized("Revealed content is treated as data and is never executed."),
                systemImage: "lock.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button(localized("Copy All Reveals"), systemImage: "doc.on.doc") {
                onCopy(FindingReportFormatter.revealedReport(fragments, language: language))
            }
            .disabled(fragments.isEmpty)
            Button(localized("Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    private func presentationColor(_ presentation: RevealedFragmentPresentation) -> Color {
        switch presentation {
        case .decodedPayload: .red
        case .binaryPayload: .red
        case .incompletePayload: .orange
        case .visibleContext: .yellow
        }
    }

    private func presentationIcon(_ presentation: RevealedFragmentPresentation) -> String {
        switch presentation {
        case .decodedPayload: "text.viewfinder"
        case .binaryPayload: "01.square.fill"
        case .incompletePayload: "exclamationmark.triangle.fill"
        case .visibleContext: "character.cursor.ibeam"
        }
    }

    private func contentLabel(_ presentation: RevealedFragmentPresentation) -> String {
        switch presentation {
        case .decodedPayload: localized("Decoded text")
        case .binaryPayload: localized("Hexadecimal bytes")
        case .incompletePayload: localized("Recoverable bits")
        case .visibleContext: localized("Visible context")
        }
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ english: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(english),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
