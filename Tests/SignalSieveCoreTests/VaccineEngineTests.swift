// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Vaccine scans safely, skips binaries and creates restorable backups")
func scansAndVaccinatesProject() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveVaccineTests-\(UUID().uuidString)", isDirectory: true)
    let project = temporary.appendingPathComponent("Project", isDirectory: true)
    let backups = temporary.appendingPathComponent("Backups", isDirectory: true)
    let sourceURL = project.appendingPathComponent("main.swift")
    let binaryURL = project.appendingPathComponent("tool.bin")
    let dependencyURL = project.appendingPathComponent("node_modules/ignored.js")
    defer { try? manager.removeItem(at: temporary) }

    try manager.createDirectory(at: dependencyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let source = "import Foundation\nlet access\u{200B}Level = “admin”\u{00A0}\n"
    try Data(source.utf8).write(to: sourceURL)
    try Data([0x7F, 0x45, 0x4C, 0x46, 0x00]).write(to: binaryURL)
    try Data("const hidden\u{200B} = true;".utf8).write(to: dependencyURL)

    let report = try VaccineEngine.scan(rootURL: project)
    #expect(report.scannedFileCount == 1)
    #expect(report.binaryFileCount == 1)
    #expect(report.excludedDirectoryCount == 1)
    #expect(report.sanitizableFileCount == 1)
    #expect(report.findings.first?.detectedLanguage == "Swift")

    let result = try VaccineEngine.vaccinate(report, backupBaseURL: backups)
    #expect(result.sanitizedFileCount == 1)
    #expect(result.filesChangedSinceScan.isEmpty)
    #expect(manager.fileExists(atPath: result.backupURL.appendingPathComponent("main.swift").path))
    #expect(try String(contentsOf: sourceURL, encoding: .utf8) == "import Foundation\nlet accessLevel = \"admin\" \n")
    #expect(try String(contentsOf: result.backupURL.appendingPathComponent("main.swift"), encoding: .utf8) == source)
}

@Test("Vaccine includes a decoded invisible fragment in its file report")
func vaccineReportsDecodedFragment() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveVaccinePreviewTests-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = temporary.appendingPathComponent("runtime_utils.py")
    defer { try? manager.removeItem(at: temporary) }
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)

    let message = "Hola estoy oculto!"
    let tags = String(String.UnicodeScalarView(message.unicodeScalars.compactMap { scalar in
        Unicode.Scalar(0xE0000 + scalar.value)
    }))
    try Data("def run():\n    print('safe')\(tags)\n".utf8).write(to: sourceURL)

    let report = try VaccineEngine.scan(rootURL: temporary)
    let finding = try #require(report.findings.first)
    let preview = try #require(finding.revealedFragments.first)
    #expect(finding.relativePath == "runtime_utils.py")
    #expect(preview.presentation == .decodedPayload)
    #expect(preview.text == message)
}

@Test("Vaccine refuses to overwrite files changed after scanning")
func refusesChangedFiles() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveVaccineRaceTests-\(UUID().uuidString)", isDirectory: true)
    let sourceURL = temporary.appendingPathComponent("main.py")
    defer { try? manager.removeItem(at: temporary) }
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    try Data("def main():\n    value\u{200B} = 1\n".utf8).write(to: sourceURL)
    let report = try VaccineEngine.scan(rootURL: temporary)
    let changed = "def main():\n    return 42\n"
    try Data(changed.utf8).write(to: sourceURL)

    let result = try VaccineEngine.vaccinate(
        report,
        backupBaseURL: temporary.appendingPathComponent("Backups")
    )
    #expect(result.sanitizedFileCount == 0)
    #expect(result.filesChangedSinceScan == ["main.py"])
    #expect(try String(contentsOf: sourceURL, encoding: .utf8) == changed)
}

@Test("Vaccine recognizes and refuses to modify SignalSieve itself")
func blocksSignalSieveSelfVaccination() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveSelfVaccineTests-\(UUID().uuidString)", isDirectory: true)
    let appSource = temporary.appendingPathComponent("Sources/SignalSieve/SignalSieveApp.swift")
    let infoURL = temporary.appendingPathComponent("Packaging/Info.plist")
    defer { try? manager.removeItem(at: temporary) }

    try manager.createDirectory(at: appSource.deletingLastPathComponent(), withIntermediateDirectories: true)
    try manager.createDirectory(at: infoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("import SwiftUI\n@main struct SignalSieveApp: App {}\n".utf8).write(to: appSource)
    try Data("let package = Package(name: \"SignalSieve\", products: [.executable(name: \"SignalSieve\", targets: [\"SignalSieve\"])])".utf8)
        .write(to: temporary.appendingPathComponent("Package.swift"))
    let plist = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleIdentifier": "com.signalsieve.app"],
        format: .xml,
        options: 0
    )
    try plist.write(to: infoURL)

    let report = try VaccineEngine.scan(rootURL: temporary)
    #expect(report.isSignalSieveTarget)

    do {
        _ = try VaccineEngine.vaccinate(
            report,
            backupBaseURL: temporary.appendingPathComponent("Backups")
        )
        Issue.record("Vaccine allowed SignalSieve to modify itself")
    } catch VaccineError.selfVaccinationBlocked {
        // Expected safety boundary.
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("Vaccine recognizes the installed Signal Sieve app bundle")
func recognizesSignalSieveAppBundle() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("Signal Sieve.app", isDirectory: true)
    let infoURL = temporary.appendingPathComponent("Contents/Info.plist")
    defer { try? manager.removeItem(at: temporary) }
    try manager.createDirectory(at: infoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleIdentifier": "com.signalsieve.app"],
        format: .binary,
        options: 0
    )
    try plist.write(to: infoURL)

    #expect(VaccineEngine.isSignalSieveTarget(temporary))
}

@Test("Vaccine inventories provenance and metadata in binary files across a folder")
func scansFolderMetadata() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory
        .appendingPathComponent("SignalSieveVaccineMetadata-\(UUID().uuidString)", isDirectory: true)
    let imageURL = temporary.appendingPathComponent("photo.png")
    defer { try? manager.removeItem(at: temporary) }
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)

    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    png.append(vaccinePNGChunk("eXIf", payload: Data("private".utf8)))
    png.append(vaccinePNGChunk("tEXt", payload: Data("author\0private".utf8)))
    png.append(vaccinePNGChunk("IEND", payload: Data()))
    try png.write(to: imageURL)

    let report = try VaccineEngine.scan(rootURL: temporary)
    let finding = try #require(report.findings.first)

    #expect(report.provenanceScannedFileCount == 1)
    #expect(report.metadataAffectedFileCount == 1)
    #expect(report.totalMetadataFindingCount == 2)
    #expect(report.binaryFileCount == 1)
    #expect(report.sanitizableFileCount == 0)
    #expect(!finding.isTextFile)
    #expect(finding.provenanceReport?.format == .png)
    #expect(finding.provenanceReport?.findings.count == 2)
    #expect(finding.reviewOnlyFindingCount == 2)
}

private func vaccinePNGChunk(_ type: String, payload: Data) -> Data {
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
