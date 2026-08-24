// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Conservative metadata removal for extended image and ZIP formats. Every
/// caller writes a new copy and re-runs FileProvenanceAnalyzer before success.
enum ExtendedMetadataCleaner {
    private static let c2paBMFFUUID = Data([
        0xD8, 0xFE, 0xC3, 0xD6, 0x1B, 0x0E, 0x48, 0x3C,
        0x92, 0x97, 0x58, 0x28, 0x87, 0x7E, 0xC4, 0x81
    ])
    private static let xmpBMFFUUID = Data([
        0xBE, 0x7A, 0xCF, 0xCB, 0x97, 0xA9, 0x42, 0xE8,
        0x9C, 0x71, 0x99, 0x49, 0x91, 0xE3, 0xAF, 0xAC
    ])

    static func clean(_ data: Data, format: ProvenanceFileFormat) throws -> Data {
        switch format {
        case .webp: try cleanWebP(data)
        case .avif, .heic: try cleanISOBMFF(data)
        case .bmp: try cleanBMP(data)
        case .gif: try cleanGIF(data)
        case .tiff: try cleanTIFF(data)
        case .xlsx, .pptx: try cleanOOXML(data, format: format)
        case .epub: try cleanEPUB(data)
        default: throw FileMetadataCleaningError.unsupportedFormat
        }
    }

    private static func cleanWebP(_ data: Data) throws -> Data {
        guard ExtendedContainerInspector.isWebP(data),
              let declared = le32(data, 4), Int(declared) + 8 == data.count else {
            throw FileMetadataCleaningError.invalidContainer
        }
        var chunks: [(String, Data)] = []
        var offset = 12
        var removed = false
        while offset + 8 <= data.count {
            let type = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            guard let lengthValue = le32(data, offset + 4) else { throw FileMetadataCleaningError.invalidContainer }
            let length = Int(lengthValue)
            guard length <= data.count - offset - 8 else { throw FileMetadataCleaningError.invalidContainer }
            let end = offset + 8 + length + (length & 1)
            guard end <= data.count else { throw FileMetadataCleaningError.invalidContainer }
            if ["C2PA", "EXIF", "XMP "].contains(type) { removed = true }
            else { chunks.append((type, Data(data[(offset + 8)..<(offset + 8 + length)]))) }
            offset = end
        }
        guard offset == data.count else { throw FileMetadataCleaningError.invalidContainer }
        guard removed else { throw FileMetadataCleaningError.noSupportedMetadata }
        if let index = chunks.firstIndex(where: { $0.0 == "VP8X" }), chunks[index].1.count == 10 {
            var payload = chunks[index].1
            payload[0] &= ~UInt8(0x0C) // EXIF and XMP feature bits.
            chunks[index].1 = payload
        }
        var body = Data("WEBP".utf8)
        for (type, payload) in chunks {
            body.append(Data(type.utf8)); appendLE32(UInt32(payload.count), to: &body); body.append(payload)
            if payload.count & 1 == 1 { body.append(0) }
        }
        var output = Data("RIFF".utf8); appendLE32(UInt32(body.count), to: &output); output.append(body)
        return output
    }

    private static func cleanISOBMFF(_ data: Data) throws -> Data {
        guard ExtendedContainerInspector.isoImageFormat(data) != nil else {
            throw FileMetadataCleaningError.invalidContainer
        }
        var output = data; var offset = 0; var removed = false
        while offset < data.count {
            guard let box = ExtendedContainerInspector.bmffBox(data, at: offset) else {
                throw FileMetadataCleaningError.invalidContainer
            }
            var drop = box.type == "jumb"
            if box.type == "uuid", box.headerEnd + 16 <= box.end {
                let uuid = data[box.headerEnd..<(box.headerEnd + 16)]
                drop = uuid == c2paBMFFUUID || uuid == xmpBMFFUUID
            }
            if drop {
                // Preserve every box boundary and absolute media offset. Turning
                // the carrier into an equally sized free-space box is safer
                // than shifting a following mdat/iloc relationship.
                output.replaceSubrange((offset + 4)..<(offset + 8), with: Data("free".utf8))
                if box.headerEnd < box.end {
                    output.replaceSubrange(box.headerEnd..<box.end, with: repeatElement(UInt8(0), count: box.end - box.headerEnd))
                }
                removed = true
            }
            offset = box.end
        }
        guard removed else { throw FileMetadataCleaningError.noSupportedMetadata }
        return output
    }

    private static func cleanBMP(_ data: Data) throws -> Data {
        guard ExtendedContainerInspector.isBMP(data), let declared = le32(data, 2),
              let pixelOffset = le32(data, 10), let dibSize = le32(data, 14),
              dibSize >= 12,
              pixelOffset >= 14 + dibSize,
              declared >= pixelOffset,
              declared >= 14 + dibSize,
              Int(declared) <= data.count else {
            throw FileMetadataCleaningError.invalidContainer
        }
        guard Int(declared) < data.count else { throw FileMetadataCleaningError.noSupportedMetadata }
        return Data(data.prefix(Int(declared)))
    }

    private static func cleanGIF(_ data: Data) throws -> Data {
        guard let extensions = ExtendedContainerInspector.gifExtensions(data) else {
            throw FileMetadataCleaningError.invalidContainer
        }
        guard !extensions.isEmpty else { throw FileMetadataCleaningError.noSupportedMetadata }
        var output = data
        for item in extensions.sorted(by: { $0.start > $1.start }) {
            output.removeSubrange(item.start..<item.end)
        }
        guard ExtendedContainerInspector.gifExtensions(output) != nil else {
            throw FileMetadataCleaningError.verificationFailed
        }
        return output
    }

    private static func cleanTIFF(_ data: Data) throws -> Data {
        guard let entries = ExtendedContainerInspector.tiffMetadataEntries(data) else {
            throw FileMetadataCleaningError.invalidContainer
        }
        guard !entries.isEmpty else { throw FileMetadataCleaningError.noSupportedMetadata }
        // EXIF/GPS pointers lead to arbitrary IFD graphs. Neutralizing only the
        // pointer would leave recoverable metadata, so this path deliberately
        // refuses until every referenced range can be proven disjoint from pixels.
        guard !entries.contains(where: { $0.tag == 34665 || $0.tag == 34853 }) else {
            throw FileMetadataCleaningError.unsupportedFormat
        }
        var output = data
        for entry in entries {
            if let valueOffset = entry.valueOffset, entry.valueByteCount > 0,
               valueOffset <= output.count - entry.valueByteCount {
                output.replaceSubrange(valueOffset..<(valueOffset + entry.valueByteCount), with: repeatElement(UInt8(0), count: entry.valueByteCount))
            }
            output.replaceSubrange(entry.entryOffset..<(entry.entryOffset + entry.entrySize), with: repeatElement(UInt8(0), count: entry.entrySize))
        }
        return output
    }

    private static func cleanOOXML(_ data: Data, format: ProvenanceFileFormat) throws -> Data {
        let archive = try archiveReader(data)
        let required = format == .xlsx ? "xl/workbook.xml" : "ppt/presentation.xml"
        guard archive.entry(named: "[Content_Types].xml") != nil,
              archive.entry(named: "_rels/.rels") != nil,
              archive.entry(named: required) != nil else {
            throw FileMetadataCleaningError.invalidContainer
        }
        if archive.entries.contains(where: {
            let value = $0.name.lowercased()
            return value.hasPrefix("_xmlsignatures/") || value.contains("origin.sigs")
        }) { throw FileMetadataCleaningError.signedContainer }

        let directParts: Set<String> = ["docProps/core.xml", "docProps/custom.xml", "docProps/app.xml"]
        let customParts = Set(archive.entries.map(\.name).filter { $0.hasPrefix("customXml/") && !$0.hasSuffix("/") })
        let removing = directParts.union(customParts).intersection(Set(archive.entries.map(\.name)))
        guard !removing.isEmpty else { throw FileMetadataCleaningError.noSupportedMetadata }

        var replacements: [String: Data] = [:]
        for entry in archive.entries where entry.name.hasSuffix(".rels") || entry.name == "[Content_Types].xml" {
            guard let bytes = try? archive.data(for: entry), var text = String(data: bytes, encoding: .utf8) else { continue }
            for part in removing {
                let escaped = NSRegularExpression.escapedPattern(for: part)
                text = text.replacingOccurrences(
                    of: #"<[^>]+(?:PartName|Target)=[\"'][^\"']*"# + escaped + #"[\"'][^>]*/\s*>"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
            if text != String(data: bytes, encoding: .utf8)! { replacements[entry.name] = Data(text.utf8) }
        }
        do {
            return try BoundedZIPRewriter.rewrite(data, removing: removing, replacing: replacements)
        } catch { throw FileMetadataCleaningError.invalidContainer }
    }

    private static func cleanEPUB(_ data: Data) throws -> Data {
        let archive = try archiveReader(data)
        let ordered = archive.entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
        guard let mimetype = archive.entry(named: "mimetype"), ordered.first?.name == "mimetype",
              mimetype.compressionMethod == 0, let mime = try? archive.data(for: mimetype),
              String(decoding: mime, as: UTF8.self) == "application/epub+zip",
              archive.entry(named: "META-INF/container.xml") != nil else {
            throw FileMetadataCleaningError.invalidContainer
        }
        if archive.entry(named: "META-INF/signatures.xml") != nil { throw FileMetadataCleaningError.signedContainer }
        if archive.entry(named: "META-INF/encryption.xml") != nil { throw FileMetadataCleaningError.encryptedContainer }

        var removing: Set<String> = []
        var replacements: [String: Data] = [:]
        if archive.entry(named: "META-INF/metadata.xml") != nil { removing.insert("META-INF/metadata.xml") }
        for entry in archive.entries where entry.name.lowercased().hasSuffix(".opf") || entry.name.lowercased().hasSuffix(".xhtml") || entry.name.lowercased().hasSuffix(".html") {
            guard let bytes = try? archive.data(for: entry), let source = String(data: bytes, encoding: .utf8) else { continue }
            let cleaned = removingOptionalTrackingMetadata(from: source)
            if cleaned != source { replacements[entry.name] = Data(cleaned.utf8) }
        }
        for entry in archive.entries.prefix(10_000) {
            let lower = entry.name.lowercased()
            guard [".png", ".jpg", ".jpeg", ".webp", ".gif", ".tif", ".tiff", ".avif", ".heic"].contains(where: lower.hasSuffix),
                  let bytes = try? archive.data(for: entry) else { continue }
            let report = FileProvenanceAnalyzer.analyze(bytes, fileName: entry.name)
            guard FileMetadataCleaner.supports(report.format), !report.findings.isEmpty,
                  let cleaned = try? FileMetadataCleaner.cleanedData(bytes, format: report.format), cleaned != bytes else { continue }
            replacements[entry.name] = cleaned
        }
        guard !removing.isEmpty || !replacements.isEmpty else { throw FileMetadataCleaningError.noSupportedMetadata }
        do {
            return try BoundedZIPRewriter.rewrite(data, removing: removing, replacing: replacements, requiredFirstStoredEntry: "mimetype")
        } catch { throw FileMetadataCleaningError.invalidContainer }
    }

    private static func removingOptionalTrackingMetadata(from text: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?meta\b[^>]*(?:generator|watermark|c2pa|provenance|ai[-_ ]?(?:system|generator|model))[^>]*(?:/>|>.*?</(?:[A-Za-z_][A-Za-z0-9_.-]*:)?meta\s*>)"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    private static func archiveReader(_ data: Data) throws -> BoundedZIPReader {
        do { return try BoundedZIPReader(data: data) }
        catch { throw FileMetadataCleaningError.invalidContainer }
    }
    private static func le32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
    private static func appendLE32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF)); data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8((value >> 16) & 0xFF)); data.append(UInt8((value >> 24) & 0xFF))
    }
}
