// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ProviderWatermarkMechanism: String, Sendable, Equatable {
    case undisclosed = "Mechanism undisclosed"
    case keyedTokenSampling = "Keyed token sampling"
    case invisibleUnicode = "Invisible Unicode"
    case fileProvenance = "File provenance metadata"
}

public enum ProviderDetectorAvailability: String, Sendable, Equatable {
    case unavailable = "No compatible detector published"
    case forthcoming = "Compatible detector details forthcoming"
    case available = "Compatible detector available"
    case integrated = "Compatible detector integrated"
}

public struct ProviderWatermarkProfile: Identifiable, Sendable, Equatable {
    public let id: String
    public let provider: String
    public let product: String
    public let mechanism: ProviderWatermarkMechanism
    public let detectorAvailability: ProviderDetectorAvailability
    public let effectiveFrom: String?
    public let supportedSurfaces: [String]
    public let scopeNote: String
    public let officialDocumentationURL: URL
    public let lastVerified: String

    public init(
        id: String,
        provider: String,
        product: String,
        mechanism: ProviderWatermarkMechanism,
        detectorAvailability: ProviderDetectorAvailability,
        effectiveFrom: String?,
        supportedSurfaces: [String],
        scopeNote: String,
        officialDocumentationURL: URL,
        lastVerified: String
    ) {
        self.id = id
        self.provider = provider
        self.product = product
        self.mechanism = mechanism
        self.detectorAvailability = detectorAvailability
        self.effectiveFrom = effectiveFrom
        self.supportedSurfaces = supportedSurfaces
        self.scopeNote = scopeNote
        self.officialDocumentationURL = officialDocumentationURL
        self.lastVerified = lastVerified
    }
}

public enum ProviderWatermarkDetectionStatus: String, Sendable, Equatable {
    case detected = "Detected by compatible provider adapter"
    case notDetected = "Not detected by compatible provider adapter"
    case inconclusive = "Compatible provider adapter was inconclusive"
}

public struct ProviderWatermarkDetectionResult: Sendable, Equatable {
    public let providerProfileID: String
    public let status: ProviderWatermarkDetectionStatus
    public let evidenceConfidence: EvidenceConfidence
    public let detail: String

    public init(
        providerProfileID: String,
        status: ProviderWatermarkDetectionStatus,
        evidenceConfidence: EvidenceConfidence,
        detail: String
    ) {
        self.providerProfileID = providerProfileID
        self.status = status
        self.evidenceConfidence = evidenceConfidence
        self.detail = detail
    }
}

/// Future provider integrations must implement this boundary instead of
/// reusing Surface Regularity as if it were a compatible detector.
public protocol ProviderWatermarkDetectorAdapter: Sendable {
    var providerProfileID: String { get }
    func analyze(_ text: String) async throws -> ProviderWatermarkDetectionResult
}

public enum ProviderWatermarkRegistry {
    public static let profiles: [ProviderWatermarkProfile] = [
        ProviderWatermarkProfile(
            id: "anthropic.claude.text.2026-08",
            provider: "Anthropic",
            product: "Claude text",
            mechanism: .undisclosed,
            detectorAvailability: .forthcoming,
            effectiveFrom: "2026-08-02",
            supportedSurfaces: ["Claude", "Claude API", "Claude Code", "Cowork", "Tag"],
            scopeNote: "Provider documentation describes supported models launched on or after 2026-08-02; support can vary by model.",
            officialDocumentationURL: URL(string: "https://support.claude.com/en/articles/16266773-how-claude-marks-ai-generated-content")!,
            lastVerified: "2026-08-14"
        )
    ]

    /// No provider detector is bundled until a compatible implementation and
    /// its validation parameters are publicly available and independently tested.
    public static let integratedAdapterProfileIDs: Set<String> = []

    public static func profile(id: String) -> ProviderWatermarkProfile? {
        profiles.first { $0.id == id }
    }
}
