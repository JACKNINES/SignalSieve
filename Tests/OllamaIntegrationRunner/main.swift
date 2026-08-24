import Foundation
import SignalSieveCore

@main
enum OllamaIntegrationRunner {
    static func main() throws {
        let expectedModel = CommandLine.arguments.dropFirst().first ?? "qwen3.5:4b"
        guard LocalRewriteEngine.isValidModelName(expectedModel) else {
            throw IntegrationFailure("Invalid model name: \(expectedModel)")
        }
        let models = try LocalRewriteEngine.installedModels()
        guard models.contains(expectedModel) else {
            throw IntegrationFailure("Expected model is not installed: \(expectedModel)")
        }

        let source = """
        On 2026-08-22, Signal Sieve recorded 39% at https://example.com/guide and the note said "review before sharing". Signal Sieve examines copied text locally, presents concrete findings, and leaves meaning and intent for the user to confirm.
        """
        let result = try LocalRewriteEngine.rewrite(
            source,
            model: expectedModel,
            style: .humanize,
            timeout: 180
        )

        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntegrationFailure("The model returned empty text")
        }
        guard result.text != source else {
            throw IntegrationFailure("The model returned the original text unchanged")
        }
        guard result.model == expectedModel, result.style == .humanize else {
            throw IntegrationFailure("The rewrite result lost model or style identity")
        }
        let preservationOutcome: String
        switch result.integrityReport.assessment {
        case .reviewRequired:
            guard !result.integrityReport.hasProtectedValueChanges else {
                throw IntegrationFailure("Protected changes exist without a rejecting assessment")
            }
            preservationOutcome = "PASS: exact protected values preserved"
        case .protectedValuesChanged:
            guard result.integrityReport.hasProtectedValueChanges else {
                throw IntegrationFailure("Rejecting assessment has no supporting finding")
            }
            let kinds = Set(result.integrityReport.findings.map { $0.kind.rawValue })
                .sorted()
                .joined(separator: ", ")
            preservationOutcome = "REJECTED SAFELY: \(result.integrityReport.findings.count) protected-value change(s) in \(kinds)"
        default:
            throw IntegrationFailure(
                "Unexpected integrity assessment: \(result.integrityReport.assessment.rawValue)"
            )
        }

        let hidden = HiddenTextAnalyzer.inspect(result.text)
        guard hidden.actionableFindings.isEmpty else {
            throw IntegrationFailure("The rewrite introduced actionable hidden Unicode")
        }
        print("Ollama executable: \(LocalRewriteEngine.executableURL()?.path ?? "missing")")
        print("Installed model: \(expectedModel)")
        print("Input characters: \(source.count)")
        print("Output characters: \(result.text.count)")
        print("Integrity: \(result.integrityReport.assessment.rawValue)")
        print("Protected-value outcome: \(preservationOutcome)")
        print("Lexical divergence: \(Int((result.integrityReport.lexicalDivergence * 100).rounded()))%")
        print("Actionable hidden Unicode in output: \(hidden.actionableFindings.count)")
        print("PASS: Signal Sieve completed a real Ollama rewrite and enforced its integrity boundary")
    }
}

struct IntegrationFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
