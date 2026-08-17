// SPDX-License-Identifier: MPL-2.0
import Foundation
import PDFKit
import Testing
@testable import SignalSieveCore

@Test("Creates a verified PNG copy and leaves the source byte-for-byte intact")
func cleansPNGIntoVerifiedCopy() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveMetadata-\(UUID().uuidString)", isDirectory: true)
    let source = directory.appendingPathComponent("source.png")
    let destination = directory.appendingPathComponent("clean.png")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var original = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    original.append(metadataPNGChunk("eXIf", payload: Data("private-exif".utf8)))
    original.append(metadataPNGChunk("tEXt", payload: Data("author\0private".utf8)))
    original.append(metadataPNGChunk("IDAT", payload: Data([1, 2, 3, 4])))
    original.append(metadataPNGChunk("IEND", payload: Data()))
    try original.write(to: source)

    let result = try FileMetadataCleaner.cleanCopy(of: source, to: destination)
    let cleaned = try Data(contentsOf: destination)

    #expect(try Data(contentsOf: source) == original)
    #expect(result.originalWasUnchanged)
    #expect(result.cleanedCopyURL == destination.standardizedFileURL)
    #expect(result.originalReport.findings.count == 2)
    #expect(result.cleanedReport.findings.isEmpty)
    #expect(result.removedFindingCount == 2)
    #expect(cleaned.range(of: Data([1, 2, 3, 4])) != nil)
    #expect(cleaned.range(of: Data("private".utf8)) == nil)
}

@Test("Removes JPEG metadata segments while retaining color-profile data")
func cleansJPEGMetadataSegments() throws {
    let exif = Data("Exif\0\0private".utf8)
    let icc = Data("ICC_PROFILE\0color".utf8)
    let app11 = Data("unrelated APP11 payload".utf8)
    let comment = Data("private comment".utf8)
    let source = metadataJPEG(segments: [
        (0xE1, exif),
        (0xE2, icc),
        (0xEB, app11),
        (0xFE, comment)
    ])

    let cleaned = try FileMetadataCleaner.cleanedData(source, format: .jpeg)
    let report = FileProvenanceAnalyzer.analyze(cleaned, fileName: "clean.jpg")

    #expect(report.findings.isEmpty)
    #expect(cleaned.range(of: icc) != nil)
    #expect(cleaned.range(of: Data("private".utf8)) == nil)
}

@Test("Removes DOCX property parts while preserving the document body")
func cleansDOCXPropertyParts() throws {
    let original = try #require(Data(base64Encoded: metadataDOCXBase64))
    let cleaned = try FileMetadataCleaner.cleanedData(original, format: .docx)
    let report = FileProvenanceAnalyzer.analyze(cleaned, fileName: "clean.docx")
    let archive = try BoundedZIPReader(data: cleaned)

    #expect(report.format == .docx)
    #expect(report.findings.isEmpty)
    #expect(archive.entry(named: "docProps/core.xml") == nil)
    #expect(archive.entry(named: "docProps/custom.xml") == nil)
    let body = try #require(archive.entry(named: "word/document.xml"))
    #expect(String(decoding: try archive.data(for: body), as: UTF8.self).contains("<w:p/>"))
}

@Test("Replaces ODT metadata with an empty valid metadata document")
func cleansODTMetadata() throws {
    let original = try #require(Data(base64Encoded: metadataODTBase64))
    let cleaned = try FileMetadataCleaner.cleanedData(original, format: .odt)
    let report = FileProvenanceAnalyzer.analyze(cleaned, fileName: "clean.odt")
    let archive = try BoundedZIPReader(data: cleaned)
    let ordered = archive.entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }

    #expect(report.format == .odt)
    #expect(report.findings.isEmpty)
    #expect(ordered.first?.name == "mimetype")
    #expect(ordered.first?.compressionMethod == 0)
    let metadataEntry = try #require(archive.entry(named: "meta.xml"))
    let metadata = String(decoding: try archive.data(for: metadataEntry), as: UTF8.self)
    #expect(metadata.contains("<office:meta/>"))
    #expect(!metadata.contains("Private Author"))
}

@Test("Removes PDF Info and XMP while preserving pages and form widgets")
func cleansPDFMetadataAndPreservesForms() throws {
    let original = try #require(Data(base64Encoded: metadataFormPDFBase64))
    let cleaned = try FileMetadataCleaner.cleanedData(original, format: .pdf)
    let report = FileProvenanceAnalyzer.analyze(cleaned, fileName: "clean.pdf")
    let originalDocument = try #require(PDFDocument(data: original))
    let cleanedDocument = try #require(PDFDocument(data: cleaned))
    let originalPage = try #require(originalDocument.page(at: 0))
    let cleanedPage = try #require(cleanedDocument.page(at: 0))
    let cleanedWidget = try #require(cleanedPage.annotations.first {
        $0.widgetFieldType == .text
    })

    #expect(report.format == .pdf)
    #expect(report.findings.isEmpty)
    #expect(cleaned.range(of: Data("Private Author".utf8)) == nil)
    #expect(cleaned.range(of: Data("Private XMP".utf8)) == nil)
    #expect(cleanedDocument.pageCount == originalDocument.pageCount)
    #expect(cleanedPage.bounds(for: .mediaBox) == originalPage.bounds(for: .mediaBox))
    #expect(cleanedPage.annotations.count == originalPage.annotations.count)
    #expect(cleanedWidget.widgetStringValue == "preserve me")
}

@Test("Refuses an applied PDF signature before rewriting")
func refusesSignedPDFMetadataCleaning() throws {
    let original = try #require(Data(base64Encoded: metadataFormPDFBase64))
    var signed = original
    try replaceSameLength(
        in: &signed,
        target: "/Type /Metadata",
        replacement: "/Type /Sig     "
    )
    try replaceSameLength(
        in: &signed,
        target: "/Subtype /XML",
        replacement: "/ByteRange[0]"
    )

    #expect(throws: FileMetadataCleaningError.signedContainer) {
        try FileMetadataCleaner.cleanedData(signed, format: .pdf)
    }
}

@Test("Never overwrites an existing destination")
func refusesMetadataCopyOverwrite() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignalSieveMetadataOverwrite-\(UUID().uuidString)", isDirectory: true)
    let source = directory.appendingPathComponent("source.png")
    let destination = directory.appendingPathComponent("existing.png")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    png.append(metadataPNGChunk("tEXt", payload: Data("private".utf8)))
    png.append(metadataPNGChunk("IEND", payload: Data()))
    try png.write(to: source)
    try Data("existing".utf8).write(to: destination)

    #expect(throws: FileMetadataCleaningError.destinationAlreadyExists) {
        try FileMetadataCleaner.cleanCopy(of: source, to: destination)
    }
    #expect(try Data(contentsOf: destination) == Data("existing".utf8))
}

@Test("Rejects malformed containers instead of producing a partial copy")
func rejectsMalformedMetadataContainers() {
    let malformedPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF])
    let malformedJPEG = Data([0xFF, 0xD8, 0xFF, 0xE1, 0xFF])

    #expect(throws: FileMetadataCleaningError.invalidContainer) {
        try FileMetadataCleaner.cleanedData(malformedPNG, format: .png)
    }
    #expect(throws: FileMetadataCleaningError.invalidContainer) {
        try FileMetadataCleaner.cleanedData(malformedJPEG, format: .jpeg)
    }

    var wrappedPDF = Data("HTTP/1.0 200 OK\r\n\r\n".utf8)
    wrappedPDF.append(Data("%PDF-1.7\n%%EOF\n".utf8))
    #expect(throws: FileMetadataCleaningError.invalidContainer) {
        try FileMetadataCleaner.cleanedData(wrappedPDF, format: .pdf)
    }
}

private func metadataPNGChunk(_ type: String, payload: Data) -> Data {
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

private func metadataJPEG(segments: [(UInt8, Data)]) -> Data {
    var data = Data([0xFF, 0xD8])
    for (marker, payload) in segments {
        let length = UInt16(payload.count + 2)
        data.append(contentsOf: [
            0xFF,
            marker,
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ])
        data.append(payload)
    }
    data.append(contentsOf: [0xFF, 0xD9])
    return data
}

private func replaceSameLength(
    in data: inout Data,
    target: String,
    replacement: String
) throws {
    let targetData = Data(target.utf8)
    let replacementData = Data(replacement.utf8)
    #expect(targetData.count == replacementData.count)
    let range = try #require(data.range(of: targetData))
    data.replaceSubrange(range, with: replacementData)
}

private let metadataDOCXBase64 = "UEsDBBQAAAAIAKe5Dl1A3LDuxgAAAMsBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbKWRsU4DQQxEf+W0LbpzREGBcmnoSQp+wNrzXVbcri3bCfD37BKUAqUAUVr2vJmRty8fQta957XYGI7u8ghg8UgZbWChUjcza0avoy4gGF9xIbjfbB4gcnEq3ntjhN12fybVNFF3QPVnzDQGeGOdYOJ4yvVyqLTQPV1kzXkMKLKmiJ64wLlMPzx7nucU6apvNFGOZJbKktfhusmYyl3Dw+0c9fCgLFZDK/09x3fvoan7mkBIPZH9zvFkzvnf3S+YG+bw9cPdJ1BLAwQUAAAACACnuQ5dvPyXe7sAAAAWAgAACwAAAF9yZWxzLy5yZWxzrZK7DsIwDEV/pcpOXUBiQG0nlm4I8QNW4j4EaSLHCPh7ogrEQzw6MMa5OT62km9oj9K5PrSdD8nJ7vtQqFbELwGCbsliSJ2nPt7Uji1KPHIDHvUOG4JZli2AHxmqzB+ZSWUKxZWZqmR79jSG7eq607Ry+mCplzctXhKRjNyQFOro2IC5ltOIVfDeZjbe5vOkYEnQoCBoxzTxHF+zdBTuQtFlHcthSHwTmv9zPfoQxNkfQkPmpgRP36C8AFBLAwQUAAAACACnuQ5dWTNat4sAAADNAAAAEQAAAGRvY1Byb3BzL2NvcmUueG1sZc5BCoMwEAXQq4j7OtpFFyEVegOvMEymKjVmmIzS4zctRQpdfv7n8T2Jo6Q8aBJWmzlXz7is2ZFc68lMHECmiSPmpizWUt6TRrQSdQRBeuDIcG7bC0Q2DGgIb/Akh1h/yUAHKZsuHyAQ8MKRV8vQNR3UvQ/kSBktaT/ovKNxddtsSurhp/Lw97x/AVBLAwQUAAAACACnuQ5dJbtvXmoAAACDAAAAEwAAAGRvY1Byb3BzL2N1c3RvbS54bWxFjTEKwzAMAL8SvLcKGTIUx1Mf0C8YIyeGyjKSEtrfx0NJx+Pgzr+EG4oV1OFD76qL28zaA0DThhT13nXtJrNQtI6yAudcEj457YTVYBrHGdKuxnRrV84F/4PvUCPh4pqUIxo6CB7+23ACUEsDBBQAAAAIAKe5Dl05qW7iYAAAAHcAAAARAAAAd29yZC9kb2N1bWVudC54bWxFjTEOgCAMAL9ifIA1Dg4E+QsCooltCcWgv1cH43S53HC6Ks/uwEClOXEnUXVq11KSAhC3BrTScQr0tIUz2vJojlA5+5TZBZGNIu4w9P0IaDdqja5qZn+9TGA0fAr/ytxQSwECFAMUAAAACACnuQ5dQNyw7sYAAADLAQAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIAKe5Dl28/Jd7uwAAABYCAAALAAAAAAAAAAAAAACAAfcAAABfcmVscy8ucmVsc1BLAQIUAxQAAAAIAKe5Dl1ZM1q3iwAAAM0AAAARAAAAAAAAAAAAAACAAdsBAABkb2NQcm9wcy9jb3JlLnhtbFBLAQIUAxQAAAAIAKe5Dl0lu29eagAAAIMAAAATAAAAAAAAAAAAAACAAZUCAABkb2NQcm9wcy9jdXN0b20ueG1sUEsBAhQDFAAAAAgAp7kOXTmpbuJgAAAAdwAAABEAAAAAAAAAAAAAAIABMAMAAHdvcmQvZG9jdW1lbnQueG1sUEsFBgAAAAAFAAUAOQEAAL8DAAAAAA=="

private let metadataODTBase64 = "UEsDBBQAAAAAAGSGDl1exjIMJwAAACcAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi92bmQub2FzaXMub3BlbmRvY3VtZW50LnRleHRQSwMEFAAAAAgAZIYOXS6HXNh+AAAA5AAAAAgAAABtZXRhLnhtbG2PQQoDIQxFrzK4F6ez6ELSQG/QK0jMMEJVSLX0+B3RQgcGsvj57ychkNc1EFufqUZORUcubvrEZ3rZjm6qShpaDeKpu55+ThvrXlMKYextHYInS8KuZMGHhLcrPN1r2bKA+UPQwr0LOWm/x3CZl6ueL3uBOcFgDnfM2Tf4BVBLAwQUAAAACABkhg5dcjnAYisAAAA0AAAACwAAAGNvbnRlbnQueG1ss8lPS8tMTrVKyU8uzU3NK9FNzs8rAdIKFbk5ecVWEFlbpdKiPChbSd8OAFBLAQIUAxQAAAAAAGSGDl1exjIMJwAAACcAAAAIAAAAAAAAAAAAAACAAQAAAABtaW1ldHlwZVBLAQIUAxQAAAAIAGSGDl0uh1zYfgAAAOQAAAAIAAAAAAAAAAAAAACAAU0AAABtZXRhLnhtbFBLAQIUAxQAAAAIAGSGDl1yOcBiKwAAADQAAAALAAAAAAAAAAAAAACAAfEAAABjb250ZW50LnhtbFBLBQYAAAAAAwADAKUAAABFAQAAAAA="

private let metadataFormPDFBase64 = "JVBERi0xLjMKJeLjz9MKMSAwIG9iago8PAovQWNyb0Zvcm0gMiAwIFIKL1BhZ2VNb2RlIC9Vc2VOb25lCi9QYWdlcyA5IDAgUgovVHlwZSAvQ2F0YWxvZwovTWV0YWRhdGEgMTMgMCBSCj4+CmVuZG9iagoyIDAgb2JqCjw8Ci9EQSAoXDA1N0hlbHYgMCBUZiAwIGcpCi9EUiA8PAovRW5jb2RpbmcgPDwKL1JMQUZlbmNvZGluZyAzIDAgUgo+PgovRm9udCA8PAovSGVsdiA0IDAgUgo+Pgo+PgovRmllbGRzIFsgNSAwIFIgXQo+PgplbmRvYmoKMyAwIG9iago8PAovVHlwZSAvRW5jb2RpbmcKL0RpZmZlcmVuY2VzIFsgMjQgL2JyZXZlIC9jYXJvbiAvY2lyY3VtZmxleCAvZG90YWNjZW50IC9odW5nYXJ1bWxhdXQgL29nb25layAvcmluZyAvdGlsZGUgMzkgL3F1b3Rlc2luZ2xlIDk2IC9ncmF2ZSAxMjggL2J1bGxldCAvZGFnZ2VyIC9kYWdnZXJkYmwgL2VsbGlwc2lzIC9lbWRhc2ggL2VuZGFzaCAvZmxvcmluIC9mcmFjdGlvbiAvZ3VpbHNpbmdsbGVmdCAvZ3VpbHNpbmdscmlnaHQgL21pbnVzIC9wZXJ0aG91c2FuZCAvcXVvdGVkYmxiYXNlIC9xdW90ZWRibGxlZnQgL3F1b3RlZGJscmlnaHQgL3F1b3RlbGVmdCAvcXVvdGVyaWdodCAvcXVvdGVzaW5nbGJhc2UgL3RyYWRlbWFyayAvZmkgL2ZsIC9Mc2xhc2ggL09FIC9TY2Fyb24gL1lkaWVyZXNpcyAvWmNhcm9uIC9kb3RsZXNzaSAvbHNsYXNoIC9vZSAvc2Nhcm9uIC96Y2Fyb24gMTYwIC9FdXJvIDE2NCAvY3VycmVuY3kgMTY2IC9icm9rZW5iYXIgMTY4IC9kaWVyZXNpcyAvY29weXJpZ2h0IC9vcmRmZW1pbmluZSAxNzIgL2xvZ2ljYWxub3QgLy5ub3RkZWYgL3JlZ2lzdGVyZWQgL21hY3JvbiAvZGVncmVlIC9wbHVzbWludXMgL3R3b3N1cGVyaW9yIC90aHJlZXN1cGVyaW9yIC9hY3V0ZSAvbXUgMTgzIC9wZXJpb2RjZW50ZXJlZCAvY2VkaWxsYSAvb25lc3VwZXJpb3IgL29yZG1hc2N1bGluZSAxODggL29uZXF1YXJ0ZXIgL29uZWhhbGYgL3RocmVlcXVhcnRlcnMgMTkyIC9BZ3JhdmUgL0FhY3V0ZSAvQWNpcmN1bWZsZXggL0F0aWxkZSAvQWRpZXJlc2lzIC9BcmluZyAvQUUgL0NjZWRpbGxhIC9FZ3JhdmUgL0VhY3V0ZSAvRWNpcmN1bWZsZXggL0VkaWVyZXNpcyAvSWdyYXZlIC9JYWN1dGUgL0ljaXJjdW1mbGV4IC9JZGllcmVzaXMgL0V0aCAvTnRpbGRlIC9PZ3JhdmUgL09hY3V0ZSAvT2NpcmN1bWZsZXggL090aWxkZSAvT2RpZXJlc2lzIC9tdWx0aXBseSAvT3NsYXNoIC9VZ3JhdmUgL1VhY3V0ZSAvVWNpcmN1bWZsZXggL1VkaWVyZXNpcyAvWWFjdXRlIC9UaG9ybiAvZ2VybWFuZGJscyAvYWdyYXZlIC9hYWN1dGUgL2FjaXJjdW1mbGV4IC9hdGlsZGUgL2FkaWVyZXNpcyAvYXJpbmcgL2FlIC9jY2VkaWxsYSAvZWdyYXZlIC9lYWN1dGUgL2VjaXJjdW1mbGV4IC9lZGllcmVzaXMgL2lncmF2ZSAvaWFjdXRlIC9pY2lyY3VtZmxleCAvaWRpZXJlc2lzIC9ldGggL250aWxkZSAvb2dyYXZlIC9vYWN1dGUgL29jaXJjdW1mbGV4IC9vdGlsZGUgL29kaWVyZXNpcyAvZGl2aWRlIC9vc2xhc2ggL3VncmF2ZSAvdWFjdXRlIC91Y2lyY3VtZmxleCAvdWRpZXJlc2lzIC95YWN1dGUgL3Rob3JuIC95ZGllcmVzaXMgXQo+PgplbmRvYmoKNCAwIG9iago8PAovQmFzZUZvbnQgL0hlbHZldGljYQovU3VidHlwZSAvVHlwZTEKL05hbWUgL0hlbHYKL1R5cGUgL0ZvbnQKL0VuY29kaW5nIDMgMCBSCj4+CmVuZG9iago1IDAgb2JqCjw8Ci9BUCA8PAovTiA2IDAgUgo+PgovQlMgPDwKL1MgL1MKL1cgMQo+PgovREEgKFwwNTdIZWx2IDEyIFRmIFwwNTYxIFwwNTYxIFwwNTYxIHJnKQovRFYgKHByZXNlcnZlIG1lKQovRiA0Ci9GVCAvVHgKL0ZmIDAKL01LIDw8Ci9CQyBbIDAuMSAwLjEgMC4xIF0KL0JHIFsgMC44IDAuODQzIDEgXQo+PgovTWF4TGVuIDEwMAovUCA3IDAgUgovUmVjdCBbIDcyIDY1MCAyOTIgNjc0IF0KL1N1YnR5cGUgL1dpZGdldAovVCAocHJpdmF0ZVwxMzdmaWVsZCkKL1R5cGUgL0Fubm90Ci9WIChwcmVzZXJ2ZSBtZSkKPj4KZW5kb2JqCjYgMCBvYmoKPDwKL0JCb3ggWyAwIDAgMjIwIDI0IF0KL0ZpbHRlciBbIC9GbGF0ZURlY29kZSBdCi9Gb3JtVHlwZSAxCi9NYXRyaXggWyAxIDAgMCAxIDAgMCBdCi9SZXNvdXJjZXMgPDwKL1Byb2NTZXQgWyAvUERGIC9UZXh0IF0KL0ZvbnQgPDwKL0hlbHYgNCAwIFIKPj4KPj4KL1N1YnR5cGUgL0Zvcm0KL1R5cGUgL1hPYmplY3QKL0xlbmd0aCAxMzUKPj4Kc3RyZWFtCnicTY2xCsJAGIP3PEVGXa73/z2lri2lLh2UH3yCUxBb9ArVx/cOF0kyJXxxDV0TagrTDZ6eqjmBKeIKJ/z5PED4hnc7lqgcqHXZLKjsw3bsiBeUWbJnJuTqgjkDC3RAa6iO8bFSlPbHzZ/C8ioMFE+bsHmmuMS0Rk5xS7ujN5zQjx2+wDkk0gplbmRzdHJlYW0KZW5kb2JqCjcgMCBvYmoKPDwKL0Fubm90cyBbIDUgMCBSIF0KL0NvbnRlbnRzIDggMCBSCi9NZWRpYUJveCBbIDAgMCA2MTIgNzkyIF0KL1BhcmVudCA5IDAgUgovUmVzb3VyY2VzIDw8Ci9Gb250IDEwIDAgUgovUHJvY1NldCBbIC9QREYgL1RleHQgL0ltYWdlQiAvSW1hZ2VDIC9JbWFnZUkgXQo+PgovUm90YXRlIDAKL1RyYW5zIDw8Cj4+Ci9UeXBlIC9QYWdlCj4+CmVuZG9iago4IDAgb2JqCjw8Ci9GaWx0ZXIgWyAvQVNDSUk4NURlY29kZSAvRmxhdGVEZWNvZGUgXQovTGVuZ3RoIDE0MAo+PgpzdHJlYW0KR2FwUWgwRT1GLDBVXEgzVFxwTllUXlFLaz90Yz5JUCw7VyNVMV4yM2loUEVNXz9DVzRLSVNpPCFbN2AjT0Jfc0tpNjppK2AjT0toYmdgcHRLYERvSkwidDFAYDBBMyc3InNdbGVBVCNEXVFBazdiX2hTM1UvWGpATz1aKHMvV2BnOj5RQC5CKl82fj4KZW5kc3RyZWFtCmVuZG9iago5IDAgb2JqCjw8Ci9Db3VudCAxCi9LaWRzIFsgNyAwIFIgXQovVHlwZSAvUGFnZXMKPj4KZW5kb2JqCjEwIDAgb2JqCjw8Ci9GMSAxMSAwIFIKPj4KZW5kb2JqCjExIDAgb2JqCjw8Ci9CYXNlRm9udCAvSGVsdmV0aWNhCi9FbmNvZGluZyAvV2luQW5zaUVuY29kaW5nCi9OYW1lIC9GMQovU3VidHlwZSAvVHlwZTEKL1R5cGUgL0ZvbnQKPj4KZW5kb2JqCjEyIDAgb2JqCjw8Ci9BdXRob3IgKFByaXZhdGUgQXV0aG9yKQovQ3JlYXRpb25EYXRlIChEXDA3MjIwMjYwODE2MTU0MzE2XDA1NTA2XDA0NzAwXDA0NykKL0NyZWF0b3IgKFNpZ25hbCBTaWV2ZSBUZXN0IEdlbmVyYXRvcikKL0tleXdvcmRzICgpCi9Nb2REYXRlIChEXDA3MjIwMjYwODE2MTU0MzE2XDA1NTA2XDA0NzAwXDA0NykKL1Byb2R1Y2VyIChSZXBvcnRMYWIgUERGIExpYnJhcnkgXDA1NSBcMDUwb3BlbnNvdXJjZVwwNTEpCi9TdWJqZWN0IChQcml2YXRlIFN1YmplY3QpCi9UaXRsZSAoUHJpdmF0ZSBUaXRsZSkKL1RyYXBwZWQgL0ZhbHNlCj4+CmVuZG9iagoxMyAwIG9iago8PAovVHlwZSAvTWV0YWRhdGEKL1N1YnR5cGUgL1hNTAovTGVuZ3RoIDM0Mwo+PgpzdHJlYW0KPD94cGFja2V0IGJlZ2luPSIiPz48eDp4bXBtZXRhIHhtbG5zOng9ImFkb2JlOm5zOm1ldGEvIj48cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPjxyZGY6RGVzY3JpcHRpb24gcmRmOmFib3V0PSIiIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyI+PGRjOnRpdGxlPjxyZGY6QWx0PjxyZGY6bGkgeG1sOmxhbmc9IngtZGVmYXVsdCI+UHJpdmF0ZSBYTVA8L3JkZjpsaT48L3JkZjpBbHQ+PC9kYzp0aXRsZT48L3JkZjpEZXNjcmlwdGlvbj48L3JkZjpSREY+PC94OnhtcG1ldGE+PD94cGFja2V0IGVuZD0idyI/PgplbmRzdHJlYW0KZW5kb2JqCnhyZWYKMCAxNAowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMTUgMDAwMDAgbiAKMDAwMDAwMDExNiAwMDAwMCBuIAowMDAwMDAwMjQ5IDAwMDAwIG4gCjAwMDAwMDE1NzUgMDAwMDAgbiAKMDAwMDAwMTY3MyAwMDAwMCBuIAowMDAwMDAxOTc4IDAwMDAwIG4gCjAwMDAwMDIzNDEgMDAwMDAgbiAKMDAwMDAwMjU0OSAwMDAwMCBuIAowMDAwMDI3ODAgMDAwMDAgbiAKMDAwMDAwMjgzOSAwMDAwIG4gCjAwMDAwMDI4NzIgMDAwMDAgbiAKMDAwMDAwMjk4MCAwMDAwMCBuIAowMDAwMDMzMDIgMDAwMDAgbiAKdHJhaWxlcgo8PAovU2l6ZSAxNAovUm9vdCAxIDAgUgovSW5mbyAxMiAwIFIKL0lEIFsgKFwyNjJcMDAyXDIzMlwzNjZcMTczXDM1NVwyNjBcMjUxXDMyMVwzMDdcMzIxXDAyMVwyNTBcMzMwXDM1NVwyMjYpIChcMjYyXDAwMlwyMzJcMzY2XDE3M1wzNTVcMjYwXDI1MVwzMjFcMzA3XDMyMVwwMjFcMjUwXDMzMFwzNTVcMjI2KSBdCj4+CnN0YXJ0eHJlZgozNzI3CiUlRU9GCg=="
