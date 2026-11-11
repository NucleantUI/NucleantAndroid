//
//  AppFiles.swift
//  AndroidFiles
//
//  The app's own files directory (`Context.getFilesDir()`): private to the
//  app, no permission needed, removed with it. Paths are relative to it and
//  may have subdirectories ("notes/today.txt"); ".." and absolute paths are
//  refused.
//

import AndroidCore
import Observation
import SwiftJava

/// A file or directory in the app's directory.
public final class AFileEntry: Sendable, Identifiable {
    /// Relative to the app's directory.
    public let path: String
    public let name: String
    /// Bytes; for a directory, everything under it.
    public let size: Int64
    public let isDirectory: Bool
    /// Last modified, in milliseconds since 1970-01-01 UTC.
    public let modified: Int64

    public var id: String { path }

    init(path: String, name: String, size: Int64, isDirectory: Bool, modified: Int64) {
        self.path = path
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.modified = modified
    }
}

/// The app's files directory. Create and use it on the main thread; its
/// listing is read again after every change made through it, or `refresh()`.
@Observable
public final class AAppFiles: @unchecked Sendable {
    /// The directory's absolute path.
    public let directory: String
    /// What is directly in it, directories first, then by name.
    public private(set) var entries: [AFileEntry] = []
    /// Bytes used by everything in it.
    public private(set) var usedBytes: Int64 = 0
    /// Free bytes on the volume it is on.
    public private(set) var availableBytes: Int64 = 0

    @ObservationIgnored private let root: File

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        guard let root = try AndroidContext.shared.applicationContext(in: environment).getFilesDir() else {
            throw AndroidError.serviceUnavailable("files directory")
        }
        self.root = root
        directory = root.getAbsolutePath()
        try refresh()
    }

    public func refresh() throws {
        var listed: [AFileEntry] = []
        for file in root.listFiles().compactMap({ $0 }) {
            let isDirectory = file.isDirectory()
            listed.append(AFileEntry(
                path: file.getName(),
                name: file.getName(),
                size: isDirectory ? Self.size(of: file) : file.length(),
                isDirectory: isDirectory,
                modified: file.lastModified()
            ))
        }
        entries = listed.sorted { ($0.isDirectory ? 0 : 1, $0.name) < ($1.isDirectory ? 0 : 1, $1.name) }
        usedBytes = Self.size(of: root)
        availableBytes = root.getUsableSpace()
    }

    /// What is in the subdirectory at `path`.
    public func entries(in path: String) throws -> [AFileEntry] {
        let directory = try file(at: path)
        return directory.listFiles().compactMap { $0 }.map { file in
            let isDirectory = file.isDirectory()
            return AFileEntry(
                path: path + "/" + file.getName(),
                name: file.getName(),
                size: isDirectory ? Self.size(of: file) : file.length(),
                isDirectory: isDirectory,
                modified: file.lastModified()
            )
        }
    }

    /// Write `bytes` to `path`, replacing what is there and making the
    /// directories on the way.
    public func write(_ bytes: [UInt8], to path: String) throws {
        let file = try file(at: path)
        _ = file.getParentFile()?.mkdirs()
        let environment = try JavaVirtualMachine.shared().environment()
        let stream = try FileOutputStream(file, false, environment: environment)
        do {
            try stream.write(bytes)
            try stream.close()
        } catch {
            try? stream.close()
            throw error
        }
        try refresh()
    }

    public func read(_ path: String) throws -> [UInt8] {
        let file = try file(at: path)
        guard file.exists(), !file.isDirectory() else {
            throw AFilesError.notFound(path)
        }
        let environment = try JavaVirtualMachine.shared().environment()
        return try JavaClass<JavaFiles>(environment: environment).readAllBytes(file.toPath())
    }

    public func exists(_ path: String) throws -> Bool {
        try file(at: path).exists()
    }

    /// Delete the file, or the directory and everything in it.
    public func delete(_ path: String) throws {
        let file = try file(at: path)
        guard file.exists() else {
            throw AFilesError.notFound(path)
        }
        guard Self.delete(file) else {
            throw AFilesError.deleteFailed(path)
        }
        try refresh()
    }

    // MARK: - Paths

    private func file(at path: String) throws -> File {
        guard Self.isValid(path) else {
            throw AFilesError.invalidPath(path)
        }
        let environment = try JavaVirtualMachine.shared().environment()
        return File(root, path, environment: environment)
    }

    /// Relative, non-empty, and staying inside the directory.
    static func isValid(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.hasPrefix("/") && !parts.contains { $0 == ".." || $0 == "." || $0.isEmpty }
    }

    private static func size(of file: File) -> Int64 {
        guard file.isDirectory() else { return file.length() }
        return file.listFiles().compactMap { $0 }.reduce(0) { $0 + size(of: $1) }
    }

    private static func delete(_ file: File) -> Bool {
        if file.isDirectory() {
            for child in file.listFiles().compactMap({ $0 }) where !delete(child) {
                return false
            }
        }
        return file.delete()
    }
}

public enum AFilesError: Error, CustomStringConvertible {
    case invalidPath(String)
    case notFound(String)
    case deleteFailed(String)

    public var description: String {
        switch self {
        case .invalidPath(let path): "\"\(path)\" is not a path inside the app's directory"
        case .notFound(let path): "Nothing at \"\(path)\""
        case .deleteFailed(let path): "\"\(path)\" could not be deleted"
        }
    }
}

// MARK: - Framework

extension Context {
    @JavaMethod
    public func getFilesDir() -> File!
}

/// `java.io.File`.
@JavaClass("java.io.File")
open class File: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ parent: File?, _ child: String, environment: JNIEnvironment? = nil)

    @JavaMethod open func getName() -> String
    @JavaMethod open func getAbsolutePath() -> String
    @JavaMethod open func getParentFile() -> File!
    @JavaMethod open func exists() -> Bool
    @JavaMethod open func isDirectory() -> Bool
    @JavaMethod open func length() -> Int64
    @JavaMethod open func lastModified() -> Int64
    @JavaMethod open func listFiles() -> [File?]
    @JavaMethod open func mkdirs() -> Bool
    @JavaMethod open func delete() -> Bool
    @JavaMethod open func getUsableSpace() -> Int64
    @JavaMethod open func toPath() -> JavaPath!
}

/// `java.nio.file.Path`.
@JavaInterface("java.nio.file.Path")
public struct JavaPath {}

/// `java.nio.file.Files`, API 26.
@JavaClass("java.nio.file.Files")
open class JavaFiles: JavaObject {}

extension JavaClass<JavaFiles> {
    @JavaStaticMethod
    public func readAllBytes(_ path: JavaPath?) throws -> [UInt8]
}

/// `java.io.FileOutputStream`.
@JavaClass("java.io.FileOutputStream")
open class FileOutputStream: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ file: File?, _ append: Bool, environment: JNIEnvironment? = nil) throws

    @JavaMethod
    open func write(_ bytes: [UInt8]) throws

    @JavaMethod
    open func close() throws
}
