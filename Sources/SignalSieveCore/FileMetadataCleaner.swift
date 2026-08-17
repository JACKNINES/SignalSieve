// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum FileMetadataCleaningError: Error, Equatable {
    case notARegularFile
    case unsupportedFormat
    case fileTooLarge
    case invalidContainer
    case signedContainer
    case encryptedContainer
    case cleaningBackendUnavailable
    case noSupportedMetadata
    case destinationMatchesSource
    case destinationAlreadyExists
    case sourceChangedDuringOperation
    case couldNotWriteCopy
    case verificationFailed
}

public struct FileMetadataCleaningResult: Sendable, Equatable {
    public let originalURL: URL
    public let cleanedCopyURL: URL
    public let originalReport: FileProvenanceReport
    public let cleanedReport: FileProvenanceReport
    public let removedFindingKinds: [FileProvenanceFindingKind]
    public let originalWasUnchanged: Bool

    public var removedFindingCount: Int {
        max(0, originalReport.findings.count - cleanedReport.findings.count)
    }

    public init(
        originalURL: URL,
        cleanedCopyURL: URL,
        originalReport: FileProvenanceReport,
        cleanedReport: FileProvenanceReport,
        removedFindingKinds: [FileProvenanceFindingKind],
        originalWasUnchanged: Bool
    ) {
        self.originalURL = originalURL
        self.cleanedCopyURL = cleanedCopyURL
        self.originalReport = originalReport
        self.cleanedReport = cleanedReport
        self.removedFindingKinds = removedFindingKinds
        self.originalWasUnchanged = originalWasUnchanged
    }
}

/// Removes only bounded, structurally identified metadata and always writes a
/// new file. The source is read again before the copy is created, and the copy
/// is reanalyzed from disk before success is reported.
public enum FileMetadataCleaner {
    public static let maximumCleaningBytes = 256 * 1_024 * 1_024

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let jpegSignature = Data([0xFF, 0xD8])
    private static let removablePNGChunks: Set<String> = [
        "caBX", "eXIf", "iTXt", "tEXt", "zTXt", "tIME"
    ]
    private static let removableJPEGMarkers: Set<UInt8> = [
        0xE1, // APP1: EXIF/XMP
        0xEB, // APP11: JUMBF/C2PA and other metadata
        0xEC, // APP12: picture/application metadata
        0xED, // APP13: IPTC/Photoshop metadata
        0xFE  // COM: comment
    ]

    public static func supports(_ format: ProvenanceFileFormat) -> Bool {
        [.png, .jpeg, .pdf, .docx, .odt].contains(format)
    }

    public static func suggestedCopyName(for sourceURL: URL) -> String {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        return fileExtension.isEmpty
            ? "\(stem)-signalsieve-clean"
            : "\(stem)-signalsieve-clean.\(fileExtension)"
    }

    public static func cleanCopy(
        of sourceURL: URL,
        to destinationURL: URL
    ) throws -> FileMetadataCleaningResult {
        let source = sourceURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL
        guard source != destination else {
            throw FileMetadataCleaningError.destinationMatchesSource
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileMetadataCleaningError.destinationAlreadyExists
        }

        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw FileMetadataCleaningError.notARegularFile
        }
        guard (values.fileSize ?? 0) <= maximumCleaningBytes else {
            throw FileMetadataCleaningError.fileTooLarge
        }

        let originalData = try Data(contentsOf: source, options: .mappedIfSafe)
        guard originalData.count <= maximumCleaningBytes else {
            throw FileMetadataCleaningError.fileTooLarge
        }
        let originalReport = FileProvenanceAnalyzer.analyze(
            originalData,
            fileName: source.lastPathComponent
        )
        guard supports(originalReport.format) else {
            throw FileMetadataCleaningError.unsupportedFormat
        }

        let cleanedData = try cleanedData(
            originalData,
            format: originalReport.format
        )
        guard cleanedData != originalData else {
            throw FileMetadataCleaningError.noSupportedMetadata
        }

        let sourceBeforeWrite = try Data(contentsOf: source, options: .mappedIfSafe)
        guard sourceBeforeWrite == originalData else {
            throw FileMetadataCleaningError.sourceChangedDuringOperation
        }

        let temporaryURL = destination.deletingLastPathComponent().appendingPathComponent(
            ".signalsieve-metadata-\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do {
            try cleanedData.write(to: temporaryURL, options: .atomic)
            // Moving a new temporary file fails if another process created the
            // destination after our initial check; existing files are never replaced.
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            throw FileMetadataCleaningError.couldNotWriteCopy
        }

        var verified = false
        defer {
            if !verified {
                try? FileManager.default.removeItem(at: destination)
            }
        }

        let onDiskData = try Data(contentsOf: destination, options: .mappedIfSafe)
        guard onDiskData == cleanedData else {
            throw FileMetadataCleaningError.verificationFailed
        }
        let cleanedReport = try FileProvenanceAnalyzer.analyze(url: destination)
        let originalKinds = Set(originalReport.findings.map(\.kind))
        let cleanedKinds = Set(cleanedReport.findings.map(\.kind))
        let removedKinds = originalKinds.subtracting(cleanedKinds)
            .sorted { $0.rawValue < $1.rawValue }
        guard cleanedReport.findings.count < originalReport.findings.count else {
            throw FileMetadataCleaningError.verificationFailed
        }

        let sourceAfterWrite = try Data(contentsOf: source, options: .mappedIfSafe)
        guard sourceAfterWrite == originalData else {
            throw FileMetadataCleaningError.sourceChangedDuringOperation
        }
        verified = true
        return FileMetadataCleaningResult(
            originalURL: source,
            cleanedCopyURL: destination,
            originalReport: originalReport,
            cleanedReport: cleanedReport,
            removedFindingKinds: removedKinds,
            originalWasUnchanged: true
        )
    }

    static func cleanedData(
        _ data: Data,
        format: ProvenanceFileFormat
    ) throws -> Data {
        switch format {
        case .png:
            try cleanPNG(data)
        case .jpeg:
            try cleanJPEG(data)
        case .pdf:
            try cleanPDF(data)
        case .docx:
            try cleanDOCX(data)
        case .odt:
            try cleanODT(data)
        case .svg, .html, .markdown, .other:
            throw FileMetadataCleaningError.unsupportedFormat
        }
    }

    private static func cleanPDF(_ data: Data) throws -> Data {
        do {
            return try PDFMetadataSanitizer.clean(data)
        } catch let error as PDFMetadataSanitizerError {
            switch error {
            case .helperUnavailable:
                throw FileMetadataCleaningError.cleaningBackendUnavailable
            case .signedDocument:
                throw FileMetadataCleaningError.signedContainer
            case .encryptedDocument:
                throw FileMetadataCleaningError.encryptedContainer
            case .invalidDocument:
                throw FileMetadataCleaningError.invalidContainer
            case .timedOut, .invalidOutput:
                throw FileMetadataCleaningError.verificationFailed
            }
        }
    }

    private static func cleanDOCX(_ data: Data) throws -> Data {
        let archive = try archiveReader(data)
        guard archive.entry(named: "[Content_Types].xml") != nil,
              archive.entry(named: "_rels/.rels") != nil,
              archive.entry(named: "word/document.xml") != nil else {
            throw FileMetadataCleaningError.invalidContainer
        }
        guard !containsDigitalSignature(in: archive, format: .docx) else {
            throw FileMetadataCleaningError.signedContainer
        }

        let removableParts: Set<String> = [
            "docProps/core.xml",
            "docProps/custom.xml",
            "docProps/app.xml"
        ]
        let presentParts = Set(archive.entries.map(\.name)).intersection(removableParts)
        guard !presentParts.isEmpty else {
            throw FileMetadataCleaningError.noSupportedMetadata
        }

        var replacements: [String: Data] = [:]
        if let contentTypes = try archiveText("[Content_Types].xml", in: archive) {
            let cleaned = removingSelfClosingElements(
                localName: "Override",
                from: contentTypes
            ) { element in
                guard let partName = xmlAttribute("PartName", in: element) else { return false }
                return removableParts.contains(partName.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            }
            if cleaned != contentTypes {
                replacements["[Content_Types].xml"] = Data(cleaned.utf8)
            }
        }
        if let relationships = try archiveText("_rels/.rels", in: archive) {
            let cleaned = removingSelfClosingElements(
                localName: "Relationship",
                from: relationships
            ) { element in
                let target = xmlAttribute("Target", in: element)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let type = xmlAttribute("Type", in: element)?.lowercased() ?? ""
                return target.map(removableParts.contains) == true
                    || type.hasSuffix("/metadata/core-properties")
                    || type.hasSuffix("/extended-properties")
                    || type.hasSuffix("/custom-properties")
            }
            if cleaned != relationships {
                replacements["_rels/.rels"] = Data(cleaned.utf8)
            }
        }

        let output: Data
        do {
            output = try BoundedZIPRewriter.rewrite(
                data,
                removing: presentParts,
                replacing: replacements
            )
        } catch {
            throw FileMetadataCleaningError.invalidContainer
        }
        let verified = try archiveReader(output)
        guard presentParts.allSatisfy({ verified.entry(named: $0) == nil }),
              let documentEntry = verified.entry(named: "word/document.xml"),
              (try? verified.data(for: documentEntry)) != nil else {
            throw FileMetadataCleaningError.verificationFailed
        }
        return output
    }

    private static func cleanODT(_ data: Data) throws -> Data {
        let archive = try archiveReader(data)
        let ordered = archive.entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
        guard let mimeEntry = archive.entry(named: "mimetype"),
              ordered.first?.name == "mimetype",
              mimeEntry.compressionMethod == 0,
              let mimeData = try? archive.data(for: mimeEntry),
              String(decoding: mimeData, as: UTF8.self)
                == "application/vnd.oasis.opendocument.text",
              archive.entry(named: "content.xml") != nil else {
            throw FileMetadataCleaningError.invalidContainer
        }
        guard !containsDigitalSignature(in: archive, format: .odt) else {
            throw FileMetadataCleaningError.signedContainer
        }
        guard let metadata = try archiveText("meta.xml", in: archive),
              hasOpenDocumentMetadataFields(metadata) else {
            throw FileMetadataCleaningError.noSupportedMetadata
        }

        let version = firstCapture(
            pattern: #"office:version\s*=\s*[\"']([0-9.]{1,12})[\"']"#,
            in: metadata
        ) ?? "1.2"
        let emptyMetadata = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" office:version="\(version)"><office:meta/></office:document-meta>
        """

        let output: Data
        do {
            output = try BoundedZIPRewriter.rewrite(
                data,
                removing: [],
                replacing: ["meta.xml": Data(emptyMetadata.utf8)],
                requiredFirstStoredEntry: "mimetype"
            )
        } catch {
            throw FileMetadataCleaningError.invalidContainer
        }
        let verified = try archiveReader(output)
        guard let verifiedMime = verified.entry(named: "mimetype"),
              verifiedMime.compressionMethod == 0,
              let verifiedMeta = try archiveText("meta.xml", in: verified),
              !hasOpenDocumentMetadataFields(verifiedMeta),
              let content = verified.entry(named: "content.xml"),
              (try? verified.data(for: content)) != nil else {
            throw FileMetadataCleaningError.verificationFailed
        }
        return output
    }

    private static func archiveReader(_ data: Data) throws -> BoundedZIPReader {
        do { return try BoundedZIPReader(data: data) }
        catch { throw FileMetadataCleaningError.invalidContainer }
    }

    private static func archiveText(
        _ name: String,
        in archive: BoundedZIPReader
    ) throws -> String? {
        guard let entry = archive.entry(named: name) else { return nil }
        let data: Data
        do { data = try archive.data(for: entry) }
        catch { throw FileMetadataCleaningError.invalidContainer }
        guard let text = String(data: data, encoding: .utf8) else {
            throw FileMetadataCleaningError.invalidContainer
        }
        return text
    }

    private static func containsDigitalSignature(
        in archive: BoundedZIPReader,
        format: ProvenanceFileFormat
    ) -> Bool {
        archive.entries.contains { entry in
            let name = entry.name.lowercased()
            switch format {
            case .docx:
                return name.hasPrefix("_xmlsignatures/")
                    || name.contains("origin.sigs")
            case .odt:
                return name == "meta-inf/documentsignatures.xml"
                    || name == "meta-inf/macrosignatures.xml"
                    || name == "meta-inf/xadessignatures.xml"
            default:
                return false
            }
        }
    }

    private static func removingSelfClosingElements(
        localName: String,
        from text: String,
        where shouldRemove: (String) -> Bool
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: localName)
        guard let expression = try? NSRegularExpression(
            pattern: #"<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?"#
                + escaped
                + #"\b[^>]*?/\s*>"#,
            options: [.caseInsensitive]
        ) else { return text }
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let element = String(text[range])
            guard shouldRemove(element),
                  let resultRange = Range(match.range, in: result) else { continue }
            result.removeSubrange(resultRange)
        }
        return result
    }

    private static func xmlAttribute(_ name: String, in element: String) -> String? {
        firstCapture(
            pattern: #"\b"# + NSRegularExpression.escapedPattern(for: name)
                + #"\s*=\s*[\"']([^\"']*)[\"']"#,
            in: element,
            options: [.caseInsensitive]
        )
    }

    private static func hasOpenDocumentMetadataFields(_ text: String) -> Bool {
        guard let body = firstCapture(
            pattern: #"<office:meta\b[^>]*>(.*?)</office:meta\s*>"#,
            in: text,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return text.range(
                of: #"<office:meta\b[^>]*/\s*>"#,
                options: [.regularExpression, .caseInsensitive]
            ) == nil
        }
        return body.range(
            of: #"<\s*(?!/|\?|!)[A-Za-z_][A-Za-z0-9_.-]*(?::[A-Za-z_][A-Za-z0-9_.-]*)?\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func firstCapture(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func cleanPNG(_ data: Data) throws -> Data {
        guard data.starts(with: pngSignature) else {
            throw FileMetadataCleaningError.invalidContainer
        }
        var output = pngSignature
        var offset = pngSignature.count
        var foundEnd = false

        while offset <= data.count - 12 {
            guard let length = bigEndianUInt32(data, at: offset).map(Int.init),
                  length <= data.count - offset - 12 else {
                throw FileMetadataCleaningError.invalidContainer
            }
            let chunkEnd = offset + 12 + length
            let typeStart = offset + 4
            let type = String(decoding: data[typeStart..<(typeStart + 4)], as: UTF8.self)
            if !removablePNGChunks.contains(type) {
                output.append(data[offset..<chunkEnd])
            }
            offset = chunkEnd
            if type == "IEND" {
                foundEnd = true
                break
            }
        }

        guard foundEnd, offset == data.count else {
            throw FileMetadataCleaningError.invalidContainer
        }
        return output
    }

    private static func cleanJPEG(_ data: Data) throws -> Data {
        guard data.starts(with: jpegSignature) else {
            throw FileMetadataCleaningError.invalidContainer
        }
        var output = jpegSignature
        var offset = 2

        while offset < data.count {
            let segmentStart = offset
            guard data[offset] == 0xFF else {
                throw FileMetadataCleaningError.invalidContainer
            }
            while offset < data.count, data[offset] == 0xFF { offset += 1 }
            guard offset < data.count else {
                throw FileMetadataCleaningError.invalidContainer
            }
            let marker = data[offset]
            offset += 1

            if marker == 0xD9 {
                output.append(data[segmentStart..<offset])
                guard offset == data.count else {
                    throw FileMetadataCleaningError.invalidContainer
                }
                return output
            }
            if marker == 0xDA {
                guard offset + 2 <= data.count,
                      let length = bigEndianUInt16(data, at: offset).map(Int.init),
                      length >= 2,
                      length <= data.count - offset else {
                    throw FileMetadataCleaningError.invalidContainer
                }
                output.append(data[segmentStart...])
                return output
            }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                output.append(data[segmentStart..<offset])
                continue
            }
            guard offset + 2 <= data.count,
                  let length = bigEndianUInt16(data, at: offset).map(Int.init),
                  length >= 2,
                  length <= data.count - offset else {
                throw FileMetadataCleaningError.invalidContainer
            }
            let segmentEnd = offset + length
            if !removableJPEGMarkers.contains(marker) {
                output.append(data[segmentStart..<segmentEnd])
            }
            offset = segmentEnd
        }

        throw FileMetadataCleaningError.invalidContainer
    }

    private static func bigEndianUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func bigEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
}
