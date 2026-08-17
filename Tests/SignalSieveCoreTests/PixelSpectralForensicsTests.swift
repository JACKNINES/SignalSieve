// SPDX-License-Identifier: MPL-2.0
import CoreGraphics
import Foundation
import ImageIO
import SignalSieveCore
import Testing

@Test
func detectsAndReducesSyntheticPeriodicCarrier() throws {
    let width = 256
    let height = 256
    var cleanPixels = [UInt8](repeating: 0, count: width * height * 4)
    var carrierPixels = cleanPixels
    let twoPi = 2 * Double.pi

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let base = 42 + (x * 140 / width) + (y * 46 / height)
            let carrier = Int((8 * sin(twoPi * (
                14 * Double(x) / Double(width) - 14 * Double(y) / Double(height)
            ))).rounded())
            for channel in 0..<3 {
                cleanPixels[offset + channel] = UInt8(min(255, base + channel * 3))
                carrierPixels[offset + channel] = UInt8(
                    min(255, max(0, base + channel * 3 + carrier))
                )
            }
            cleanPixels[offset + 3] = 255
            carrierPixels[offset + 3] = 255
        }
    }

    let cleanPNG = try encodeSpectralTestPNG(cleanPixels, width: width, height: height)
    let carrierPNG = try encodeSpectralTestPNG(carrierPixels, width: width, height: height)
    let cleanReport = try PixelSpectralForensics.analyze(cleanPNG)
    let carrierReport = try PixelSpectralForensics.analyze(carrierPNG)

    #expect(cleanReport.hasEnoughSamples)
    #expect(!cleanReport.isElevated)
    #expect(carrierReport.isElevated)
    #expect(carrierReport.carrierFrequencyX == 14)
    #expect(carrierReport.carrierFrequencyY == -14)
    #expect(carrierReport.score > cleanReport.score + 0.30)

    let regenerated = try PixelSpectralForensics.regenerate(carrierPNG, strength: 0.70)
    let regeneratedReport = try PixelSpectralForensics.analyze(regenerated)
    #expect(regenerated != carrierPNG)
    #expect(regeneratedReport.score < carrierReport.score)
    let provenance = FileProvenanceAnalyzer.analyze(regenerated, fileName: "spectral-clean.png")
    #expect(provenance.findings.isEmpty)
}

@Test
func spectralScreenDoesNotVerdictTinyImages() throws {
    let tiny = try encodeSpectralTestPNG(
        [255, 255, 255, 255, 0, 0, 0, 255, 40, 50, 60, 255, 90, 80, 70, 255],
        width: 2,
        height: 2
    )
    let report = try PixelSpectralForensics.analyze(tiny)
    #expect(!report.hasEnoughSamples)
    #expect(!report.isElevated)
}

private func encodeSpectralTestPNG(
    _ pixels: [UInt8],
    width: Int,
    height: Int
) throws -> Data {
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
