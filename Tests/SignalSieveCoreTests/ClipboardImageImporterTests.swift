// SPDX-License-Identifier: MPL-2.0
import CoreGraphics
import Foundation
import ImageIO
import SignalSieveCore
import Testing

@Test("Preserves PNG clipboard bytes for metadata inspection")
func preservesClipboardPNGBytes() throws {
    let png = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+Avz6WQAAAABJRU5ErkJggg=="
    ))
    let payload = try ClipboardImageImporter.importImage(from: [
        ClipboardImageRepresentation(typeIdentifier: "public.png", data: png)
    ])

    #expect(payload.data == png)
    #expect(payload.fileName == "clipboard-image.png")
    #expect(!payload.wasTranscodedToPNG)
    #expect(FileProvenanceAnalyzer.analyze(payload.data, fileName: payload.fileName).format == .png)
}

@Test("Normalizes TIFF clipboard representations to metadata-free PNG")
func normalizesClipboardTIFF() throws {
    let tiff = try makeClipboardTIFF()
    let payload = try ClipboardImageImporter.importImage(from: [
        ClipboardImageRepresentation(typeIdentifier: "public.tiff", data: tiff)
    ])
    let report = FileProvenanceAnalyzer.analyze(payload.data, fileName: payload.fileName)

    #expect(payload.wasTranscodedToPNG)
    #expect(payload.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
    #expect(report.format == .png)
    #expect(report.findings.isEmpty)
}

@Test("Rejects clipboard values without a supported image representation")
func rejectsUnsupportedClipboardValue() {
    #expect(throws: ClipboardImageImportError.noSupportedImage) {
        try ClipboardImageImporter.importImage(from: [
            ClipboardImageRepresentation(
                typeIdentifier: "public.utf8-plain-text",
                data: Data("not an image".utf8)
            )
        ])
    }
}

@Test("Rebuilds clipboard pixels into a verified metadata-free PNG")
func rebuildsClipboardImageWithoutMetadata() throws {
    let base = try #require(Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+Avz6WQAAAABJRU5ErkJggg=="
    ))
    let sourceData = try insertingPNGChunk(
        pngChunk("tEXt", payload: Data("Author\0Private".utf8)),
        beforeIENDIn: base
    )
    let sourcePayload = ClipboardImagePayload(
        data: sourceData,
        fileName: "clipboard-image.png",
        sourceTypeIdentifier: "public.png",
        wasTranscodedToPNG: false
    )
    let originalSnapshot = sourcePayload.data
    let result = try ClipboardImageCleaner.makeFreshCopy(from: sourcePayload)

    #expect(sourcePayload.data == originalSnapshot)
    #expect(result.originalReport.findings.contains { $0.kind == .pngTextMetadata })
    #expect(result.removedFindingCount == 1)
    #expect(result.cleanedReport.findings.isEmpty)
    #expect(!result.cleanedReport.containsC2PAContainer)
    #expect(result.cleanedPayload.fileName == "clipboard-image-signalsieve-clean.png")
    #expect(result.cleanedPayload.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
    let cleanedSource = try #require(CGImageSourceCreateWithData(
        result.cleanedPayload.data as CFData,
        nil
    ))
    let cleanedImage = try #require(CGImageSourceCreateImageAtIndex(cleanedSource, 0, nil))
    #expect(cleanedImage.bitsPerComponent == 8)
    #expect(cleanedImage.colorSpace?.model == .rgb)
}

private func makeClipboardTIFF() throws -> Data {
    var pixels: [UInt8] = [20, 40, 80, 255, 200, 180, 120, 255]
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: &pixels,
        width: 2,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 8,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        output,
        "public.tiff" as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

private func insertingPNGChunk(_ chunk: Data, beforeIENDIn png: Data) throws -> Data {
    let marker = Data([0x49, 0x45, 0x4E, 0x44])
    let typeRange = try #require(png.range(of: marker))
    let chunkStart = try #require(png.index(typeRange.lowerBound, offsetBy: -4, limitedBy: png.startIndex))
    var result = png
    result.insert(contentsOf: chunk, at: chunkStart)
    return result
}

private func pngChunk(_ type: String, payload: Data) -> Data {
    var chunk = Data()
    var length = UInt32(payload.count).bigEndian
    withUnsafeBytes(of: &length) { chunk.append(contentsOf: $0) }
    let typeData = Data(type.utf8)
    chunk.append(typeData)
    chunk.append(payload)
    var checksumInput = typeData
    checksumInput.append(payload)
    var checksum = pngCRC32(checksumInput).bigEndian
    withUnsafeBytes(of: &checksum) { chunk.append(contentsOf: $0) }
    return chunk
}

private func pngCRC32(_ data: Data) -> UInt32 {
    var crc = UInt32.max
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = (crc & 1) == 1
                ? (crc >> 1) ^ 0xEDB8_8320
                : crc >> 1
        }
    }
    return crc ^ UInt32.max
}
