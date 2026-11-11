//
//  Picking.swift
//  AndroidPhotos
//
//  Getting a photo from the user through other apps: the system photo picker
//  (Android 13+; the document chooser before that), and the camera app taking
//  one straight into the library. Both answer through `onActivityResult`,
//  which the host forwards to `AndroidContext.handleActivityResult`.
//

import AndroidCore
import SwiftJava

extension APhotoLibrary {
    /// Let the user pick one photo. Needs no permission: the picker runs in
    /// the system, and the app may read only what was picked. Nil when they
    /// cancelled.
    public func pickPhoto() async throws -> APickedImage? {
        let environment = try JavaVirtualMachine.shared().environment()
        let intent: Intent
        if try AndroidContext.shared.sdkLevel(in: environment) >= 33 {
            intent = Intent("android.provider.action.PICK_IMAGES", environment: environment)
        } else {
            intent = Intent("android.intent.action.GET_CONTENT", environment: environment)
            _ = intent.setType("image/*")
            _ = intent.addCategory("android.intent.category.OPENABLE")
        }
        let result = try await AndroidContext.shared.startActivityForResult(intent)
        guard result.isOK else { return nil }
        let answer = try JavaVirtualMachine.shared().environment()
        guard let uri = result.data?.wrapped(as: Intent.self, in: answer).getData() else {
            throw AndroidError.unexpectedResult("The photo picker sent back no photo")
        }
        return try APickedImage(uri: uri, in: answer)
    }

    /// Take a photo with the camera app, into Pictures/`album` as `name`. Nil
    /// when the user backed out.
    ///
    /// The camera app writes the full-size photo itself (`EXTRA_OUTPUT`), so
    /// nothing passes through this app. Android refuses the camera intent to an
    /// app that declares the CAMERA permission without holding it, so this
    /// asks for it first.
    public func captureWithCameraApp(name: String) async throws -> APhotoAsset? {
        let camera = "android.permission.CAMERA"
        guard try await AndroidContext.shared.requestPermissions([camera])[camera] == true else {
            throw APhotoLibraryError.cameraPermissionDenied
        }
        let (uri, id) = try insertEmptyPhoto(name: name)
        let environment = try JavaVirtualMachine.shared().environment()
        let intent = Intent("android.media.action.IMAGE_CAPTURE", environment: environment)
        _ = intent.putExtra("output", uri.wrapped(as: Uri.self, in: environment).as(Parcelable.self))
        _ = intent.addFlags(Self.flagGrantReadURIPermission | Self.flagGrantWriteURIPermission)

        let result: AndroidActivityResult
        do {
            result = try await AndroidContext.shared.startActivityForResult(intent)
        } catch {
            try? deletePhoto(uri)
            throw error
        }
        guard result.isOK else {
            try? deletePhoto(uri)
            return nil
        }
        return try await AndroidMainThread.shared.run { _ in
            try self.refresh()
            return self.photos.first { $0.id == id }
        }
    }

    /// An empty row for an app to write a photo into. On the calling thread.
    private func insertEmptyPhoto(name: String) throws -> (uri: JavaGlobalReference, id: Int64) {
        let environment = try JavaVirtualMachine.shared().environment()
        let resolver = try contentResolverForThread()
        let values = ContentValues(environment: environment)
        values.put("_display_name", JavaString(name, environment: environment))
        values.put("mime_type", JavaString("image/jpeg", environment: environment))
        values.put("relative_path", JavaString("Pictures/\(album)", environment: environment))
        guard let uri = try resolver.insert(try imagesURIForThread(), values), let id = Int64(uri.getLastPathSegment()) else {
            throw APhotoLibraryError.insertFailed
        }
        return (JavaGlobalReference(uri), id)
    }

    private func deletePhoto(_ uri: JavaGlobalReference) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        _ = try contentResolverForThread().delete(uri.wrapped(as: Uri.self, in: environment), nil, [])
    }

    static let flagGrantReadURIPermission: Int32 = 1
    static let flagGrantWriteURIPermission: Int32 = 2
}

// MARK: - APickedImage

/// A photo the user picked. The app may read it for as long as it runs.
public final class APickedImage: @unchecked Sendable {
    /// Its content:// URI, from the picker.
    public let uri: Uri
    public let name: String
    public let mimeType: String
    /// Degrees to rotate the stored image clockwise to show it upright (0 when
    /// the provider does not say).
    public let rotation: Int

    init(uri: Uri, in environment: JNIEnvironment) throws {
        self.uri = uri
        let resolver = try pickedContentResolver(in: environment)
        mimeType = resolver.getType(uri)
        var name = uri.getLastPathSegment()
        var rotation = 0
        if let cursor = try? resolver.query(uri, ["_display_name"], nil, [], nil) {
            if cursor.moveToNext(), let column = try? cursor.getColumnIndexOrThrow("_display_name") {
                name = cursor.getString(column)
            }
            cursor.close()
        }
        // The photo picker's provider has MediaStore's columns; a document provider may not.
        if let cursor = try? resolver.query(uri, ["orientation"], nil, [], nil) {
            if cursor.moveToNext(), let column = try? cursor.getColumnIndexOrThrow("orientation") {
                rotation = Int(cursor.getInt(column))
            }
            cursor.close()
        }
        self.name = name
        self.rotation = rotation
    }

    /// The file as stored, read off the main thread.
    public func data() async throws -> [UInt8] {
        let environment = try JavaVirtualMachine.shared().environment()
        guard let file = try pickedContentResolver(in: environment).openFileDescriptor(try uri.boundToCurrentThread(), "r") else {
            throw APhotoLibraryError.notFound(uri.getLastPathSegment())
        }
        return try readAll(fileDescriptor: file.detachFd())
    }

    /// Decoded to pixels, upright, at most `maxPixelSize` on its longer side.
    public func decode(maxPixelSize: Int) async throws -> APixelBuffer {
        try decodePixels(try await data(), maxPixelSize: maxPixelSize, rotation: rotation)
    }
}

private func pickedContentResolver(in environment: JNIEnvironment) throws -> ContentResolver {
    guard let resolver = try AndroidContext.shared.applicationContext(in: environment).getContentResolver() else {
        throw AndroidError.serviceUnavailable("content resolver")
    }
    return resolver
}
