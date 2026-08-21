// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import SignalSieveCore

struct PrivateRulesView: View {
    let rules: [CustomURLRule]
    let language: AppLanguage
    let onAdd: (String, String) -> String?
    let onRemove: (CustomURLRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var domain = ""
    @State private var parameter = ""
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(
            title: localized("Private Link Rules"),
            subtitle: localized("Only domain and parameter names are stored locally"),
            systemImage: "slider.horizontal.3",
            doneTitle: localized("Done"),
            onDone: { dismiss() },
            headerBadge: formatted("%d active", rules.count),
            footerNote: localized("Community pack signatures can be verified; automatic downloads remain disabled until a signer is explicitly trusted."),
            content: { rulesContent },
            footer: { EmptyView() }
        )
        .frame(minWidth: 700, minHeight: 580)
    }

    private var rulesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(localized("Add a rule")) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(localized("Domain"))
                        TextField("example.com", text: $domain)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(localized("Parameter"))
                        TextField("share_token", text: $parameter)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 6)

                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button(localized("Add Rule")) { addRule() }
                        .sieveSheetButton(.primary)
                        .disabled(domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || parameter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("Active rules")).font(.headline)
                if rules.isEmpty {
                    Text(localized("No private rules yet."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    List(rules) { rule in
                        HStack {
                            Text(rule.domain).font(.body.monospaced())
                            Text(rule.parameter)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) { onRemove(rule) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(formatted(
                                "Remove rule for %@, %@",
                                rule.domain,
                                rule.parameter
                            ))
                        }
                    }
                    .frame(minHeight: 180)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addRule() {
        errorMessage = onAdd(domain, parameter)
        guard errorMessage == nil else { return }
        domain = ""
        parameter = ""
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ englishFormat: String, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.text(englishFormat, language: language),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
