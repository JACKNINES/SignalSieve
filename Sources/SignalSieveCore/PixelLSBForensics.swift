// SPDX-License-Identifier: MPL-2.0
import CoreGraphics
import Foundation
import ImageIO

public struct PixelLSBForensicsReport: Sendable, Equatable {
    public let score: Double
    public let threshold: Double
    public let sampledPixelCount: Int
    public let bitEntropy: Double
    public let valuePairBalance: Double
    public let transitionRandomness: Double
    public let hasEnoughSamples: Bool

    public init(
        score: Double,
        threshold: Double,
        sampledPixelCount: Int,
        bitEntropy: Double,
        valuePairBalance: Double,
        transitionRandomness: Double,
        hasEnoughSamples: Bool
    ) {
        self.score = score
        self.threshold = threshold
        self.sampledPixelCount = sampledPixelCount
        self.bitEntropy = bitEntropy
        self.valuePairBalance = valuePairBalance
        self.transitionRandomness = transitionRandomness
        self.hasEnoughSamples = hasEnoughSamples
    }

    public var isElevated: Bool {
        hasEnoughSamples && score >= threshold
    }
}

public enum PixelLSBForensicsError: Error, Sendable, Equatable {
    case invalidImage
    case imageTooLarge
    case couldNotRender
    case couldNotEncode
    case invalidStrength
}

/// A deterministic, model-free screen for classic LSB carrier regularity.
/// It is useful for steganographic payload triage but is not a SynthID, C2PA,
/// or provider-specific watermark detector.
public enum PixelLSBForensics {
    public static let maximumPixelCount = 40_000_000
    public static let maximumSampledPixels = 2_000_000
    public static let minimumReliableSamples = 4_096
    public static let elevatedThreshold = 0.86

    public static func analyze(_ data: Data) throws -> PixelLSBForensicsReport {
        let raster = try rasterize(data)
        let totalPixels = raster.width * raster.height
        let stride = max(1, totalPixels / maximumSampledPixels)
        var zeros = 0
        var ones = 0
        var pairCounts = [Int](repeating: 0, count: 3 * 128 * 2)
        var transitions = 0
        var transitionComparisons = 0
        var previousBits: (Int, Int, Int)?
        var sampledPixels = 0

        for pixelIndex in Swift.stride(from: 0, to: totalPixels, by: stride) {
            let offset = pixelIndex * 4
            guard raster.bytes[offset + 3] != 0 else { continue }
            let red = Int(raster.bytes[offset])
            let green = Int(raster.bytes[offset + 1])
            let blue = Int(raster.bytes[offset + 2])
            let bits = (red & 1, green & 1, blue & 1)
            for (channel, value) in [red, green, blue].enumerated() {
                let bit = value & 1
                if bit == 0 { zeros += 1 } else { ones += 1 }
                pairCounts[(channel * 128 + value / 2) * 2 + bit] += 1
            }
            if let previousBits {
                transitions += previousBits.0 == bits.0 ? 0 : 1
                transitions += previousBits.1 == bits.1 ? 0 : 1
                transitions += previousBits.2 == bits.2 ? 0 : 1
                transitionComparisons += 3
            }
            previousBits = bits
            sampledPixels += 1
        }

        let totalBits = zeros + ones
        guard totalBits > 0 else { throw PixelLSBForensicsError.invalidImage }
        let oneProbability = Double(ones) / Double(totalBits)
        let entropy = binaryEntropy(oneProbability)

        var pairDifference = 0
        var pairPopulation = 0
        for index in Swift.stride(from: 0, to: pairCounts.count, by: 2) {
            let even = pairCounts[index]
            let odd = pairCounts[index + 1]
            let population = even + odd
            guard population >= 4 else { continue }
            pairDifference += abs(even - odd)
            pairPopulation += population
        }
        let pairBalance = pairPopulation == 0
            ? 0
            : 1 - Double(pairDifference) / Double(pairPopulation)
        let transitionRate = transitionComparisons == 0
            ? 0
            : Double(transitions) / Double(transitionComparisons)
        let transitionRandomness = max(0, 1 - abs(transitionRate - 0.5) * 2)
        let enoughSamples = sampledPixels >= minimumReliableSamples
        let rawScore = 0.40 * pairBalance
            + 0.35 * entropy
            + 0.25 * transitionRandomness
        let reliability = min(1, Double(sampledPixels) / Double(minimumReliableSamples))
        let score = min(1, max(0, rawScore * reliability))

        return PixelLSBForensicsReport(
            score: score,
            threshold: elevatedThreshold,
            sampledPixelCount: sampledPixels,
            bitEntropy: entropy,
            valuePairBalance: pairBalance,
            transitionRandomness: transitionRandomness,
            hasEnoughSamples: enoughSamples
        )
    }

    public static func regenerate(
        _ data: Data,
        strength: Double
    ) throws -> Data {
        guard strength.isFinite, (0.05...0.70).contains(strength) else {
            throw PixelLSBForensicsError.invalidStrength
        }
        var raster = try rasterize(data)
        let coverage = min(1, 0.45 + strength / 1.20)
        let threshold = UInt64(coverage * Double(UInt32.max))

        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let offset = (y * raster.width + x) * 4
                guard raster.bytes[offset + 3] != 0 else { continue }
                for channel in 0..<3 {
                    let mixed = coordinateHash(x: x, y: y, channel: channel)
                    if UInt64(mixed) <= threshold {
                        raster.bytes[offset + channel] &= 0xFE
                    }
                }
            }
        }
        return try encode(raster, sourceType: raster.sourceType, orientation: raster.orientation)
    }

    private struct Raster {
        let width: Int
        let height: Int
        var bytes: [UInt8]
        let sourceType: CFString
        let orientation: Int?
    }

    private static func rasterize(_ data: Data) throws -> Raster {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PixelLSBForensicsError.invalidImage
        }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              width <= maximumPixelCount / height else {
            throw PixelLSBForensicsError.imageTooLarge
        }
        let pixelCount = width * height
        guard pixelCount <= maximumPixelCount,
              pixelCount <= Int.max / 4 else {
            throw PixelLSBForensicsError.imageTooLarge
        }
        var bytes = [UInt8](repeating: 0, count: pixelCount * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            throw PixelLSBForensicsError.couldNotRender
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int
        return Raster(
            width: width,
            height: height,
            bytes: bytes,
            sourceType: type,
            orientation: orientation
        )
    }

    private static func encode(
        _ raster: Raster,
        sourceType: CFString,
        orientation: Int?
    ) throws -> Data {
        var bytes = raster.bytes
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &bytes,
                width: raster.width,
                height: raster.height,
                bitsPerComponent: 8,
                bytesPerRow: raster.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ),
              let image = context.makeImage() else {
            throw PixelLSBForensicsError.couldNotRender
        }
        let supportedTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard supportedTypes.contains(sourceType as String) else {
            throw PixelLSBForensicsError.couldNotEncode
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            sourceType,
            1,
            nil
        ) else {
            throw PixelLSBForensicsError.couldNotEncode
        }
        var properties: [CFString: Any] = [:]
        if let orientation, orientation != 1 {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if (sourceType as String).lowercased().contains("jpeg") {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.95
        }
        let destinationProperties: CFDictionary? = properties.isEmpty
            ? nil
            : properties as CFDictionary
        CGImageDestinationAddImage(destination, image, destinationProperties)
        guard CGImageDestinationFinalize(destination) else {
            throw PixelLSBForensicsError.couldNotEncode
        }
        let encoded = output as Data
        guard orientation == nil || orientation == 1 else {
            return encoded
        }
        do {
            switch (sourceType as String).lowercased() {
            case let type where type.contains("png"):
                return try FileMetadataCleaner.cleanedData(encoded, format: .png)
            case let type where type.contains("jpeg") || type.contains("jpg"):
                return try FileMetadataCleaner.cleanedData(encoded, format: .jpeg)
            default:
                return encoded
            }
        } catch {
            throw PixelLSBForensicsError.couldNotEncode
        }
    }

    private static func binaryEntropy(_ probability: Double) -> Double {
        guard probability > 0, probability < 1 else { return 0 }
        return -(probability * log2(probability)
            + (1 - probability) * log2(1 - probability))
    }

    private static func coordinateHash(x: Int, y: Int, channel: Int) -> UInt32 {
        var value = UInt32(truncatingIfNeeded: x) &* 0x9E37_79B1
        value ^= UInt32(truncatingIfNeeded: y) &* 0x85EB_CA77
        value ^= UInt32(channel + 1) &* 0xC2B2_AE3D
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        value &*= 0x846C_A68B
        value ^= value >> 16
        return value
    }
}
