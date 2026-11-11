//
//  Framework.swift
//  AndroidPhotos
//
//  swift-java wrappers for the MediaStore side of the Android framework:
//  ContentResolver, its Cursor, and the Bitmap/stream classes a thumbnail goes
//  through. Only what APhotoLibrary and APhotoAsset call is declared. Parameters Java allows to
//  be null and Swift passes nil for are `JavaString?` rather than `String`,
//  because swift-java has no null for a plain `String`.
//

import AndroidCore
import SwiftJava

// MARK: - android.content

/// `android.content.ContentResolver`.
@JavaClass("android.content.ContentResolver")
open class ContentResolver: JavaObject {
    @JavaMethod
    open func query(
        _ uri: Uri?,
        _ projection: [String],
        _ selection: JavaString?,
        _ selectionArgs: [String],
        _ sortOrder: JavaString?
    ) throws -> Cursor!

    @JavaMethod
    open func insert(_ uri: Uri?, _ values: ContentValues?) throws -> Uri!

    @JavaMethod
    open func update(_ uri: Uri?, _ values: ContentValues?, _ selection: JavaString?, _ selectionArgs: [String]) throws -> Int32

    @JavaMethod
    open func delete(_ uri: Uri?, _ selection: JavaString?, _ selectionArgs: [String]) throws -> Int32

    @JavaMethod
    open func registerContentObserver(_ uri: Uri?, _ notifyForDescendants: Bool, _ observer: ContentObserver?) throws

    @JavaMethod
    open func unregisterContentObserver(_ observer: ContentObserver?) throws

    @JavaMethod
    open func openFileDescriptor(_ uri: Uri?, _ mode: String) throws -> ParcelFileDescriptor!

    /// The MIME type of `uri`, or "" when unknown.
    @JavaMethod
    open func getType(_ uri: Uri?) -> String

    /// API 29.
    @JavaMethod
    open func loadThumbnail(_ uri: Uri?, _ size: Size?, _ signal: CancellationSignal?) throws -> Bitmap!
}

extension Context {
    @JavaMethod
    public func getContentResolver() -> ContentResolver!
}

/// `android.content.ContentValues`.
@JavaClass("android.content.ContentValues")
open class ContentValues: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(environment: JNIEnvironment? = nil)

    @JavaMethod
    open func put(_ key: String, _ value: JavaString?)

    @JavaMethod
    open func put(_ key: String, _ value: JavaInteger?)
}

/// `android.content.ContentUris`.
@JavaClass("android.content.ContentUris")
open class ContentUris: JavaObject {}

extension JavaClass<ContentUris> {
    @JavaStaticMethod
    public func withAppendedId(_ contentUri: Uri?, _ id: Int64) -> Uri!
}

// MARK: - android.database

/// `android.database.ContentObserver`.
@JavaClass("android.database.ContentObserver")
open class ContentObserver: JavaObject {}

/// `android.database.Cursor`.
@JavaInterface("android.database.Cursor")
public struct Cursor {
    @JavaMethod
    public func moveToNext() -> Bool

    @JavaMethod
    public func getColumnIndexOrThrow(_ columnName: String) throws -> Int32

    @JavaMethod
    public func getLong(_ columnIndex: Int32) -> Int64

    @JavaMethod
    public func getInt(_ columnIndex: Int32) -> Int32

    /// Null comes back as "".
    @JavaMethod
    public func getString(_ columnIndex: Int32) -> String

    @JavaMethod
    public func isNull(_ columnIndex: Int32) -> Bool

    @JavaMethod
    public func close()
}

// MARK: - android.provider

/// `android.provider.MediaStore.Images.Media`.
@JavaClass("android.provider.MediaStore$Images$Media")
open class MediaStoreImagesMedia: JavaObject {}

extension JavaClass<MediaStoreImagesMedia> {
    @JavaStaticField(isFinal: true)
    public var EXTERNAL_CONTENT_URI: Uri!
}

// MARK: - android.os

/// `android.os.ParcelFileDescriptor`.
@JavaClass("android.os.ParcelFileDescriptor")
open class ParcelFileDescriptor: JavaObject {
    /// Take the file descriptor over: closing it becomes the caller's job.
    @JavaMethod
    open func detachFd() -> Int32
}

// MARK: - android.graphics

/// `android.graphics.Bitmap`.
@JavaClass("android.graphics.Bitmap")
open class Bitmap: JavaObject {
    @JavaMethod
    open func compress(_ format: BitmapCompressFormat?, _ quality: Int32, _ stream: OutputStream?) -> Bool

    @JavaMethod
    open func recycle()

    @JavaMethod
    open func getWidth() -> Int32

    @JavaMethod
    open func getHeight() -> Int32

    @JavaMethod
    open func getRowBytes() -> Int32

    @JavaMethod
    open func getByteCount() -> Int32

    @JavaMethod
    open func copyPixelsToBuffer(_ destination: JavaNioBufferObject?) throws
}

extension JavaClass<Bitmap> {
    @JavaStaticMethod
    public func createBitmap(
        _ source: Bitmap?, _ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32, _ matrix: Matrix?, _ filter: Bool
    ) throws -> Bitmap!
}

/// `android.graphics.Bitmap.CompressFormat` (an enum; its constants are static fields).
@JavaClass("android.graphics.Bitmap$CompressFormat")
open class BitmapCompressFormat: JavaObject {}

extension JavaClass<BitmapCompressFormat> {
    @JavaStaticField(isFinal: true)
    public var JPEG: BitmapCompressFormat!
}

// MARK: - java.io

/// `java.io.OutputStream`.
@JavaClass("java.io.OutputStream")
open class OutputStream: JavaObject {}

/// `java.io.ByteArrayOutputStream`.
@JavaClass("java.io.ByteArrayOutputStream")
open class ByteArrayOutputStream: OutputStream {
    @JavaMethod
    @_nonoverride public convenience init(environment: JNIEnvironment? = nil)

    @JavaMethod
    open func toByteArray() -> [UInt8]
}
