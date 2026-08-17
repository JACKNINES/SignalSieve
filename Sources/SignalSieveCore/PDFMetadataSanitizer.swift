// SPDX-License-Identifier: MPL-2.0
import Foundation
import PDFKit

enum PDFMetadataSanitizerError: Error, Equatable {
    case helperUnavailable
    case signedDocument
    case encryptedDocument
    case invalidDocument
    case timedOut
    case invalidOutput
}

enum PDFMetadataSanitizer {
    static let helperName = "SignalSievePDFSanitizer"
    static let maximumOutputBytes = FileMetadataCleaner.maximumCleaningBytes
    static let timeout: TimeInterval = 180

    private struct PageSnapshot: Equatable {
        let mediaBox: CGRect
        let cropBox: CGRect
        let rotation: Int
        let annotationTypes: [String]
    }

    private struct DocumentSnapshot: Equatable {
        let pageCount: Int
        let pages: [PageSnapshot]
    }

    static func clean(_ data: Data) throws -> Data {
        guard data.starts(with: Data("%PDF-".utf8)),
              data.count <= maximumOutputBytes,
              let originalDocument = PDFDocument(data: data),
              !originalDocument.isLocked else {
            throw PDFMetadataSanitizerError.invalidDocument
        }
        let originalSnapshot = snapshot(of: originalDocument)
        let helper = try helperURL()
        let workURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SignalSievePDF-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: workURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw PDFMetadataSanitizerError.invalidDocument
        }
        defer { try? FileManager.default.removeItem(at: workURL) }

        let inputURL = workURL.appendingPathComponent("input.pdf")
        let outputURL = workURL.appendingPathComponent("output.pdf")
        let standardOutputURL = workURL.appendingPathComponent("stdout.json")
        let standardErrorURL = workURL.appendingPathComponent("stderr.txt")
        do {
            try data.write(to: inputURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o400],
                ofItemAtPath: inputURL.path
            )
        } catch {
            throw PDFMetadataSanitizerError.invalidDocument
        }

        guard FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil),
              FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: standardOutputURL),
              let errorHandle = try? FileHandle(forWritingTo: standardErrorURL) else {
            throw PDFMetadataSanitizerError.invalidDocument
        }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = helper
        process.arguments = [inputURL.path, outputURL.path]
        process.currentDirectoryURL = workURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        process.environment = [
            "HOME": workURL.path,
            "PATH": "/usr/bin:/bin",
            "TMPDIR": workURL.path,
            "SIGNALSIEVE_OFFLINE": "1"
        ]
        do { try process.run() }
        catch { throw PDFMetadataSanitizerError.helperUnavailable }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                throw PDFMetadataSanitizerError.timedOut
            }
            if let size = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > maximumOutputBytes {
                process.terminate()
                process.waitUntilExit()
                throw PDFMetadataSanitizerError.invalidOutput
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0:
            break
        case 10:
            throw PDFMetadataSanitizerError.signedDocument
        case 11:
            throw PDFMetadataSanitizerError.encryptedDocument
        default:
            throw PDFMetadataSanitizerError.invalidDocument
        }

        guard let output = try? Data(contentsOf: outputURL, options: .mappedIfSafe),
              !output.isEmpty,
              output.count <= maximumOutputBytes,
              output != data,
              let cleanedDocument = PDFDocument(data: output),
              snapshot(of: cleanedDocument) == originalSnapshot else {
            throw PDFMetadataSanitizerError.invalidOutput
        }
        let report = FileProvenanceAnalyzer.analyze(output, fileName: "cleaned.pdf")
        guard !report.findings.contains(where: { $0.kind == .pdfMetadata }) else {
            throw PDFMetadataSanitizerError.invalidOutput
        }
        return output
    }

    private static func snapshot(of document: PDFDocument) -> DocumentSnapshot {
        let pages = (0..<document.pageCount).compactMap { index -> PageSnapshot? in
            guard let page = document.page(at: index) else { return nil }
            return PageSnapshot(
                mediaBox: page.bounds(for: .mediaBox),
                cropBox: page.bounds(for: .cropBox),
                rotation: page.rotation,
                annotationTypes: page.annotations.compactMap(\.type).sorted()
            )
        }
        return DocumentSnapshot(pageCount: document.pageCount, pages: pages)
    }

    private static func helperURL() throws -> URL {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL
                    .appendingPathComponent("PDFTools", isDirectory: true)
                    .appendingPathComponent(helperName)
            )
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/manual", isDirectory: true)
                .appendingPathComponent(helperName)
        )
        for candidate in candidates {
            let values = try? candidate.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey
            ])
            if values?.isRegularFile == true,
               values?.isSymbolicLink != true,
               FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw PDFMetadataSanitizerError.helperUnavailable
    }
}
