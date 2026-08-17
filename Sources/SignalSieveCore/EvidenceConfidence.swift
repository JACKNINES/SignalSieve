// SPDX-License-Identifier: MPL-2.0
/// Describes how strongly SignalSieve can support the existence of a finding.
/// This is intentionally independent from the finding's potential impact.
public enum EvidenceConfidence: String, CaseIterable, Sendable, Equatable {
    /// A deterministic observation, such as a specific Unicode scalar.
    case exact = "Exact detection"

    /// Evidence whose integrity has been cryptographically validated.
    case verified = "Cryptographically verified"

    /// A recognized structure with some remaining ambiguity.
    case probable = "Probable detection"

    /// A correlation or model-free score rather than direct evidence.
    case heuristic = "Heuristic indication"

    /// The required compatible detector or validation material is unavailable.
    case notTestable = "Not testable"
}
