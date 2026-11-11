//
//  Camera.swift
//  AndroidCamera
//
//  The device's cameras, and taking a photo with one, through Camera2.
//
//  Taking a photo needs `android.permission.CAMERA` in the app's manifest and
//  granted at run time (`ACameras.requestAccess()`). Listing cameras does not.
//

import AndroidCore
import AndroidHardwareCamera2
import Observation
import SwiftJava

/// Which way a camera faces.
public enum ACameraPosition: Sendable, Hashable {
    case front
    case back
    /// Plugged in rather than built in (USB, or an emulator's webcam).
    case external

    /// From `CameraCharacteristics.LENS_FACING`.
    init?(lensFacing: Int32) {
        switch lensFacing {
        case 0: self = .front
        case 1: self = .back
        case 2: self = .external
        default: return nil
        }
    }
}

/// Whether the app may use the cameras.
public enum ACameraAuthorization: Sendable, Hashable {
    case authorized
    case denied
}

// MARK: - ACameras

/// The device's cameras, and the app's access to them. Create and use it on
/// the main thread.
@Observable
public final class ACameras: @unchecked Sendable {
    public private(set) var all: [ACamera] = []
    public private(set) var authorization: ACameraAuthorization

    @ObservationIgnored private let manager: CameraManager

    static let permission = "android.permission.CAMERA"

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        manager = try CameraManager.service(in: environment)
        authorization = try Self.currentAuthorization()
        try refresh()
    }

    /// Read the camera list and the access state again. Cameras that are still
    /// there keep their `ACamera` object.
    public func refresh() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let keys = try JavaClass<CameraCharacteristics>(environment: environment)
        var cameras: [ACamera] = []
        for id in try manager.getCameraIdList() {
            if let existing = all.first(where: { $0.id == id }) {
                cameras.append(existing)
            } else if let characteristics = try manager.getCameraCharacteristics(id) {
                cameras.append(ACamera(id: id, characteristics: characteristics, keys: keys))
            }
        }
        all = cameras
        authorization = try Self.currentAuthorization()
    }

    /// Ask the user for camera access, if not granted yet. True when granted.
    public func requestAccess() async throws -> Bool {
        let answer = try await AndroidContext.shared.requestPermissions([Self.permission])
        let granted = answer[Self.permission] ?? false
        try await AndroidMainThread.shared.run { _ in
            self.authorization = granted ? .authorized : .denied
        }
        return granted
    }

    static func currentAuthorization() throws -> ACameraAuthorization {
        try AndroidContext.shared.isGranted(permission) ? .authorized : .denied
    }
}

// MARK: - ACamera

/// One of the device's cameras. Its state changes on the main thread.
@Observable
public final class ACamera: Identifiable, @unchecked Sendable {
    /// Camera2's camera id.
    public let id: String
    public let position: ACameraPosition
    public let hasFlash: Bool
    /// Degrees the sensor image is rotated from the device's natural orientation.
    public let sensorOrientation: Int
    /// Everything Camera2 knows about the camera.
    @ObservationIgnored public let characteristics: CameraCharacteristics
    /// The sizes it takes photos at (JPEG), largest first.
    @ObservationIgnored public let photoSizes: [Size]
    /// Its YUV stream sizes, smallest first: what a capture warms the camera's
    /// exposure up on before the photo.
    @ObservationIgnored let warmupSizes: [Size]

    /// Whether a photo is being taken.
    public private(set) var isCapturing = false
    /// The last photo it took.
    public private(set) var lastPhoto: APhoto?

    /// Whether frames are streaming into a preview texture.
    public private(set) var isPreviewing = false
    /// The preview's frame size, as the sensor delivers it (before
    /// `sensorOrientation`); 0 while not previewing.
    public private(set) var previewWidth = 0
    public private(set) var previewHeight = 0
    /// Why the last preview ended on its own (disconnected, an error), if it did.
    public private(set) var previewFailure: String?

    @ObservationIgnored private var previewSession: CameraSession?

    init(id: String, characteristics: CameraCharacteristics, keys: JavaClass<CameraCharacteristics>) {
        self.id = id
        self.characteristics = characteristics
        let facing = characteristics.get(keys.LENS_FACING)?.as(JavaInteger.self)?.intValue()
        position = facing.flatMap(ACameraPosition.init(lensFacing:)) ?? .external
        hasFlash = characteristics.get(keys.FLASH_INFO_AVAILABLE)?.as(JavaBoolean.self)?.booleanValue() ?? false
        sensorOrientation = Int(characteristics.get(keys.SENSOR_ORIENTATION)?.as(JavaInteger.self)?.intValue() ?? 0)

        let streams = characteristics.get(keys.SCALER_STREAM_CONFIGURATION_MAP)?.as(StreamConfigurationMap.self)
        photoSizes = (streams?.getOutputSizes(ImageFormat.jpeg) ?? []).compactMap { $0 }
            .sorted { Self.pixelCount($0) > Self.pixelCount($1) }
        warmupSizes = (streams?.getOutputSizes(ImageFormat.yuv420888) ?? []).compactMap { $0 }
            .sorted { Self.pixelCount($0) < Self.pixelCount($1) }
    }

    // MARK: - Preview

    /// Stream the camera live into `texture` — a TextureView's SurfaceTexture,
    /// or any other — until `stopPreview()`. On the main thread.
    ///
    /// Frames arrive as the sensor produces them: the view showing them turns
    /// them by `sensorOrientation` and scales `previewWidth`×`previewHeight`
    /// to fit. While previewing, `takePhoto` takes its photo from the running
    /// session (no warm-up), at the size chosen here from `maxPixelCount`.
    public func startPreview(on texture: SurfaceTexture, maxPixelCount: Int = 12_000_000) throws {
        guard try ACameras.currentAuthorization() == .authorized else {
            throw ACameraError.notAuthorized
        }
        stopPreview()
        let environment = try JavaVirtualMachine.shared().environment()
        let photos = Self.dimensions(photoSizes)
        let streams = Self.dimensions(warmupSizes)
        guard let photoIndex = Self.photoSizeIndex(in: photos, maxPixelCount: maxPixelCount),
              let previewIndex = Self.previewSizeIndex(in: streams, matching: photos[photoIndex])
        else {
            throw ACameraError.noOutputSizes(id)
        }
        let session = CameraSession(
            camera: self,
            photoSize: photoSizes[photoIndex],
            previewTexture: try texture.boundToCurrentThread(),
            previewSize: warmupSizes[previewIndex]
        ) { failure in
            // Ended by stopPreview (nil) or by the camera (a failure).
            self.isPreviewing = false
            self.previewWidth = 0
            self.previewHeight = 0
            if let failure {
                self.previewFailure = failure.description
            }
            self.previewSession = nil
        }
        previewSession = session
        previewFailure = nil
        previewWidth = streams[previewIndex].width
        previewHeight = streams[previewIndex].height
        isPreviewing = true
        session.start(in: environment)
    }

    /// Stop streaming into the preview texture, and close the camera.
    public func stopPreview() {
        previewSession?.stop()
        previewSession = nil
    }

    // MARK: - Photos

    /// Take a photo at the largest size of at most `maxPixelCount` pixels (the
    /// smallest size the camera has, if none is that small).
    ///
    /// While previewing, the photo comes from the running preview at the size
    /// `startPreview` chose. Otherwise this opens the camera, runs it for a
    /// moment so exposure and focus settle, takes one photo, and closes the
    /// camera again. The photo also becomes `lastPhoto`.
    public func takePhoto(maxPixelCount: Int = 12_000_000) async throws -> APhoto {
        guard try ACameras.currentAuthorization() == .authorized else {
            throw ACameraError.notAuthorized
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try AndroidMainThread.shared.post { environment in
                    self.startCapture(maxPixelCount: maxPixelCount, continuation: continuation, in: environment)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// On the main thread.
    private func startCapture(
        maxPixelCount: Int,
        continuation: CheckedContinuation<APhoto, any Error>,
        in environment: JNIEnvironment
    ) {
        guard !isCapturing else {
            continuation.resume(throwing: ACameraError.busy)
            return
        }
        let finished: CameraSession.PhotoCompletion = { result in
            self.isCapturing = false
            if case .success(let photo) = result {
                self.lastPhoto = photo
            }
            continuation.resume(with: result)
        }
        if let previewSession {
            isCapturing = true
            previewSession.takePhoto(completion: finished)
            return
        }
        guard let photoIndex = Self.photoSizeIndex(in: Self.dimensions(photoSizes), maxPixelCount: maxPixelCount),
              let warmupIndex = Self.warmupSizeIndex(in: Self.dimensions(warmupSizes))
        else {
            continuation.resume(throwing: ACameraError.noOutputSizes(id))
            return
        }
        isCapturing = true
        CameraSession(
            camera: self,
            photoSize: photoSizes[photoIndex],
            warmupSize: warmupSizes[warmupIndex],
            completion: finished
        ).start(in: environment)
    }

    // MARK: - Sizes

    static func pixelCount(_ size: Size) -> Int {
        Int(size.getWidth()) * Int(size.getHeight())
    }

    static func dimensions(_ sizes: [Size]) -> [(width: Int, height: Int)] {
        sizes.map { (width: Int($0.getWidth()), height: Int($0.getHeight())) }
    }

    /// The largest of `sizes` with at most `maxPixelCount` pixels, else the smallest.
    static func photoSizeIndex(in sizes: [(width: Int, height: Int)], maxPixelCount: Int) -> Int? {
        let counts = sizes.map { $0.width * $0.height }
        return counts.indices.filter { counts[$0] <= maxPixelCount }.max { counts[$0] < counts[$1] }
            ?? counts.indices.min { counts[$0] < counts[$1] }
    }

    /// The smallest of `sizes` at least 320 wide (warm-up frames are thrown
    /// away, so smaller is cheaper), else the largest there is.
    static func warmupSizeIndex(in sizes: [(width: Int, height: Int)]) -> Int? {
        let counts = sizes.map { $0.width * $0.height }
        return counts.indices.filter { sizes[$0].width >= 320 }.min { counts[$0] < counts[$1] }
            ?? counts.indices.max { counts[$0] < counts[$1] }
    }

    /// The largest of `sizes` up to 1920×1080 with the photo's aspect ratio
    /// (so what the preview shows is what the photo gets), else the largest up
    /// to 1920×1080 at all, else the smallest.
    static func previewSizeIndex(in sizes: [(width: Int, height: Int)], matching photo: (width: Int, height: Int)) -> Int? {
        let limit = 1920 * 1080
        let counts = sizes.map { $0.width * $0.height }
        let fitting = counts.indices.filter { counts[$0] <= limit && sizes[$0].width <= 1920 }
        let aspect = Double(photo.width) / Double(max(photo.height, 1))
        let matching = fitting.filter {
            abs(Double(sizes[$0].width) / Double(max(sizes[$0].height, 1)) - aspect) < 0.01
        }
        return matching.max { counts[$0] < counts[$1] }
            ?? fitting.max { counts[$0] < counts[$1] }
            ?? counts.indices.min { counts[$0] < counts[$1] }
    }
}

// MARK: - APhoto

/// A photo as the camera encoded it.
public final class APhoto: Sendable {
    /// The JPEG file's bytes.
    public let jpegData: [UInt8]
    /// Size of the image as stored, before `rotation`.
    public let width: Int
    public let height: Int
    /// Degrees (0, 90, 180, 270) to rotate the image clockwise to show it
    /// upright for a device held in its natural orientation. The pixels are
    /// stored as the sensor produced them.
    public let rotation: Int

    init(jpegData: [UInt8], width: Int, height: Int, rotation: Int) {
        self.jpegData = jpegData
        self.width = width
        self.height = height
        self.rotation = rotation
    }
}

public enum ACameraError: Error, CustomStringConvertible {
    case notAuthorized
    case busy
    case noOutputSizes(String)
    /// `CameraDevice.StateCallback.onError`'s error code.
    case deviceError(Int32)
    case disconnected
    case sessionConfigurationFailed
    /// The camera produced no photo in time.
    case timedOut
    /// The preview session it was asked of has ended.
    case sessionClosed
    /// Something Android reported, as text.
    case failed(String)

    public var description: String {
        switch self {
        case .notAuthorized: "Camera access has not been granted"
        case .busy: "The camera is already taking a photo"
        case .noOutputSizes(let id): "Camera \(id) reports no photo sizes"
        case .deviceError(let code): "The camera reported error \(code)"
        case .disconnected: "The camera was disconnected"
        case .sessionConfigurationFailed: "The camera could not be configured for a photo"
        case .timedOut: "The camera did not deliver a photo in time"
        case .sessionClosed: "The camera session has closed"
        case .failed(let message): message
        }
    }
}
