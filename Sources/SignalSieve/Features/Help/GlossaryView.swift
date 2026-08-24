// SPDX-License-Identifier: MPL-2.0
import Foundation
import SignalSieveCore
import SwiftUI

struct GlossaryView: View {
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        SheetScaffold(
            title: localized("Glossary"),
            subtitle: localized("Plain-language explanations of SignalSieve terms."),
            systemImage: "book.closed",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            headerBadge: formatted("%d terms", filteredEntries.count)
        ) {
            VStack(spacing: 14) {
                TextField(localized("Search terms"), text: $query)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            glossaryCard(entry)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private var filteredEntries: [GlossaryEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return Self.entries }
        return Self.entries.filter { entry in
            localized(entry.term).localizedCaseInsensitiveContains(search)
                || localized(entry.definition).localizedCaseInsensitiveContains(search)
        }
    }

    private func glossaryCard(_ entry: GlossaryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(localized(entry.term))
                    .font(.subheadline.weight(.semibold))
                Text(localized(entry.definition))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ format: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(format),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }

    private struct GlossaryEntry: Identifiable {
        let term: String
        let definition: String
        let systemImage: String

        var id: String { term }
    }

    private static let entries = [
        GlossaryEntry(
            term: "Active Guard",
            definition: "Watches new clipboard copies while SignalSieve is open and warns you locally about enabled risks.",
            systemImage: "eye.circle"
        ),
        GlossaryEntry(
            term: "Copying Settings",
            definition: "Controls automatic cleaning separately from alert visibility. You may hide green and yellow alerts, or hide green through orange alerts. Red alerts always remain visible.",
            systemImage: "arrow.triangle.2.circlepath"
        ),
        GlossaryEntry(
            term: "Safe Clean",
            definition: "Removes confirmed suspicious invisible characters while trying to preserve emojis and normal writing systems.",
            systemImage: "wand.and.stars"
        ),
        GlossaryEntry(
            term: "Strict Clean",
            definition: "Uses stronger Unicode cleanup and normalization. It may change emojis or some writing systems, so review the result.",
            systemImage: "wand.and.sparkles"
        ),
        GlossaryEntry(
            term: "Hidden Unicode",
            definition: "An invisible character that can carry data or change how text is displayed or interpreted.",
            systemImage: "character.cursor.ibeam"
        ),
        GlossaryEntry(
            term: "Carrier Lab",
            definition: "Looks for hidden messages formed by a repeated relationship between spaces, tabs, zero-width symbols, or look-alike letters.",
            systemImage: "point.3.filled.connected.trianglepath.dotted"
        ),
        GlossaryEntry(
            term: "Community Engines",
            definition: "Optional tools installed and maintained outside Signal Sieve. They run as a separate local service and receive text only after you choose an action.",
            systemImage: "shippingbox.and.arrow.backward"
        ),
        GlossaryEntry(
            term: "Red alert",
            definition: "A high-risk finding. Its popup stays in front until you close it, even when automatic cleaning is enabled.",
            systemImage: "exclamationmark.triangle.fill"
        ),
        GlossaryEntry(
            term: "Tracking parameter",
            definition: "Extra information in a link that can identify its source or measure who opened it. Cleaning keeps the useful destination when possible.",
            systemImage: "link"
        ),
        GlossaryEntry(
            term: "My Usual Copy Patterns",
            definition: "An optional local learner that remembers only numerical measurements, such as length and punctuation, to notice unusual future copies. It never stores the copied text.",
            systemImage: "waveform.path.ecg.rectangle"
        ),
        GlossaryEntry(
            term: "UUID",
            definition: "A long unique identifier. It is often legitimate, but it can sometimes connect the same message, device, document, or account across systems.",
            systemImage: "number.square"
        ),
        GlossaryEntry(
            term: "Vaccine",
            definition: "Scans a folder for suspicious text or Unicode and creates reviewable, restorable changes instead of silently editing everything.",
            systemImage: "syringe.fill"
        ),
        GlossaryEntry(
            term: "Signature Hunt",
            definition: "Searches files for a selected suspicious signature and reports where it appears before any change is made.",
            systemImage: "scope"
        ),
        GlossaryEntry(
            term: "Visual Transfer",
            definition: "Renders text as an image and reads it back with local OCR to leave non-visible text encoding behind.",
            systemImage: "viewfinder"
        ),
        GlossaryEntry(
            term: "Metadata",
            definition: "Information stored around a file or image, such as software, dates, author, device, or location. It may reveal more than the visible content.",
            systemImage: "doc.badge.gearshape"
        )
    ]
}
