// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation
import SignalSieveCore

private struct QualityFailure: CustomStringConvertible {
    let fileName: String
    let detail: String

    var description: String { "\(fileName): \(detail)" }
}

private struct CorpusFile {
    let url: URL
    let size: Int
}

@main
enum CorpusQualityRunner {
    private static let provenanceExtensions = VaccineEngine.provenanceFileExtensions
    private static let rasterTypeIdentifiers: [String: String] = [
        "png": "public.png",
        "jpg": "public.jpeg",
        "jpeg": "public.jpeg",
        "tif": "public.tiff",
        "tiff": "public.tiff",
        "heic": "public.heic",
        "heif": "public.heif",
        "gif": "com.compuserve.gif"
    ]
    private static let maximumCleanSamplesPerFormat = 3
    private static let maximumFreshImageSamplesPerFormat = 5
    private static let maximumVaccineSampleFiles = 100
    private static let maximumVaccineSampleBytes = 64 * 1_024 * 1_024

    static func main() {
        guard CommandLine.arguments.count == 2 else {
            writeError("Usage: SignalSieveCorpusQuality <directory>\n")
            Foundation.exit(EXIT_FAILURE)
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .standardizedFileURL
        do {
            try run(root: root)
        } catch {
            writeError("Corpus quality run failed: \(error)\n")
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func run(root: URL) throws {
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard rootValues.isDirectory == true, rootValues.isReadable != false else {
            throw VaccineError.invalidRoot
        }

        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SignalSieveCorpusQuality-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let files = try corpusFiles(under: root)
        let vaccineSample = try prepareVaccineSample(from: files, under: temporaryRoot)
        let vaccineReport = try VaccineEngine.scan(rootURL: vaccineSample.url)
        var failures: [QualityFailure] = []
        var provenanceCount = 0
        var provenanceFindingCount = 0
        var formatCounts: [String: Int] = [:]
        var cleaningAttempts: [String: Int] = [:]
        var cleaningSuccesses: [String: Int] = [:]
        var expectedCleaningRefusals: [String: Int] = [:]
        var freshImageAttempts: [String: Int] = [:]
        var freshImageSuccesses: [String: Int] = [:]

        for file in files {
            let fileExtension = file.url.pathExtension.lowercased()
            if provenanceExtensions.contains(fileExtension) {
                do {
                    let report = try FileProvenanceAnalyzer.analyze(url: file.url)
                    provenanceCount += 1
                    provenanceFindingCount += report.findings.count
                    formatCounts[report.format.rawValue, default: 0] += 1
                    validate(report, source: file, failures: &failures)
                    testCleanCopyIfUseful(
                        source: file,
                        report: report,
                        temporaryRoot: temporaryRoot,
                        attempts: &cleaningAttempts,
                        successes: &cleaningSuccesses,
                        expectedRefusals: &expectedCleaningRefusals,
                        failures: &failures
                    )
                } catch {
                    failures.append(QualityFailure(
                        fileName: file.url.lastPathComponent,
                        detail: "provenance inspection failed (\(error))"
                    ))
                }
            }

            if let typeIdentifier = rasterTypeIdentifiers[fileExtension] {
                testFreshImageIfUseful(
                    source: file,
                    typeIdentifier: typeIdentifier,
                    attempts: &freshImageAttempts,
                    successes: &freshImageSuccesses,
                    failures: &failures
                )
            }
        }

        print("Signal Sieve real-corpus quality report")
        print("Corpus root: \(root.path)")
        print("Regular files inventoried: \(files.count)")
        print("Files copied into bounded Vaccine sample: \(vaccineSample.fileCount)")
        print("Vaccine text files scanned: \(vaccineReport.scannedFileCount)")
        print("Vaccine binary files classified: \(vaccineReport.binaryFileCount)")
        print("Vaccine skipped files: \(vaccineReport.skippedFileCount)")
        print("Vaccine affected files: \(vaccineReport.affectedFileCount)")
        print("Vaccine Unicode findings: \(vaccineReport.totalUnicodeFindingCount)")
        print("Vaccine metadata findings: \(vaccineReport.totalMetadataFindingCount)")
        print("Provenance files inspected: \(provenanceCount)")
        print("Provenance findings: \(provenanceFindingCount)")
        print("Formats: \(formattedCounts(formatCounts))")
        print("Verified clean-copy attempts: \(cleaningAttempts.values.reduce(0, +))")
        print("Verified clean-copy successes: \(cleaningSuccesses.values.reduce(0, +))")
        print("Expected safe refusals: \(expectedCleaningRefusals.values.reduce(0, +))")
        print("Fresh-image attempts: \(freshImageAttempts.values.reduce(0, +))")
        print("Fresh-image successes: \(freshImageSuccesses.values.reduce(0, +))")
        print("Temporary copies removed: yes")
        print("Download originals modified: no")

        if failures.isEmpty {
            print("RESULT: PASS")
            return
        }
        print("RESULT: FAIL (\(failures.count) invariant violation(s))")
        for failure in failures.prefix(25) {
            print("FAIL  \(failure)")
        }
        if failures.count > 25 {
            print("FAIL  ... \(failures.count - 25) additional failure(s)")
        }
        Foundation.exit(EXIT_FAILURE)
    }

    private static func corpusFiles(under root: URL) throws -> [CorpusFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        var files: [CorpusFile] = []
        for url in children {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true else { continue }
            files.append(CorpusFile(url: url, size: max(0, values?.fileSize ?? 0)))
        }
        return files.sorted { $0.url.path < $1.url.path }
    }

    private static func prepareVaccineSample(
        from files: [CorpusFile],
        under temporaryRoot: URL
    ) throws -> (url: URL, fileCount: Int) {
        let sampleRoot = temporaryRoot.appendingPathComponent("vaccine-sample", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sampleRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        var copiedCount = 0
        var copiedBytes = 0
        for file in files where file.size <= VaccineEngine.maximumFileSize {
            guard copiedCount < maximumVaccineSampleFiles,
                  copiedBytes + file.size <= maximumVaccineSampleBytes else { break }
            let destination = sampleRoot.appendingPathComponent(file.url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: file.url, to: destination)
                copiedCount += 1
                copiedBytes += file.size
            } catch {
                continue
            }
        }
        return (sampleRoot, copiedCount)
    }

    private static func validate(
        _ report: FileProvenanceReport,
        source: CorpusFile,
        failures: inout [QualityFailure]
    ) {
        let expectedFormats: [String: ProvenanceFileFormat] = [
            "png": .png,
            "jpg": .jpeg,
            "jpeg": .jpeg,
            "svg": .svg,
            "pdf": .pdf,
            "docx": .docx,
            "odt": .odt,
            "html": .html,
            "htm": .html,
            "md": .markdown,
            "markdown": .markdown
        ]
        let fileExtension = source.url.pathExtension.lowercased()
        if let expectedFormat = expectedFormats[fileExtension],
           report.format != expectedFormat,
           !report.findings.contains(where: {
               $0.kind == .extensionContentMismatch && $0.evidenceConfidence == .exact
           }) {
            failures.append(QualityFailure(
                fileName: source.url.lastPathComponent,
                detail: "expected \(expectedFormat.rawValue), got \(report.format.rawValue)"
            ))
        }
        if report.fileSize != source.size {
            failures.append(QualityFailure(
                fileName: source.url.lastPathComponent,
                detail: "reported size does not match the source"
            ))
        }
        if report.scannedByteCount > FileProvenanceAnalyzer.maximumScanBytes {
            failures.append(QualityFailure(
                fileName: source.url.lastPathComponent,
                detail: "bounded scan limit was exceeded"
            ))
        }
        if report.wasTruncated != (source.size > report.scannedByteCount) {
            failures.append(QualityFailure(
                fileName: source.url.lastPathComponent,
                detail: "truncation state is inconsistent"
            ))
        }
        let uniqueFindings = Set(report.findings.map { "\($0.kind.rawValue)|\($0.evidence)" })
        if uniqueFindings.count != report.findings.count {
            failures.append(QualityFailure(
                fileName: source.url.lastPathComponent,
                detail: "duplicate provenance findings were emitted"
            ))
        }
    }

    private static func testCleanCopyIfUseful(
        source: CorpusFile,
        report: FileProvenanceReport,
        temporaryRoot: URL,
        attempts: inout [String: Int],
        successes: inout [String: Int],
        expectedRefusals: inout [String: Int],
        failures: inout [QualityFailure]
    ) {
        let format = report.format.rawValue
        guard FileMetadataCleaner.supports(report.format),
              !report.findings.isEmpty,
              source.size <= FileMetadataCleaner.maximumCleaningBytes,
              attempts[format, default: 0] < maximumCleanSamplesPerFormat else { return }
        attempts[format, default: 0] += 1

        do {
            let originalDigest = try digest(source.url)
            let destination = temporaryRoot.appendingPathComponent(
                "clean-\(attempts.values.reduce(0, +))-\(source.url.lastPathComponent)"
            )
            let result = try FileMetadataCleaner.cleanCopy(of: source.url, to: destination)
            let afterDigest = try digest(source.url)
            guard originalDigest == afterDigest,
                  result.originalWasUnchanged,
                  result.cleanedReport.findings.count < result.originalReport.findings.count,
                  result.cleanedCopyURL.deletingLastPathComponent() == temporaryRoot else {
                failures.append(QualityFailure(
                    fileName: source.url.lastPathComponent,
                    detail: "verified clean-copy invariants failed"
                ))
                return
            }
            successes[format, default: 0] += 1
        } catch let error as FileMetadataCleaningError {
            switch error {
            case .signedContainer, .encryptedContainer, .invalidContainer,
                 .noSupportedMetadata, .cleaningBackendUnavailable:
                expectedRefusals[format, default: 0] += 1
            default:
                failures.append(QualityFailure(
                    fileName: source.url.lastPathComponent,
                    detail: "clean copy failed unexpectedly (\(error))"
                ))
            }
        } catch {
            failures.append(QualityFailure(
                fileName: source.url.lastPathComponent,
                detail: "clean copy failed unexpectedly (\(error))"
            ))
        }
    }

    private static func testFreshImageIfUseful(
        source: CorpusFile,
        typeIdentifier: String,
        attempts: inout [String: Int],
        successes: inout [String: Int],
        failures: inout [QualityFailure]
    ) {
        let fileExtension = source.url.pathExtension.lowercased()
        guard source.size <= ClipboardImageImporter.maximumInputBytes,
              attempts[fileExtension, default: 0] < maximumFreshImageSamplesPerFormat else { return }
        attempts[fileExtension, default: 0] += 1

        do {
            let sourceData = try Data(contentsOf: source.url, options: .mappedIfSafe)
            let sourceDigest = SHA256.hash(data: sourceData)
            let payload = try ClipboardImageImporter.importImage(from: [
                ClipboardImageRepresentation(
                    typeIdentifier: typeIdentifier,
                    data: sourceData
                )
            ])
            let result = try ClipboardImageCleaner.makeFreshCopy(from: payload)
            guard SHA256.hash(data: sourceData) == sourceDigest,
                  result.cleanedReport.findings.isEmpty,
                  !result.cleanedReport.containsC2PAContainer,
                  result.cleanedPayload.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) else {
                failures.append(QualityFailure(
                    fileName: source.url.lastPathComponent,
                    detail: "fresh-image verification invariants failed"
                ))
                return
            }
            successes[fileExtension, default: 0] += 1
        } catch ClipboardImageImportError.imageTooLarge {
            // Pixel count is a deliberate safety limit, not a quality failure.
        } catch {
            failures.append(QualityFailure(
                fileName: source.url.lastPathComponent,
                detail: "fresh-image conversion failed (\(error))"
            ))
        }
    }

    private static func digest(_ url: URL) throws -> SHA256.Digest {
        SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    private static func formattedCounts(_ counts: [String: Int]) -> String {
        counts.keys.sorted().map { "\($0)=\(counts[$0, default: 0])" }.joined(separator: ", ")
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }
}
