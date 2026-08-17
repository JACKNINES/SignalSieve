// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Groups the same decoded signature across files and verifies neutralization")
func groupsAndNeutralizesSignatures() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveSignatureHunt-\(UUID().uuidString)", isDirectory: true)
    let backups = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveSignatureBackups-\(UUID().uuidString)", isDirectory: true)
    defer { try? manager.removeItem(at: backups) }
    defer { try? manager.removeItem(at: temporary) }
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)

    let message = "Hola estoy oculto!"
    let tags = String(String.UnicodeScalarView(message.unicodeScalars.compactMap { scalar in
        Unicode.Scalar(0xE0000 + scalar.value)
    }))
    for name in ["one.py", "two.py"] {
        try Data("def run():\n    return 1\(tags)\n".utf8)
            .write(to: temporary.appendingPathComponent(name))
    }

    let report = try SignatureHuntEngine.scan(rootURL: temporary)
    let group = try #require(report.groups.first { $0.revealedFragment == message })
    #expect(group.technique == .unicodeTags)
    #expect(group.disposition == .safeToNeutralize)
    #expect(group.occurrenceCount == 2)
    #expect(group.fileCount == 2)
    #expect(group.occurrences.first?.changePreview != nil)

    let result = try SignatureHuntEngine.neutralizeSafeSignatures(
        in: report,
        backupBaseURL: backups
    )
    #expect(result.verificationPassed)
    #expect(result.neutralizedGroupIDs.contains(group.id))
    #expect(result.vaccineResult.sanitizedFileCount == 2)
}

@Test("Honors .signalsieveignore during a signature hunt")
func huntHonorsIgnoreFile() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveSignatureIgnore-\(UUID().uuidString)", isDirectory: true)
    let ignored = temporary.appendingPathComponent("fixtures", isDirectory: true)
    defer { try? manager.removeItem(at: temporary) }
    try manager.createDirectory(at: ignored, withIntermediateDirectories: true)
    try Data("fixtures/\n".utf8).write(to: temporary.appendingPathComponent(".signalsieveignore"))
    try Data("let hidden\u{200B} = true;".utf8).write(to: ignored.appendingPathComponent("attack.swift"))

    let report = try SignatureHuntEngine.scan(rootURL: temporary)
    #expect(report.groups.isEmpty)
    #expect(report.vaccineReport.ignoredPathCount == 1)
}

@Test("Keeps a variation selector in ordinary text as review-only")
func variationSelectorInProseIsReviewOnly() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveSignatureReview-\(UUID().uuidString)", isDirectory: true)
    defer { try? manager.removeItem(at: temporary) }
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    try Data("A visible heart may legitimately use a selector: ♥\u{FE0F}\n".utf8)
        .write(to: temporary.appendingPathComponent("README.txt"))

    let report = try SignatureHuntEngine.scan(rootURL: temporary)
    let group = try #require(report.groups.first { $0.codePoint == "U+FE0F" })
    #expect(group.disposition == .reviewOnly)
    #expect(report.safeGroupCount == 0)
}

@Test("Vaccine preserves UTF-16 LE with BOM while neutralizing")
func vaccinePreservesUTF16Endianness() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveUTF16Vaccine-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = temporary.appendingPathComponent("main.swift")
    defer { try? manager.removeItem(at: temporary) }
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    let source = "let access\u{200B}Level = true\n"
    let encoded = try #require(TextEncodingDetector.encode(
        source,
        as: .utf16LittleEndian,
        includeByteOrderMark: true
    ))
    try encoded.write(to: sourceURL)

    let report = try VaccineEngine.scan(rootURL: temporary)
    let finding = try #require(report.findings.first)
    #expect(finding.textEncoding == .utf16LittleEndian)
    #expect(finding.hasByteOrderMark)
    _ = try VaccineEngine.vaccinate(
        report,
        backupBaseURL: temporary.appendingPathComponent("Backups")
    )
    let output = try Data(contentsOf: sourceURL)
    #expect(output.starts(with: [0xFF, 0xFE]))
    #expect(TextEncodingDetector.decode(output)?.text == "let accessLevel = true\n")
}
