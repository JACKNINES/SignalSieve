// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Folder Triage classifies high, medium, metadata, and benign files without calling red malware")
func folderTriageClassifiesSupportedEvidence() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }

    try fixture.write("safe visible text\n", to: "benign.txt")
    try fixture.write("plain text with zero\u{200B}width\n", to: "medium.txt")
    try fixture.write("print('safe') # \u{202E} dangerous display order\n", to: "high.py")
    try fixture.write(markdownWithFrontMatter(), to: "metadata.md")

    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    let severities = Dictionary(uniqueKeysWithValues: report.assessments.map { ($0.relativePath, $0.severity) })

    #expect(severities["benign.txt"] == .green)
    #expect(severities["medium.txt"] == .orange)
    #expect(severities["high.py"] == .red)
    #expect(severities["metadata.md"] == .yellow)
    #expect(report.redDoesNotMeanMalwareNotice.contains("not proof of malware"))
}

@Test("Folder Triage reports symlinks as unassessed and does not follow root escapes")
func folderTriageSkipsSymlinkRootEscape() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let outside = fixture.temporary.appendingPathComponent("outside.py")
    try Data("print('outside') # \u{202E}\n".utf8).write(to: outside)
    let link = fixture.root.appendingPathComponent("escape.py")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

    let report = try FolderTriageEngine.scan(rootURL: fixture.root)

    #expect(report.assessments.isEmpty)
    #expect(report.unassessedFiles.contains { $0.relativePath == "escape.py" && $0.reason == .symlinkOrNonRegular })
}

@Test("Folder Triage revalidates identity and refuses files changed after scan")
func folderTriageRefusesChangedFileBeforeMarkerMutation() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let url = try fixture.write("print('safe') # \u{202E}\n", to: "high.py")
    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    let store = FakeFinderMarkerStore()
    store.states[url.path] = FinderMarkerState(tagNames: [], labelNumber: nil)

    try fixture.write("print('changed')\n", to: "high.py")
    let result = try FolderTriageEngine.applyRedMarkers(
        to: report,
        manifestDirectory: fixture.manifests,
        markerStore: store
    )

    #expect(result.count(.changedSinceScan) == 1)
    #expect(store.states[url.path]?.tagNames.isEmpty == true)
    #expect(!FileManager.default.fileExists(atPath: result.manifestURL.path))
}

@Test("Folder Triage preserves existing Finder tags and restores prior labels")
func folderTriagePreservesTagsAndRestoresPriorLabel() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let url = try fixture.write("print('safe') # \u{202E}\n", to: "high.py")
    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    let store = FakeFinderMarkerStore()
    store.states[url.path] = FinderMarkerState(tagNames: ["UserTag"], labelNumber: 3)

    let apply = try FolderTriageEngine.applyRedMarkers(
        to: report,
        manifestDirectory: fixture.manifests,
        markerStore: store
    )
    #expect(apply.count(.applied) == 1)
    #expect(store.states[url.path]?.tagNames == ["UserTag", FolderTriageEngine.appMarkerTag])
    #expect(store.states[url.path]?.labelNumber == FolderTriageEngine.markerLabelNumber)
    #expect(try String(contentsOf: url, encoding: .utf8) == "print('safe') # \u{202E}\n")
    #expect(try manifestEntryCount(at: apply.manifestURL) == 1)

    let restore = try FolderTriageEngine.restoreMarkers(
        rootURL: fixture.root,
        manifestDirectory: fixture.manifests,
        markerStore: store
    )
    #expect(restore.count(.restored) == 1)
    #expect(store.states[url.path] == FinderMarkerState(tagNames: ["UserTag"], labelNumber: 3))
    #expect(!FileManager.default.fileExists(atPath: apply.manifestURL.path))
}

@Test("Folder Triage reports partial Finder marker failures")
func folderTriageReportsPartialMarkerFailures() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let first = try fixture.write("print('one') # \u{202E}\n", to: "one.py")
    let second = try fixture.write("print('two') # \u{202E}\n", to: "two.py")
    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    let store = FakeFinderMarkerStore()
    store.states[first.path] = FinderMarkerState(tagNames: [], labelNumber: nil)
    store.states[second.path] = FinderMarkerState(tagNames: [], labelNumber: nil)
    store.failSetPaths.insert(second.path)

    let result = try FolderTriageEngine.applyRedMarkers(
        to: report,
        manifestDirectory: fixture.manifests,
        markerStore: store
    )

    #expect(result.count(.applied) == 1)
    #expect(result.count(.failed) == 1)
    #expect(try manifestEntryCount(at: result.manifestURL) == 1)
    #expect(store.states[first.path]?.tagNames.contains(FolderTriageEngine.appMarkerTag) == true)
    #expect(store.states[second.path]?.tagNames.contains(FolderTriageEngine.appMarkerTag) == false)
}

@Test("Folder Triage bounds marker manifests")
func folderTriageBoundsMarkerManifestEntries() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    for index in 0..<(FolderTriageEngine.maximumManifestEntries + 10) {
        try fixture.write("print('\(index)') # \u{202E}\n", to: String(format: "f%03d.py", index))
    }
    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    let store = FakeFinderMarkerStore()
    for item in report.redFiles {
        store.states[item.fileURL.path] = FinderMarkerState(tagNames: [], labelNumber: nil)
    }

    let result = try FolderTriageEngine.applyRedMarkers(
        to: report,
        manifestDirectory: fixture.manifests,
        markerStore: store
    )

    #expect(result.count(.applied) == FolderTriageEngine.maximumManifestEntries)
    #expect(result.count(.manifestLimit) == 10)
    #expect(try manifestEntryCount(at: result.manifestURL) == FolderTriageEngine.maximumManifestEntries)
}

@Test("Folder Triage restoration removes only its owned marker and does not overwrite newer labels")
func folderTriageRestoreRespectsMarkerOwnership() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let url = try fixture.write("print('safe') # \u{202E}\n", to: "high.py")
    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    let store = FakeFinderMarkerStore()
    store.states[url.path] = FinderMarkerState(tagNames: ["UserTag"], labelNumber: 3)

    _ = try FolderTriageEngine.applyRedMarkers(
        to: report,
        manifestDirectory: fixture.manifests,
        markerStore: store
    )
    store.states[url.path] = FinderMarkerState(
        tagNames: ["UserTag", FolderTriageEngine.appMarkerTag, "LaterUserTag"],
        labelNumber: 4
    )

    let restore = try FolderTriageEngine.restoreMarkers(
        rootURL: fixture.root,
        manifestDirectory: fixture.manifests,
        markerStore: store
    )

    #expect(restore.count(.labelNotRestored) == 1)
    #expect(store.states[url.path] == FinderMarkerState(tagNames: ["UserTag", "LaterUserTag"], labelNumber: 4))
}

@Test("Folder Triage never reports unsupported binary content as green")
func folderTriageKeepsUnsupportedBinaryUnassessed() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    try fixture.writeData(Data([0x00, 0xFF, 0x00, 0x81, 0x82]), to: "opaque.bin")

    let report = try FolderTriageEngine.scan(rootURL: fixture.root)

    #expect(!report.assessments.contains { $0.relativePath == "opaque.bin" })
    #expect(report.unassessedFiles.contains {
        $0.relativePath == "opaque.bin" && $0.reason == .unsupportedBinary
    })
}

@Test("Folder Triage retains high severity when the high Unicode evidence is outside the display bound")
func folderTriageUsesAggregateUnicodeRisk() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let boundedSuspiciousPrefix = String(
        repeating: "visible\u{00A0}",
        count: HiddenTextAnalyzer.maximumReportedFindings + 1
    )
    try fixture.write(boundedSuspiciousPrefix + "final\u{202E}payload", to: "bounded.txt")

    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    let assessment = try #require(report.assessments.first { $0.relativePath == "bounded.txt" })

    #expect(assessment.severity == .red)
    #expect(assessment.evidenceKinds.contains(.highUnicode))
    #expect(assessment.finding?.unicodeFindingCount == HiddenTextAnalyzer.maximumReportedFindings + 2)
}

@Test("Folder Triage refuses to claim a preexisting marker with no ownership manifest")
func folderTriageRefusesUnownedMarkerName() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let url = try fixture.write("print('safe') # \u{202E}\n", to: "high.py")
    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    let original = FinderMarkerState(
        tagNames: [FolderTriageEngine.appMarkerTag, "UserTag"],
        labelNumber: 2
    )
    let store = FakeFinderMarkerStore()
    store.states[url.path] = original

    let result = try FolderTriageEngine.applyRedMarkers(
        to: report,
        manifestDirectory: fixture.manifests,
        markerStore: store
    )

    #expect(result.count(.ownershipConflict) == 1)
    #expect(store.states[url.path] == original)
    #expect(!FileManager.default.fileExists(atPath: result.manifestURL.path))
}

@Test("Folder Triage rejects oversized manifests before any Finder mutation")
func folderTriageRejectsOversizedManifest() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let url = try fixture.write("print('safe') # \u{202E}\n", to: "high.py")
    let report = try FolderTriageEngine.scan(rootURL: fixture.root)
    try FileManager.default.createDirectory(at: fixture.manifests, withIntermediateDirectories: true)
    let manifestURL = FolderTriageEngine.manifestURL(forRoot: fixture.root, in: fixture.manifests)
    try Data(repeating: 0x41, count: FolderTriageEngine.maximumManifestBytes + 1)
        .write(to: manifestURL)
    let original = FinderMarkerState(tagNames: ["UserTag"], labelNumber: 3)
    let store = FakeFinderMarkerStore()
    store.states[url.path] = original

    #expect(throws: FolderTriageError.manifestTooLarge) {
        try FolderTriageEngine.applyRedMarkers(
            to: report,
            manifestDirectory: fixture.manifests,
            markerStore: store
        )
    }
    #expect(store.states[url.path] == original)
}

@Test("Folder Triage exposes bounded Vaccine finding inventories")
func folderTriageReportsOmittedFindingInventory() {
    let root = URL(fileURLWithPath: "/tmp/synthetic-triage")
    let vaccine = VaccineScanReport(
        rootURL: root,
        scannedFileCount: 10_005,
        binaryFileCount: 0,
        skippedFileCount: 0,
        excludedDirectoryCount: 0,
        ignoredPathCount: 0,
        isSignalSieveTarget: false,
        findings: [],
        assessedFiles: [],
        unassessedFiles: [],
        omittedAssessedFileCount: 5,
        omittedFindingCount: 5
    )

    let report = FolderTriageEngine.report(from: vaccine)

    #expect(report.isAssessmentBounded)
    #expect(vaccine.affectedFileCount == 5)
}

@Test("The system Finder marker adapter round-trips synthetic temp-file state")
func systemFinderMarkerStoreRoundTripsTempFile() throws {
    let fixture = try FolderTriageFixture()
    defer { fixture.cleanup() }
    let url = try fixture.write("synthetic", to: "marker.txt")
    let store = SystemFinderMarkerStore()
    let original = try store.state(for: url)
    defer { try? store.setState(original, for: url) }
    let syntheticTag = "SignalSieve-Test-\(UUID().uuidString)"
    let desired = FinderMarkerState(
        tagNames: original.tagNames + [syntheticTag],
        labelNumber: FolderTriageEngine.markerLabelNumber
    )

    try store.setState(desired, for: url)
    let persisted = try store.state(for: url)

    #expect(Set(persisted.tagNames) == Set(desired.tagNames))
    #expect(persisted.labelNumber == desired.labelNumber)
}

private struct FolderTriageFixture {
    let temporary: URL
    let root: URL
    let manifests: URL

    init() throws {
        temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignalSieveFolderTriage-\(UUID().uuidString)", isDirectory: true)
        root = temporary.appendingPathComponent("Root", isDirectory: true)
        manifests = temporary.appendingPathComponent("Manifests", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporary)
    }

    @discardableResult
    func write(_ string: String, to relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: url, options: [.atomic])
        return url
    }

    @discardableResult
    func writeData(_ data: Data, to relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        return url
    }
}

private final class FakeFinderMarkerStore: @unchecked Sendable, FinderMarkerStore {
    var states: [String: FinderMarkerState] = [:]
    var failSetPaths: Set<String> = []

    func state(for url: URL) throws -> FinderMarkerState {
        states[url.path]
            ?? states[url.standardizedFileURL.path]
            ?? FinderMarkerState(tagNames: [], labelNumber: nil)
    }

    func setState(_ state: FinderMarkerState, for url: URL) throws {
        if failSetPaths.contains(url.path) || failSetPaths.contains(url.standardizedFileURL.path) {
            throw CocoaError(.fileWriteNoPermission)
        }
        states[url.path] = state
        states[url.standardizedFileURL.path] = state
    }
}

private func markdownWithFrontMatter() -> String {
    """
    ---
    author: Synthetic
    ---
    Plain synthetic note.
    """
}

private func manifestEntryCount(at url: URL) throws -> Int {
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let entries = object?["entries"] as? [[String: Any]]
    return entries?.count ?? 0
}
