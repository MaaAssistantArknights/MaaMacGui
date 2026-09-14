//
//  ByteReader.swift
//  MAA
//
//  Created by hguandl on 2026/8/28.
//

import Foundation

struct ByteReader<Bytes: ContiguousBytes> {
    private let bytes: Bytes
    private var offset = 0

    init(_ bytes: Bytes) {
        self.bytes = bytes
    }

    struct OutOfBoundsError: Error {
    }

    mutating func read<R>(_ count: Int, _ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        guard count >= 0 else {
            throw OutOfBoundsError()
        }
        let result = try bytes.withUnsafeBytes { buffer in
            guard offset <= buffer.count,
                count <= buffer.count - offset
            else {
                throw OutOfBoundsError()
            }
            let slice = UnsafeRawBufferPointer(rebasing: buffer[offset..<offset + count])
            return try body(slice)
        }
        offset += count
        return result
    }

    mutating func read<T: FixedWidthInteger>(_ type: T.Type = T.self) throws -> T {
        try read(MemoryLayout<T>.size) {
            T(bigEndian: $0.loadUnaligned(as: T.self))
        }
    }
}
