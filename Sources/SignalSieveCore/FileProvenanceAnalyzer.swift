// SPDX-License-Identifier: MPL-2.0
import Foundation
import PDFKit

public enum ProvenanceFileFormat: String, Sendable, Equatable {
    case png = "PNG image"
    case jpeg = "JPEG image"
    case webp = "WebP image"
    case avif = "AVIF image"
    case heic = "HEIC/HEIF image"
    case bmp = "BMP image"
    case gif = "GIF image"
    case tiff = "TIFF image"
    case svg = "SVG image"
    case pdf = "PDF document"
    case docx = "Office Open XML document"
    case xlsx = "Excel Open XML workbook"
    case pptx = "PowerPoint Open XML presentation"
    case epub = "EPUB publication"
    case odt = "OpenDocument Text document"
    case html = "HTML document"
    case markdown = "Markdown document"
    case other = "Other file"
}

public enum FileProvenanceFindingKind: String, Sendable, Equatable {
    case c2paManifest = "C2PA manifest container"
    case exifMetadata = "EXIF metadata"
    case xmpMetadata = "XMP metadata"
    case pngTextMetadata = "PNG textual metadata"
    case jpegApp11 = "JPEG APP11 segment"
    case svgMetadata = "SVG metadata"
    case pdfMetadata = "PDF metadata"
    case documentProperties = "Document properties"
    case openDocumentMetadata = "OpenDocument metadata"
    case htmlMetadata = "HTML metadata"
    case markdownFrontMatter = "Markdown front matter"
    case leadingContainerData = "Leading data before container"
    case extensionContentMismatch = "File extension and content mismatch"
    case riffMetadata = "RIFF image metadata"
    case isobmffMetadata = "ISO-BMFF image metadata"
    case gifMetadata = "GIF extension metadata"
    case tiffMetadata = "TIFF metadata tag"
    case trailingContainerData = "Trailing data after image payload"
    case epubMetadata = "EPUB metadata"
    case embeddedResourceMetadata = "Embedded resource metadata"
    case protectedContainer = "Signed or encrypted container"
}

public struct FileProvenanceFinding: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: FileProvenanceFindingKind
    public let evidenceConfidence: EvidenceConfidence
    public let detail: String
    public let evidence: String

    public init(
        id: String,
        kind: FileProvenanceFindingKind,
        evidenceConfidence: EvidenceConfidence,
        detail: String,
        evidence: String
    ) {
        self.id = id
        self.kind = kind
        self.evidenceConfidence = evidenceConfidence
        self.detail = detail
        self.evidence = evidence
    }
}

public struct FileProvenanceReport: Sendable, Equatable {
    public let fileName: String
    public let format: ProvenanceFileFormat
    public let fileSize: Int
    public let scannedByteCount: Int
    public let wasTruncated: Bool
    public let findings: [FileProvenanceFinding]

    public var containsC2PAContainer: Bool {
        findings.contains { $0.kind == .c2paManifest }
    }

    public init(
        fileName: String,
        format: ProvenanceFileFormat,
        fileSize: Int,
        scannedByteCount: Int,
        wasTruncated: Bool,
        findings: [FileProvenanceFinding]
    ) {
        self.fileName = fileName
        self.format = format
        self.fileSize = fileSize
        self.scannedByteCount = scannedByteCount
        self.wasTruncated = wasTruncated
        self.findings = findings
    }
}

public enum FileProvenanceAnalyzerError: Error, Equatable {
    case notARegularFile
    case unreadableFile
}

/// Performs a bounded, read-only inspection of file containers and metadata.
/// It recognizes structural markers but deliberately does not claim to validate
/// C2PA signatures. Validation requires a compatible cryptographic validator.
public enum FileProvenanceAnalyzer {
    public static let maximumScanBytes = 64 * 1_024 * 1_024

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let jpegSignature = Data([0xFF, 0xD8])
    private static let pdfSignature = Data("%PDF-".utf8)
    private static let zipSignature = Data([0x50, 0x4B, 0x03, 0x04])
    private static let c2paManifestUUID = Data([
        0x63, 0x32, 0x70, 0x61, 0x00, 0x11, 0x00, 0x10,
        0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
    ])

    public static func analyze(url: URL) throws -> FileProvenanceReport {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw FileProvenanceAnalyzerError.notARegularFile
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw FileProvenanceAnalyzerError.unreadableFile
        }
        defer { try? handle.close() }

        let data: Data
        do {
            data = try handle.read(upToCount: maximumScanBytes) ?? Data()
        } catch {
            throw FileProvenanceAnalyzerError.unreadableFile
        }
        let fileSize = values.fileSize ?? data.count
        return analyze(
            data,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            wasTruncated: fileSize > data.count
        )
    }

    public static func analyze(
        _ data: Data,
        fileName: String,
        fileSize: Int? = nil,
        wasTruncated: Bool = false
    ) -> FileProvenanceReport {
        let format = detectFormat(data, fileName: fileName)
        var findings: [FileProvenanceFinding] = []

        func append(
            _ kind: FileProvenanceFindingKind,
            confidence: EvidenceConfidence,
            detail: String,
            evidence: String
        ) {
            let duplicate = findings.contains {
                $0.kind == kind && $0.evidence == evidence
            }
            guard !duplicate else { return }
            findings.append(FileProvenanceFinding(
                id: "\(kind.rawValue):\(findings.count)",
                kind: kind,
                evidenceConfidence: confidence,
                detail: detail,
                evidence: evidence
            ))
        }

        switch format {
        case .png:
            inspectPNG(data, append: append)
        case .jpeg:
            inspectJPEG(data, append: append)
        case .webp, .avif, .heic, .bmp, .gif, .tiff,
             .xlsx, .pptx, .epub:
            ExtendedContainerInspector.inspect(data, format: format, append: append)
        case .svg:
            inspectSVG(data, append: append)
        case .pdf:
            inspectPDF(data, append: append)
        case .docx:
            inspectDOCX(data, append: append)
        case .odt:
            inspectODT(data, append: append)
        case .html:
            inspectHTML(data, append: append)
        case .markdown:
            inspectMarkdown(data, append: append)
        case .other:
            break
        }

        inspectGenericMarkers(data, existing: findings, append: append)
        if let expectedFormat = expectedFormat(for: fileName),
           expectedFormat != format {
            append(
                .extensionContentMismatch,
                confidence: .exact,
                detail: "The filename extension and detected content type do not match. This can indicate a mislabeled file or polyglot content.",
                evidence: "Extension .\((fileName as NSString).pathExtension.lowercased()) · detected \(format.rawValue)"
            )
        }

        return FileProvenanceReport(
            fileName: fileName,
            format: format,
            fileSize: fileSize ?? data.count,
            scannedByteCount: data.count,
            wasTruncated: wasTruncated,
            findings: findings
        )
    }

    private static func detectFormat(_ data: Data, fileName: String) -> ProvenanceFileFormat {
        let extensionValue = (fileName as NSString).pathExtension.lowercased()
        if data.starts(with: pngSignature) { return .png }
        if data.starts(with: jpegSignature) { return .jpeg }
        if ExtendedContainerInspector.isWebP(data) { return .webp }
        if ExtendedContainerInspector.isBMP(data) { return .bmp }
        if ExtendedContainerInspector.isGIF(data) { return .gif }
        if ExtendedContainerInspector.isTIFF(data) { return .tiff }
        if let format = ExtendedContainerInspector.isoImageFormat(data) { return format }
        if data.starts(with: pdfSignature) { return .pdf }
        if extensionValue == "pdf", pdfHeaderOffset(in: data) != nil { return .pdf }
        if data.starts(with: zipSignature),
           let format = ExtendedContainerInspector.zipFormat(data, extensionValue: extensionValue) {
            return format
        }

        let prefix = String(decoding: data.prefix(8_192), as: UTF8.self).lowercased()
        if extensionValue == "svg" || prefix.contains("<svg") { return .svg }
        if ["html", "htm"].contains(extensionValue)
            || prefix.contains("<!doctype html")
            || prefix.contains("<html") { return .html }
        if ["md", "markdown"].contains(extensionValue) { return .markdown }
        return .other
    }

    private static func expectedFormat(for fileName: String) -> ProvenanceFileFormat? {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "webp": return .webp
        case "avif": return .avif
        case "heic", "heif": return .heic
        case "bmp": return .bmp
        case "gif": return .gif
        case "tif", "tiff": return .tiff
        case "svg": return .svg
        case "pdf": return .pdf
        case "docx": return .docx
        case "xlsx": return .xlsx
        case "pptx": return .pptx
        case "epub": return .epub
        case "odt": return .odt
        case "html", "htm": return .html
        case "md", "markdown": return .markdown
        default: return nil
        }
    }

    private static func inspectPNG(
        _ data: Data,
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        guard data.starts(with: pngSignature) else { return }
        var offset = pngSignature.count
        while offset <= data.count - 12 {
            guard let length = bigEndianUInt32(data, at: offset).map(Int.init),
                  length <= data.count - offset - 12 else { break }
            let typeStart = offset + 4
            let typeEnd = typeStart + 4
            let type = String(decoding: data[typeStart..<typeEnd], as: UTF8.self)

            switch type {
            case "caBX":
                append(
                    .c2paManifest,
                    .exact,
                    "An embedded C2PA container marker is present. Its cryptographic claim has not been validated.",
                    "PNG caBX chunk"
                )
            case "eXIf":
                append(
                    .exifMetadata,
                    .exact,
                    "EXIF metadata is present and may contain camera, software, time, or location information.",
                    "PNG eXIf chunk"
                )
            case "iTXt", "tEXt", "zTXt":
                append(
                    .pngTextMetadata,
                    .exact,
                    "A PNG textual metadata chunk is present. Its private contents are not included in this report.",
                    "PNG \(type) chunk"
                )
            default:
                break
            }
            offset += 12 + length
        }
    }

    private static func inspectJPEG(
        _ data: Data,
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        guard data.starts(with: jpegSignature) else { return }
        var offset = 2
        var app11Payload = Data()

        while offset + 1 < data.count {
            guard data[offset] == 0xFF else {
                offset += 1
                continue
            }
            while offset < data.count && data[offset] == 0xFF { offset += 1 }
            guard offset < data.count else { break }
            let marker = data[offset]
            offset += 1

            if marker == 0xD9 || marker == 0xDA { break }
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { continue }
            guard offset + 2 <= data.count,
                  let segmentLength = bigEndianUInt16(data, at: offset).map(Int.init),
                  segmentLength >= 2,
                  segmentLength <= data.count - offset else { break }

            let payloadStart = offset + 2
            let payloadEnd = offset + segmentLength
            let payload = data[payloadStart..<payloadEnd]

            if marker == 0xE1 {
                if payload.starts(with: Data([0x45, 0x78, 0x69, 0x66, 0x00, 0x00])) {
                    append(
                        .exifMetadata,
                        .exact,
                        "EXIF metadata is present and may contain camera, software, time, or location information.",
                        "JPEG APP1 Exif segment"
                    )
                }
                if containsASCII(payload, "http://ns.adobe.com/xap/1.0/")
                    || containsASCII(payload, "<x:xmpmeta") {
                    append(
                        .xmpMetadata,
                        .exact,
                        "XMP metadata is present. It can contain editing, creator, rights, or provenance fields.",
                        "JPEG APP1 XMP segment"
                    )
                }
            } else if marker == 0xEB {
                app11Payload.append(contentsOf: payload)
            }
            offset = payloadEnd
        }

        if !app11Payload.isEmpty {
            if app11Payload.range(of: c2paManifestUUID) != nil
                || (containsASCII(app11Payload, "c2pa") && containsASCII(app11Payload, "jumb")) {
                append(
                    .c2paManifest,
                    .exact,
                    "A C2PA-labelled JUMBF structure is present in JPEG APP11 data. Its cryptographic claim has not been validated.",
                    "JPEG APP11 C2PA/JUMBF structure"
                )
            } else {
                append(
                    .jpegApp11,
                    .exact,
                    "JPEG APP11 data is present, but APP11 is not exclusive to C2PA and is not treated as proof of provenance.",
                    "JPEG APP11 segment"
                )
            }
        }
    }

    private static func inspectSVG(
        _ data: Data,
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        let text = decodedText(data)
        if text.range(of: "<metadata", options: .caseInsensitive) != nil {
            append(
                .svgMetadata,
                .exact,
                "The SVG contains a metadata element. Its private contents are not copied into this report.",
                "SVG metadata element"
            )
        }
    }

    private static func inspectPDF(
        _ data: Data,
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        let headerOffset = pdfHeaderOffset(in: data) ?? 0
        if headerOffset > 0 {
            append(
                .leadingContainerData,
                .exact,
                "The PDF header begins after leading data. This can indicate a wrapped download or polyglot container, so metadata cleaning must refuse it unless the structure is normalized first.",
                "PDF header at byte \(headerOffset)"
            )
        }
        var exactEvidenceFound = false
        let parserData = headerOffset > 0 ? Data(data.dropFirst(headerOffset)) : data
        if let document = PDFDocument(data: parserData) {
            let attributes = document.documentAttributes ?? [:]
            let metadataKeys = attributes.keys.filter { key in
                let normalized = String(describing: key).lowercased()
                return [
                    "title", "author", "subject", "keyword", "creator",
                    "producer", "creation", "modification", "trapped"
                ].contains { normalized.contains($0) }
            }
            if !metadataKeys.isEmpty {
                append(
                    .pdfMetadata,
                    .exact,
                    "The parsed PDF Info dictionary contains document metadata. Values are excluded from this report.",
                    "PDF Info dictionary · \(metadataKeys.count) field(s)"
                )
                exactEvidenceFound = true
            }
            if hasStructuredPDFMetadataReference(data) {
                append(
                    .pdfMetadata,
                    .exact,
                    "The parsed PDF contains a structural metadata-stream reference. Metadata values are excluded.",
                    "PDF Metadata object reference"
                )
                exactEvidenceFound = true
            }
        }

        if !exactEvidenceFound,
           containsASCII(data, "/Metadata") || containsASCII(data, "<x:xmpmeta") {
            append(
                .pdfMetadata,
                .probable,
                "PDF metadata markers are present, but the native parser could not confirm their object relationship.",
                "Unconfirmed PDF metadata marker"
            )
        }
    }

    private static func inspectDOCX(
        _ data: Data,
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        guard let archive = try? BoundedZIPReader(data: data) else {
            if containsASCII(data, "docProps/core.xml")
                || containsASCII(data, "docProps/custom.xml")
                || containsASCII(data, "customXml/") {
                append(
                    .documentProperties,
                    .probable,
                    "OOXML metadata part names are present, but the ZIP directory could not be parsed safely.",
                    "Unconfirmed OOXML metadata part name"
                )
            }
            return
        }

        let propertyParts = archive.entries.filter {
            ["docProps/core.xml", "docProps/custom.xml", "docProps/app.xml"].contains($0.name)
        }
        for entry in propertyParts {
            let fieldCount = (try? archive.data(for: entry))
                .map(xmlElementCount) ?? 0
            append(
                .documentProperties,
                .exact,
                "The OOXML ZIP directory contains a document-property part. It was parsed locally without reporting private values.",
                "OOXML \(entry.name) · \(fieldCount) element(s)"
            )
        }
        let customXMLCount = archive.entries.filter {
            $0.name.hasPrefix("customXml/") && !$0.name.hasSuffix("/")
        }.count
        if customXMLCount > 0 {
            append(
                .documentProperties,
                .exact,
                "The OOXML ZIP directory contains custom XML data parts. Their values are excluded from this report.",
                "OOXML customXml · \(customXMLCount) part(s)"
            )
        }
    }

    private static func inspectODT(
        _ data: Data,
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        guard let archive = try? BoundedZIPReader(data: data) else { return }
        if let mimeEntry = archive.entry(named: "mimetype"),
           let mimeData = try? archive.data(for: mimeEntry),
           String(decoding: mimeData, as: UTF8.self)
            != "application/vnd.oasis.opendocument.text" {
            return
        }
        guard let metadataEntry = archive.entry(named: "meta.xml") else { return }
        guard let metadataData = try? archive.data(for: metadataEntry) else { return }
        let fieldCount = openDocumentMetadataFieldCount(metadataData)
        guard fieldCount > 0 else { return }
        append(
            .openDocumentMetadata,
            .exact,
            "The OpenDocument container includes meta.xml. It was parsed locally without reporting private values.",
            "ODT meta.xml · \(fieldCount) element(s)"
        )
    }

    private static func inspectHTML(
        _ data: Data,
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        let text = decodedText(data)
        if text.range(of: "<meta", options: .caseInsensitive) != nil
            || text.range(of: "application/ld+json", options: .caseInsensitive) != nil {
            append(
                .htmlMetadata,
                .exact,
                "The HTML contains meta elements or structured metadata. Values are not included in this report.",
                "HTML metadata element"
            )
        }
    }

    private static func inspectMarkdown(
        _ data: Data,
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        let text = decodedText(data)
        if text.hasPrefix("---\n") || text.hasPrefix("---\r\n") {
            append(
                .markdownFrontMatter,
                .exact,
                "The Markdown file begins with front matter. Values are not included in this report.",
                "Markdown front matter delimiter"
            )
        }
    }

    private static func inspectGenericMarkers(
        _ data: Data,
        existing: [FileProvenanceFinding],
        append: (FileProvenanceFindingKind, EvidenceConfidence, String, String) -> Void
    ) {
        if !existing.contains(where: { $0.kind == .c2paManifest }),
           data.range(of: c2paManifestUUID) != nil
            || (containsASCII(data, "c2pa") && containsASCII(data, "jumb")) {
            append(
                .c2paManifest,
                .probable,
                "C2PA/JUMBF marker bytes were found outside a fully parsed container. Cryptographic validation is still required.",
                "C2PA/JUMBF byte marker"
            )
        }
        if !existing.contains(where: { $0.kind == .xmpMetadata }),
           containsASCII(data, "<x:xmpmeta") {
            append(
                .xmpMetadata,
                .probable,
                "An XMP marker was found outside a fully parsed metadata container.",
                "XMP byte marker"
            )
        }
    }

    private static func hasStructuredPDFMetadataReference(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        let patterns = [
            #"/Metadata\s+\d+\s+\d+\s+R\b"#,
            #"/Type\s*/Metadata\b"#,
            #"/Info\s+\d+\s+\d+\s+R\b"#
        ]
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            return expression.firstMatch(in: text, range: range) != nil
        }
    }

    private static func pdfHeaderOffset(in data: Data) -> Int? {
        let upperBound = min(data.count, 1_024)
        guard upperBound >= pdfSignature.count,
              let range = data.range(
                of: pdfSignature,
                options: [],
                in: data.startIndex..<upperBound
              ) else {
            return nil
        }
        return data.distance(from: data.startIndex, to: range.lowerBound)
    }

    private static func xmlElementCount(_ data: Data) -> Int {
        let text = String(decoding: data.prefix(8 * 1_024 * 1_024), as: UTF8.self)
        guard let expression = try? NSRegularExpression(
            pattern: #"<[A-Za-z_][A-Za-z0-9_.-]*(?::[A-Za-z_][A-Za-z0-9_.-]*)?(?:\s|>)"#
        ) else { return 0 }
        return expression.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
    }

    private static func openDocumentMetadataFieldCount(_ data: Data) -> Int {
        let text = String(decoding: data.prefix(8 * 1_024 * 1_024), as: UTF8.self)
        guard let container = try? NSRegularExpression(
            pattern: #"<office:meta\b[^>]*>(.*?)</office:meta\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ),
        let match = container.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ),
        match.numberOfRanges > 1,
        let bodyRange = Range(match.range(at: 1), in: text),
        let fields = try? NSRegularExpression(
            pattern: #"<\s*(?!/|\?|!)[A-Za-z_][A-Za-z0-9_.-]*(?::[A-Za-z_][A-Za-z0-9_.-]*)?\b"#
        ) else { return 0 }
        let body = String(text[bodyRange])
        return fields.numberOfMatches(
            in: body,
            range: NSRange(body.startIndex..., in: body)
        )
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

    private static func decodedText(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private static func containsASCII<C: DataProtocol>(_ data: C, _ marker: String) -> Bool {
        let bytes = Array(data)
        let haystack = String(decoding: bytes, as: UTF8.self).lowercased()
        return haystack.contains(marker.lowercased())
    }
}
