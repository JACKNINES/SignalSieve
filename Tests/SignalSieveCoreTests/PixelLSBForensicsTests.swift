// SPDX-License-Identifier: MPL-2.0
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SignalSieveCore

@Test("Distinguishes a synthetic LSB carrier and lowers it after regeneration")
func detectsAndNeutralizesSyntheticLSBCarrier() throws {
    let width = 128
    let height = 128
    var clean = [UInt8](repeating: 255, count: width * height * 4)
    var carrier = clean
    var state: UInt32 = 0xA5C3_91E7

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            for channel in 0..<3 {
                let base = UInt8(((x * 3 + y * 5 + channel * 11) % 64) * 4)
                clean[offset + channel] = base
                state = state &* 1_664_525 &+ 1_013_904_223
                carrier[offset + channel] = base | UInt8((state >> 31) & 1)
            }
        }
    }

    let cleanPNG = try encodeRGBA(clean, width: width, height: height)
    let carrierPNG = try encodeRGBA(carrier, width: width, height: height)
    let cleanReport = try PixelLSBForensics.analyze(cleanPNG)
    let carrierReport = try PixelLSBForensics.analyze(carrierPNG)

    #expect(cleanReport.hasEnoughSamples)
    #expect(!cleanReport.isElevated)
    #expect(carrierReport.isElevated)
    #expect(carrierReport.score > cleanReport.score + 0.50)

    let regenerated = try PixelLSBForensics.regenerate(carrierPNG, strength: 0.70)
    let regeneratedReport = try PixelLSBForensics.analyze(regenerated)
    let provenanceReport = FileProvenanceAnalyzer.analyze(
        regenerated,
        fileName: "regenerated.png"
    )
    #expect(regenerated != carrierPNG)
    #expect(!regeneratedReport.isElevated)
    #expect(regeneratedReport.score < carrierReport.score - 0.50)
    #expect(provenanceReport.findings.isEmpty)
}

@Test("Labels tiny images as an insufficient forensic sample")
func boundsTinyLSBSamples() throws {
    let tiny = try encodeRGBA(
        [255, 1, 1, 255, 1, 255, 1, 255, 1, 1, 255, 255, 255, 255, 255, 255],
        width: 2,
        height: 2
    )
    let report = try PixelLSBForensics.analyze(tiny)
    #expect(!report.hasEnoughSamples)
    #expect(!report.isElevated)
}

@Test("Rejects non-finite and out-of-policy LSB regeneration strengths")
func rejectsInvalidLSBStrengths() {
    for strength in [Double.nan, Double.infinity, -Double.infinity, 0.0, 0.71] {
        #expect(throws: PixelLSBForensicsError.invalidStrength) {
            try PixelLSBForensics.regenerate(Data(), strength: strength)
        }
    }
}

private func encodeRGBA(_ pixels: [UInt8], width: Int, height: Int) throws -> Data {
    var mutable = pixels
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: &mutable,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        output,
        "public.png" as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}
