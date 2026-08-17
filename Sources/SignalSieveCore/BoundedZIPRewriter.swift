// SPDX-License-Identifier: MPL-2.0
import Foundation

enum BoundedZIPRewriteError: Error, Equatable {
    case invalidContainer
    case unsupportedCompression
    case invalidPlan
    case outputTooLarge
}

/// Rebuilds a non-ZIP64 archive without archive comments, entry comments, or
/// extra fields. Unchanged compressed payloads are copied byte-for-byte; only
/// explicitly replaced entries are stored again. This avoids expanding large
/// document bodies while still producing deterministic container metadata.
struct BoundedZIPRewriter {
    static func rewrite(
        _ data: Data,
        removing removedNames: Set<String>,
        replacing replacements: [String: Data],
        requiredFirstStoredEntry: String? = nil
    ) throws -> Data {
        let archive: BoundedZIPReader
        do {
            archive = try BoundedZIPReader(data: data)
        } catch {
            throw BoundedZIPRewriteError.invalidContainer
        }

        let existingNames = Set(archive.entries.map(\.name))
        guard replacements.keys.allSatisfy(existingNames.contains),
              removedNames.isDisjoint(with: replacements.keys) else {
            throw BoundedZIPRewriteError.invalidPlan
        }

        let orderedEntries = archive.entries.sorted {
            $0.localHeaderOffset < $1.localHeaderOffset
        }
        if let requiredFirstStoredEntry {
            guard orderedEntries.first?.name == requiredFirstStoredEntry,
                  orderedEntries.first?.compressionMethod == 0 else {
                throw BoundedZIPRewriteError.invalidContainer
            }
        }

        var output = Data()
        var centralRecords: [Data] = []

        for entry in orderedEntries where !removedNames.contains(entry.name) {
            let nameData = Data(entry.name.utf8)
            guard !nameData.isEmpty, nameData.count <= Int(UInt16.max) else {
                throw BoundedZIPRewriteError.invalidContainer
            }
            guard output.count <= Int(UInt32.max) else {
                throw BoundedZIPRewriteError.outputTooLarge
            }
            let localOffset = UInt32(output.count)

            let payload: Data
            let compressionMethod: UInt16
            let uncompressedSize: Int
            let checksum: UInt32
            if let replacement = replacements[entry.name] {
                payload = replacement
                compressionMethod = 0
                uncompressedSize = replacement.count
                checksum = crc32(replacement)
            } else {
                guard entry.compressionMethod == 0 || entry.compressionMethod == 8 else {
                    throw BoundedZIPRewriteError.unsupportedCompression
                }
                payload = try compressedPayload(for: entry, in: data)
                compressionMethod = entry.compressionMethod
                uncompressedSize = entry.uncompressedSize
                checksum = entry.crc32
            }

            guard payload.count <= Int(UInt32.max),
                  uncompressedSize <= Int(UInt32.max),
                  output.count <= Int(UInt32.max) - payload.count - 30 - nameData.count else {
                throw BoundedZIPRewriteError.outputTooLarge
            }

            let flags: UInt16 = 0x0800 // Names are normalized to UTF-8; no data descriptor.
            output.appendLittleEndian(UInt32(0x04034B50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(flags)
            output.appendLittleEndian(compressionMethod)
            output.appendLittleEndian(UInt16(0)) // deterministic DOS time
            output.appendLittleEndian(UInt16(0)) // deterministic DOS date
            output.appendLittleEndian(checksum)
            output.appendLittleEndian(UInt32(payload.count))
            output.appendLittleEndian(UInt32(uncompressedSize))
            output.appendLittleEndian(UInt16(nameData.count))
            output.appendLittleEndian(UInt16(0))
            output.append(nameData)
            output.append(payload)

            var central = Data()
            central.appendLittleEndian(UInt32(0x02014B50))
            central.appendLittleEndian(UInt16(20))
            central.appendLittleEndian(UInt16(20))
            central.appendLittleEndian(flags)
            central.appendLittleEndian(compressionMethod)
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(checksum)
            central.appendLittleEndian(UInt32(payload.count))
            central.appendLittleEndian(UInt32(uncompressedSize))
            central.appendLittleEndian(UInt16(nameData.count))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt32(entry.name.hasSuffix("/") ? 0x10 : 0))
            central.appendLittleEndian(localOffset)
            central.append(nameData)
            centralRecords.append(central)
        }

        guard !centralRecords.isEmpty,
              centralRecords.count <= Int(UInt16.max),
              output.count <= Int(UInt32.max) else {
            throw BoundedZIPRewriteError.outputTooLarge
        }
        let centralOffset = UInt32(output.count)
        for record in centralRecords { output.append(record) }
        guard output.count <= Int(UInt32.max) else {
            throw BoundedZIPRewriteError.outputTooLarge
        }
        let centralSize = UInt32(output.count) - centralOffset
        let count = UInt16(centralRecords.count)
        output.appendLittleEndian(UInt32(0x06054B50))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(count)
        output.appendLittleEndian(count)
        output.appendLittleEndian(centralSize)
        output.appendLittleEndian(centralOffset)
        output.appendLittleEndian(UInt16(0))
        return output
    }

    private static func compressedPayload(
        for entry: BoundedZIPEntry,
        in data: Data
    ) throws -> Data {
        let offset = entry.localHeaderOffset
        guard littleEndianUInt32(data, at: offset) == 0x04034B50,
              let localFlags = littleEndianUInt16(data, at: offset + 6),
              let localMethod = littleEndianUInt16(data, at: offset + 8),
              let nameLength = littleEndianUInt16(data, at: offset + 26).map(Int.init),
              let extraLength = littleEndianUInt16(data, at: offset + 28).map(Int.init),
              localFlags & 0x0001 == 0,
              localMethod == entry.compressionMethod else {
            throw BoundedZIPRewriteError.invalidContainer
        }
        let nameStart = offset + 30
        let payloadStart = nameStart + nameLength + extraLength
        guard nameStart >= 0,
              nameLength >= 0,
              nameStart <= data.count - nameLength,
              String(data: data[nameStart..<(nameStart + nameLength)], encoding: .utf8)
                ?? String(data: data[nameStart..<(nameStart + nameLength)], encoding: .isoLatin1)
                == entry.name,
              payloadStart >= 0,
              entry.compressedSize >= 0,
              payloadStart <= data.count - entry.compressedSize else {
            throw BoundedZIPRewriteError.invalidContainer
        }
        return Data(data[payloadStart..<(payloadStart + entry.compressedSize)])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0xFFFF_FFFF
        for byte in data {
            checksum ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -Int32(checksum & 1))
                checksum = (checksum >> 1) ^ (0xEDB8_8320 & mask)
            }
        }
        return ~checksum
    }

    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
