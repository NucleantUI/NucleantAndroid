//
//  FileDescriptorIO.swift
//  AndroidCore
//
//  Reading and writing the file descriptors ContentResolver hands out
//  (`ParcelFileDescriptor.detachFd()`: MediaStore photos, picked documents),
//  with the C library directly: the bytes go straight into Swift memory
//  instead of through Java byte arrays.
//
//  The C library's module is `Android` on Android; the other two are only here
//  so the package also compiles on the host it is developed on.
//

#if canImport(Android)
import Android
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Read `descriptor` to its end, and close it.
public func readAll(fileDescriptor descriptor: Int32) throws -> [UInt8] {
    defer { _ = close(descriptor) }
    var result: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 256 * 1024)
    while true {
        let count = chunk.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
        if count < 0 {
            if errno == EINTR { continue }
            throw AndroidError.io(errno)
        }
        if count == 0 {
            return result
        }
        result.append(contentsOf: chunk[0..<count])
    }
}

/// Write all of `bytes` to `descriptor`, and close it.
public func writeAll(_ bytes: [UInt8], fileDescriptor descriptor: Int32) throws {
    var written = 0
    defer { _ = close(descriptor) }
    try bytes.withUnsafeBytes { buffer in
        while written < buffer.count {
            let count = write(descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
            if count < 0 {
                if errno == EINTR { continue }
                throw AndroidError.io(errno)
            }
            written += count
        }
    }
}
