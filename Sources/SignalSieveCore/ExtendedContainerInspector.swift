// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Bounded structural inspection for formats whose metadata lives in RIFF,
/// ISO-BMFF, TIFF, GIF, BMP, OOXML, or EPUB containers.
enum ExtendedContainerInspector {
    typealias AppendFinding = (
        FileProvenanceFindingKind,
        EvidenceConfidence,
        String,
        String
    ) -> Void

    private static let c2paBMFFUUID = Data([
        0xD8, 0xFE, 0xC3, 0xD6, 0x1B, 0x0E, 0x48, 0x3C,
        0x92, 0x97, 0x58, 0x28, 0x87, 0x7E, 0xC4, 0x81
    ])
    private static let xmpBMFFUUID = Data([
        0xBE, 0x7A, 0xCF, 0xCB, 0x97, 0xA9, 0x42, 0xE8,
        0x9C, 0x71, 0x99, 0x49, 0x91, 0xE3, 0xAF, 0xAC
    ])

    static func isWebP(_ data: Data) -> Bool {
        data.count >= 12
            && data.prefix(4) == Data("RIFF".utf8)
            && data[8..<12] == Data("WEBP".utf8)
    }

    static func isBMP(_ data: Data) -> Bool {
        data.count >= 14 && data[0] == 0x42 && data[1] == 0x4D
    }

    static func isGIF(_ data: Data) -> Bool {
        data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8))
    }

    static func isTIFF(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        return data.prefix(4) == Data([0x49, 0x49, 0x2A, 0x00])
            || data.prefix(4) == Data([0x4D, 0x4D, 0x00, 0x2A])
            || data.prefix(4) == Data([0x49, 0x49, 0x2B, 0x00])
            || data.prefix(4) == Data([0x4D, 0x4D, 0x00, 0x2B])
    }

    static func isoImageFormat(_ data: Data) -> ProvenanceFileFormat? {
        guard data.count >= 16, String(decoding: data[4..<8], as: UTF8.self) == "ftyp" else {
            return nil
        }
        let boxSize = Int(be32(data, 0) ?? 0)
        guard boxSize >= 16, boxSize <= data.count else { return nil }
        var brands: Set<String> = [String(decoding: data[8..<12], as: UTF8.self)]
        var offset = 16
        while offset + 4 <= boxSize {
            brands.insert(String(decoding: data[offset..<(offset + 4)], as: UTF8.self))
            offset += 4
        }
        if !brands.isDisjoint(with: ["avif", "avis"]) { return .avif }
        if !brands.isDisjoint(with: ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"]) {
            return .heic
        }
        return nil
    }

    static func zipFormat(_ data: Data, extensionValue: String) -> ProvenanceFileFormat? {
        guard let archive = try? BoundedZIPReader(data: data) else { return nil }
        let names = Set(archive.entries.map(\.name))
        if names.contains("word/document.xml") { return .docx }
        if names.contains("xl/workbook.xml") { return .xlsx }
        if names.contains("ppt/presentation.xml") { return .pptx }
        if let mimetype = archive.entry(named: "mimetype"),
           let bytes = try? archive.data(for: mimetype) {
            let value = String(decoding: bytes, as: UTF8.self)
            if value == "application/vnd.oasis.opendocument.text" { return .odt }
            if value == "application/epub+zip" { return .epub }
        }
        if names.contains("META-INF/container.xml") && extensionValue == "epub" { return .epub }
        switch extensionValue {
        case "docx": return .docx
        case "xlsx": return .xlsx
        case "pptx": return .pptx
        case "odt": return .odt
        case "epub": return .epub
        default: return nil
        }
    }

    static func inspect(
        _ data: Data,
        format: ProvenanceFileFormat,
        append: AppendFinding
    ) {
        switch format {
        case .webp: inspectWebP(data, append: append)
        case .avif, .heic: inspectISOBMFF(data, append: append)
        case .bmp: inspectBMP(data, append: append)
        case .gif: inspectGIF(data, append: append)
        case .tiff: inspectTIFF(data, append: append)
        case .xlsx, .pptx: inspectOOXML(data, append: append)
        case .epub: inspectEPUB(data, append: append)
        default: break
        }
    }

    private static func inspectWebP(_ data: Data, append: AppendFinding) {
        guard isWebP(data), Int(le32(data, 4) ?? 0) + 8 <= data.count else { return }
        var offset = 12
        while offset + 8 <= data.count {
            let type = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let length = Int(le32(data, offset + 4) ?? UInt32.max)
            guard length <= data.count - offset - 8 else { return }
            switch type {
            case "C2PA":
                append(.c2paManifest, .exact, "A C2PA RIFF chunk is present; its claim has not been cryptographically validated.", "WebP C2PA chunk")
            case "EXIF":
                append(.exifMetadata, .exact, "The WebP contains EXIF metadata.", "WebP EXIF chunk")
            case "XMP ":
                append(.xmpMetadata, .exact, "The WebP contains XMP metadata.", "WebP XMP chunk")
            default: break
            }
            offset += 8 + length + (length & 1)
        }
    }

    private static func inspectISOBMFF(_ data: Data, append: AppendFinding) {
        var offset = 0
        var boxes = 0
        while offset + 8 <= data.count, boxes < 100_000 {
            guard let box = bmffBox(data, at: offset) else { return }
            let payloadStart = box.headerEnd
            if box.type == "jumb" {
                append(.c2paManifest, .exact, "A top-level JUMBF box is present; its claim has not been cryptographically validated.", "ISO-BMFF jumb box")
            } else if box.type == "uuid", payloadStart + 16 <= box.end {
                let uuid = data[payloadStart..<(payloadStart + 16)]
                if uuid == c2paBMFFUUID {
                    append(.c2paManifest, .exact, "The standardized C2PA UUID box is present; its claim has not been cryptographically validated.", "ISO-BMFF C2PA uuid box")
                } else if uuid == xmpBMFFUUID {
                    append(.xmpMetadata, .exact, "An Adobe XMP UUID box is present.", "ISO-BMFF XMP uuid box")
                } else if asciiContains(data[payloadStart..<box.end], "<x:xmpmeta") {
                    append(.isobmffMetadata, .probable, "A UUID box contains an XMP marker but uses an unrecognized UUID.", "ISO-BMFF unrecognized XMP uuid box")
                }
            }
            offset = box.end
            boxes += 1
        }
    }

    private static func inspectBMP(_ data: Data, append: AppendFinding) {
        guard isBMP(data), let declared = le32(data, 2), declared >= 14 else { return }
        if Int(declared) < data.count {
            append(.trailingContainerData, .exact, "Bytes exist after the BMP file size declared by its header.", "BMP trailing bytes · \(data.count - Int(declared)) byte(s)")
        }
    }

    private static func inspectGIF(_ data: Data, append: AppendFinding) {
        guard let blocks = gifExtensions(data) else { return }
        for block in blocks {
            switch block.kind {
            case .comment:
                append(.gifMetadata, .exact, "The GIF contains a comment extension.", "GIF Comment Extension")
            case .xmp:
                append(.xmpMetadata, .exact, "The GIF contains an XMP application extension.", "GIF XMP DataXMP extension")
            case .c2pa:
                append(.c2paManifest, .exact, "The GIF contains a C2PA application extension; its claim has not been cryptographically validated.", "GIF C2PA_GIF extension")
            }
        }
    }

    private static func inspectTIFF(_ data: Data, append: AppendFinding) {
        guard let entries = tiffMetadataEntries(data) else { return }
        for entry in entries {
            switch entry.tag {
            case 700: append(.xmpMetadata, .exact, "The TIFF IFD contains the XMP tag.", "TIFF tag 700")
            case 34665: append(.exifMetadata, .exact, "The TIFF IFD contains an EXIF sub-IFD pointer.", "TIFF tag 34665")
            case 34853: append(.exifMetadata, .exact, "The TIFF IFD contains a GPS sub-IFD pointer.", "TIFF tag 34853")
            case 33723: append(.tiffMetadata, .exact, "The TIFF IFD contains IPTC metadata.", "TIFF tag 33723")
            case 37500: append(.tiffMetadata, .exact, "The TIFF IFD contains MakerNote metadata.", "TIFF tag 37500")
            case 52545: append(.c2paManifest, .exact, "The TIFF IFD contains the standardized C2PA tag; its claim has not been cryptographically validated.", "TIFF tag 52545 (0xCD41)")
            default: break
            }
        }
    }

    private static func inspectOOXML(_ data: Data, append: AppendFinding) {
        guard let archive = try? BoundedZIPReader(data: data) else { return }
        for name in ["docProps/core.xml", "docProps/custom.xml", "docProps/app.xml"] {
            if archive.entry(named: name) != nil {
                append(.documentProperties, .exact, "The OOXML package contains a document-property part.", "OOXML \(name)")
            }
        }
        let custom = archive.entries.filter { $0.name.hasPrefix("customXml/") && !$0.name.hasSuffix("/") }.count
        if custom > 0 {
            append(.documentProperties, .exact, "The OOXML package contains custom XML data.", "OOXML customXml · \(custom) part(s)")
        }
        if archive.entries.contains(where: { $0.name.lowercased().hasPrefix("_xmlsignatures/") }) {
            append(.protectedContainer, .exact, "The OOXML package is digitally signed. Cleaning must not invalidate it silently.", "OOXML digital signature")
        }
    }

    private static func inspectEPUB(_ data: Data, append: AppendFinding) {
        guard let archive = try? BoundedZIPReader(data: data) else { return }
        if archive.entry(named: "META-INF/signatures.xml") != nil {
            append(.protectedContainer, .exact, "The EPUB contains digital signatures. Cleaning must refuse it.", "EPUB META-INF/signatures.xml")
        }
        if archive.entry(named: "META-INF/encryption.xml") != nil {
            append(.protectedContainer, .exact, "The EPUB declares encrypted or obfuscated resources. Cleaning must refuse it.", "EPUB META-INF/encryption.xml")
        }
        if archive.entry(named: "META-INF/metadata.xml") != nil {
            append(.epubMetadata, .exact, "The EPUB contains optional container-level metadata.", "EPUB META-INF/metadata.xml")
        }
        for entry in archive.entries where entry.name.lowercased().hasSuffix(".opf") {
            guard let bytes = try? archive.data(for: entry) else { continue }
            let text = String(decoding: bytes.prefix(8 * 1_024 * 1_024), as: UTF8.self)
            let metaCount = (try? NSRegularExpression(
                pattern: #"<(?:[A-Za-z_][A-Za-z0-9_.-]*:)?meta\b"#,
                options: .caseInsensitive
            ))?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
            if metaCount > 0 {
                append(.epubMetadata, .exact, "The EPUB package document contains optional meta elements; required title, identifier, and language are not treated as removable tracking.", "EPUB \(entry.name) · \(metaCount) meta element(s)")
            }
        }
        let mediaEntries = archive.entries.filter {
            let lower = $0.name.lowercased()
            return [".png", ".jpg", ".jpeg", ".webp", ".gif", ".tif", ".tiff", ".avif", ".heic"].contains { lower.hasSuffix($0) }
        }.prefix(2_000)
        var count = 0
        for entry in mediaEntries {
            guard let bytes = try? archive.data(for: entry) else { continue }
            if asciiContains(bytes, "<x:xmpmeta") || asciiContains(bytes, "Exif") || asciiContains(bytes, "c2pa") {
                count += 1
            }
        }
        if count > 0 {
            append(.embeddedResourceMetadata, .probable, "Embedded image resources contain provenance or metadata markers and require individual structural inspection.", "EPUB embedded media · \(count) resource(s)")
        }
    }

    struct TIFFEntry {
        let tag: UInt16
        let entryOffset: Int
        let valueOffset: Int?
        let valueByteCount: Int
        let entrySize: Int
    }

    static func tiffMetadataEntries(_ data: Data) -> [TIFFEntry]? {
        guard isTIFF(data) else { return nil }
        let little = data[0] == 0x49
        let bigTIFF = read16(data, 2, little) == 43
        let firstOffset: UInt64
        if bigTIFF {
            guard read16(data, 4, little) == 8 else { return nil }
            firstOffset = read64(data, 8, little) ?? UInt64.max
        } else {
            firstOffset = UInt64(read32(data, 4, little) ?? UInt32.max)
        }
        var pending = [firstOffset]
        var visited = Set<UInt64>()
        var output: [TIFFEntry] = []
        while let ifd = pending.popLast(), visited.count < 256 {
            guard visited.insert(ifd).inserted, ifd <= UInt64(data.count) else { continue }
            let base = Int(ifd)
            let countSize = bigTIFF ? 8 : 2
            let entrySize = bigTIFF ? 20 : 12
            let rawCount = bigTIFF ? read64(data, base, little) : read16(data, base, little).map(UInt64.init)
            guard let rawCount, rawCount <= 65_535 else { return nil }
            let count = Int(rawCount)
            guard base <= data.count - countSize,
                  count <= (data.count - base - countSize) / entrySize else { return nil }
            for index in 0..<count {
                let entryOffset = base + countSize + index * entrySize
                guard let tag = read16(data, entryOffset, little),
                      let type = read16(data, entryOffset + 2, little) else { return nil }
                let componentCount = bigTIFF
                    ? read64(data, entryOffset + 4, little)
                    : read32(data, entryOffset + 4, little).map(UInt64.init)
                guard let componentCount,
                      let typeSize = tiffTypeSize(type),
                      componentCount <= UInt64(Int.max) / UInt64(typeSize) else { continue }
                let byteCount = Int(componentCount) * typeSize
                let inlineSize = bigTIFF ? 8 : 4
                let rawOffset = bigTIFF
                    ? read64(data, entryOffset + 12, little)
                    : read32(data, entryOffset + 8, little).map(UInt64.init)
                let valueOffset = byteCount > inlineSize ? rawOffset.flatMap { $0 <= UInt64(data.count) ? Int($0) : nil } : nil
                output.append(TIFFEntry(tag: tag, entryOffset: entryOffset, valueOffset: valueOffset, valueByteCount: byteCount, entrySize: entrySize))
                if [330, 34665, 34853, 40965].contains(tag), let rawOffset { pending.append(rawOffset) }
            }
            let nextLocation = base + countSize + count * entrySize
            let next = bigTIFF ? read64(data, nextLocation, little) : read32(data, nextLocation, little).map(UInt64.init)
            if let next, next != 0 { pending.append(next) }
        }
        return output.filter { [700, 33723, 34665, 34853, 37500, 52545].contains($0.tag) }
    }

    enum GIFExtensionKind { case comment, xmp, c2pa }
    struct GIFExtension { let start: Int; let end: Int; let kind: GIFExtensionKind }

    static func gifExtensions(_ data: Data) -> [GIFExtension]? {
        guard isGIF(data), data.count >= 13 else { return nil }
        var offset = 13
        if data[10] & 0x80 != 0 { offset += 3 * (1 << (Int(data[10] & 0x07) + 1)) }
        guard offset <= data.count else { return nil }
        var output: [GIFExtension] = []
        while offset < data.count {
            let start = offset
            switch data[offset] {
            case 0x3B:
                return offset + 1 == data.count ? output : nil
            case 0x21:
                guard offset + 2 < data.count else { return nil }
                let label = data[offset + 1]
                offset += 2
                guard offset < data.count else { return nil }
                let headerLength = Int(data[offset])
                guard headerLength <= data.count - offset - 1 else { return nil }
                let header = data[(offset + 1)..<(offset + 1 + headerLength)]
                offset += 1 + headerLength
                while true {
                    guard offset < data.count else { return nil }
                    let length = Int(data[offset]); offset += 1
                    if length == 0 { break }
                    guard length <= data.count - offset else { return nil }
                    offset += length
                }
                let kind: GIFExtensionKind?
                if label == 0xFE { kind = .comment }
                else if label == 0xFF && String(decoding: header, as: UTF8.self).hasPrefix("XMP DataXMP") { kind = .xmp }
                else if label == 0xFF && String(decoding: header, as: UTF8.self).hasPrefix("C2PA_GIF") { kind = .c2pa }
                else { kind = nil }
                if let kind { output.append(GIFExtension(start: start, end: offset, kind: kind)) }
            case 0x2C:
                guard offset + 10 <= data.count else { return nil }
                let packed = data[offset + 9]
                offset += 10
                if packed & 0x80 != 0 { offset += 3 * (1 << (Int(packed & 0x07) + 1)) }
                guard offset < data.count else { return nil }
                offset += 1
                while true {
                    guard offset < data.count else { return nil }
                    let length = Int(data[offset]); offset += 1
                    if length == 0 { break }
                    guard length <= data.count - offset else { return nil }
                    offset += length
                }
            default: return nil
            }
        }
        return nil
    }

    struct BMFFBox { let type: String; let headerEnd: Int; let end: Int }
    static func bmffBox(_ data: Data, at offset: Int) -> BMFFBox? {
        guard offset >= 0, offset <= data.count - 8, let size32 = be32(data, offset) else { return nil }
        let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
        var header = offset + 8
        let size: UInt64
        if size32 == 1 {
            guard let size64 = read64(data, offset + 8, false) else { return nil }
            size = size64; header += 8
        } else if size32 == 0 {
            size = UInt64(data.count - offset)
        } else { size = UInt64(size32) }
        guard size >= UInt64(header - offset), size <= UInt64(data.count - offset) else { return nil }
        return BMFFBox(type: type, headerEnd: header, end: offset + Int(size))
    }

    private static func tiffTypeSize(_ type: UInt16) -> Int? {
        switch type {
        case 1, 2, 6, 7: 1
        case 3, 8: 2
        case 4, 9, 11, 13: 4
        case 5, 10, 12, 16, 17, 18: 8
        default: nil
        }
    }

    private static func asciiContains<C: DataProtocol>(_ data: C, _ text: String) -> Bool {
        String(decoding: Array(data), as: UTF8.self).lowercased().contains(text.lowercased())
    }
    private static func le32(_ data: Data, _ offset: Int) -> UInt32? { read32(data, offset, true) }
    private static func be32(_ data: Data, _ offset: Int) -> UInt32? { read32(data, offset, false) }
    private static func read16(_ data: Data, _ offset: Int, _ little: Bool) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return little ? UInt16(data[offset]) | UInt16(data[offset + 1]) << 8 : UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
    private static func read32(_ data: Data, _ offset: Int, _ little: Bool) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        let bytes = (0..<4).map { UInt32(data[offset + $0]) }
        return little ? bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24 : bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
    }
    private static func read64(_ data: Data, _ offset: Int, _ little: Bool) -> UInt64? {
        guard offset >= 0, offset <= data.count - 8 else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            let source = little ? offset + 7 - index : offset + index
            value = (value << 8) | UInt64(data[source])
        }
        return value
    }
}
