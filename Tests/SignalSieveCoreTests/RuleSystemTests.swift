// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Normalizes private domain rules")
func normalizesPrivateRules() throws {
    let rule = try CustomURLRule(
        domain: "HTTPS://WWW.Example.COM/path",
        parameter: "  Share_Token  "
    )

    #expect(rule.domain == "example.com")
    #expect(rule.parameter == "share_token")
}

@Test("Persists only private rule metadata")
func persistsPrivateRules() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveTests-\(UUID().uuidString)", isDirectory: true)
    let url = directory.appendingPathComponent("private-rules.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let rules = [
        try CustomURLRule(domain: "example.com", parameter: "share_token"),
        try CustomURLRule(domain: "video.example", parameter: "device_id")
    ]
    try URLRulePersistence.save(rules, to: url)
    let loaded = try URLRulePersistence.load(from: url)
    let storedText = try String(contentsOf: url, encoding: .utf8)

    #expect(loaded == rules)
    #expect(!storedText.contains("https://"))
    #expect(!storedText.contains("parameter-value"))
}

@Test("Applies a private rule only to its domain")
func appliesPrivateRuleByDomain() throws {
    let rule = try CustomURLRule(domain: "example.com", parameter: "private_tracker")
    let input = "https://example.com/page?private_tracker=abc&q=keep and https://other.com/page?private_tracker=keep"
    let result = URLTrackerCleaner.cleanLinks(in: input, customRules: [rule])

    #expect(result.text == "https://example.com/page?q=keep and https://other.com/page?private_tracker=keep")
}

@Test("Verifies a signed community rule pack")
func verifiesSignedRulePack() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let pack = CommunityRulePack(
        identifier: "community.test",
        version: 1,
        createdAt: "2026-08-11T00:00:00Z",
        rules: [try CustomURLRule(domain: "example.com", parameter: "campaign_token")]
    )
    let payload = try JSONEncoder().encode(pack)
    let signature = try privateKey.signature(for: payload)
    let envelope = SignedCommunityRuleEnvelope(
        payload: payload,
        signature: signature,
        publicKey: privateKey.publicKey.rawRepresentation
    )
    let envelopeData = try JSONEncoder().encode(envelope)
    let verified = try CommunityRulePackVerifier.verify(envelopeData: envelopeData)

    #expect(verified.pack == pack)
    #expect(!verified.signerFingerprint.isEmpty)
}

@Test("Rejects a community rule pack changed after signing")
func rejectsTamperedRulePack() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let originalPack = CommunityRulePack(
        identifier: "community.test",
        version: 1,
        createdAt: "2026-08-11T00:00:00Z",
        rules: [try CustomURLRule(domain: "example.com", parameter: "safe_rule")]
    )
    let originalPayload = try JSONEncoder().encode(originalPack)
    let signature = try privateKey.signature(for: originalPayload)

    let tamperedPack = CommunityRulePack(
        identifier: "community.test",
        version: 2,
        createdAt: "2026-08-11T00:00:00Z",
        rules: [try CustomURLRule(domain: "example.com", parameter: "different_rule")]
    )
    let tamperedPayload = try JSONEncoder().encode(tamperedPack)
    let envelope = SignedCommunityRuleEnvelope(
        payload: tamperedPayload,
        signature: signature,
        publicKey: privateKey.publicKey.rawRepresentation
    )
    let envelopeData = try JSONEncoder().encode(envelope)

    do {
        _ = try CommunityRulePackVerifier.verify(envelopeData: envelopeData)
        Issue.record("A tampered rule pack was accepted")
    } catch let error as CommunityRulePackError {
        #expect(error == .invalidSignature)
    }
}

@Test("Rejects invalid private rule inputs", arguments: [
    ("localhost", "tracker", RuleValidationError.invalidDomain),
    ("bad domain.example", "tracker", RuleValidationError.invalidDomain),
    ("example.com", "", RuleValidationError.invalidParameter),
    ("example.com", "token=value", RuleValidationError.invalidParameter),
    ("example.com", "token?value", RuleValidationError.invalidParameter)
])
func rejectsInvalidPrivateRules(
    domain: String,
    parameter: String,
    expectedError: RuleValidationError
) {
    do {
        _ = try CustomURLRule(domain: domain, parameter: parameter)
        Issue.record("An invalid private rule was accepted")
    } catch let error as RuleValidationError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("Loading a missing private rule file returns an empty collection")
func loadsMissingRuleFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveMissing-\(UUID().uuidString)")
        .appendingPathComponent("rules.json")

    #expect(try URLRulePersistence.load(from: url).isEmpty)
}

@Test("Persistence deduplicates and sorts private rules")
func deduplicatesPersistedRules() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveTests-\(UUID().uuidString)", isDirectory: true)
    let url = directory.appendingPathComponent("rules.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let later = try CustomURLRule(domain: "z.example", parameter: "z_token")
    let earlier = try CustomURLRule(domain: "a.example", parameter: "a_token")
    try URLRulePersistence.save([later, earlier, later], to: url)

    #expect(try URLRulePersistence.load(from: url) == [earlier, later])
}

@Test("Migrates legacy private rules without deleting the old document")
func migratesLegacyRules() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveMigration-\(UUID().uuidString)", isDirectory: true)
    let legacyURL = directory.appendingPathComponent("TextScrub/private-rules.json")
    let currentURL = directory.appendingPathComponent("SignalSieve/private-rules.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let rule = try CustomURLRule(domain: "example.com", parameter: "legacy_tracker")
    try URLRulePersistence.save([rule], to: legacyURL)
    try URLRulePersistence.migrateIfNeeded(from: legacyURL, to: currentURL)

    #expect(try URLRulePersistence.load(from: currentURL) == [rule])
    #expect(FileManager.default.fileExists(atPath: legacyURL.path))
}

@Test("Migration never overwrites current private rules")
func preservesCurrentRulesDuringMigration() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveMigration-\(UUID().uuidString)", isDirectory: true)
    let legacyURL = directory.appendingPathComponent("TextScrub/private-rules.json")
    let currentURL = directory.appendingPathComponent("SignalSieve/private-rules.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let legacyRule = try CustomURLRule(domain: "legacy.example", parameter: "old")
    let currentRule = try CustomURLRule(domain: "current.example", parameter: "new")
    try URLRulePersistence.save([legacyRule], to: legacyURL)
    try URLRulePersistence.save([currentRule], to: currentURL)
    try URLRulePersistence.migrateIfNeeded(from: legacyURL, to: currentURL)

    #expect(try URLRulePersistence.load(from: currentURL) == [currentRule])
}

@Test("Rejects malformed signed rule envelopes")
func rejectsMalformedEnvelope() {
    do {
        _ = try CommunityRulePackVerifier.verify(envelopeData: Data("not-json".utf8))
        Issue.record("A malformed envelope was accepted")
    } catch let error as CommunityRulePackError {
        #expect(error == .invalidEnvelope)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("Rejects signed payloads that are not valid rule packs")
func rejectsMalformedSignedPayload() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let payload = Data("validly-signed-but-not-json".utf8)
    let envelope = SignedCommunityRuleEnvelope(
        payload: payload,
        signature: try privateKey.signature(for: payload),
        publicKey: privateKey.publicKey.rawRepresentation
    )

    do {
        _ = try CommunityRulePackVerifier.verify(envelopeData: JSONEncoder().encode(envelope))
        Issue.record("A malformed signed payload was accepted")
    } catch let error as CommunityRulePackError {
        #expect(error == .invalidEnvelope)
    }
}

@Test("Rejects unsupported community pack formats")
func rejectsUnsupportedPackFormat() throws {
    let pack = CommunityRulePack(
        formatVersion: 99,
        identifier: "community.future",
        version: 1,
        createdAt: "2026-08-11T00:00:00Z",
        rules: [try CustomURLRule(domain: "example.com", parameter: "token")]
    )

    do {
        _ = try CommunityRulePackVerifier.verify(envelopeData: try signedEnvelopeData(for: pack))
        Issue.record("An unsupported pack format was accepted")
    } catch let error as CommunityRulePackError {
        #expect(error == .unsupportedFormat)
    }
}

@Test("Rejects empty community rule packs")
func rejectsEmptyPack() throws {
    let pack = CommunityRulePack(
        identifier: "community.empty",
        version: 1,
        createdAt: "2026-08-11T00:00:00Z",
        rules: []
    )

    do {
        _ = try CommunityRulePackVerifier.verify(envelopeData: try signedEnvelopeData(for: pack))
        Issue.record("An empty pack was accepted")
    } catch let error as CommunityRulePackError {
        #expect(error == .emptyPack)
    }
}

private func signedEnvelopeData(for pack: CommunityRulePack) throws -> Data {
    let privateKey = Curve25519.Signing.PrivateKey()
    let payload = try JSONEncoder().encode(pack)
    let envelope = SignedCommunityRuleEnvelope(
        payload: payload,
        signature: try privateKey.signature(for: payload),
        publicKey: privateKey.publicKey.rawRepresentation
    )
    return try JSONEncoder().encode(envelope)
}
