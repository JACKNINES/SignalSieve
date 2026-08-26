// SPDX-License-Identifier: MPL-2.0
import AppKit
import CoreGraphics
import Foundation
import ImageIO

private let canvasSize = 1_024
private let bytesPerPixel = 4
private let bytesPerRow = canvasSize * bytesPerPixel
private let latticeSpacing = 180
private let latticeHalfWidth = 2
private let outlineRadius = 7

private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
    let remainder = value % divisor
    return remainder >= 0 ? remainder : remainder + divisor
}

private func isNearLatticeLine(_ value: Int) -> Bool {
    let remainder = positiveModulo(value, latticeSpacing)
    return min(remainder, latticeSpacing - remainder) <= latticeHalfWidth
}

private func isInsideRoundedSquare(
    x: Int,
    y: Int,
    inset: Int,
    radius: Int
) -> Bool {
    let minimum = inset
    let maximum = canvasSize - 1 - inset
    guard x >= minimum, x <= maximum, y >= minimum, y <= maximum else {
        return false
    }

    if x >= minimum + radius, x <= maximum - radius
        || y >= minimum + radius, y <= maximum - radius {
        return true
    }

    let centerX = x < minimum + radius ? minimum + radius : maximum - radius
    let centerY = y < minimum + radius ? minimum + radius : maximum - radius
    let deltaX = x - centerX
    let deltaY = y - centerY
    return deltaX * deltaX + deltaY * deltaY <= radius * radius
}

private func loadRGBA(from url: URL) throws -> [UInt8] {
    let data = try Data(contentsOf: url)
    guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw CocoaError(.fileReadCorruptFile)
    }

    var pixels = [UInt8](repeating: 0, count: canvasSize * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: &pixels,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw CocoaError(.fileReadUnknown)
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    return pixels
}

private func logoMask(from pixels: [UInt8]) -> [UInt8] {
    var mask = [UInt8](repeating: 0, count: canvasSize * canvasSize)
    for pixelIndex in 0..<(canvasSize * canvasSize) {
        let sourceIndex = pixelIndex * bytesPerPixel
        let luminance = max(
            pixels[sourceIndex],
            max(pixels[sourceIndex + 1], pixels[sourceIndex + 2])
        )
        let alpha = pixels[sourceIndex + 3]

        // The official dark icon has a near-black tile and a white mark. This
        // bounded ramp preserves the mark's antialiasing while dropping the tile.
        let normalized = max(0, Int(luminance) - 32)
        let markAlpha = min(255, normalized * 255 / 180)
        mask[pixelIndex] = UInt8(markAlpha * Int(alpha) / 255)
    }
    return mask
}

private func dilateSquare(_ mask: [UInt8], radius: Int) -> [UInt8] {
    var horizontal = [UInt8](repeating: 0, count: mask.count)
    var result = [UInt8](repeating: 0, count: mask.count)

    for y in 0..<canvasSize {
        for x in 0..<canvasSize {
            var maximum: UInt8 = 0
            for sampleX in max(0, x - radius)...min(canvasSize - 1, x + radius) {
                maximum = max(maximum, mask[y * canvasSize + sampleX])
            }
            horizontal[y * canvasSize + x] = maximum
        }
    }

    for y in 0..<canvasSize {
        for x in 0..<canvasSize {
            var maximum: UInt8 = 0
            for sampleY in max(0, y - radius)...min(canvasSize - 1, y + radius) {
                maximum = max(maximum, horizontal[sampleY * canvasSize + x])
            }
            result[y * canvasSize + x] = maximum
        }
    }

    return result
}

private func putWhite(alpha: UInt8, at pixelIndex: Int, into output: inout [UInt8]) {
    let outputIndex = pixelIndex * bytesPerPixel
    let existingAlpha = Int(output[outputIndex + 3])
    let addedAlpha = Int(alpha)
    let combinedAlpha = addedAlpha + existingAlpha * (255 - addedAlpha) / 255
    let value = UInt8(clamping: combinedAlpha)
    output[outputIndex] = value
    output[outputIndex + 1] = value
    output[outputIndex + 2] = value
    output[outputIndex + 3] = value
}

private func putBlack(alpha: UInt8, at pixelIndex: Int, into output: inout [UInt8]) {
    let outputIndex = pixelIndex * bytesPerPixel
    let foregroundAlpha = Int(alpha)
    let retainedBackground = 255 - foregroundAlpha
    output[outputIndex] = UInt8(Int(output[outputIndex]) * retainedBackground / 255)
    output[outputIndex + 1] = UInt8(Int(output[outputIndex + 1]) * retainedBackground / 255)
    output[outputIndex + 2] = UInt8(Int(output[outputIndex + 2]) * retainedBackground / 255)
    output[outputIndex + 3] = UInt8(clamping:
        foregroundAlpha + Int(output[outputIndex + 3]) * retainedBackground / 255
    )
}

private func writePNG(_ pixels: [UInt8], to url: URL) throws {
    let data = Data(pixels)
    guard
        let provider = CGDataProvider(data: data as CFData),
        let image = CGImage(
            width: canvasSize,
            height: canvasSize,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue:
                CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    let representation = NSBitmapImageRep(cgImage: image)
    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url, options: .atomic)
}

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = projectRoot
    .appendingPathComponent("Packaging/ThemeIcons/SignalSieveIcon-Dark.png")
let outputURL = projectRoot
    .appendingPathComponent("docs/images/signal-sieve-mark.png")

let sourcePixels = try loadRGBA(from: sourceURL)
let mark = logoMask(from: sourcePixels)
let outline = dilateSquare(mark, radius: outlineRadius)
var output = [UInt8](repeating: 0, count: canvasSize * bytesPerRow)

for y in 0..<canvasSize {
    for x in 0..<canvasSize {
        let pixelIndex = y * canvasSize + x
        let insideOuter = isInsideRoundedSquare(x: x, y: y, inset: 54, radius: 128)
        guard insideOuter else { continue }

        let insideInner = isInsideRoundedSquare(x: x, y: y, inset: 62, radius: 120)
        let isBorder = !insideInner
        let isLattice = isNearLatticeLine(x + y) || isNearLatticeLine(x - y)
        if isBorder || isLattice {
            putWhite(alpha: 255, at: pixelIndex, into: &output)
        }
    }
}

for pixelIndex in 0..<mark.count where outline[pixelIndex] > 0 {
    putWhite(alpha: outline[pixelIndex], at: pixelIndex, into: &output)
}
for pixelIndex in 0..<mark.count where mark[pixelIndex] > 0 {
    putBlack(alpha: mark[pixelIndex], at: pixelIndex, into: &output)
}

try writePNG(output, to: outputURL)
print("README mark written to \(outputURL.path)")
