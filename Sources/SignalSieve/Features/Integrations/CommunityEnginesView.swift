// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import SignalSieveCore

private enum CommunityTaskResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
}

struct CommunityEnginesView: View {
    @Environment(\.dismiss) private var dismiss

    let text: String
    let language: AppLanguage
    let onUseResult: (String) -> Void

    @State private var health: CommunityWatermarkServiceHealth?
    @State private var capabilities = ""
    @State private var result: CommunityWatermarkServiceResult?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        SheetScaffold(
            title: localized("Community Engines"),
            subtitle: localized("Use independently maintained local MIT tools without making them a Signal Sieve dependency."),
            systemImage: "shippingbox.and.arrow.backward",
            doneTitle: localized("Close"),
            onDone: { dismiss() },
            headerBadge: health?.isHealthy == true
                ? localized("Local service ready")
                : localized("Optional service"),
            footerNote: localized("Signal Sieve never downloads, starts, or updates a community engine automatically."),
            content: { content },
            footer: { EmptyView() }
        )
        .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 680)
        .task { checkHealth() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                disclosureCard
                serviceCard
                if let result { resultCard(result) }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
        }
    }

    private var disclosureCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("watermarks-remover", systemImage: "network.badge.shield.half.filled")
                .font(.headline)
            Text(localized("The adapter accepts only the fixed loopback endpoint 127.0.0.1:8765. Text is sent to that local process only after you press an action button."))
                .font(.callout)
            Text(localized("The engine is independent, MIT-licensed software and a separate trust boundary. Its statistical results apply only to the detector and configuration named in its report."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Local engine status"))
                        .font(.headline)
                    Text(health.map { "watermarks-remover \($0.version)" }
                        ?? localized("No compatible service has answered yet."))
                        .font(.caption.monospaced())
                        .foregroundStyle(health == nil ? Color.secondary : Color.green)
                }
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button(localized("Check Service"), systemImage: "arrow.clockwise") {
                    checkHealth()
                }
                .sieveSheetButton()
                .disabled(isWorking)
            }

            Text("docker run --rm -p 127.0.0.1:8765:8765 --read-only --tmpfs /tmp ghcr.io/guillaumemeyer/watermarks-remover:latest")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))

            HStack {
                Button(localized("Capabilities"), systemImage: "list.bullet.clipboard") {
                    loadCapabilities()
                }
                Button(localized("Inspect with Engine"), systemImage: "magnifyingglass") {
                    run(.inspect)
                }
                Button(localized("Create Community Clean Copy"), systemImage: "doc.badge.gearshape") {
                    run(.clean)
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(isWorking || text.isEmpty || health == nil)

            if !capabilities.isEmpty {
                Text(capabilities)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resultCard(_ result: CommunityWatermarkServiceResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(localized("Community engine report"), systemImage: "checkmark.seal")
                    .font(.headline)
                Spacer()
                Text(result.operation.rawValue.uppercased())
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(result.suspicious == true ? .orange : .green)
            }
            Text(result.report)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            if let cleaned = result.cleanedText {
                let residual = HiddenTextAnalyzer.inspect(cleaned).actionableFindings.count
                    + CovertTextChannelAnalyzer.analyze(cleaned).findings.count
                HStack {
                    Text(formatted("Signal Sieve reanalysis: %d native text risk(s) remain.", residual))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(residual == 0 ? .green : .orange)
                    Spacer()
                    Button(localized("Use as Result"), systemImage: "arrow.down.doc") {
                        onUseResult(cleaned)
                    }
                    .sieveSheetButton(.primary)
                }
            }
        }
        .padding(12)
        .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func checkHealth() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            let outcome = await Task.detached { () -> CommunityTaskResult<CommunityWatermarkServiceHealth> in
                do { return .success(try CommunityWatermarkService.health()) }
                catch { return .failure(Self.message(for: error)) }
            }.value
            isWorking = false
            switch outcome {
            case .success(let value): health = value
            case .failure(let message): health = nil; errorMessage = localized(message)
            }
        }
    }

    private func loadCapabilities() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            let outcome = await Task.detached { () -> CommunityTaskResult<String> in
                do { return .success(try CommunityWatermarkService.capabilities()) }
                catch { return .failure(Self.message(for: error)) }
            }.value
            isWorking = false
            switch outcome {
            case .success(let value): capabilities = value
            case .failure(let message): errorMessage = localized(message)
            }
        }
    }

    private func run(_ operation: CommunityWatermarkOperation) {
        guard !isWorking else { return }
        let sample = text
        isWorking = true
        result = nil
        errorMessage = nil
        Task {
            let outcome = await Task.detached { () -> CommunityTaskResult<CommunityWatermarkServiceResult> in
                do {
                    switch operation {
                    case .inspect: return .success(try CommunityWatermarkService.inspectText(sample))
                    case .clean: return .success(try CommunityWatermarkService.cleanText(sample))
                    }
                } catch {
                    return .failure(Self.message(for: error))
                }
            }.value
            isWorking = false
            switch outcome {
            case .success(let value): result = value
            case .failure(let message): errorMessage = localized(message)
            }
        }
    }

    nonisolated private static func message(for error: Error) -> String {
        switch error as? CommunityWatermarkServiceError {
        case .emptyText: "There is no text to send to the community engine."
        case .inputTooLarge: "The text is too large for the bounded community-engine bridge."
        case .couldNotStart: "Signal Sieve could not start the fixed local curl process."
        case .timedOut: "The local community engine timed out."
        case .serviceUnavailable: "No compatible watermarks-remover service answered on 127.0.0.1:8765."
        case .responseTooLarge: "The community engine response exceeded the safety limit."
        case .invalidResponse: "The community engine returned an invalid response."
        case .serviceRejected(let message): message
        case nil: "The community engine could not complete the request."
        }
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ english: String, _ arguments: CVarArg...) -> String {
        String(format: localized(english), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}
