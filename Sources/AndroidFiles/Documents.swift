//
//  Documents.swift
//  AndroidFiles
//
//  Files outside the app, through the system's document pickers (the Storage
//  Access Framework): the user picks a file to open, or a place and name to
//  save one. No permission needed — the app gets access to exactly what was
//  picked. Answers come through `onActivityResult`, which the host forwards to
//  `AndroidContext.handleActivityResult`.
//

import AndroidCore
import Observation
import SwiftJava

/// The document pickers. Create and use it on the main thread.
@Observable
public final class ADocuments: @unchecked Sendable {
    /// Documents opened or created through it, newest first.
    public private(set) var recent: [ADocument] = []

    public init() {}

    /// Let the user pick a file to open, of one of `mimeTypes` ("image/*",
    /// "text/plain"; empty for any). Nil when they cancelled.
    public func open(mimeTypes: [String] = []) async throws -> ADocument? {
        let environment = try JavaVirtualMachine.shared().environment()
        let intent = Intent("android.intent.action.OPEN_DOCUMENT", environment: environment)
        _ = intent.addCategory("android.intent.category.OPENABLE")
        _ = intent.setType(mimeTypes.count == 1 ? mimeTypes[0] : "*/*")
        if mimeTypes.count > 1 {
            _ = intent.putExtra("android.intent.extra.MIME_TYPES", mimeTypes)
        }
        return try await pick(intent)
    }

    /// Let the user choose where to save a new `mimeType` file, suggesting
    /// `name`. Nil when they cancelled; otherwise an empty document to `write` to.
    public func create(name: String, mimeType: String) async throws -> ADocument? {
        let environment = try JavaVirtualMachine.shared().environment()
        let intent = Intent("android.intent.action.CREATE_DOCUMENT", environment: environment)
        _ = intent.addCategory("android.intent.category.OPENABLE")
        _ = intent.setType(mimeType)
        _ = intent.putExtra("android.intent.extra.TITLE", JavaString(name, environment: environment))
        return try await pick(intent)
    }

    private func pick(_ intent: Intent) async throws -> ADocument? {
        let result = try await AndroidContext.shared.startActivityForResult(intent)
        guard result.isOK, let data = result.data else { return nil }
        return try await AndroidMainThread.shared.run { environment in
            guard let uri = data.wrapped(as: Intent.self, in: environment).getData() else {
                throw AndroidError.unexpectedResult("The document picker sent back no document")
            }
            let document = try ADocument(uri: uri, in: environment)
            self.recent.insert(document, at: 0)
            return document
        }
    }
}

/// A document the user picked. Its state changes on the main thread.
@Observable
public final class ADocument: Identifiable, @unchecked Sendable {
    /// Its content:// URI.
    @ObservationIgnored public let uri: Uri
    public let mimeType: String
    public private(set) var name: String
    /// Bytes; nil when the provider does not say.
    public private(set) var size: Int64?

    public var id: String { uri.toString() }

    init(uri: Uri, in environment: JNIEnvironment) throws {
        self.uri = uri
        mimeType = try documentResolver(in: environment).getType(uri)
        name = uri.getLastPathSegment()
        try refresh()
    }

    /// Read its name and size from the provider again.
    public func refresh() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let resolver = try documentResolver(in: environment)
        guard let cursor = try resolver.query(uri, ["_display_name", "_size"], nil, [], nil) else { return }
        defer { cursor.close() }
        guard cursor.moveToNext() else { return }
        let nameColumn = try cursor.getColumnIndexOrThrow("_display_name")
        let sizeColumn = try cursor.getColumnIndexOrThrow("_size")
        name = cursor.getString(nameColumn)
        size = cursor.isNull(sizeColumn) ? nil : cursor.getLong(sizeColumn)
    }

    /// The document's bytes, read off the main thread.
    public func read() async throws -> [UInt8] {
        let environment = try JavaVirtualMachine.shared().environment()
        guard let file = try documentResolver(in: environment).openFileDescriptor(try uri.boundToCurrentThread(), "r") else {
            throw AFilesError.notFound(name)
        }
        return try readAll(fileDescriptor: file.detachFd())
    }

    /// Replace the document's contents with `bytes`, off the main thread.
    public func write(_ bytes: [UInt8]) async throws {
        let environment = try JavaVirtualMachine.shared().environment()
        // "wt": write, truncating what was there.
        guard let file = try documentResolver(in: environment).openFileDescriptor(try uri.boundToCurrentThread(), "wt") else {
            throw AFilesError.notFound(name)
        }
        try writeAll(bytes, fileDescriptor: file.detachFd())
        try await AndroidMainThread.shared.run { _ in try self.refresh() }
    }
}

private func documentResolver(in environment: JNIEnvironment) throws -> DocumentResolver {
    guard let resolver = try AndroidContext.shared.applicationContext(in: environment).getDocumentResolver() else {
        throw AndroidError.serviceUnavailable("content resolver")
    }
    return resolver
}

// MARK: - Framework

extension Context {
    /// `getContentResolver()`, as this module's wrapper of it.
    @JavaMethod("getContentResolver")
    func getDocumentResolver() -> DocumentResolver!
}

/// `android.content.ContentResolver`: what documents need of it.
@JavaClass("android.content.ContentResolver")
open class DocumentResolver: JavaObject {
    @JavaMethod
    open func query(
        _ uri: Uri?, _ projection: [String], _ selection: JavaString?, _ selectionArgs: [String], _ sortOrder: JavaString?
    ) throws -> DocumentCursor!

    @JavaMethod
    open func openFileDescriptor(_ uri: Uri?, _ mode: String) throws -> DocumentFileDescriptor!

    @JavaMethod
    open func getType(_ uri: Uri?) -> String
}

/// `android.database.Cursor`: what documents need of it.
@JavaInterface("android.database.Cursor")
public struct DocumentCursor {
    @JavaMethod public func moveToNext() -> Bool
    @JavaMethod public func getColumnIndexOrThrow(_ columnName: String) throws -> Int32
    @JavaMethod public func getLong(_ columnIndex: Int32) -> Int64
    @JavaMethod public func getString(_ columnIndex: Int32) -> String
    @JavaMethod public func isNull(_ columnIndex: Int32) -> Bool
    @JavaMethod public func close()
}

/// `android.os.ParcelFileDescriptor`.
@JavaClass("android.os.ParcelFileDescriptor")
open class DocumentFileDescriptor: JavaObject {
    @JavaMethod
    open func detachFd() -> Int32
}
