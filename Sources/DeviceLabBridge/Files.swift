//
//  Files.swift
//  DeviceLabBridge
//
//  AndroidFiles for Kotlin.
//

import AndroidCore
import AndroidFiles
import Observation
import SwiftJava

public final class LabAppFiles: @unchecked Sendable {
    let files: AAppFiles
    let observer = ChangeObserver()

    public init() throws {
        files = try AAppFiles()
    }

    public var directory: String { files.directory }
    public var entries: [LabFileEntry] { files.entries.map(LabFileEntry.init) }
    public var usedBytes: Int64 { files.usedBytes }
    public var availableBytes: Int64 { files.availableBytes }

    public func writeText(path: String, text: String) throws { try files.write(Array(text.utf8), to: path) }
    public func readText(path: String) throws -> String { String(decoding: try files.read(path), as: UTF8.self) }
    public func delete(path: String) throws { try files.delete(path) }
    public func refresh() throws { try files.refresh() }

    public func observe(listener: JavaObject) {
        observer.observe({ [files] in _ = (files.entries, files.usedBytes, files.availableBytes) }, listener: listener)
    }
}

public final class LabFileEntry: @unchecked Sendable {
    let entry: AFileEntry

    init(_ entry: AFileEntry) {
        self.entry = entry
    }

    public var path: String { entry.path }
    public var name: String { entry.name }
    public var size: Int64 { entry.size }
    public var isDirectory: Bool { entry.isDirectory }
    /// Milliseconds since 1970.
    public var modified: Int64 { entry.modified }
}

public final class LabDocuments: @unchecked Sendable {
    let documents = ADocuments()
    let observer = ChangeObserver()

    public init() {}

    public var recent: [LabDocument] { documents.recent.map(LabDocument.init) }

    /// `mimeTypes` empty for any file. Nil when cancelled.
    public func open(mimeTypes: [String]) async throws -> LabDocument? {
        try await documents.open(mimeTypes: mimeTypes).map(LabDocument.init)
    }

    /// Nil when cancelled.
    public func create(name: String, mimeType: String) async throws -> LabDocument? {
        try await documents.create(name: name, mimeType: mimeType).map(LabDocument.init)
    }

    public func observe(listener: JavaObject) {
        observer.observe({ [documents] in _ = documents.recent }, listener: listener)
    }
}

public final class LabDocument: @unchecked Sendable {
    let document: ADocument
    let observer = ChangeObserver()

    init(_ document: ADocument) {
        self.document = document
    }

    public var name: String { document.name }
    public var mimeType: String { document.mimeType }
    /// Bytes; -1 when the provider does not say.
    public var size: Int64 { document.size ?? -1 }
    public var uri: String { document.id }

    public func read() async throws -> [UInt8] { try await document.read() }
    public func readText() async throws -> String { String(decoding: try await document.read(), as: UTF8.self) }
    public func writeText(text: String) async throws { try await document.write(Array(text.utf8)) }

    public func observe(listener: JavaObject) {
        observer.observe({ [document] in _ = (document.name, document.size) }, listener: listener)
    }
}
