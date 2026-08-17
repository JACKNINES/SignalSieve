// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import SignalSieveCore

enum LocalTestFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case .expectation(let message): message
        }
    }
}

struct LocalTestSkip: Error, CustomStringConvertible {
    let description: String
}

struct LocalTestCase {
    let name: String
    let body: () throws -> Void
}

@main
enum LocalTestRunner {
    static func main() {
        let tests = [
            LocalTestCase(name: "hidden Unicode classification", body: testHiddenUnicode),
            LocalTestCase(name: "contextual Unicode preservation", body: testContextualUnicode),
            LocalTestCase(name: "private research query", body: testPrivateResearchQuery),
            LocalTestCase(name: "Unicode positions", body: testUnicodePositions),
            LocalTestCase(name: "safe and strict cleaning", body: testCleaningModes),
            LocalTestCase(name: "source-code security", body: testCodeGuard),
            LocalTestCase(name: "programming-language detection", body: testCodeLanguageDetection),
            LocalTestCase(name: "binary and encoded-data detection", body: testBinaryDetection),
            LocalTestCase(name: "Vaccine project sanitization", body: testVaccine),
            LocalTestCase(name: "invisible fragment revelation", body: testInvisibleFragmentRevelation),
            LocalTestCase(name: "text encoding and endianness", body: testTextEncoding),
            LocalTestCase(name: "Signature Hunt grouping and verification", body: testSignatureHunt),
            LocalTestCase(name: "Vaccine self-protection", body: testVaccineSelfProtection),
            LocalTestCase(name: "source-code false-positive guard", body: testCodeGuardFalsePositives),
            LocalTestCase(name: "Instagram and universal URL cleaning", body: testUniversalURLCleaning),
            LocalTestCase(name: "service-specific URL cleaning", body: testServiceURLCleaning),
            LocalTestCase(name: "functional URL preservation", body: testFunctionalURLPreservation),
            LocalTestCase(name: "private domain rules", body: testPrivateRules),
            LocalTestCase(name: "private rule persistence", body: testRulePersistence),
            LocalTestCase(name: "pattern detection", body: testPatternDetection),
            LocalTestCase(name: "pattern false-positive guard", body: testUnrelatedPatterns),
            LocalTestCase(name: "statistical watermark probe boundaries", body: testWatermarkProbe),
            LocalTestCase(name: "read-only file provenance inspection", body: testFileProvenance),
            LocalTestCase(name: "verified metadata copy cleaning", body: testMetadataCleaning),
            LocalTestCase(name: "external pixel module contract", body: testExternalPixelModule),
            LocalTestCase(name: "built-in LSB pixel forensics", body: testPixelLSBBaseline),
            LocalTestCase(name: "built-in spectral pixel forensics", body: testPixelSpectralLab),
            LocalTestCase(name: "local rewrite boundaries", body: testLocalRewriteBoundaries),
            LocalTestCase(name: "non-text clipboard type inventory", body: testClipboardTypeInventory),
            LocalTestCase(name: "bounded clipboard image import", body: testClipboardImageImport),
            LocalTestCase(name: "rewrite integrity boundaries", body: testRewriteIntegrity),
            LocalTestCase(name: "active clipboard protection", body: testActiveClipboardProtection),
            LocalTestCase(name: "bounded private clipboard history", body: testClipboardHistory),
            LocalTestCase(name: "English, Spanish, and Norwegian localization", body: testLocalization),
            LocalTestCase(name: "safe copyable finding reports", body: testFindingReports),
            LocalTestCase(name: "signed community packs", body: testSignedPack),
            LocalTestCase(name: "tampered community packs", body: testTamperedPack),
            LocalTestCase(name: "empty visual transfer", body: testEmptyVisualTransfer),
            LocalTestCase(name: "local visual transfer", body: testVisualTransfer)
        ]

        var failures: [String] = []
        var skipped: [String] = []
        for test in tests {
            do {
                try test.body()
                print("PASS  \(test.name)")
            } catch let skip as LocalTestSkip {
                skipped.append("\(test.name): \(skip)")
                print("SKIP  \(test.name): \(skip)")
            } catch {
                failures.append("\(test.name): \(error)")
                print("FAIL  \(test.name): \(error)")
            }
        }

        if failures.isEmpty {
            print("\n\(tests.count - skipped.count) local test group(s) passed; \(skipped.count) skipped by environment.")
        } else {
            FileHandle.standardError.write(
                Data("\n\(failures.count) local test group(s) failed.\n".utf8)
            )
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func testHiddenUnicode() throws {
        let inspection = HiddenTextAnalyzer.inspect("hola\u{200B}mundo\u{202E}\u{00A0}!")
        try expect(inspection.findings.map(\.kind) == [
            .zeroWidth,
            .bidirectional,
            .unusualWhitespace
        ], "Unexpected hidden-element classification")
        try expect(inspection.findings.map { $0.kind.riskLevel } == [
            .medium,
            .high,
            .suspicious
        ], "Unexpected hidden-element risk levels")
        try expect(HiddenTextAnalyzer.inspect("line one\nline two\tvalue").isClean, "Visible whitespace was flagged")

        let directionalMarks = HiddenTextAnalyzer.inspect("A\u{061C}B\u{200E}C\u{200F}D")
        try expect(
            directionalMarks.findings.map(\.kind) == [.bidirectional, .bidirectional, .bidirectional],
            "ALM, LRM, or RLM was not classified as a bidirectional control"
        )
        try expect(
            directionalMarks.findings.allSatisfy { $0.kind.riskLevel == .high },
            "A directional mark did not receive high risk"
        )
    }

    private static func testPrivateResearchQuery() throws {
        let source = "private-before\u{200B}private-after"
        let finding = try value(HiddenTextAnalyzer.inspect(source).findings.first, "Missing finding")
        let url = try value(finding.researchURL, "Missing research URL")
        let components = try value(URLComponents(url: url, resolvingAgainstBaseURL: false), "Invalid research URL")
        let query = try value(
            components.queryItems?.first(where: { $0.name == "q" })?.value,
            "Missing research query"
        )
        try expect(url.host == "duckduckgo.com", "Unexpected research host")
        try expect(query.contains("U+200B"), "The query omitted the code point")
        try expect(!query.contains("private-before"), "The query leaked source text")
    }

    private static func testContextualUnicode() throws {
        let family = "👨\u{200D}👩\u{200D}👧"
        let persian = "نامه\u{200C}ای"
        let devanagari = "क्\u{200D}ष"
        let mixedDirection = "العربية\u{200F} English"
        let ideographic = "邊\u{E0100}"
        let wales = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"

        for functional in [family, persian, devanagari, mixedDirection, ideographic, wales] {
            let inspection = HiddenTextAnalyzer.inspect(functional)
            try expect(!inspection.findings.isEmpty, "A functional invisible was not reported")
            try expect(inspection.isClean, "A functional Unicode sequence was marked actionable")
            try expect(
                inspection.findings.allSatisfy { $0.riskLevel == .clear },
                "A functional Unicode sequence was not marked clear"
            )
            try expect(
                TextCleaner.clean(functional, mode: .safe).text == functional,
                "Safe cleaning altered functional Unicode"
            )
        }

        let payload = "A\u{FE0F}B\u{200D}C\u{200C}D"
        let payloadInspection = HiddenTextAnalyzer.inspect(payload)
        try expect(payloadInspection.actionableFindings.count == 3, "Payload carriers were not actionable")
        try expect(TextCleaner.clean(payload, mode: .safe).text == "ABCD", "Safe cleaning retained payload carriers")
        try expect(InvisibleFragmentRevealer.reveal(in: family).isEmpty, "Reveal treated emoji composition as a payload")
        try expect(ClipboardHistory.visiblePreview(family) == family, "Clipboard history broke emoji composition")
    }

    private static func testUnicodePositions() throws {
        let result = HiddenTextAnalyzer.inspect("😀A\u{200B}B")
        let finding = try value(result.findings.first, "Missing zero-width finding")
        try expect(finding.scalarPosition == 3, "Wrong scalar position")
        try expect(finding.utf16Position == 4, "Wrong UTF-16 position")
    }

    private static func testCleaningModes() throws {
        let suspicious = "hola\u{200B}mundo\u{202E}\u{00A0}!"
        let safe = TextCleaner.clean(suspicious, mode: .safe)
        try expect(safe.text == "holamundo !", "Safe cleaning produced unexpected text")
        try expect(safe.removedCount == 2 && safe.replacedCount == 1, "Safe cleaning counts are wrong")

        let family = "👨\u{200D}👩\u{200D}👧"
        try expect(TextCleaner.clean(family, mode: .safe).text == family, "Safe mode altered an emoji")
        let strict = TextCleaner.clean(family, mode: .strict).text
        try expect(strict != family, "Strict mode retained invisible joiners")
        try expect(HiddenTextAnalyzer.inspect(strict).isClean, "Strict output still contains hidden elements")

        let directionalMarks = "A\u{061C}B\u{200E}C\u{200F}D"
        for mode in [CleaningMode.safe, .strict] {
            let cleaned = TextCleaner.clean(directionalMarks, mode: mode)
            try expect(cleaned.text == "ABCD", "A bidirectional mark survived cleaning")
            try expect(cleaned.removedCount == 3, "Directional-mark removal count is wrong")
        }
    }

    private static func testCodeGuard() throws {
        let source = "let p\u{0430}ssword\u{200B} = “value”\u{00A0}; // guard\u{202E}"
        let analysis = CodeGuardAnalyzer.analyze(source)
        try expect(analysis.isLikelyCode, "Code Guard did not recognize source code")
        try expect(analysis.findings.contains { $0.kind == .confusableIdentifier }, "Confusable identifier was missed")
        try expect(analysis.findings.contains { $0.kind == .invisibleCharacter }, "Invisible code character was missed")
        try expect(analysis.findings.contains { $0.kind == .bidirectionalControl }, "Trojan Source control was missed")
        try expect(analysis.findings.contains { $0.kind == .typographicPunctuation }, "Typographic punctuation was missed")

        let sanitized = CodeGuardAnalyzer.sanitize(source)
        try expect(!sanitized.text.contains("\u{200B}"), "Code sanitizer retained a zero-width character")
        try expect(!sanitized.text.contains("\u{202E}"), "Code sanitizer retained a bidi control")
        try expect(sanitized.text.contains("p\u{0430}ssword"), "Code sanitizer guessed a confusable identifier replacement")
        try expect(sanitized.text.contains("\"value\""), "Code sanitizer did not normalize smart quotes")
    }

    private static func testCodeGuardFalsePositives() throws {
        let prose = CodeGuardAnalyzer.analyze("Let the reader review this ordinary sentence without source code.")
        try expect(!prose.isLikelyCode && prose.findings.isEmpty, "Ordinary prose was classified as code")

        let cyrillic = CodeGuardAnalyzer.analyze("let пароль = true;")
        try expect(cyrillic.isLikelyCode, "Valid Unicode code was not recognized")
        try expect(
            !cyrillic.findings.contains { $0.kind == .mixedScriptIdentifier || $0.kind == .confusableIdentifier },
            "A single-script identifier was flagged"
        )
    }

    private static func testBinaryDetection() throws {
        try expect(BinaryContentDetector.analyze("SGVsbG8sIFNpZ25hbCBTaWV2ZSE=").kind == .base64, "Base64 was missed")
        try expect(BinaryContentDetector.analyze("89 50 4E 47 0D 0A 1A 0A").kind == .hexadecimal, "Hex bytes were missed")
        try expect(BinaryContentDetector.analyze("01010011 01101001 01100111 01101110").kind == .binaryDigits, "Binary digits were missed")
        try expect(BinaryContentDetector.analyze(#"\x48 \x65 \x6c \x6c \x6f"#).kind == .byteEscapes, "Byte escapes were missed")
        try expect(BinaryContentDetector.analyze(Data([0x7F, 0x45, 0x4C, 0x46])).kind == .rawBinary, "ELF data was missed")
        try expect(!BinaryContentDetector.analyze("A normal sentence about copied text.").isDetected, "Prose was classified as binary")
    }

    private static func testVaccine() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("SignalSieveVaccineLocal-\(UUID().uuidString)", isDirectory: true)
        let project = directory.appendingPathComponent("Project", isDirectory: true)
        let sourceURL = project.appendingPathComponent("main.swift")
        let binaryURL = project.appendingPathComponent("asset.bin")
        defer { try? manager.removeItem(at: directory) }
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        let source = "import Foundation\nlet access\u{200B}Level = “admin”\u{00A0}\n"
        try Data(source.utf8).write(to: sourceURL)
        try Data([0x7F, 0x45, 0x4C, 0x46, 0x00]).write(to: binaryURL)

        let report = try VaccineEngine.scan(rootURL: project)
        try expect(report.scannedFileCount == 1 && report.binaryFileCount == 1, "Vaccine scan counts were wrong")
        try expect(report.sanitizableFileCount == 1, "Vaccine missed a sanitizable source file")

        var metadataPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        metadataPNG.append(localPNGChunk("eXIf", payload: Data("private".utf8)))
        metadataPNG.append(localPNGChunk("IEND", payload: Data()))
        let metadataURL = project.appendingPathComponent("photo.png")
        try metadataPNG.write(to: metadataURL)
        let metadataReport = try VaccineEngine.scan(rootURL: project)
        try expect(metadataReport.provenanceScannedFileCount == 1, "Vaccine did not inspect file provenance")
        try expect(metadataReport.totalMetadataFindingCount == 1, "Vaccine missed folder metadata")
        let result = try VaccineEngine.vaccinate(
            report,
            backupBaseURL: directory.appendingPathComponent("Backups")
        )
        try expect(result.sanitizedFileCount == 1, "Vaccine did not sanitize the file")
        try expect(manager.fileExists(atPath: result.backupURL.appendingPathComponent("main.swift").path), "Vaccine backup is missing")
        let cleaned = try String(contentsOf: sourceURL, encoding: .utf8)
        try expect(cleaned == "import Foundation\nlet accessLevel = \"admin\" \n", "Vaccine output was unexpected")
    }

    private static func testVaccineSelfProtection() throws {
        let manager = FileManager.default
        let actualProjectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try expect(
            VaccineEngine.isSignalSieveTarget(actualProjectRoot),
            "The real SignalSieve project was not recognized as self"
        )
        let directory = manager.temporaryDirectory
            .appendingPathComponent("SignalSieveSelfVaccineLocal-\(UUID().uuidString)", isDirectory: true)
        let appSource = directory.appendingPathComponent("Sources/SignalSieve/SignalSieveApp.swift")
        let infoURL = directory.appendingPathComponent("Packaging/Info.plist")
        defer { try? manager.removeItem(at: directory) }
        try manager.createDirectory(at: appSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(at: infoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("import SwiftUI\n@main struct SignalSieveApp: App {}\n".utf8).write(to: appSource)
        try Data("let package = Package(name: \"SignalSieve\", products: [.executable(name: \"SignalSieve\", targets: [\"SignalSieve\"])])".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "com.signalsieve.app"],
            format: .xml,
            options: 0
        )
        try plist.write(to: infoURL)

        let report = try VaccineEngine.scan(rootURL: directory)
        try expect(report.isSignalSieveTarget, "SignalSieve source project was not recognized")
        do {
            _ = try VaccineEngine.vaccinate(
                report,
                backupBaseURL: directory.appendingPathComponent("Backups")
            )
            throw LocalTestFailure.expectation("Vaccine allowed SignalSieve to modify itself")
        } catch VaccineError.selfVaccinationBlocked {
            // Expected safety boundary.
        }
    }

    private static func testInvisibleFragmentRevelation() throws {
        let message = "Hola estoy oculto!"
        let tags = String(String.UnicodeScalarView(message.unicodeScalars.compactMap { scalar in
            Unicode.Scalar(0xE0000 + scalar.value)
        }))
        let tagPreview = InvisibleFragmentRevealer.reveal(
            in: "def run():\n    print('safe')\(tags)\n"
        ).first
        try expect(tagPreview?.text == message, "Unicode Tag payload was not revealed")
        try expect(tagPreview?.presentation == .decodedPayload, "Unicode Tags were shown only as context")

        let fallback = InvisibleFragmentRevealer.reveal(
            in: "let greeting = \"Hola\"\u{FE0F}\n"
        ).first
        try expect(fallback?.presentation == .visibleContext, "A lone selector was incorrectly decoded")
        try expect(fallback?.text.contains("⟦U+FE0F⟧") == true, "The invisible selector was not made visible")

        var joinerPayload = ""
        for byte in "u suck".utf8 {
            for shift in stride(from: 7, through: 0, by: -1) {
                joinerPayload.append(((byte >> shift) & 1) == 0 ? "\u{200C}" : "\u{200D}")
            }
        }
        let decoded = InvisibleFragmentRevealer.reveal(in: "Visible\(joinerPayload)").first
        try expect(decoded?.text == "u suck", "ZWNJ/ZWJ binary payload was not revealed")
        var incompleteScalars = Array(joinerPayload.unicodeScalars)
        incompleteScalars.removeLast()
        let incompletePayload = String(String.UnicodeScalarView(incompleteScalars))
        let incomplete = InvisibleFragmentRevealer.reveal(
            in: "Visible\(incompletePayload)"
        ).first
        try expect(
            incomplete?.presentation == .incompletePayload,
            "A truncated binary payload was not reported as incomplete"
        )
        try expect(
            incomplete?.zeroWidthBinary?.probableTextEquivalence?.text == "u suck",
            "A close known payload was not labeled as a probable equivalence"
        )

        let damagedBits = "11101000010000001110011011101001100001101101011"
        let damagedPayload = String(String.UnicodeScalarView(damagedBits.compactMap { bit in
            Unicode.Scalar(bit == "0" ? 0x200C : 0x200D)
        }))
        let damaged = InvisibleFragmentRevealer.reveal(
            in: "Acting like is worth sum is next level\(damagedPayload) 💀"
        ).first
        let equivalence = damaged?.zeroWidthBinary?.probableTextEquivalence
        try expect(equivalence?.text == "u suck", "The documented damaged payload was not recovered")
        try expect(equivalence?.bitEditDistance == 4, "Recovery omitted its binary edit distance")
        try expect(equivalence?.confidence == .low, "Damaged recovery was presented too confidently")
    }

    private static func testTextEncoding() throws {
        let text = "let value\u{200B} = true\n"
        for encoding in TextEncodingKind.allCases {
            for hasBOM in [false, true] {
                let data = try value(
                    TextEncodingDetector.encode(text, as: encoding, includeByteOrderMark: hasBOM),
                    "Could not encode \(encoding.rawValue)"
                )
                let decoded = try value(TextEncodingDetector.decode(data), "Could not detect \(encoding.rawValue)")
                try expect(
                    decoded.text == text,
                    "Text changed while decoding \(encoding.rawValue), BOM=\(hasBOM), detected=\(decoded.encoding.rawValue), value=\(decoded.text.debugDescription)"
                )
                try expect(decoded.encoding == encoding, "Wrong encoding detected for \(encoding.rawValue)")
                try expect(decoded.hasByteOrderMark == hasBOM, "BOM status was not preserved")
            }
        }
    }

    private static func testSignatureHunt() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("SignalSieveSignatureLocal-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: directory) }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let message = "Hola estoy oculto!"
        let tags = String(String.UnicodeScalarView(message.unicodeScalars.compactMap { scalar in
            Unicode.Scalar(0xE0000 + scalar.value)
        }))
        for name in ["one.py", "two.py"] {
            try Data("def run():\n    return 1\(tags)\n".utf8)
                .write(to: directory.appendingPathComponent(name))
        }

        let report = try SignatureHuntEngine.scan(rootURL: directory)
        let group = try value(
            report.groups.first { $0.revealedFragment == message },
            "Decoded signature group was not created"
        )
        try expect(group.occurrenceCount == 2 && group.fileCount == 2, "Signature occurrences were not grouped")
        let result = try SignatureHuntEngine.neutralizeSafeSignatures(
            in: report,
            backupBaseURL: manager.temporaryDirectory
                .appendingPathComponent("SignalSieveSignatureBackups-\(UUID().uuidString)")
        )
        try expect(result.verificationPassed, "Post-neutralization scan still found the signature")
        try expect(result.neutralizedGroupIDs.contains(group.id), "Neutralized signature was not verified")
    }

    private static func testCodeLanguageDetection() throws {
        let samples: [(CodeLanguage, String)] = [
            (.swift, "import Foundation\nfunc greet(name: String) -> String { name }"),
            (.typescript, "interface User { id: number; name: string }\nconst user: User = { id: 1, name: 'A' };"),
            (.javascript, "const greet = (name) => console.log(name);"),
            (.rust, "fn main() { let mut count = 0; println!(\"{}\", count); }"),
            (.python, "def greet(name: str) -> str:\n    return name if name is not None else ''"),
            (.c, "#include <stdio.h>\nint main(void) { printf(\"hi\"); return 0; }"),
            (.cpp, "#include <iostream>\nint main() { std::cout << \"hi\"; }"),
            (.objectiveC, "#import <Foundation/Foundation.h>\n@interface Greeter : NSObject\n@end"),
            (.go, "package main\nfunc main() { value := 1; fmt.Println(value) }"),
            (.java, "package demo;\npublic class Main { public static void main(String[] args) { System.out.println(args); } }"),
            (.kotlin, "data class User(val name: String)\nfun main() { println(User(\"A\")) }"),
            (.cSharp, "using System;\nnamespace Demo { public class MainClass { Console.WriteLine(1); } }"),
            (.shell, "#!/usr/bin/env bash\nfor file in *.txt; do echo \"${file}\"; done"),
            (.sql, "SELECT user_id, COUNT(*) FROM events GROUP BY user_id ORDER BY user_id;"),
            (.solidity, "pragma solidity ^0.8.20;\ncontract Vault { mapping(address => uint256) balances; }"),
            (.move, "module 0x1::vault { public entry fun deposit(account: &signer) { move_to(account, Vault {}); } }"),
            (.ruby, "def greet\n  puts 'hello'\nend"),
            (.php, "<?php\n$user = 'Ada';\necho $user;"),
            (.dart, "import 'package:flutter/widgets.dart';\nclass App extends StatelessWidget { Widget build(context) => Text('Hi'); }"),
            (.lua, "local function greet(name)\n  print(name)\nend"),
            (.html, "<!DOCTYPE html><html><body><main>Hello</main></body></html>"),
            (.css, ".card {\n  display: flex;\n  color: blue;\n}"),
            (.json, "{\"name\":\"Signal Sieve\",\"enabled\":true}"),
            (.yaml, "name: Signal Sieve\nenabled: true\nlanguages:\n  - Swift"),
            (.toml, "[package]\nname = \"signal-sieve\"\nversion = \"0.3.0\"")
        ]

        for (expected, source) in samples {
            let detection = CodeLanguageDetector.detect(source)
            try expect(detection.isLikelyCode, "Did not recognize \(expected.rawValue) as code")
            try expect(
                detection.primary == expected,
                "Expected \(expected.rawValue), detected \(detection.displayName)"
            )
        }

        let ambiguous = CodeLanguageDetector.detect("let answer = compute(value);")
        try expect(ambiguous.isLikelyCode && ambiguous.primary == nil, "Ambiguous shared syntax was guessed")
    }

    private static func testUniversalURLCleaning() throws {
        let result = URLTrackerCleaner.cleanLinks(
            in: "https://www.instagram.com/reel/DbyPgivF8qU/?utm_source=ig_web_copy_link&igsh=value"
        )
        try expect(result.text == "https://www.instagram.com/reel/DbyPgivF8qU", "Instagram cleanup failed")
        try expect(result.removedParameterCount == 2, "Unexpected Instagram removal count")

        let prose = URLTrackerCleaner.cleanLinks(
            in: "See https://example.com/a?q=keep&utm_medium=email, then continue."
        )
        try expect(prose.text == "See https://example.com/a?q=keep, then continue.", "Prose URL cleanup failed")
    }

    private static func testServiceURLCleaning() throws {
        let social = URLTrackerCleaner.cleanLinks(
            in: "https://youtu.be/abc?si=share https://www.tiktok.com/@u/video/1?_t=x&_r=1 https://x.com/u/status/2?s=20&t=x"
        )
        try expect(
            social.text == "https://youtu.be/abc https://www.tiktok.com/@u/video/1 https://x.com/u/status/2",
            "YouTube, TikTok, or X cleanup failed"
        )

        let destination = "https%3A%2F%2Fexample.com%2Farticle%3Fq%3Dprivacy%26utm_source%3Dfacebook"
        let facebook = URLTrackerCleaner.cleanLinks(
            in: "https://l.facebook.com/l.php?u=\(destination)&h=signature"
        )
        try expect(facebook.text == "https://example.com/article?q=privacy", "Facebook redirect cleanup failed")
    }

    private static func testFunctionalURLPreservation() throws {
        let signedURL = "https://files.example.com/download?signature=required&expires=123#section"
        try expect(URLTrackerCleaner.cleanLinks(in: signedURL).text == signedURL, "A functional signature was removed")

        let noLinks = URLTrackerCleaner.cleanLinks(in: "Plain text only")
        try expect(noLinks.linksFound == 0 && noLinks.text == "Plain text only", "Plain text was changed")
    }

    private static func testPrivateRules() throws {
        let rule = try CustomURLRule(domain: "HTTPS://WWW.Example.COM/path", parameter: " Private_Tracker ")
        try expect(rule.domain == "example.com", "Domain normalization failed")
        try expect(rule.parameter == "private_tracker", "Parameter normalization failed")

        let result = URLTrackerCleaner.cleanLinks(
            in: "https://news.example.com/a?private_tracker=x&q=keep https://notexample.com/a?private_tracker=keep",
            customRules: [rule]
        )
        try expect(
            result.text == "https://news.example.com/a?q=keep https://notexample.com/a?private_tracker=keep",
            "Private rule crossed its domain boundary"
        )
    }

    private static func testRulePersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignalSieveLocalTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("rules.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let later = try CustomURLRule(domain: "z.example", parameter: "token")
        let earlier = try CustomURLRule(domain: "a.example", parameter: "token")
        try URLRulePersistence.save([later, earlier, later], to: url)
        let loaded = try URLRulePersistence.load(from: url)
        try expect(loaded == [earlier, later], "Rules were not deduplicated and sorted")
    }

    private static func testPatternDetection() throws {
        let report = PatternAnalyzer.analyze([
            "Privacy tools should remain entirely local and transparent for everyone. This sample discusses links.",
            "Our view is that privacy tools should remain entirely local and transparent for everyone. This sample discusses Unicode.",
            "In practice, privacy tools should remain entirely local and transparent for everyone. This sample discusses patterns."
        ])
        try expect(report.sampleCount == 3, "Pattern analysis lost a sample")
        try expect(report.findings.contains { finding in
            finding.kind == .repeatedPhrase
                && finding.pattern.contains("privacy tools should remain entirely local")
        }, "Repeated phrase was not detected")
    }

    private static func testUnrelatedPatterns() throws {
        let report = PatternAnalyzer.analyze([
            "A report about coastal weather and changing temperatures.",
            "Software teams review database migrations before deployment begins.",
            "The museum opened a collection of landscape paintings."
        ])
        try expect(!report.hasSuspiciousRepetition, "Unrelated samples produced a false positive")
    }

    private static func testWatermarkProbe() throws {
        let short = WatermarkProbeAnalyzer.analyze("A short sample cannot support a statistical conclusion.")
        try expect(short.assessment == .insufficientText, "Watermark Probe assessed a short sample")

        let varied = """
        I interviewed a research team and spent a month reading its public material. The central idea is that a generator can make small token choices that are individually ordinary. Across a sufficiently long sample, a detector with matching configuration may measure a bias in those choices. That observation does not establish why any particular assistant writes at length. Product style, safety training, user instructions, and ordinary variation can all affect response length. A careful review therefore separates a documented algorithm from claims about one provider's motives. It also avoids treating fluent prose, connective words, or long answers as proof of origin. Paraphrasing can alter token sequences and may weaken some published detectors, although the outcome depends on the scheme, the amount of text, and the strength of the edit. Back translation is another transformation rather than a universal guarantee. A short answer may contain too little evidence for a detector, but absence of evidence in a short sample is not evidence that no watermark exists. Any reliable provider-specific conclusion requires the correct tokenizer, detector settings, secret material, and calibrated reference data.
        """
        let natural = WatermarkProbeAnalyzer.analyze(varied)
        try expect(natural.assessment == .noElevatedRegularity, "Verbosity alone triggered Watermark Probe")

        let mechanical = (1...16).map { index in
            "Signal pattern keeps the same repeated phrase while numbered sample \(index) preserves cadence."
        }.joined(separator: " ")
        let elevated = WatermarkProbeAnalyzer.analyze(mechanical)
        try expect(elevated.assessment == .elevatedRegularity, "Mechanical regularity was missed")
        try expect(elevated.elevatedSignalCount >= 3, "Too few independent indicators were reported")

        let report = FindingReportFormatter.watermarkProbeReport(elevated, language: .english)
        try expect(report.contains("keyless heuristic screen"), "Copied probe report omitted its limitation")
        try expect(
            report.contains("Provider watermark: Not testable without a compatible detector"),
            "Copied probe report implied that provider watermark status was testable"
        )
        try expect(
            ProviderWatermarkRegistry.profiles.allSatisfy {
                $0.mechanism == .undisclosed
                    && $0.detectorAvailability != .integrated
                    && !ProviderWatermarkRegistry.integratedAdapterProfileIDs.contains($0.id)
            },
            "Provider registry claimed an unverified detector or mechanism"
        )
        try expect(
            AppLocalization.text("Surface Regularity", language: .spanish) == "Regularidad superficial",
            "Surface Regularity Spanish translation is missing"
        )
        try expect(
            AppLocalization.text("Review", language: .spanish) == "Revisar"
                && AppLocalization.text("Analyze", language: .spanish) == "Analizar"
                && AppLocalization.text("Clean", language: .spanish) == "Limpiar",
            "Spanish toolbar section translations are missing"
        )
        try expect(
            AppLocalization.text("Review", language: .norwegianBokmal) == "Se gjennom"
                && AppLocalization.text("Analyze", language: .norwegianBokmal) == "Analyser"
                && AppLocalization.text("Clean", language: .norwegianBokmal) == "Rens",
            "Norwegian toolbar section translations are missing"
        )
    }

    private static func testFileProvenance() throws {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(localPNGChunk("caBX", payload: Data("manifest".utf8)))
        png.append(localPNGChunk("eXIf", payload: Data("private".utf8)))
        png.append(localPNGChunk("IEND", payload: Data()))

        let pngReport = FileProvenanceAnalyzer.analyze(png, fileName: "sample.png")
        try expect(pngReport.containsC2PAContainer, "PNG caBX provenance was missed")
        try expect(
            pngReport.findings.contains { $0.kind == .exifMetadata },
            "PNG EXIF metadata was missed"
        )
        try expect(
            pngReport.findings.allSatisfy { $0.evidenceConfidence == .exact },
            "Parsed PNG structures were not marked exact"
        )
        let mismatchedExtensionReport = FileProvenanceAnalyzer.analyze(
            png,
            fileName: "masquerade.svg"
        )
        try expect(mismatchedExtensionReport.format == .png, "Byte signature lost to file extension")
        try expect(
            mismatchedExtensionReport.findings.contains {
                $0.kind == .extensionContentMismatch && $0.evidenceConfidence == .exact
            },
            "Extension and content mismatch was not reported"
        )
        let copiedPNGReport = FindingReportFormatter.fileProvenanceReport(
            pngReport,
            language: .english
        )
        try expect(
            copiedPNGReport.contains("cryptographic validation not performed"),
            "Copied provenance report overstated C2PA validation"
        )

        var jpeg = Data([0xFF, 0xD8, 0xFF, 0xEB, 0x00, 0x0B])
        jpeg.append(Data("not-c2pa".utf8))
        jpeg.append(contentsOf: [0xFF, 0xD9])
        let jpegReport = FileProvenanceAnalyzer.analyze(jpeg, fileName: "sample.jpg")
        try expect(
            jpegReport.findings.contains { $0.kind == .jpegApp11 },
            "Generic JPEG APP11 metadata was missed"
        )
        try expect(!jpegReport.containsC2PAContainer, "Generic JPEG APP11 was misclassified as C2PA")

        var wrappedPDF = Data("HTTP/1.0 200 OK\r\nContent-Type: application/pdf\r\n\r\n".utf8)
        let wrappedPDFBody = try value(
            Data(base64Encoded: "JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgL01ldGFkYXRhIDUgMCBSID4+CmVuZG9iagoyIDAgb2JqCjw8IC9UeXBlIC9QYWdlcyAvS2lkcyBbMyAwIFJdIC9Db3VudCAxID4+CmVuZG9iagozIDAgb2JqCjw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMiAwIFIgL01lZGlhQm94IFswIDAgNjEyIDc5Ml0gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL1RpdGxlIChTZWNyZXQpIC9BdXRob3IgKFByaXZhdGUpID4+CmVuZG9iago1IDAgb2JqCjw8IC9UeXBlIC9NZXRhZGF0YSAvU3VidHlwZSAvWE1MIC9MZW5ndGggMjMgPj4Kc3RyZWFtCjx4OnhtcG1ldGE+PC94OnhtcG1ldGE+CmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNzQgMDAwMDAgbiAKMDAwMDAwMDEzMSAwMDAwMCBuIAowMDAwMDAwMjAyIDAwMDAwIG4gCjAwMDAwMDAyNTcgMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA2IC9Sb290IDEgMCBSIC9JbmZvIDQgMCBSID4+CnN0YXJ0eHJlZgozNjAKJSVFT0YK"),
            "Invalid wrapped PDF fixture"
        )
        wrappedPDF.append(wrappedPDFBody)
        let wrappedPDFReport = FileProvenanceAnalyzer.analyze(
            wrappedPDF,
            fileName: "wrapped.pdf"
        )
        try expect(wrappedPDFReport.format == .pdf, "A wrapped PDF header was not recognized")
        try expect(
            wrappedPDFReport.findings.contains { $0.kind == .leadingContainerData },
            "Leading PDF response data was not reported"
        )

        let docxBase64 = "UEsDBBQAAAAIAGSGDl3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgAZIYOXcSt3EB0AAAAuwAAABEAAABkb2NQcm9wcy9jb3JlLnhtbLNJLrBKzi9KDSjKL0gtKslMLVaoyM3JK7ZKLrBVKi3KA9JKdjYpyVbJRamJJflFUNmUZIhsSrKSXUBRZlliSaqCY2lJRn6RjT5CMUhjSWpRbjFEIDUFrhssCjMCzFGyMzIwMtM1MAQikBko+uxs9DHcaQcAUEsDBBQAAAAIAGSGDl19mTaIUQAAAGwAAAATAAAAZG9jUHJvcHMvY3VzdG9tLnhtbLMJKMovSC0qyUwttrMpgLArFfISc1NtlYJTk4tSS5TsbMpKrHIKyotLihQqcnPyiq3KSmyVSovygLSSXUFRZlliSaqNPlyRnY0+zCAgE8l8AFBLAwQUAAAACABkhg5dCpCgcTEAAABAAAAAEQAAAHdvcmQvZG9jdW1lbnQueG1ssym3SslPLs1NzStRqMjNySu2KrdVKi3KsypXsrMpt0rKT6kE0QX6djb6MK4+Qo8dAFBLAQIUAxQAAAAIAGSGDl3HHBc8CgAAAAgAAAATAAAAAAAAAAAAAACAAQAAAABbQ29udGVudF9UeXBlc10ueG1sUEsBAhQDFAAAAAgAZIYOXcSt3EB0AAAAuwAAABEAAAAAAAAAAAAAAIABOwAAAGRvY1Byb3BzL2NvcmUueG1sUEsBAhQDFAAAAAgAZIYOXX2ZNohRAAAAbAAAABMAAAAAAAAAAAAAAIAB3gAAAGRvY1Byb3BzL2N1c3RvbS54bWxQSwECFAMUAAAACABkhg5dCpCgcTEAAABAAAAAEQAAAAAAAAAAAAAAgAFgAQAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAQABAAAAQAAwAEAAAAA"
        let docx = try value(Data(base64Encoded: docxBase64), "Invalid DOCX fixture")
        let docxReport = FileProvenanceAnalyzer.analyze(docx, fileName: "sample.docx")
        try expect(docxReport.format == .docx, "DOCX format was not detected")
        try expect(
            docxReport.findings.count == 2
                && docxReport.findings.allSatisfy { $0.evidenceConfidence == .exact },
            "Deflated DOCX metadata parts were not parsed exactly"
        )
    }

    private static func testClipboardTypeInventory() throws {
        let inventory = ClipboardTypeAnalyzer.analyze(typeIdentifiers: [
            "public.png",
            "public.file-url",
            "public.html",
            "public.rtf",
            "public.utf8-plain-text"
        ])
        try expect(
            inventory.kinds == [.image, .fileURL, .html, .richText],
            "Clipboard representations were classified incorrectly"
        )
        try expect(
            inventory.requiresFileProvenanceReview,
            "Image and file clipboard types did not request provenance review"
        )
    }

    private static func testMetadataCleaning() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignalSieveMetadataLocal-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("source.png")
        let destination = directory.appendingPathComponent("clean.png")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(localPNGChunk("eXIf", payload: Data("private".utf8)))
        png.append(localPNGChunk("IDAT", payload: Data([1, 2, 3])))
        png.append(localPNGChunk("IEND", payload: Data()))
        try png.write(to: source)

        let result = try FileMetadataCleaner.cleanCopy(of: source, to: destination)
        let sourceAfterCleaning = try Data(contentsOf: source)
        try expect(sourceAfterCleaning == png, "Metadata cleaning modified the source")
        try expect(result.originalWasUnchanged, "Source verification was not reported")
        try expect(result.removedFindingCount == 1, "Cleaned metadata count is wrong")
        try expect(result.cleanedReport.findings.isEmpty, "The cleaned copy was not reanalyzed clean")

        do {
            _ = try FileMetadataCleaner.cleanCopy(of: source, to: destination)
            throw LocalTestFailure.expectation("Metadata cleaner overwrote an existing copy")
        } catch FileMetadataCleaningError.destinationAlreadyExists {
            // Expected: an existing file is never replaced.
        }

        let docxBase64 = "UEsDBBQAAAAIAKe5Dl1A3LDuxgAAAMsBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbKWRsU4DQQxEf+W0LbpzREGBcmnoSQp+wNrzXVbcri3bCfD37BKUAqUAUVr2vJmRty8fQta957XYGI7u8ghg8UgZbWChUjcza0avoy4gGF9xIbjfbB4gcnEq3ntjhN12fybVNFF3QPVnzDQGeGOdYOJ4yvVyqLTQPV1kzXkMKLKmiJ64wLlMPzx7nucU6apvNFGOZJbKktfhusmYyl3Dw+0c9fCgLFZDK/09x3fvoan7mkBIPZH9zvFkzvnf3S+YG+bw9cPdJ1BLAwQUAAAACACnuQ5dvPyXe7sAAAAWAgAACwAAAF9yZWxzLy5yZWxzrZK7DsIwDEV/pcpOXUBiQG0nlm4I8QNW4j4EaSLHCPh7ogrEQzw6MMa5OT62km9oj9K5PrSdD8nJ7vtQqFbELwGCbsliSJ2nPt7Uji1KPHIDHvUOG4JZli2AHxmqzB+ZSWUKxZWZqmR79jSG7eq607Ry+mCplzctXhKRjNyQFOro2IC5ltOIVfDeZjbe5vOkYEnQoCBoxzTxHF+zdBTuQtFlHcthSHwTmv9zPfoQxNkfQkPmpgRP36C8AFBLAwQUAAAACACnuQ5dWTNat4sAAADNAAAAEQAAAGRvY1Byb3BzL2NvcmUueG1sZc5BCoMwEAXQq4j7OtpFFyEVegOvMEymKjVmmIzS4zctRQpdfv7n8T2Jo6Q8aBJWmzlXz7is2ZFc68lMHECmiSPmpizWUt6TRrQSdQRBeuDIcG7bC0Q2DGgIb/Akh1h/yUAHKZsuHyAQ8MKRV8vQNR3UvQ/kSBktaT/ovKNxddtsSurhp/Lw97x/AVBLAwQUAAAACACnuQ5dJbtvXmoAAACDAAAAEwAAAGRvY1Byb3BzL2N1c3RvbS54bWxFjTEKwzAMAL8SvLcKGTIUx1Mf0C8YIyeGyjKSEtrfx0NJx+Pgzr+EG4oV1OFD76qL28zaA0DThhT13nXtJrNQtI6yAudcEj457YTVYBrHGdKuxnRrV84F/4PvUCPh4pqUIxo6CB7+23ACUEsDBBQAAAAIAKe5Dl05qW7iYAAAAHcAAAARAAAAd29yZC9kb2N1bWVudC54bWxFjTEOgCAMAL9ifIA1Dg4E+QsCooltCcWgv1cH43S53HC6Ks/uwEClOXEnUXVq11KSAhC3BrTScQr0tIUz2vJojlA5+5TZBZGNIu4w9P0IaDdqja5qZn+9TGA0fAr/ytxQSwECFAMUAAAACACnuQ5dQNyw7sYAAADLAQAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIAKe5Dl28/Jd7uwAAABYCAAALAAAAAAAAAAAAAACAAfcAAABfcmVscy8ucmVsc1BLAQIUAxQAAAAIAKe5Dl1ZM1q3iwAAAM0AAAARAAAAAAAAAAAAAACAAdsBAABkb2NQcm9wcy9jb3JlLnhtbFBLAQIUAxQAAAAIAKe5Dl0lu29eagAAAIMAAAATAAAAAAAAAAAAAACAAZUCAABkb2NQcm9wcy9jdXN0b20ueG1sUEsBAhQDFAAAAAgAp7kOXTmpbuJgAAAAdwAAABEAAAAAAAAAAAAAAIABMAMAAHdvcmQvZG9jdW1lbnQueG1sUEsFBgAAAAAFAAUAOQEAAL8DAAAAAA=="
        let docxSource = directory.appendingPathComponent("source.docx")
        let docxDestination = directory.appendingPathComponent("clean.docx")
        try value(Data(base64Encoded: docxBase64), "Invalid metadata DOCX fixture")
            .write(to: docxSource)
        let docxResult = try FileMetadataCleaner.cleanCopy(
            of: docxSource,
            to: docxDestination
        )
        try expect(
            docxResult.cleanedReport.findings.isEmpty,
            "DOCX property parts remained after verified cleaning"
        )

        let odtBase64 = "UEsDBBQAAAAAAGSGDl1exjIMJwAAACcAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi92bmQub2FzaXMub3BlbmRvY3VtZW50LnRleHRQSwMEFAAAAAgAZIYOXS6HXNh+AAAA5AAAAAgAAABtZXRhLnhtbG2PQQoDIQxFrzK4F6ez6ELSQG/QK0jMMEJVSLX0+B3RQgcGsvj57ychkNc1EFufqUZORUcubvrEZ3rZjm6qShpaDeKpu55+ThvrXlMKYextHYInS8KuZMGHhLcrPN1r2bKA+UPQwr0LOWm/x3CZl6ueL3uBOcFgDnfM2Tf4BVBLAwQUAAAACABkhg5dcjnAYisAAAA0AAAACwAAAGNvbnRlbnQueG1ss8lPS8tMTrVKyU8uzU3NK9FNzs8rAdIKFbk5ecVWEFlbpdKiPChbSd8OAFBLAQIUAxQAAAAAAGSGDl1exjIMJwAAACcAAAAIAAAAAAAAAAAAAACAAQAAAABtaW1ldHlwZVBLAQIUAxQAAAAIAGSGDl0uh1zYfgAAAOQAAAAIAAAAAAAAAAAAAACAAU0AAABtZXRhLnhtbFBLAQIUAxQAAAAIAGSGDl1yOcBiKwAAADQAAAALAAAAAAAAAAAAAACAAfEAAABjb250ZW50LnhtbFBLBQYAAAAAAwADAKUAAABFAQAAAAA="
        let odtSource = directory.appendingPathComponent("source.odt")
        let odtDestination = directory.appendingPathComponent("clean.odt")
        try value(Data(base64Encoded: odtBase64), "Invalid metadata ODT fixture")
            .write(to: odtSource)
        let odtResult = try FileMetadataCleaner.cleanCopy(
            of: odtSource,
            to: odtDestination
        )
        try expect(
            odtResult.cleanedReport.findings.isEmpty,
            "ODT metadata remained after verified cleaning"
        )

        let pdfBase64 = "JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgL01ldGFkYXRhIDUgMCBSID4+CmVuZG9iagoyIDAgb2JqCjw8IC9UeXBlIC9QYWdlcyAvS2lkcyBbMyAwIFJdIC9Db3VudCAxID4+CmVuZG9iagozIDAgb2JqCjw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMiAwIFIgL01lZGlhQm94IFswIDAgNjEyIDc5Ml0gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL1RpdGxlIChTZWNyZXQpIC9BdXRob3IgKFByaXZhdGUpID4+CmVuZG9iago1IDAgb2JqCjw8IC9UeXBlIC9NZXRhZGF0YSAvU3VidHlwZSAvWE1MIC9MZW5ndGggMjMgPj4Kc3RyZWFtCjx4OnhtcG1ldGE+PC94OnhtcG1ldGE+CmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNzQgMDAwMDAgbiAKMDAwMDAwMDEzMSAwMDAwMCBuIAowMDAwMDAwMjAyIDAwMDAwIG4gCjAwMDAwMDAyNTcgMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA2IC9Sb290IDEgMCBSIC9JbmZvIDQgMCBSID4+CnN0YXJ0eHJlZgozNjAKJSVFT0YK"
        let pdf = try value(Data(base64Encoded: pdfBase64), "Invalid metadata PDF fixture")
        let pdfSource = directory.appendingPathComponent("source.pdf")
        let pdfDestination = directory.appendingPathComponent("clean.pdf")
        try pdf.write(to: pdfSource)
        let pdfResult = try FileMetadataCleaner.cleanCopy(
            of: pdfSource,
            to: pdfDestination
        )
        let persistedPDFSource = try Data(contentsOf: pdfSource)
        try expect(persistedPDFSource == pdf, "PDF cleaning modified the source")
        try expect(
            pdfResult.cleanedReport.findings.isEmpty,
            "PDF Info or XMP metadata remained after verified cleaning"
        )
    }

    private static func testLocalRewriteBoundaries() throws {
        try expect(LocalRewriteEngine.isValidModelName("llama3.2"), "A valid Ollama model name was rejected")
        try expect(
            LocalRewriteEngine.isValidModelName("qwen2.5:7b-instruct-q4_K_M"),
            "A valid tagged Ollama model name was rejected"
        )
        try expect(!LocalRewriteEngine.isValidModelName("--help"), "An option-like model name was accepted")
        try expect(
            !LocalRewriteEngine.isValidModelName("model; curl example.com"),
            "A shell-like model name was accepted"
        )
    }

    private static func testExternalPixelModule() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("SignalSievePixelLocal-\(UUID().uuidString)", isDirectory: true)
        let moduleDirectory = directory.appendingPathComponent("module", isDirectory: true)
        let imageURL = directory.appendingPathComponent("input.png")
        let outputURL = directory.appendingPathComponent("output.png")
        defer { try? manager.removeItem(at: directory) }
        try manager.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)

        let manifest = PixelWatermarkModuleManifest(
            schemaVersion: 1,
            name: "Fixture Pixel Module",
            version: "1.0.0",
            executable: "module.sh",
            capabilities: [.score, .regenerate],
            license: "Test-only"
        )
        try JSONEncoder().encode(manifest).write(
            to: moduleDirectory.appendingPathComponent(ExternalPixelWatermarkEngine.manifestFileName)
        )
        let script = """
        #!/bin/sh
        set -eu
        operation="$1"
        shift
        input=""
        output=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --input) input="$2"; shift 2 ;;
            --output) output="$2"; shift 2 ;;
            --strength) shift 2 ;;
            --json) shift ;;
            *) exit 64 ;;
          esac
        done
        if [ "$operation" = "score" ]; then
          echo '{"schemaVersion":1,"detector":"fixture","score":0.73,"threshold":0.50}'
        else
          cp "$input" "$output"
          printf 'x' >> "$output"
          echo '{"schemaVersion":1,"status":"ok"}'
        fi
        """
        let executableURL = moduleDirectory.appendingPathComponent("module.sh")
        try Data(script.utf8).write(to: executableURL)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        let image = try value(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII="),
            "Invalid PNG fixture"
        )
        try image.write(to: imageURL)

        let module = try ExternalPixelWatermarkEngine.loadModule(at: moduleDirectory)
        let score = try ExternalPixelWatermarkEngine.score(imageURL: imageURL, using: module, timeout: 5)
        try expect(score.score == 0.73 && score.isElevated == true, "External pixel score was invalid")
        let result = try ExternalPixelWatermarkEngine.regenerateCopy(
            imageURL: imageURL,
            destinationURL: outputURL,
            strength: 0.25,
            using: module,
            timeout: 5
        )
        let sourceAfter = try Data(contentsOf: imageURL)
        let output = try Data(contentsOf: outputURL)
        try expect(sourceAfter == image, "External pixel module modified the source")
        try expect(output != image, "External pixel module did not create a changed copy")
        try expect(result.width == 1 && result.height == 1, "Regenerated dimensions were not verified")
    }

    private static func testPixelLSBBaseline() throws {
        let iconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Packaging/SignalSieveIcon-1024.png")
        let data = try Data(contentsOf: iconURL)
        let before = try PixelLSBForensics.analyze(data)
        try expect(before.hasEnoughSamples, "The built-in pixel baseline did not sample the image")
        try expect(before.score.isFinite && (0...1).contains(before.score), "The LSB score was invalid")
        let regenerated = try PixelLSBForensics.regenerate(data, strength: 0.70)
        let after = try PixelLSBForensics.analyze(regenerated)
        let provenance = FileProvenanceAnalyzer.analyze(
            regenerated,
            fileName: "regenerated.png"
        )
        try expect(regenerated != data, "The built-in pixel baseline did not create a regenerated image")
        try expect(after.score < before.score, "LSB regeneration did not lower the measured regularity")
        try expect(provenance.findings.isEmpty, "LSB regeneration introduced PNG metadata")
    }

    private static func testPixelSpectralLab() throws {
        let width = 192
        let height = 192
        var cleanPixels = [UInt8](repeating: 0, count: width * height * 4)
        var carrierPixels = cleanPixels
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let base = 42 + (x * 140 / width) + (y * 46 / height)
                let phase = 2 * Double.pi * (
                    14 * Double(x) / Double(width) - 14 * Double(y) / Double(height)
                )
                let carrier = Int((8 * sin(phase)).rounded())
                for channel in 0..<3 {
                    cleanPixels[offset + channel] = UInt8(min(255, base + channel * 3))
                    carrierPixels[offset + channel] = UInt8(
                        min(255, max(0, base + channel * 3 + carrier))
                    )
                }
                cleanPixels[offset + 3] = 255
                carrierPixels[offset + 3] = 255
            }
        }
        let clean = try encodeTestPNG(cleanPixels, width: width, height: height)
        let carrier = try encodeTestPNG(carrierPixels, width: width, height: height)
        let cleanReport = try PixelSpectralForensics.analyze(clean)
        let carrierReport = try PixelSpectralForensics.analyze(carrier)
        try expect(!cleanReport.isElevated, "A smooth gradient produced an elevated spectral verdict")
        try expect(carrierReport.isElevated, "The synthetic periodic carrier was not detected")
        try expect(
            carrierReport.carrierFrequencyX == 14 && carrierReport.carrierFrequencyY == -14,
            "The spectral detector selected the wrong carrier frequency"
        )
        let regenerated = try PixelSpectralForensics.regenerate(carrier, strength: 0.70)
        let after = try PixelSpectralForensics.analyze(regenerated)
        try expect(
            after.score < carrierReport.score,
            "Spectral regeneration did not lower the score "
                + "(before \(carrierReport.score), after \(after.score), "
                + "correlation \(carrierReport.normalizedCorrelation) -> "
                + "\(after.normalizedCorrelation), residual "
                + "\(carrierReport.residualRMS) -> \(after.residualRMS), "
                + "frequency \(after.carrierFrequencyX),\(after.carrierFrequencyY))"
        )
        let provenance = FileProvenanceAnalyzer.analyze(
            regenerated,
            fileName: "spectral-clean.png"
        )
        try expect(provenance.findings.isEmpty, "Spectral regeneration introduced PNG metadata")
    }

    private static func testClipboardImageImport() throws {
        let iconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Packaging/SignalSieveIcon-1024.png")
        let png = try Data(contentsOf: iconURL)
        let payload = try ClipboardImageImporter.importImage(from: [
            ClipboardImageRepresentation(typeIdentifier: "public.png", data: png)
        ])
        try expect(payload.data == png, "Clipboard PNG bytes were not preserved for inspection")
        try expect(!payload.wasTranscodedToPNG, "A PNG clipboard image was unnecessarily transcoded")
        let report = FileProvenanceAnalyzer.analyze(payload.data, fileName: payload.fileName)
        try expect(report.format == .png, "Clipboard image provenance used the wrong format")

        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LocalTestFailure.expectation("Could not decode the clipboard TIFF fixture")
        }
        let tiff = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            tiff,
            "public.tiff" as CFString,
            1,
            nil
        ) else {
            throw LocalTestFailure.expectation("Could not create the clipboard TIFF fixture")
        }
        CGImageDestinationAddImage(destination, image, nil)
        try expect(CGImageDestinationFinalize(destination), "Could not finalize the TIFF fixture")
        let normalized = try ClipboardImageImporter.importImage(from: [
            ClipboardImageRepresentation(typeIdentifier: "public.tiff", data: tiff as Data)
        ])
        try expect(normalized.wasTranscodedToPNG, "TIFF clipboard data was not normalized")
        try expect(
            normalized.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])),
            "Normalized clipboard data is not PNG"
        )

        var metadataPNG = png
        let iendMarker = Data([0x49, 0x45, 0x4E, 0x44])
        guard let iendTypeRange = metadataPNG.range(of: iendMarker),
              iendTypeRange.lowerBound >= 4 else {
            throw LocalTestFailure.expectation("Could not locate the clipboard PNG IEND chunk")
        }
        metadataPNG.insert(
            contentsOf: localPNGChunk("tEXt", payload: Data("Author\0Private".utf8)),
            at: iendTypeRange.lowerBound - 4
        )
        let metadataPayload = ClipboardImagePayload(
            data: metadataPNG,
            fileName: "clipboard-image.png",
            sourceTypeIdentifier: "public.png",
            wasTranscodedToPNG: false
        )
        let originalSnapshot = metadataPayload.data
        let regeneratedPreview = try ClipboardImageImporter.regeneratedPNG(
            from: metadataPayload.data
        )
        let regeneratedPreviewReport = FileProvenanceAnalyzer.analyze(
            regeneratedPreview,
            fileName: "clipboard-image-signalsieve-clean.png"
        )
        try expect(
            regeneratedPreviewReport.findings.isEmpty,
            "Fresh PNG retained findings: \(regeneratedPreviewReport.findings.map { $0.kind.rawValue })"
        )
        try expect(
            !regeneratedPreviewReport.containsC2PAContainer,
            "Fresh PNG retained a C2PA container"
        )
        let cleaned = try ClipboardImageCleaner.makeFreshCopy(from: metadataPayload)
        try expect(metadataPayload.data == originalSnapshot, "Fresh image creation changed its source")
        try expect(
            cleaned.removedFindingCount == cleaned.originalReport.findings.count
                && cleaned.removedFindingCount > 0,
            "Fresh image did not remove all detected PNG metadata"
        )
        try expect(cleaned.cleanedReport.findings.isEmpty, "Fresh image failed metadata reanalysis")
        try expect(
            cleaned.cleanedPayload.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])),
            "Fresh clipboard image is not PNG"
        )
    }

    private static func encodeTestPNG(
        _ pixels: [UInt8],
        width: Int,
        height: Int
    ) throws -> Data {
        var mutable = pixels
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &mutable,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ),
              let image = context.makeImage() else {
            throw LocalTestFailure.expectation("Could not create the spectral PNG fixture")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw LocalTestFailure.expectation("Could not encode the spectral PNG fixture")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LocalTestFailure.expectation("Could not finalize the spectral PNG fixture")
        }
        return output as Data
    }

    private static func testRewriteIntegrity() throws {
        let report = RewriteIntegrityAnalyzer.analyze(
            original: "The total was 39% on 2026-08-14. Keep “quoted fact”.",
            candidate: "On 2026-08-15, the total became 40%. Keep “different fact”."
        )
        try expect(
            report.assessment == .protectedValuesChanged,
            "Protected rewrite values changed without an alert"
        )
        try expect(
            report.findings.contains { $0.kind == .number },
            "Rewrite integrity missed a changed number or date"
        )
        try expect(
            report.findings.contains { $0.kind == .quotation },
            "Rewrite integrity missed a changed quotation"
        )
        try expect(
            report.semanticEquivalenceConfidence == .notTestable,
            "Rewrite integrity claimed semantic equivalence"
        )
        let copiedReport = FindingReportFormatter.rewriteIntegrityReport(
            report,
            language: .english
        )
        try expect(
            copiedReport.contains("Semantic equivalence: Not testable"),
            "Copied rewrite report overstated semantic equivalence"
        )

        let code = RewriteIntegrityAnalyzer.analyze(
            original: "func total() -> Int { return 39 }",
            candidate: "func sum() -> Int { return 40 }"
        )
        try expect(code.assessment == .codeNotSupported, "Rewrite integrity accepted source code")
    }

    private static func localPNGChunk(_ type: String, payload: Data) -> Data {
        var data = Data()
        let length = UInt32(payload.count)
        data.append(contentsOf: [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ])
        data.append(Data(type.utf8))
        data.append(payload)
        data.append(contentsOf: [0, 0, 0, 0])
        return data
    }

    private static func testActiveClipboardProtection() throws {
        let first = ClipboardProtectionAnalyzer.analyze(
            "Privacy tools should remain entirely local and transparent for everyone. First sample.",
            recentPatternTexts: []
        )
        let second = ClipboardProtectionAnalyzer.analyze(
            "Privacy tools should remain entirely local and transparent for everyone. Second sample.",
            recentPatternTexts: first.updatedPatternTexts
        )
        let third = ClipboardProtectionAnalyzer.analyze(
            "Privacy tools should remain entirely local and transparent for everyone. Third​ sample https://example.com?a=keep&utm_source=test",
            recentPatternTexts: second.updatedPatternTexts
        )

        try expect(third.containsHiddenUnicode, "Active protection missed hidden Unicode")
        try expect(third.containsTrackedLinks, "Active protection missed a tracked link")
        try expect(third.containsRecentPattern, "Active protection missed a three-copy pattern")
        try expect(third.updatedPatternTexts.count == 3, "Active protection lost recent samples")

        let medium = HiddenTextAnalyzer.inspect("medium\u{200B}")
        let high = HiddenTextAnalyzer.inspect("high\u{202E}")
        try expect(
            ClipboardProtectionAnalyzer.alertPriority(
                hiddenUnicodeRisk: medium.highestRiskLevel,
                codeRisk: nil
            ) == .standard,
            "An orange finding was incorrectly promoted to a persistent alert"
        )
        try expect(
            ClipboardProtectionAnalyzer.alertPriority(
                hiddenUnicodeRisk: high.highestRiskLevel,
                codeRisk: nil
            ) == .high,
            "A red finding did not receive high-priority treatment"
        )

        let standardPriorityPairs: [(HiddenElementRiskLevel?, HiddenElementRiskLevel?)] = [
            (nil, nil), (.suspicious, nil), (.medium, nil),
            (nil, .suspicious), (nil, .medium), (.medium, .suspicious)
        ]
        for (hiddenRisk, codeRisk) in standardPriorityPairs {
            try expect(
                ClipboardProtectionAnalyzer.alertPriority(
                    hiddenUnicodeRisk: hiddenRisk,
                    codeRisk: codeRisk
                ) == .standard,
                "A non-red risk pair escaped the standard alert boundary"
            )
        }
        let highPriorityPairs: [(HiddenElementRiskLevel?, HiddenElementRiskLevel?)] = [
            (.high, nil), (nil, .high), (.high, .medium), (.suspicious, .high), (.high, .high)
        ]
        for (hiddenRisk, codeRisk) in highPriorityPairs {
            try expect(
                ClipboardProtectionAnalyzer.alertPriority(
                    hiddenUnicodeRisk: hiddenRisk,
                    codeRisk: codeRisk
                ) == .high,
                "A red risk pair escaped the persistent alert boundary"
            )
        }
    }

    private static func testClipboardHistory() throws {
        var history: [ClipboardHistoryEntry] = []
        for index in 0..<(ClipboardHistory.maximumEntries + 3) {
            let entry = ClipboardHistory.makeEntry(
                text: "copy \(index)",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                sourceApplicationName: "Test Editor",
                sourceBundleIdentifier: "test.editor",
                hiddenUnicodeCount: 0,
                codeRiskCount: 0,
                trackedLinkCount: 0,
                binaryKind: nil,
                wasAutomaticallyCleaned: false
            )
            history = ClipboardHistory.appending(entry, to: history)
        }
        try expect(history.count == ClipboardHistory.maximumEntries, "Copy history exceeded its limit")
        try expect(history.first?.text == "copy 52", "Copy history is not newest-first")

        let invisible = "\u{200B}"
        let preview = ClipboardHistory.visiblePreview("alpha\(invisible)beta")
        try expect(preview == "alpha⟦U+200B⟧beta", "Copy history did not reveal hidden Unicode")
        try expect(!preview.contains(invisible), "Copy history preview retained invisible Unicode")
    }

    private static func testFindingReports() throws {
        let invisible = "\u{200B}"
        let inspection = HiddenTextAnalyzer.inspect("alpha\(invisible)beta")
        let hiddenReport = FindingReportFormatter.hiddenReport(
            inspection,
            language: .spanish
        )
        try expect(hiddenReport.contains("U+200B"), "Copied report omitted the code point")
        try expect(hiddenReport.contains("Riesgo:"), "Copied report was not localized")
        try expect(
            hiddenReport.contains("Confianza de evidencia: Detección exacta"),
            "Copied report did not separate evidence confidence from risk"
        )
        try expect(!hiddenReport.contains(invisible), "Copied report preserved an invisible scalar")

        let pattern = PatternFinding(
            kind: .repeatedPhrase,
            pattern: "privacy remains\(invisible) local",
            detail: "",
            matchingSampleCount: 3,
            confidence: 0.82
        )
        let patternReport = FindingReportFormatter.patternFinding(pattern, language: .english)
        try expect(
            patternReport.contains("Evidence confidence: Heuristic indication"),
            "Pattern report did not identify heuristic evidence"
        )
        try expect(patternReport.contains("⟦U+200B⟧"), "Pattern report did not visualize Unicode")
        try expect(!patternReport.contains(invisible), "Pattern report copied hidden Unicode")

        let revealed = RevealedInvisibleFragment(
            id: 0,
            findingNumber: 1,
            codePoint: "U+200C",
            line: 1,
            column: 8,
            presentation: .incompletePayload,
            text: "0111010",
            hiddenScalarCount: 7,
            scalarPositions: Array(1...7),
            zeroWidthBinary: ZeroWidthBinaryDetails(
                zeroCodePoint: "U+200C",
                oneCodePoint: "U+200D",
                bits: "0111010",
                completeByteCount: 0,
                trailingBitCount: 7,
                isPreviewTruncated: false
            )
        )
        let revealReport = FindingReportFormatter.revealedFragment(revealed, language: .spanish)
        try expect(revealReport.contains("U+200C = 0"), "Reveal report omitted its bit mapping")
        try expect(revealReport.contains("Bits faltantes: 1"), "Reveal report omitted truncation evidence")
    }

    private static func testLocalization() throws {
        try expect(
            AppLocalization.text("Active Guard", language: .spanish) == "Protección activa",
            "Spanish interface translation is missing"
        )
        try expect(
            AppLocalization.text("Active Guard", language: .norwegianBokmal) == "Aktiv beskyttelse",
            "Norwegian interface translation is missing"
        )
        try expect(
            AppLocalization.format("Found %d elements to review.", language: .spanish, 4)
                == "Se encontraron 4 elementos para revisar.",
            "Localized formatting lost its dynamic value"
        )
    }

    private static func testSignedPack() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pack = CommunityRulePack(
            identifier: "community.local-test",
            version: 1,
            createdAt: "2026-08-11T00:00:00Z",
            rules: [try CustomURLRule(domain: "example.com", parameter: "share_token")]
        )
        let payload = try JSONEncoder().encode(pack)
        let envelope = SignedCommunityRuleEnvelope(
            payload: payload,
            signature: try key.signature(for: payload),
            publicKey: key.publicKey.rawRepresentation
        )
        let verified = try CommunityRulePackVerifier.verify(envelopeData: JSONEncoder().encode(envelope))
        try expect(verified.pack == pack, "Verified pack differs from the signed pack")
        try expect(!verified.signerFingerprint.isEmpty, "Signer fingerprint is empty")
    }

    private static func testTamperedPack() throws {
        let key = Curve25519.Signing.PrivateKey()
        let original = CommunityRulePack(
            identifier: "community.local-test",
            version: 1,
            createdAt: "2026-08-11T00:00:00Z",
            rules: [try CustomURLRule(domain: "example.com", parameter: "original")]
        )
        let originalPayload = try JSONEncoder().encode(original)
        let changed = CommunityRulePack(
            identifier: original.identifier,
            version: 2,
            createdAt: original.createdAt,
            rules: [try CustomURLRule(domain: "example.com", parameter: "changed")]
        )
        let envelope = SignedCommunityRuleEnvelope(
            payload: try JSONEncoder().encode(changed),
            signature: try key.signature(for: originalPayload),
            publicKey: key.publicKey.rawRepresentation
        )

        do {
            _ = try CommunityRulePackVerifier.verify(envelopeData: JSONEncoder().encode(envelope))
            throw LocalTestFailure.expectation("A changed pack was accepted")
        } catch CommunityRulePackError.invalidSignature {
            return
        }
    }

    private static func testEmptyVisualTransfer() throws {
        do {
            _ = try VisualTransfer.roundTrip(" \n\t")
            throw LocalTestFailure.expectation("Whitespace-only visual input was accepted")
        } catch VisualTransferError.emptyInput {
            return
        }
    }

    private static func testVisualTransfer() throws {
        do {
            let visible = try VisualTransfer.roundTrip("Clean text 123")
            try expect(visible.text.localizedCaseInsensitiveContains("Clean text"), "OCR lost visible words")
            try expect(visible.text.contains("123"), "OCR lost visible numbers")

            let wrappedSource = "A local OCR paragraph is deliberately long enough to wrap across several visual rows while remaining one logical line in the original text."
            let wrapped = try VisualTransfer.roundTrip(wrappedSource)
            try expect(!wrapped.text.contains("\n"), "OCR introduced a visual-wrap newline")

            let hidden = try VisualTransfer.roundTrip("hola\u{200B}mundo")
            try expect(hidden.text.localizedCaseInsensitiveContains("holamundo"), "OCR misread hidden-character input")
            try expect(HiddenTextAnalyzer.inspect(hidden.text).isClean, "OCR output contains hidden Unicode")
        } catch {
            let description = String(describing: error)
            let nsError = error as NSError
            if description == "nilError"
                || (nsError.domain == NSOSStatusErrorDomain && nsError.code == -6662) {
                throw LocalTestSkip(
                    description: "Apple Vision is unavailable in this command-line environment"
                )
            }
            throw error
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw LocalTestFailure.expectation(message) }
}

private func value<T>(_ optional: T?, _ message: String) throws -> T {
    guard let optional else { throw LocalTestFailure.expectation(message) }
    return optional
}
