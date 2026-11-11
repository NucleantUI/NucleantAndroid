//
//  CameraSession.swift
//  AndroidCamera
//
//  An open camera, as a Camera2 state machine. Two ways to run it:
//
//  - one photo (`ACamera.takePhoto` while not previewing):
//      openCamera ─▶ onOpened ─▶ createCaptureSession([warm-up YUV, JPEG])
//        ─▶ repeating preview request into the warm-up reader
//        ─▶ after `warmupFrameCount` frames: one still into the JPEG reader
//        ─▶ the photo ─▶ close everything.
//    The warm-up frames are there because a camera opened cold has not metered
//    yet: a still captured at once comes out dark or blurred. They are dropped.
//
//  - a live preview (`ACamera.startPreview(on:)`):
//      openCamera ─▶ onOpened ─▶ createCaptureSession([preview surface, JPEG])
//        ─▶ repeating preview request into the SurfaceTexture
//        ─▶ every `takePhoto` is a still into the JPEG reader
//        ─▶ open until `stop`.
//
//  Threading: everything here runs on the main Looper thread — `start` is
//  called there, and every callback arrives there (each is registered with a
//  main-Looper Handler) — so its state is only touched from that thread.
//
//  Lifetime: Camera2 calls back through the Java helpers in Android/java, which
//  carry a NativeHandle to this session. It keeps itself alive (`retainedSelf`)
//  until `close`, which disarms every helper first — a callback still queued
//  after that reaches a zeroed handle in Java and stops there.
//

import AndroidCore
import AndroidHardwareCamera2
import SwiftJava

final class CameraSession: @unchecked Sendable {
    /// Frames to run before a cold still: about half a second at 30 fps.
    static let warmupFrameCount = 15
    /// Give up on a photo that has not arrived in this long.
    static let photoTimeoutMilliseconds: Int64 = 15_000

    /// `ImageAvailableListener.stream` values.
    static let warmupStream: Int32 = 0
    static let photoStream: Int32 = 1

    typealias PhotoCompletion = (Result<APhoto, any Error>) -> Void

    private let camera: ACamera
    private let photoSize: Size
    /// One-photo mode: the YUV size it warms up on.
    private let warmupSize: Size?
    /// Preview mode: where frames go, at `previewSize`.
    private let previewTexture: SurfaceTexture?
    private let previewSize: Size?
    /// Preview mode: told once when the session ends, with why if it failed.
    private var onEnd: ((ACameraError?) -> Void)?

    /// Photos asked for and not delivered yet, oldest first. Each still that
    /// arrives answers the first.
    private var pendingPhotos: [(id: Int, completion: PhotoCompletion)] = []
    private var nextPhotoID = 0
    private var stillsInFlight = 0

    private var retainedSelf: Unmanaged<CameraSession>?
    private var handle: Int64 = 0
    private var handler: Handler?
    private var photoReader: ImageReader?
    private var warmupReader: ImageReader?
    private var previewSurface: Surface?
    private var deviceCallback: CameraStateCallback?
    private var sessionCallback: CaptureSessionCallback?
    private var photoListener: ImageAvailableListener?
    private var warmupListener: ImageAvailableListener?
    private var device: CameraDevice?
    private var session: CameraCaptureSession?
    private var isStreaming = false
    private var warmupFrames = 0
    private var isClosed = false

    /// One photo, then close.
    init(camera: ACamera, photoSize: Size, warmupSize: Size, completion: @escaping PhotoCompletion) {
        self.camera = camera
        self.photoSize = photoSize
        self.warmupSize = warmupSize
        self.previewTexture = nil
        self.previewSize = nil
        pendingPhotos = [(0, completion)]
        nextPhotoID = 1
    }

    /// A live preview on `texture`, until `stop`.
    init(camera: ACamera, photoSize: Size, previewTexture: SurfaceTexture, previewSize: Size, onEnd: @escaping (ACameraError?) -> Void) {
        self.camera = camera
        self.photoSize = photoSize
        self.warmupSize = nil
        self.previewTexture = previewTexture
        self.previewSize = previewSize
        self.onEnd = onEnd
    }

    private var isPreview: Bool { previewTexture != nil }

    static func from(handle: Int64) -> CameraSession? {
        NativeHandle<CameraSession>.owner(handle)
    }

    // MARK: - Steps

    func start(in environment: JNIEnvironment) {
        retainedSelf = Unmanaged.passRetained(self)
        handle = NativeHandle.retain(self)
        do {
            let manager = try CameraManager.service(in: environment)
            let handler = try AndroidMainThread.shared.mainHandler(in: environment)
            let readers = try JavaClass<ImageReader>(environment: environment)
            self.handler = handler

            guard let photoReader = readers.newInstance(photoSize.getWidth(), photoSize.getHeight(), ImageFormat.jpeg, 2) else {
                throw ACameraError.sessionConfigurationFailed
            }
            self.photoReader = photoReader
            let photoListener = ImageAvailableListener(handle, Self.photoStream, environment: environment)
            self.photoListener = photoListener
            photoReader.setOnImageAvailableListener(photoListener.as(ImageReaderOnImageAvailableListener.self), handler)

            if let previewTexture, let previewSize {
                previewTexture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight())
                previewSurface = Surface(previewTexture, environment: environment)
            } else if let warmupSize {
                guard let warmupReader = readers.newInstance(
                    warmupSize.getWidth(), warmupSize.getHeight(), ImageFormat.yuv420888, 3)
                else {
                    throw ACameraError.sessionConfigurationFailed
                }
                self.warmupReader = warmupReader
                let warmupListener = ImageAvailableListener(handle, Self.warmupStream, environment: environment)
                self.warmupListener = warmupListener
                warmupReader.setOnImageAvailableListener(warmupListener.as(ImageReaderOnImageAvailableListener.self), handler)
                scheduleTimeout(forPhoto: 0)
            }

            let deviceCallback = CameraStateCallback(handle, environment: environment)
            self.deviceCallback = deviceCallback
            self.sessionCallback = CaptureSessionCallback(handle, environment: environment)
            try manager.openCamera(camera.id, deviceCallback, handler)
        } catch {
            close(because: error)
        }
    }

    /// The surface the repeating request feeds: the preview, or the warm-up reader.
    private var streamSurface: Surface? {
        previewSurface ?? warmupReader?.getSurface()
    }

    func opened(_ device: CameraDevice, in environment: JNIEnvironment) {
        self.device = device
        do {
            guard let streamSurface, let photoSurface = photoReader?.getSurface() else {
                throw ACameraError.sessionConfigurationFailed
            }
            let outputs = JavaArrayList(environment: environment)
            _ = outputs.add(streamSurface)
            _ = outputs.add(photoSurface)
            try device.createCaptureSession(outputs.as(List<Surface>.self), sessionCallback, handler)
        } catch {
            close(because: error)
        }
    }

    func configured(_ session: CameraCaptureSession, in environment: JNIEnvironment) {
        self.session = session
        do {
            guard let device, let request = try device.createCaptureRequest(CameraDevice.templatePreview) else {
                throw ACameraError.sessionConfigurationFailed
            }
            request.addTarget(streamSurface)
            _ = try session.setRepeatingRequest(request.build(), nil, handler)
            isStreaming = true
            if isPreview {
                try requestStills()
            }
        } catch {
            close(because: error)
        }
    }

    func imageAvailable(stream: Int32, reader: ImageReader, in environment: JNIEnvironment) {
        do {
            if stream == Self.photoStream {
                guard let image = try reader.acquireNextImage() else { return }
                defer { image.close() }
                let photo = try photo(from: image, in: environment)
                stillsInFlight = max(0, stillsInFlight - 1)
                if !pendingPhotos.isEmpty {
                    pendingPhotos.removeFirst().completion(.success(photo))
                }
                if !isPreview {
                    close(because: nil)
                }
                return
            }

            // A warm-up frame: drop it, and once enough have gone by, take the photo.
            try reader.acquireLatestImage()?.close()
            warmupFrames += 1
            if warmupFrames == Self.warmupFrameCount {
                try requestStills()
            }
        } catch {
            close(because: error)
        }
    }

    func failed(_ error: ACameraError, in environment: JNIEnvironment) {
        close(because: error)
    }

    // MARK: - Photos while previewing

    /// Take a photo from the running preview. On the main thread.
    func takePhoto(completion: @escaping PhotoCompletion) {
        guard !isClosed else {
            completion(.failure(ACameraError.sessionClosed))
            return
        }
        let id = nextPhotoID
        nextPhotoID += 1
        pendingPhotos.append((id, completion))
        scheduleTimeout(forPhoto: id)
        if isStreaming {
            do {
                try requestStills()
            } catch {
                close(because: error)
            }
        }
    }

    /// One still request per photo asked for and not yet requested.
    private func requestStills() throws {
        guard let device, let session else { return }
        while stillsInFlight < pendingPhotos.count {
            guard let request = try device.createCaptureRequest(CameraDevice.templateStillCapture) else {
                throw ACameraError.sessionConfigurationFailed
            }
            request.addTarget(photoReader?.getSurface())
            _ = try session.capture(request.build(), nil, handler)
            stillsInFlight += 1
        }
    }

    private func scheduleTimeout(forPhoto id: Int) {
        try? AndroidMainThread.shared.post(afterMilliseconds: Self.photoTimeoutMilliseconds) { _ in
            guard let index = self.pendingPhotos.firstIndex(where: { $0.id == id }) else { return }
            let completion = self.pendingPhotos.remove(at: index).completion
            completion(.failure(ACameraError.timedOut))
            if !self.isPreview {
                self.close(because: nil)
            }
        }
    }

    // MARK: - Result

    /// A JPEG Image has one plane: the encoded file, in a direct ByteBuffer.
    private func photo(from image: Image, in environment: JNIEnvironment) throws -> APhoto {
        guard let plane = image.getPlanes().first ?? nil,
              let buffer = plane.getBuffer(),
              let base = environment.interface.GetDirectBufferAddress(environment, buffer.javaThis)
        else {
            throw ACameraError.sessionConfigurationFailed
        }
        let start = Int(buffer.position())
        let count = Int(buffer.remaining())
        let bytes = [UInt8](UnsafeRawBufferPointer(start: base.advanced(by: start), count: count))
        return APhoto(
            jpegData: bytes,
            width: Int(image.getWidth()),
            height: Int(image.getHeight()),
            rotation: camera.sensorOrientation
        )
    }

    // MARK: - Closing

    /// Preview mode: end the session. On the main thread.
    func stop() {
        close(because: nil)
    }

    /// Close the camera and everything opened for it. `error` fails what is
    /// still waiting (nil: those waiting are told the session closed).
    private func close(because error: (any Error)?) {
        guard !isClosed else { return }
        isClosed = true

        deviceCallback?.disarm()
        sessionCallback?.disarm()
        photoListener?.disarm()
        warmupListener?.disarm()
        if let session {
            try? session.stopRepeating()
            session.close()
        }
        device?.close()
        photoReader?.close()
        warmupReader?.close()
        previewSurface?.release()

        session = nil
        device = nil
        photoReader = nil
        warmupReader = nil
        previewSurface = nil
        deviceCallback = nil
        sessionCallback = nil
        photoListener = nil
        warmupListener = nil
        handler = nil

        let waiting = pendingPhotos
        pendingPhotos = []
        for photo in waiting {
            photo.completion(.failure(error ?? ACameraError.sessionClosed))
        }
        if let onEnd {
            self.onEnd = nil
            onEnd(error.map { ($0 as? ACameraError) ?? .failed(String(describing: $0)) })
        }
        NativeHandle<CameraSession>.release(handle)
        retainedSelf?.release()
        retainedSelf = nil
    }
}
