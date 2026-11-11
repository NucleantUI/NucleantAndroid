//
//  Media.swift
//  DeviceLabBridge
//
//  AndroidFlashlight, AndroidCamera, AndroidPhotos and AndroidShare for Kotlin.
//

import AndroidCamera
import AndroidCore
import AndroidFlashlight
import AndroidHardwareCamera2
import AndroidPhotos
import AndroidShare
import Observation
import SwiftJava

// MARK: - Flashlight

/// The device's flashlight; nil when there is none.
public func makeFlashlight() throws -> LabFlashlight? {
    try AFlashlight().map(LabFlashlight.init)
}

public final class LabFlashlight: @unchecked Sendable {
    let flashlight: AFlashlight
    let observer = ChangeObserver()

    init(_ flashlight: AFlashlight) {
        self.flashlight = flashlight
    }

    public var cameraID: String { flashlight.cameraID }
    public var isOn: Bool { flashlight.isOn }
    public var isAvailable: Bool { flashlight.isAvailable }
    public var supportsBrightness: Bool { flashlight.supportsBrightness }
    public var level: Int32 { Int32(flashlight.level) }
    public var maximumLevel: Int32 { Int32(flashlight.maximumLevel) }

    public func turnOn(brightness: Double) throws { try flashlight.turnOn(brightness: brightness) }
    public func turnOff() throws { try flashlight.turnOff() }
    public func toggle() throws { try flashlight.toggle() }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [flashlight] in _ = (flashlight.isOn, flashlight.isAvailable, flashlight.level) }, listener: listener)
    }
}

// MARK: - Camera

public final class LabCameras: @unchecked Sendable {
    let cameras: ACameras
    let observer = ChangeObserver()

    public init() throws {
        cameras = try ACameras()
    }

    public var all: [LabCamera] { cameras.all.map(LabCamera.init) }
    public var isAuthorized: Bool { cameras.authorization == .authorized }

    public func requestAccess() async throws -> Bool { try await cameras.requestAccess() }
    public func refresh() throws { try cameras.refresh() }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [cameras] in _ = (cameras.all, cameras.authorization) }, listener: listener)
    }
}

public final class LabCamera: @unchecked Sendable {
    let camera: ACamera
    let observer = ChangeObserver()

    init(_ camera: ACamera) {
        self.camera = camera
    }

    public var id: String { camera.id }

    /// "front", "back" or "external".
    public var position: String {
        switch camera.position {
        case .front: "front"
        case .back: "back"
        case .external: "external"
        }
    }

    public var hasFlash: Bool { camera.hasFlash }
    public var sensorOrientation: Int32 { Int32(camera.sensorOrientation) }
    public var photoSizeCount: Int32 { Int32(camera.photoSizes.count) }
    public var largestPhotoWidth: Int32 { camera.photoSizes.first?.getWidth() ?? 0 }
    public var largestPhotoHeight: Int32 { camera.photoSizes.first?.getHeight() ?? 0 }
    public var isCapturing: Bool { camera.isCapturing }
    public var isPreviewing: Bool { camera.isPreviewing }
    public var previewWidth: Int32 { Int32(camera.previewWidth) }
    public var previewHeight: Int32 { Int32(camera.previewHeight) }
    /// Why the last preview ended on its own; empty if it did not.
    public var previewFailure: String { camera.previewFailure ?? "" }

    /// `texture` is the `android.graphics.SurfaceTexture` to stream into (a TextureView's).
    public func startPreview(texture: JavaObject) throws {
        try camera.startPreview(on: SurfaceTexture(javaThis: texture.javaThis, environment: texture.javaEnvironment))
    }

    public func stopPreview() { camera.stopPreview() }
    public var lastPhoto: LabPhoto? { camera.lastPhoto.map(LabPhoto.init) }

    public func takePhoto(maxPixelCount: Int64) async throws -> LabPhoto {
        LabPhoto(try await camera.takePhoto(maxPixelCount: Int(maxPixelCount)))
    }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [camera] in
            _ = (camera.isCapturing, camera.lastPhoto, camera.isPreviewing, camera.previewWidth, camera.previewFailure)
        }, listener: listener)
    }
}

public final class LabPhoto: @unchecked Sendable {
    let photo: APhoto

    init(_ photo: APhoto) {
        self.photo = photo
    }

    public var jpegData: [UInt8] { photo.jpegData }
    public var width: Int32 { Int32(photo.width) }
    public var height: Int32 { Int32(photo.height) }
    /// Degrees clockwise to show it upright.
    public var rotation: Int32 { Int32(photo.rotation) }
}

// MARK: - Photos

public enum LibraryAccess {
    case authorized
    case limited
    case denied

    init(_ authorization: APhotoLibraryAuthorization) {
        switch authorization {
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .denied: self = .denied
        }
    }
}

public final class LabPhotoLibrary: @unchecked Sendable {
    let library: APhotoLibrary
    let observer = ChangeObserver()

    /// Saved photos go into Pictures/`album`.
    public init(album: String) throws {
        library = try APhotoLibrary(album: album, limit: 60)
    }

    public var access: LibraryAccess { LibraryAccess(library.authorization) }
    public var photos: [LabPhotoAsset] { library.photos.map(LabPhotoAsset.init) }

    public func requestAccess() async throws -> LibraryAccess {
        LibraryAccess(try await library.requestAuthorization())
    }

    public func refresh() throws { try library.refresh() }

    /// The system photo picker; nil when cancelled.
    public func pickPhoto() async throws -> LabPickedImage? {
        try await library.pickPhoto().map(LabPickedImage.init)
    }

    /// A photo taken by the camera app, straight into the library; nil when cancelled.
    public func captureWithCameraApp(name: String) async throws -> LabPhotoAsset? {
        try await library.captureWithCameraApp(name: name).map(LabPhotoAsset.init)
    }

    /// Save `photo`, with its rotation recorded.
    public func save(photo: LabPhoto, name: String) async throws -> LabPhotoAsset {
        LabPhotoAsset(try await library.save(jpeg: photo.photo.jpegData, name: name, rotation: photo.photo.rotation))
    }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [library] in _ = (library.photos, library.authorization) }, listener: listener)
    }
}

public final class LabPhotoAsset: @unchecked Sendable {
    let asset: APhotoAsset
    let observer = ChangeObserver()

    init(_ asset: APhotoAsset) {
        self.asset = asset
    }

    public var id: Int64 { asset.id }
    public var name: String { asset.name }
    public var width: Int32 { Int32(asset.pixelWidth) }
    public var height: Int32 { Int32(asset.pixelHeight) }
    public var rotation: Int32 { Int32(asset.rotation) }
    public var mimeType: String { asset.mimeType }
    /// Milliseconds since 1970; -1 when unknown.
    public var creationTime: Int64 { asset.creationTime ?? -1 }
    /// The loaded thumbnail (JPEG); empty until `loadThumbnail` has run.
    public var thumbnail: [UInt8] { asset.thumbnail ?? [] }

    public func loadThumbnail(maxPixelSize: Int32) async throws -> [UInt8] {
        try await asset.loadThumbnail(maxPixelSize: Int(maxPixelSize))
    }

    public func data() async throws -> [UInt8] {
        try await asset.imageData()
    }

    public func decode(maxPixelSize: Int32) async throws -> LabPixels {
        LabPixels(try await asset.decode(maxPixelSize: Int(maxPixelSize)))
    }

    /// Offer the photo to other apps through the share sheet.
    public func share() throws {
        try AShareSheet(defaultTitle: "Share photo").share(uri: asset.uri, mimeType: asset.mimeType)
    }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [asset] in _ = asset.thumbnail }, listener: listener)
    }
}

public final class LabPickedImage: @unchecked Sendable {
    let image: APickedImage

    init(_ image: APickedImage) {
        self.image = image
    }

    public var name: String { image.name }
    public var mimeType: String { image.mimeType }
    public var rotation: Int32 { Int32(image.rotation) }

    public func data() async throws -> [UInt8] { try await image.data() }

    public func decode(maxPixelSize: Int32) async throws -> LabPixels {
        LabPixels(try await image.decode(maxPixelSize: Int(maxPixelSize)))
    }
}

/// Decoded RGBA pixels.
public final class LabPixels: @unchecked Sendable {
    let buffer: APixelBuffer

    init(_ buffer: APixelBuffer) {
        self.buffer = buffer
    }

    public var width: Int32 { Int32(buffer.width) }
    public var height: Int32 { Int32(buffer.height) }
    public var bytesPerRow: Int32 { Int32(buffer.bytesPerRow) }
    public var byteCount: Int32 { Int32(buffer.pixels.count) }
    /// The pixel bytes: RGBA, premultiplied, `bytesPerRow` apart.
    public var pixels: [UInt8] { buffer.pixels }

    /// The mean colour over every pixel, as 0xAARRGGBB — worked out in Swift
    /// from the pixel bytes, to show they are really there.
    public var averageColor: Int32 {
        var sums: (red: Int, green: Int, blue: Int, alpha: Int) = (0, 0, 0, 0)
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let pixel = buffer.rgba(x: x, y: y)
                sums = (sums.red + Int(pixel.red), sums.green + Int(pixel.green), sums.blue + Int(pixel.blue), sums.alpha + Int(pixel.alpha))
            }
        }
        let count = max(1, buffer.width * buffer.height)
        let argb = UInt32(sums.alpha / count) << 24 | UInt32(sums.red / count) << 16 | UInt32(sums.green / count) << 8 | UInt32(sums.blue / count)
        return Int32(bitPattern: argb)
    }
}

// MARK: - Share

/// Offer `text` to other apps through the share sheet.
public func shareText(text: String) throws {
    try AShareSheet(defaultTitle: "Share text").share(text: text)
}
