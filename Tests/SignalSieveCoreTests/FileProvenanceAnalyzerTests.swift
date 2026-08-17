// SPDX-License-Identifier: MPL-2.0
import Foundation
import SignalSieveCore
import Testing

@Test("Parses PNG provenance chunks without reading their private values")
func parsesPNGProvenance() {
    var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    data.append(pngChunk("caBX", payload: Data("manifest".utf8)))
    data.append(pngChunk("eXIf", payload: Data("private-exif".utf8)))
    data.append(pngChunk("tEXt", payload: Data("private-text".utf8)))
    data.append(pngChunk("IEND", payload: Data()))

    let report = FileProvenanceAnalyzer.analyze(data, fileName: "sample.png")

    #expect(report.format == .png)
    #expect(report.containsC2PAContainer)
    #expect(report.findings.contains { $0.kind == .exifMetadata })
    #expect(report.findings.contains { $0.kind == .pngTextMetadata })
    #expect(report.findings.allSatisfy { $0.evidenceConfidence == .exact })
    #expect(!report.findings.map(\.evidence).joined().contains("private"))
}

@Test("Reports a filename extension that disagrees with the byte signature")
func reportsExtensionContentMismatch() {
    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    png.append(pngChunk("IEND", payload: Data()))

    let report = FileProvenanceAnalyzer.analyze(png, fileName: "masquerade.svg")

    #expect(report.format == .png)
    #expect(report.findings.contains {
        $0.kind == .extensionContentMismatch
            && $0.evidenceConfidence == .exact
            && $0.evidence.contains("Extension .svg")
    })
}

@Test("Does not treat every JPEG APP11 segment as C2PA")
func distinguishesGenericJPEGApp11() {
    let data = jpeg(segments: [(0xEB, Data("unrelated APP11 payload".utf8))])
    let report = FileProvenanceAnalyzer.analyze(data, fileName: "sample.jpg")

    #expect(report.findings.contains { $0.kind == .jpegApp11 })
    #expect(!report.containsC2PAContainer)
}

@Test("Recognizes the official C2PA manifest UUID in JPEG APP11")
func recognizesJPEGC2PAUUID() {
    let uuid = Data([
        0x63, 0x32, 0x70, 0x61, 0x00, 0x11, 0x00, 0x10,
        0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
    ])
    let data = jpeg(segments: [(0xEB, uuid)])
    let report = FileProvenanceAnalyzer.analyze(data, fileName: "credential.jpg")

    #expect(report.containsC2PAContainer)
    #expect(report.findings.first?.evidenceConfidence == .exact)
}

@Test("Reports text-container metadata without claiming cryptographic validation")
func reportsTextContainerMetadata() {
    let svg = FileProvenanceAnalyzer.analyze(
        Data("<svg><metadata>private</metadata></svg>".utf8),
        fileName: "image.svg"
    )
    let markdown = FileProvenanceAnalyzer.analyze(
        Data("---\nauthor: private\n---\nBody".utf8),
        fileName: "note.md"
    )

    #expect(svg.findings.contains { $0.kind == .svgMetadata })
    #expect(markdown.findings.contains { $0.kind == .markdownFrontMatter })
    #expect(!svg.containsC2PAContainer)
}

@Test("Malformed containers stop safely")
func malformedProvenanceContainerIsBounded() {
    let malformedPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF])
    let malformedJPEG = Data([0xFF, 0xD8, 0xFF, 0xEB, 0xFF, 0xFF, 0x00])

    #expect(FileProvenanceAnalyzer.analyze(malformedPNG, fileName: "bad.png").findings.isEmpty)
    #expect(FileProvenanceAnalyzer.analyze(malformedJPEG, fileName: "bad.jpg").findings.isEmpty)
}

@Test("Parses deflated DOCX property parts from the ZIP directory")
func parsesDOCXPropertyParts() throws {
    let base64 = "UEsDBBQAAAAIAGSGDl3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgAZIYOXcSt3EB0AAAAuwAAABEAAABkb2NQcm9wcy9jb3JlLnhtbLNJLrBKzi9KDSjKL0gtKslMLVaoyM3JK7ZKLrBVKi3KA9JKdjYpyVbJRamJJflFUNmUZIhsSrKSXUBRZlliSaqCY2lJRn6RjT5CMUhjSWpRbjFEIDUFrhssCjMCzFGyMzIwMtM1MAQikBko+uxs9DHcaQcAUEsDBBQAAAAIAGSGDl19mTaIUQAAAGwAAAATAAAAZG9jUHJvcHMvY3VzdG9tLnhtbLMJKMovSC0qyUwttrMpgLArFfISc1NtlYJTk4tSS5TsbMpKrHIKyotLihQqcnPyiq3KSmyVSovygLSSXUFRZlliSaqNPlyRnY0+zCAgE8l8AFBLAwQUAAAACABkhg5dCpCgcTEAAABAAAAAEQAAAHdvcmQvZG9jdW1lbnQueG1ssym3SslPLs1NzStRqMjNySu2KrdVKi3KsypXsrMpt0rKT6kE0QX6djb6MK4+Qo8dAFBLAQIUAxQAAAAIAGSGDl3HHBc8CgAAAAgAAAATAAAAAAAAAAAAAACAAQAAAABbQ29udGVudF9UeXBlc10ueG1sUEsBAhQDFAAAAAgAZIYOXcSt3EB0AAAAuwAAABEAAAAAAAAAAAAAAIABOwAAAGRvY1Byb3BzL2NvcmUueG1sUEsBAhQDFAAAAAgAZIYOXX2ZNohRAAAAbAAAABMAAAAAAAAAAAAAAIAB3gAAAGRvY1Byb3BzL2N1c3RvbS54bWxQSwECFAMUAAAACABkhg5dCpCgcTEAAABAAAAAEQAAAAAAAAAAAAAAgAFgAQAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAQABAAAAQAAwAEAAAAA"
    let data = try #require(Data(base64Encoded: base64))
    let report = FileProvenanceAnalyzer.analyze(data, fileName: "document.docx")

    #expect(report.format == .docx)
    #expect(report.findings.count == 2)
    #expect(report.findings.allSatisfy {
        $0.kind == .documentProperties && $0.evidenceConfidence == .exact
    })
    #expect(report.findings.contains { $0.evidence.contains("docProps/core.xml") })
    #expect(!report.findings.map(\.evidence).joined().contains("Private Author"))
}

@Test("Parses deflated OpenDocument meta.xml with a validated mimetype")
func parsesODTMetadata() throws {
    let base64 = "UEsDBBQAAAAAAGSGDl1exjIMJwAAACcAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi92bmQub2FzaXMub3BlbmRvY3VtZW50LnRleHRQSwMEFAAAAAgAZIYOXS6HXNh+AAAA5AAAAAgAAABtZXRhLnhtbG2PQQoDIQxFrzK4F6ez6ELSQG/QK0jMMEJVSLX0+B3RQgcGsvj57ychkNc1EFufqUZORUcubvrEZ3rZjm6qShpaDeKpu55+ThvrXlMKYextHYInS8KuZMGHhLcrPN1r2bKA+UPQwr0LOWm/x3CZl6ueL3uBOcFgDnfM2Tf4BVBLAwQUAAAACABkhg5dcjnAYisAAAA0AAAACwAAAGNvbnRlbnQueG1ss8lPS8tMTrVKyU8uzU3NK9FNzs8rAdIKFbk5ecVWEFlbpdKiPChbSd8OAFBLAQIUAxQAAAAAAGSGDl1exjIMJwAAACcAAAAIAAAAAAAAAAAAAACAAQAAAABtaW1ldHlwZVBLAQIUAxQAAAAIAGSGDl0uh1zYfgAAAOQAAAAIAAAAAAAAAAAAAACAAU0AAABtZXRhLnhtbFBLAQIUAxQAAAAIAGSGDl1yOcBiKwAAADQAAAALAAAAAAAAAAAAAACAAfEAAABjb250ZW50LnhtbFBLBQYAAAAAAwADAKUAAABFAQAAAAA="
    let data = try #require(Data(base64Encoded: base64))
    let report = FileProvenanceAnalyzer.analyze(data, fileName: "document.odt")

    #expect(report.format == .odt)
    #expect(report.findings.count == 1)
    #expect(report.findings.first?.kind == .openDocumentMetadata)
    #expect(report.findings.first?.evidenceConfidence == .exact)
    #expect(report.findings.first?.evidence.contains("meta.xml") == true)
    #expect(!report.findings.map(\.evidence).joined().contains("Private Author"))
}

@Test("Uses structured PDF relationships and the native parser for exact evidence")
func parsesPDFMetadataStructures() throws {
    let base64 = "JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgL01ldGFkYXRhIDUgMCBSID4+CmVuZG9iagoyIDAgb2JqCjw8IC9UeXBlIC9QYWdlcyAvS2lkcyBbMyAwIFJdIC9Db3VudCAxID4+CmVuZG9iagozIDAgb2JqCjw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMiAwIFIgL01lZGlhQm94IFswIDAgNjEyIDc5Ml0gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL1RpdGxlIChTZWNyZXQpIC9BdXRob3IgKFByaXZhdGUpID4+CmVuZG9iago1IDAgb2JqCjw8IC9UeXBlIC9NZXRhZGF0YSAvU3VidHlwZSAvWE1MIC9MZW5ndGggMjMgPj4Kc3RyZWFtCjx4OnhtcG1ldGE+PC94OnhtcG1ldGE+CmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNzQgMDAwMDAgbiAKMDAwMDAwMDEzMSAwMDAwMCBuIAowMDAwMDAwMjAyIDAwMDAwIG4gCjAwMDAwMDAyNTcgMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA2IC9Sb290IDEgMCBSIC9JbmZvIDQgMCBSID4+CnN0YXJ0eHJlZgozNjAKJSVFT0YK"
    let data = try #require(Data(base64Encoded: base64))
    let report = FileProvenanceAnalyzer.analyze(data, fileName: "document.pdf")

    #expect(report.format == .pdf)
    #expect(report.findings.contains {
        $0.kind == .pdfMetadata && $0.evidenceConfidence == .exact
    })
    #expect(report.findings.contains { $0.evidence == "PDF Metadata object reference" })
    #expect(!report.findings.map(\.evidence).joined().contains("Private"))
}

@Test("Recognizes a PDF wrapped in leading response data and reports the anomaly")
func recognizesWrappedPDFHeader() throws {
    var wrapped = Data("HTTP/1.0 200 OK\r\nContent-Type: application/pdf\r\n\r\n".utf8)
    let body = try #require(Data(base64Encoded: "JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgL01ldGFkYXRhIDUgMCBSID4+CmVuZG9iagoyIDAgb2JqCjw8IC9UeXBlIC9QYWdlcyAvS2lkcyBbMyAwIFJdIC9Db3VudCAxID4+CmVuZG9iagozIDAgb2JqCjw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMiAwIFIgL01lZGlhQm94IFswIDAgNjEyIDc5Ml0gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL1RpdGxlIChTZWNyZXQpIC9BdXRob3IgKFByaXZhdGUpID4+CmVuZG9iago1IDAgb2JqCjw8IC9UeXBlIC9NZXRhZGF0YSAvU3VidHlwZSAvWE1MIC9MZW5ndGggMjMgPj4Kc3RyZWFtCjx4OnhtcG1ldGE+PC94OnhtcG1ldGE+CmVuZHN0cmVhbQplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNzQgMDAwMDAgbiAKMDAwMDAwMDEzMSAwMDAwMCBuIAowMDAwMDAwMjAyIDAwMDAwIG4gCjAwMDAwMDAyNTcgMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA2IC9Sb290IDEgMCBSIC9JbmZvIDQgMCBSID4+CnN0YXJ0eHJlZgozNjAKJSVFT0YK"))
    wrapped.append(body)

    let report = FileProvenanceAnalyzer.analyze(wrapped, fileName: "wrapped.pdf")

    #expect(report.format == .pdf)
    #expect(report.findings.contains {
        $0.kind == .leadingContainerData
            && $0.evidenceConfidence == .exact
            && $0.evidence.contains("PDF header at byte")
    })
}

private func pngChunk(_ type: String, payload: Data) -> Data {
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

private func jpeg(segments: [(UInt8, Data)]) -> Data {
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
