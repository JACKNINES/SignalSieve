// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Inspects and removes structured WebP metadata without touching image chunks")
func cleansStructuredWebPMetadata() throws {
    let image = riffChunk("VP8 ", Data([1, 2, 3, 4]))
    let metadata = riffChunk("XMP ", Data("<x:xmpmeta>private</x:xmpmeta>".utf8))
    var body = Data("WEBP".utf8); body.append(image); body.append(metadata)
    var webp = Data("RIFF".utf8); appendLE32(UInt32(body.count), to: &webp); webp.append(body)
    let report = FileProvenanceAnalyzer.analyze(webp, fileName: "sample.webp")
    let cleaned = try FileMetadataCleaner.cleanedData(webp, format: .webp)
    #expect(report.format == .webp)
    #expect(report.findings.contains { $0.kind == .xmpMetadata })
    #expect(cleaned.range(of: image) != nil)
    #expect(FileProvenanceAnalyzer.analyze(cleaned, fileName: "clean.webp").findings.isEmpty)
}

@Test("Recognizes exact C2PA carriers in AVIF, GIF, and TIFF")
func recognizesExtendedC2PACarriers() throws {
    var avif = bmffBox("ftyp", Data("avif\0\0\0\0avif".utf8))
    let uuid = Data([0xD8, 0xFE, 0xC3, 0xD6, 0x1B, 0x0E, 0x48, 0x3C, 0x92, 0x97, 0x58, 0x28, 0x87, 0x7E, 0xC4, 0x81])
    avif.append(bmffBox("uuid", uuid))
    var gif = Data("GIF89a".utf8); gif.append(Data([1, 0, 1, 0, 0, 0, 0]))
    gif.append(Data([0x21, 0xFF, 0x0B])); gif.append(Data("C2PA_GIF001".utf8)); gif.append(Data([1, 0x01, 0, 0x3B]))
    var tiff = Data([0x49, 0x49, 0x2A, 0, 8, 0, 0, 0, 1, 0])
    tiff.append(Data([0x41, 0xCD, 7, 0, 1, 0, 0, 0, 0xAA, 0, 0, 0, 0, 0, 0, 0]))
    for (bytes, name, format) in [(avif, "a.avif", ProvenanceFileFormat.avif), (gif, "a.gif", .gif), (tiff, "a.tiff", .tiff)] {
        let report = FileProvenanceAnalyzer.analyze(bytes, fileName: name)
        #expect(report.format == format)
        #expect(report.containsC2PAContainer)
        #expect(report.findings.contains { $0.kind == .c2paManifest && $0.evidenceConfidence == .exact })
    }
}

@Test("Cleans GIF comments and BMP trailing data with bounded reconstruction")
func cleansGIFAndBMPTrailingMetadata() throws {
    var gif = Data("GIF89a".utf8); gif.append(Data([1, 0, 1, 0, 0, 0, 0]))
    gif.append(Data([0x21, 0xFE, 3])); gif.append(Data("tag".utf8)); gif.append(Data([0, 0x3B]))
    let cleanGIF = try FileMetadataCleaner.cleanedData(gif, format: .gif)
    #expect(cleanGIF.last == 0x3B)
    #expect(FileProvenanceAnalyzer.analyze(cleanGIF, fileName: "clean.gif").findings.isEmpty)
    var bmp = Data([0x42, 0x4D, 26, 0, 0, 0, 0, 0, 0, 0, 26, 0, 0, 0, 12, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0]); bmp.append(Data("private trailer".utf8))
    let cleanBMP = try FileMetadataCleaner.cleanedData(bmp, format: .bmp)
    #expect(cleanBMP.count == 26)
}

@Test("Recognizes and cleans XLSX, PPTX, and unprotected EPUB metadata")
func cleansExtendedZIPMetadata() throws {
    for (name, body) in [("book.xlsx", "xl/workbook.xml"), ("slides.pptx", "ppt/presentation.xml")] {
        let archive = storedZIP([
            ("[Content_Types].xml", "<Types><Override PartName=\"/docProps/core.xml\"/></Types>"),
            ("_rels/.rels", "<Relationships><Relationship Target=\"docProps/core.xml\"/></Relationships>"),
            (body, "<root/>"), ("docProps/core.xml", "<cp:coreProperties><dc:creator>Private</dc:creator></cp:coreProperties>")
        ])
        let before = FileProvenanceAnalyzer.analyze(archive, fileName: name)
        let cleaned = try FileMetadataCleaner.cleanedData(archive, format: before.format)
        #expect(before.findings.contains { $0.kind == .documentProperties })
        #expect(FileProvenanceAnalyzer.analyze(cleaned, fileName: name).findings.isEmpty)
    }
    let epub = storedZIP([
        ("mimetype", "application/epub+zip"),
        ("META-INF/container.xml", "<container><rootfile full-path=\"book.opf\"/></container>"),
        ("book.opf", "<package><metadata><dc:title>Keep</dc:title><meta name=\"generator\">Private Tool</meta></metadata></package>")
    ])
    let cleanedEPUB = try FileMetadataCleaner.cleanedData(epub, format: .epub)
    let reader = try BoundedZIPReader(data: cleanedEPUB)
    let opf = try #require(reader.entry(named: "book.opf"))
    let text = String(decoding: try reader.data(for: opf), as: UTF8.self)
    #expect(text.contains("<dc:title>Keep</dc:title>"))
    #expect(!text.contains("generator"))
}

@Test("EPUB cleaning refuses signatures and encryption")
func refusesProtectedEPUB() {
    for protectedPart in ["META-INF/signatures.xml", "META-INF/encryption.xml"] {
        let epub = storedZIP([("mimetype", "application/epub+zip"), ("META-INF/container.xml", "<container/>"), (protectedPart, "<protected/>")])
        #expect(throws: (any Error).self) { try FileMetadataCleaner.cleanedData(epub, format: .epub) }
    }
}

private func riffChunk(_ type: String, _ payload: Data) -> Data { var r = Data(type.utf8); appendLE32(UInt32(payload.count), to: &r); r.append(payload); if payload.count & 1 == 1 { r.append(0) }; return r }
private func bmffBox(_ type: String, _ payload: Data) -> Data { var r = Data(); appendBE32(UInt32(payload.count + 8), to: &r); r.append(Data(type.utf8)); r.append(payload); return r }
private func storedZIP(_ entries: [(String, String)]) -> Data {
    var output = Data(); var central = Data(); var records: [(String, UInt32, UInt32, UInt32)] = []
    for (name, value) in entries {
        let n = Data(name.utf8), p = Data(value.utf8), crc = crc32(p), offset = UInt32(output.count)
        appendLE32(0x04034B50, to: &output); appendLE16(20, to: &output); appendLE16(0, to: &output); appendLE16(0, to: &output); appendLE16(0, to: &output); appendLE16(0, to: &output); appendLE32(crc, to: &output); appendLE32(UInt32(p.count), to: &output); appendLE32(UInt32(p.count), to: &output); appendLE16(UInt16(n.count), to: &output); appendLE16(0, to: &output); output.append(n); output.append(p); records.append((name, crc, UInt32(p.count), offset))
    }
    for record in records {
        let n = Data(record.0.utf8); appendLE32(0x02014B50, to: &central); appendLE16(20, to: &central); appendLE16(20, to: &central); appendLE16(0, to: &central); appendLE16(0, to: &central); appendLE16(0, to: &central); appendLE16(0, to: &central); appendLE32(record.1, to: &central); appendLE32(record.2, to: &central); appendLE32(record.2, to: &central); appendLE16(UInt16(n.count), to: &central); appendLE16(0, to: &central); appendLE16(0, to: &central); appendLE16(0, to: &central); appendLE16(0, to: &central); appendLE32(0, to: &central); appendLE32(record.3, to: &central); central.append(n)
    }
    let offset = UInt32(output.count); output.append(central); appendLE32(0x06054B50, to: &output); appendLE16(0, to: &output); appendLE16(0, to: &output); appendLE16(UInt16(records.count), to: &output); appendLE16(UInt16(records.count), to: &output); appendLE32(UInt32(central.count), to: &output); appendLE32(offset, to: &output); appendLE16(0, to: &output); return output
}
private func crc32(_ data: Data) -> UInt32 { var crc: UInt32 = 0xFFFF_FFFF; for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB8_8320 : 0) } }; return crc ^ 0xFFFF_FFFF }
private func appendLE16(_ v: UInt16, to d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8)) }
private func appendLE32(_ v: UInt32, to d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)); d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF)) }
private func appendBE32(_ v: UInt32, to d: inout Data) { d.append(UInt8((v >> 24) & 0xFF)); d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)); d.append(UInt8(v & 0xFF)) }
