// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation

public enum RuleValidationError: LocalizedError, Equatable {
    case invalidDomain
    case invalidParameter

    public var errorDescription: String? {
        switch self {
        case .invalidDomain:
            return "Enter a valid domain such as example.com."
        case .invalidParameter:
            return "Enter a query parameter name without a value."
        }
    }
}

public struct CustomURLRule: Codable, Hashable, Identifiable, Sendable {
    public let domain: String
    public let parameter: String

    public var id: String { "\(domain)|\(parameter)" }

    public init(domain: String, parameter: String) throws {
        guard let normalizedDomain = Self.normalizeDomain(domain) else {
            throw RuleValidationError.invalidDomain
        }
        guard let normalizedParameter = Self.normalizeParameter(parameter) else {
            throw RuleValidationError.invalidParameter
        }
        self.domain = normalizedDomain
        self.parameter = normalizedParameter
    }

    private static func normalizeDomain(_ input: String) -> String? {
        var candidate = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard
            let host = URLComponents(string: candidate)?.host?
                .trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            !host.isEmpty,
            host.contains("."),
            !host.contains(" ")
        else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func normalizeParameter(_ input: String) -> String? {
        let forbidden = CharacterSet(charactersIn: "=&?#/ ")
        let candidate = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard
            !candidate.isEmpty,
            candidate.rangeOfCharacter(from: forbidden) == nil
        else {
            return nil
        }
        return candidate
    }
}

public struct PrivateRuleDocument: Codable, Sendable, Equatable {
    public let formatVersion: Int
    public let rules: [CustomURLRule]

    public init(formatVersion: Int = 1, rules: [CustomURLRule]) {
        self.formatVersion = formatVersion
        self.rules = rules
    }
}

public enum URLRulePersistence {
    public static func load(from url: URL) throws -> [CustomURLRule] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(PrivateRuleDocument.self, from: data)
        return Array(Set(document.rules)).sorted {
            $0.domain == $1.domain ? $0.parameter < $1.parameter : $0.domain < $1.domain
        }
    }

    public static func save(_ rules: [CustomURLRule], to url: URL) throws {
        let uniqueRules = Array(Set(rules)).sorted {
            $0.domain == $1.domain ? $0.parameter < $1.parameter : $0.domain < $1.domain
        }
        let document = PrivateRuleDocument(rules: uniqueRules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Copies a legacy rule document into the current location without
    /// deleting the old file or replacing a current document.
    public static func migrateIfNeeded(from legacyURL: URL, to currentURL: URL) throws {
        let fileManager = FileManager.default
        guard
            !fileManager.fileExists(atPath: currentURL.path),
            fileManager.fileExists(atPath: legacyURL.path)
        else {
            return
        }

        try save(load(from: legacyURL), to: currentURL)
    }
}

public struct CommunityRulePack: Codable, Sendable, Equatable {
    public let formatVersion: Int
    public let identifier: String
    public let version: Int
    public let createdAt: String
    public let rules: [CustomURLRule]

    public init(
        formatVersion: Int = 1,
        identifier: String,
        version: Int,
        createdAt: String,
        rules: [CustomURLRule]
    ) {
        self.formatVersion = formatVersion
        self.identifier = identifier
        self.version = version
        self.createdAt = createdAt
        self.rules = rules
    }
}

public struct SignedCommunityRuleEnvelope: Codable, Sendable, Equatable {
    public let payloadBase64: String
    public let signatureBase64: String
    public let publicKeyBase64: String

    public init(payload: Data, signature: Data, publicKey: Data) {
        self.payloadBase64 = payload.base64EncodedString()
        self.signatureBase64 = signature.base64EncodedString()
        self.publicKeyBase64 = publicKey.base64EncodedString()
    }
}

public struct VerifiedCommunityRulePack: Sendable, Equatable {
    public let pack: CommunityRulePack
    public let signerFingerprint: String
}

public enum CommunityRulePackError: LocalizedError, Equatable {
    case invalidEnvelope
    case invalidSignature
    case unsupportedFormat
    case emptyPack

    public var errorDescription: String? {
        switch self {
        case .invalidEnvelope:
            return "The rule pack envelope is malformed."
        case .invalidSignature:
            return "The rule pack signature is invalid."
        case .unsupportedFormat:
            return "This rule pack format is not supported."
        case .emptyPack:
            return "The rule pack does not contain any rules."
        }
    }
}

public enum CommunityRulePackVerifier {
    /// Verifies integrity and returns the signer fingerprint. Trust in that
    /// signer is a separate user decision and must never be inferred here.
    public static func verify(envelopeData: Data) throws -> VerifiedCommunityRulePack {
        guard
            let envelope = try? JSONDecoder().decode(SignedCommunityRuleEnvelope.self, from: envelopeData),
            let payload = Data(base64Encoded: envelope.payloadBase64),
            let signature = Data(base64Encoded: envelope.signatureBase64),
            let publicKeyData = Data(base64Encoded: envelope.publicKeyBase64),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        else {
            throw CommunityRulePackError.invalidEnvelope
        }

        guard publicKey.isValidSignature(signature, for: payload) else {
            throw CommunityRulePackError.invalidSignature
        }

        guard let decodedPack = try? JSONDecoder().decode(CommunityRulePack.self, from: payload) else {
            throw CommunityRulePackError.invalidEnvelope
        }
        guard decodedPack.formatVersion == 1 else {
            throw CommunityRulePackError.unsupportedFormat
        }
        guard !decodedPack.rules.isEmpty else {
            throw CommunityRulePackError.emptyPack
        }

        let normalizedRules: [CustomURLRule]
        do {
            normalizedRules = try decodedPack.rules.map {
                try CustomURLRule(domain: $0.domain, parameter: $0.parameter)
            }
        } catch {
            throw CommunityRulePackError.invalidEnvelope
        }

        let pack = CommunityRulePack(
            identifier: decodedPack.identifier,
            version: decodedPack.version,
            createdAt: decodedPack.createdAt,
            rules: Array(Set(normalizedRules))
        )

        let digest = SHA256.hash(data: publicKeyData)
        let fingerprint = digest.prefix(10)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")

        return VerifiedCommunityRulePack(
            pack: pack,
            signerFingerprint: fingerprint
        )
    }
}
