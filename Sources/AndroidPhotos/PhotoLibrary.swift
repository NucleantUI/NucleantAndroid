//
//  PhotoLibrary.swift
//  AndroidPhotos
//
//  The device's photos, through MediaStore.
//
//  Reading other apps' photos needs the media permission — READ_MEDIA_IMAGES
//  from Android 13, READ_EXTERNAL_STORAGE before — declared in the manifest and
//  granted at run time (`requestAuthorization()`). From Android 14 the user may
//  grant a selection only (READ_MEDIA_VISUAL_USER_SELECTED): `.limited`.
//  Photos the app saved itself are visible without any permission, and saving
//  needs none from Android 10, the oldest Android `save` supports.
//

import AndroidCore
import Observation
import SwiftJava

/// How much of the library the app may read.
public enum APhotoLibraryAuthorization: Sendable, Hashable {
    case authorized
    /// Only the photos the user picked.
    case limited
    /// Only the photos the app saved itself.
    case denied
}

// MARK: - APhotoLibrary

/// The newest photos in the library, kept current: MediaStore tells it about
/// every change (another app's new photo, one deleted in the gallery, one this
/// app saved), and `photos` is read again. Create and use it on the main
/// thread, where those changes arrive.
@Observable
public final class APhotoLibrary: @unchecked Sendable {
    /// Saved photos go into Pictures/`album`.
    public let album: String
    /// How many of the newest photos `photos` holds.
    public let limit: Int

    public private(set) var authorization: APhotoLibraryAuthorization
    /// Newest first. A photo keeps its `APhotoAsset` object across updates.
    public private(set) var photos: [APhotoAsset] = []

    @ObservationIgnored private let resolver: ContentResolver
    @ObservationIgnored private let imagesURI: Uri
    @ObservationIgnored private let sdkLevel: Int
    @ObservationIgnored private var observer: MediaObserver?
    @ObservationIgnored private var handle: Int64 = 0

    public init(album: String, limit: Int = 100) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        guard let resolver = try AndroidContext.shared.applicationContext(in: environment).getContentResolver(),
              let imagesURI = try JavaClass<MediaStoreImagesMedia>(environment: environment).EXTERNAL_CONTENT_URI
        else {
            throw AndroidError.serviceUnavailable("media store")
        }
        self.album = album
        self.limit = limit
        self.resolver = resolver
        self.imagesURI = imagesURI
        self.sdkLevel = try AndroidContext.shared.sdkLevel(in: environment)
        self.authorization = try Self.currentAuthorization(sdkLevel: sdkLevel)

        let handle = NativeHandle.retain(self)
        let observer = MediaObserver(handle, try AndroidMainThread.shared.mainHandler(in: environment), environment: environment)
        self.handle = handle
        self.observer = observer
        try resolver.registerContentObserver(imagesURI, true, observer)
        try refresh()
    }

    deinit {
        guard let observer else { return }
        let mediaObserver = JavaGlobalReference(observer)
        let resolver = JavaGlobalReference(self.resolver)
        let handle = self.handle
        try? AndroidMainThread.shared.post { environment in
            let observer = mediaObserver.wrapped(as: MediaObserver.self, in: environment)
            observer.disarm()
            try? resolver.wrapped(as: ContentResolver.self, in: environment).unregisterContentObserver(observer)
            NativeHandle<APhotoLibrary>.release(handle)
        }
    }

    // MARK: - Access

    /// Ask the user for access to their photos, if not granted yet.
    public func requestAuthorization() async throws -> APhotoLibraryAuthorization {
        let sdkLevel = self.sdkLevel
        let granted = try await AndroidContext.shared.requestPermissions(Self.permissions(sdkLevel: sdkLevel))
        let authorization = Self.authorization(sdkLevel: sdkLevel, granted: granted)
        try await AndroidMainThread.shared.run { _ in
            self.authorization = authorization
            // What the app can see just changed.
            try self.refresh()
        }
        return authorization
    }

    // MARK: - Reading

    /// Read the newest `limit` photos again. Runs by itself whenever MediaStore
    /// reports a change.
    public func refresh() throws {
        authorization = try Self.currentAuthorization(sdkLevel: sdkLevel)
        let environment = try JavaVirtualMachine.shared().environment()
        let order = JavaString("date_added DESC", environment: environment)
        guard let cursor = try resolver.query(imagesURI, Self.columns, nil, [], order) else {
            photos = []
            return
        }
        let uris = try JavaClass<ContentUris>(environment: environment)
        var updated: [APhotoAsset] = []
        for row in try Self.rows(from: cursor, limit: limit) {
            if let existing = photos.first(where: { $0.id == row.id }) {
                updated.append(existing)
            } else if let uri = uris.withAppendedId(imagesURI, row.id) {
                updated.append(APhotoAsset(row, uri: uri))
            }
        }
        photos = updated
    }

    // MARK: - Saving

    /// Add a JPEG to the library, in Pictures/`album`. Android 10+.
    ///
    /// `rotation` is recorded with it (degrees clockwise to show it upright),
    /// for photos stored the way the sensor produced them. The file is written
    /// off the main thread; the photo is in `photos` when this returns.
    @discardableResult
    public func save(jpeg: [UInt8], name: String, rotation: Int = 0) async throws -> APhotoAsset {
        guard sdkLevel >= 29 else {
            throw AndroidError.requiresSDK(29)
        }
        let id = try saveFile(jpeg: jpeg, name: name, rotation: rotation)
        return try await AndroidMainThread.shared.run { _ in
            try self.refresh()
            guard let asset = self.photos.first(where: { $0.id == id }) else {
                throw APhotoLibraryError.notFound(String(id))
            }
            return asset
        }
    }

    /// The resolver, for the calling thread.
    func contentResolverForThread() throws -> ContentResolver {
        try resolver.boundToCurrentThread()
    }

    /// MediaStore's images URI, for the calling thread.
    func imagesURIForThread() throws -> Uri {
        try imagesURI.boundToCurrentThread()
    }

    /// Insert, write, publish; on the calling thread. The new photo's id.
    private func saveFile(jpeg: [UInt8], name: String, rotation: Int) throws -> Int64 {
        let environment = try JavaVirtualMachine.shared().environment()
        let resolver = try self.resolver.boundToCurrentThread()
        let integers = try JavaClass<JavaInteger>(environment: environment)
        func text(_ value: String) -> JavaString { JavaString(value, environment: environment) }

        // Pending while it is written, so no other app sees a half-written file.
        let values = ContentValues(environment: environment)
        values.put("_display_name", text(name))
        values.put("mime_type", text("image/jpeg"))
        values.put("relative_path", text("Pictures/\(album)"))
        values.put("orientation", integers.valueOf(Int32(rotation)))
        values.put("is_pending", integers.valueOf(1))
        guard let uri = try resolver.insert(try imagesURI.boundToCurrentThread(), values) else {
            throw APhotoLibraryError.insertFailed
        }
        do {
            guard let file = try resolver.openFileDescriptor(uri, "w") else {
                throw APhotoLibraryError.insertFailed
            }
            try writeAll(jpeg, fileDescriptor: file.detachFd())
            let published = ContentValues(environment: environment)
            published.put("is_pending", integers.valueOf(0))
            _ = try resolver.update(uri, published, nil, [])
        } catch {
            _ = try? resolver.delete(uri, nil, [])
            throw error
        }
        guard let id = Int64(uri.getLastPathSegment()) else {
            throw APhotoLibraryError.insertFailed
        }
        return id
    }

    // MARK: - MediaStore

    static let columns = ["_id", "_display_name", "width", "height", "orientation", "datetaken", "mime_type"]

    typealias Row = (
        id: Int64, name: String, width: Int, height: Int, rotation: Int, creationTime: Int64?, mimeType: String
    )

    /// Up to `limit` rows of `columns`; closes the cursor.
    static func rows(from cursor: Cursor, limit: Int) throws -> [Row] {
        defer { cursor.close() }
        let id = try cursor.getColumnIndexOrThrow("_id")
        let name = try cursor.getColumnIndexOrThrow("_display_name")
        let width = try cursor.getColumnIndexOrThrow("width")
        let height = try cursor.getColumnIndexOrThrow("height")
        let orientation = try cursor.getColumnIndexOrThrow("orientation")
        let taken = try cursor.getColumnIndexOrThrow("datetaken")
        let mimeType = try cursor.getColumnIndexOrThrow("mime_type")

        var rows: [Row] = []
        while rows.count < limit, cursor.moveToNext() {
            rows.append((
                id: cursor.getLong(id),
                name: cursor.getString(name),
                width: Int(cursor.getInt(width)),
                height: Int(cursor.getInt(height)),
                rotation: Int(cursor.getInt(orientation)),
                creationTime: cursor.isNull(taken) ? nil : cursor.getLong(taken),
                mimeType: cursor.getString(mimeType)
            ))
        }
        return rows
    }

    // MARK: - Permissions

    static let readMediaImages = "android.permission.READ_MEDIA_IMAGES"
    static let readMediaVisualUserSelected = "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
    static let readExternalStorage = "android.permission.READ_EXTERNAL_STORAGE"

    /// The runtime permissions that stand for photo access on `sdkLevel`.
    static func permissions(sdkLevel: Int) -> [String] {
        if sdkLevel >= 34 {
            // Both, so the system offers "Select photos" as well as "Allow all".
            return [readMediaImages, readMediaVisualUserSelected]
        }
        if sdkLevel >= 33 {
            return [readMediaImages]
        }
        return [readExternalStorage]
    }

    /// What a set of answers to `permissions(sdkLevel:)` amounts to.
    static func authorization(sdkLevel: Int, granted: [String: Bool]) -> APhotoLibraryAuthorization {
        if sdkLevel >= 33 {
            if granted[readMediaImages] == true {
                return .authorized
            }
            if sdkLevel >= 34, granted[readMediaVisualUserSelected] == true {
                return .limited
            }
            return .denied
        }
        return granted[readExternalStorage] == true ? .authorized : .denied
    }

    static func currentAuthorization(sdkLevel: Int) throws -> APhotoLibraryAuthorization {
        var granted: [String: Bool] = [:]
        for permission in permissions(sdkLevel: sdkLevel) {
            granted[permission] = try AndroidContext.shared.isGranted(permission)
        }
        return authorization(sdkLevel: sdkLevel, granted: granted)
    }
}

// MARK: - APhotoAsset

/// A photo in the library.
@Observable
public final class APhotoAsset: Identifiable, @unchecked Sendable {
    /// MediaStore's id for it.
    public let id: Int64
    /// Its content:// URI.
    @ObservationIgnored public let uri: Uri
    public let name: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Degrees to rotate the stored image clockwise to show it upright.
    public let rotation: Int
    /// When it was taken, in milliseconds since 1970-01-01 UTC, if known.
    public let creationTime: Int64?
    public let mimeType: String

    /// A JPEG thumbnail, once `loadThumbnail(maxPixelSize:)` has run.
    public private(set) var thumbnail: [UInt8]?

    init(_ row: APhotoLibrary.Row, uri: Uri) {
        self.id = row.id
        self.uri = uri
        self.name = row.name
        self.pixelWidth = row.width
        self.pixelHeight = row.height
        self.rotation = row.rotation
        self.creationTime = row.creationTime
        self.mimeType = row.mimeType
    }

    /// Make a JPEG thumbnail at most `maxPixelSize` on its longer side, upright,
    /// off the main thread, and keep it in `thumbnail`. Android 10+.
    @discardableResult
    public func loadThumbnail(maxPixelSize: Int) async throws -> [UInt8] {
        let environment = try JavaVirtualMachine.shared().environment()
        guard try AndroidContext.shared.sdkLevel(in: environment) >= 29 else {
            throw AndroidError.requiresSDK(29)
        }
        let side = Int32(clamping: maxPixelSize)
        guard let bitmap = try contentResolver(in: environment).loadThumbnail(
            try uri.boundToCurrentThread(), Size(side, side, environment: environment), nil
        ) else {
            throw APhotoLibraryError.notFound(String(id))
        }
        defer { bitmap.recycle() }
        let stream = ByteArrayOutputStream(environment: environment)
        guard bitmap.compress(try JavaClass<BitmapCompressFormat>(environment: environment).JPEG, 85, stream) else {
            throw APhotoLibraryError.encodingFailed
        }
        let jpeg = stream.toByteArray()
        try await AndroidMainThread.shared.run { _ in self.thumbnail = jpeg }
        return jpeg
    }

    /// The photo's file as stored (JPEG, HEIF, PNG, …: see `mimeType`), read
    /// off the main thread.
    public func imageData() async throws -> [UInt8] {
        let environment = try JavaVirtualMachine.shared().environment()
        guard let file = try contentResolver(in: environment).openFileDescriptor(try uri.boundToCurrentThread(), "r") else {
            throw APhotoLibraryError.notFound(String(id))
        }
        return try readAll(fileDescriptor: file.detachFd())
    }

    /// The photo decoded to pixels, upright, at most `maxPixelSize` on its
    /// longer side; read and decoded off the main thread.
    public func decode(maxPixelSize: Int) async throws -> APixelBuffer {
        try decodePixels(try await imageData(), maxPixelSize: maxPixelSize, rotation: rotation)
    }

    private func contentResolver(in environment: JNIEnvironment) throws -> ContentResolver {
        guard let resolver = try AndroidContext.shared.applicationContext(in: environment).getContentResolver() else {
            throw AndroidError.serviceUnavailable("content resolver")
        }
        return resolver
    }
}

public enum APhotoLibraryError: Error, CustomStringConvertible {
    case notFound(String)
    case insertFailed
    case encodingFailed
    case decodingFailed
    /// Taking a photo with the camera app needs the CAMERA permission, because
    /// this app declares it.
    case cameraPermissionDenied

    public var description: String {
        switch self {
        case .notFound(let id): "No photo with id \(id)"
        case .insertFailed: "MediaStore did not accept the new photo"
        case .encodingFailed: "The thumbnail could not be encoded"
        case .decodingFailed: "The image could not be decoded"
        case .cameraPermissionDenied: "Camera access is needed to use the camera app"
        }
    }
}

// MARK: - MediaObserver (Android/java)

@JavaClass("org.nucleantui.android.photos.MediaObserver")
class MediaObserver: ContentObserver {
    @JavaMethod
    convenience init(_ handle: Int64, _ handler: Handler?, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.photos.MediaObserver")
extension MediaObserver {
    @JavaMethod
    static func nativeOnChange(_ handle: Int64, environment: JNIEnvironment) {
        try? NativeHandle<APhotoLibrary>.owner(handle)?.refresh()
    }
}
