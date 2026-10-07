import Foundation

/// Reads only headers/load commands; never maps, loads or executes the game binary.
enum MachOLibraries {
    private static let arm64: UInt32 = 0x0100_000c
    private static let maximumCommandsBytes = 1024 * 1024

    static func read(at url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        return try parse(length: length) { offset, count in
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw PlayCoverInspectionError.invalidExecutable
            }
            return data
        }
    }

    static func read(_ data: Data) throws -> [String] {
        try parse(length: UInt64(data.count)) { offset, count in
            Data(data[Int(offset)..<(Int(offset) + count)])
        }
    }

    private static func parse(length: UInt64, read: (UInt64, Int) throws -> Data) throws -> [String] {
        func bytes(_ offset: UInt64, _ count: Int, limit: UInt64) throws -> Data {
            guard count >= 0, offset <= limit, UInt64(count) <= limit - offset, limit <= length else {
                throw PlayCoverInspectionError.invalidExecutable
            }
            return count == 0 ? Data() : try read(offset, count)
        }
        func number<T: FixedWidthInteger>(_ data: Data, _ offset: Int, little: Bool, as: T.Type = T.self) -> T {
            data.withUnsafeBytes {
                let value = $0.loadUnaligned(fromByteOffset: offset, as: T.self)
                return little ? T(littleEndian: value) : T(bigEndian: value)
            }
        }
        func slice(_ base: UInt64, limit: UInt64) throws -> [String] {
            let header = try bytes(base, 32, limit: limit)
            let magic: UInt32 = number(header, 0, little: true)
            let little = magic == 0xfeed_facf
            guard little || magic == 0xcffa_edfe,
                number(header, 4, little: little, as: UInt32.self) == arm64
            else {
                throw PlayCoverInspectionError.invalidExecutable
            }
            let count = Int(number(header, 16, little: little, as: UInt32.self))
            let length = Int(number(header, 20, little: little, as: UInt32.self))
            guard count <= length / 8, UInt64(length) <= limit - base - 32 else {
                throw PlayCoverInspectionError.invalidExecutable
            }
            guard length <= maximumCommandsBytes else { throw PlayCoverInspectionError.oversizedLoadCommands }
            let commands = try bytes(base + 32, length, limit: limit)
            var offset = 0
            var names = [String]()
            for _ in 0..<count {
                guard offset <= commands.count - 8 else { throw PlayCoverInspectionError.invalidExecutable }
                let kind: UInt32 = number(commands, offset, little: little)
                let size = Int(number(commands, offset + 4, little: little, as: UInt32.self))
                guard size >= 8, size <= commands.count - offset else {
                    throw PlayCoverInspectionError.invalidExecutable
                }
                if [UInt32(0xc), 0x8000_0018, 0x8000_001f, 0x20, 0x8000_0023].contains(kind) {
                    guard size >= 24 else { throw PlayCoverInspectionError.invalidExecutable }
                    let nameOffset = Int(number(commands, offset + 8, little: little, as: UInt32.self))
                    guard nameOffset >= 24, nameOffset < size else { throw PlayCoverInspectionError.invalidExecutable }
                    let nameBytes = commands[(offset + nameOffset)..<(offset + size)]
                    guard let terminator = nameBytes.firstIndex(of: 0),
                        let name = String(data: nameBytes[..<terminator], encoding: .utf8), !name.isEmpty
                    else {
                        throw PlayCoverInspectionError.invalidExecutable
                    }
                    names.append(name)
                }
                offset += size
            }
            guard offset == commands.count else { throw PlayCoverInspectionError.invalidExecutable }
            return names
        }
        let magicData = try bytes(0, 8, limit: length)
        let magic: UInt32 = number(magicData, 0, little: false)
        if [UInt32(0xcafe_babe), 0xbeba_feca, 0xcafe_babf, 0xbfba_feca].contains(magic) {
            let little = magic == 0xbeba_feca || magic == 0xbfba_feca
            let is64 = magic == 0xcafe_babf || magic == 0xbfba_feca
            let count = Int(number(magicData, 4, little: little, as: UInt32.self))
            guard count > 0, count <= 32 else { throw PlayCoverInspectionError.invalidExecutable }
            let entrySize = is64 ? 32 : 20
            let table = try bytes(8, count * entrySize, limit: length)
            for index in 0..<count {
                let entry = index * entrySize
                guard number(table, entry, little: little, as: UInt32.self) == arm64 else { continue }
                let offset =
                    is64
                    ? number(table, entry + 8, little: little, as: UInt64.self)
                    : UInt64(number(table, entry + 8, little: little, as: UInt32.self))
                let size =
                    is64
                    ? number(table, entry + 16, little: little, as: UInt64.self)
                    : UInt64(number(table, entry + 12, little: little, as: UInt32.self))
                guard offset >= UInt64(8 + count * entrySize), offset <= length, size <= length - offset else {
                    throw PlayCoverInspectionError.invalidExecutable
                }
                return try slice(offset, limit: offset + size)
            }
            throw PlayCoverInspectionError.invalidExecutable
        }
        return try slice(0, limit: length)
    }
}
