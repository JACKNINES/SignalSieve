// SPDX-License-Identifier: MPL-2.0
import Foundation
import SignalSieveCore

enum CommunityEngineIntegrationFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case .expectation(let message): message
        }
    }
}

@main
enum CommunityEngineIntegrationRunner {
    static func main() {
        do {
            let source = "Synthetic integration sample\u{200B} with one hidden separator."
            let health = try CommunityWatermarkService.health()
            guard health.isHealthy else {
                throw CommunityEngineIntegrationFailure.expectation("Health response was not accepted")
            }

            let capabilities = try CommunityWatermarkService.capabilities()
            guard !capabilities.isEmpty else {
                throw CommunityEngineIntegrationFailure.expectation("Capabilities response was empty")
            }

            let inspection = try CommunityWatermarkService.inspectText(source)
            guard inspection.operation == .inspect, !inspection.report.isEmpty else {
                throw CommunityEngineIntegrationFailure.expectation("Inspect response was not accepted")
            }

            let clean = try CommunityWatermarkService.cleanText(source)
            guard let cleaned = clean.cleanedText, cleaned != source else {
                throw CommunityEngineIntegrationFailure.expectation("Clean did not return a changed text copy")
            }
            let residual = HiddenTextAnalyzer.inspect(cleaned).actionableFindings.count
                + CovertTextChannelAnalyzer.analyze(cleaned).findings.count
            guard residual == 0 else {
                throw CommunityEngineIntegrationFailure.expectation(
                    "Native reanalysis found \(residual) residual text risk(s)"
                )
            }

            print("Community engine smoke test passed")
            print("Service version: \(health.version)")
            print("Inspect kind: \(inspection.kind ?? "unknown")")
            print("Clean kind: \(clean.kind ?? "unknown")")
            print("Native residual risks: \(residual)")
        } catch {
            FileHandle.standardError.write(Data("Community engine smoke test failed: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
