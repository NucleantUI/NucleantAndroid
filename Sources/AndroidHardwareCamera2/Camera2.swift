//
//  Camera2.swift
//  AndroidHardwareCamera2
//
//  swift-java wrappers for android.hardware.camera2 (and the android.media /
//  android.view classes a capture needs), shared by AndroidFlashlight and
//  AndroidCamera. Only what those two call is declared.
//
//  Camera2's generic `get(Key<T>)` / `set(Key<T>, T)` are declared with their
//  erased signatures (`Object`), which is what JNI looks them up by; read
//  results back with `as(JavaInteger.self)` and friends.
//

import AndroidCore
import SwiftJava

// MARK: - CameraManager

/// `android.hardware.camera2.CameraManager` (`Context.CAMERA_SERVICE`).
@JavaClass("android.hardware.camera2.CameraManager")
open class CameraManager: JavaObject {
    @JavaMethod
    open func getCameraIdList() throws -> [String]

    @JavaMethod
    open func getCameraCharacteristics(_ cameraId: String) throws -> CameraCharacteristics!

    @JavaMethod
    open func setTorchMode(_ cameraId: String, _ enabled: Bool) throws

    /// API 33.
    @JavaMethod
    open func turnOnTorchWithStrengthLevel(_ cameraId: String, _ torchStrength: Int32) throws

    /// API 33.
    @JavaMethod
    open func getTorchStrengthLevel(_ cameraId: String) throws -> Int32

    @JavaMethod
    open func registerTorchCallback(_ callback: CameraManagerTorchCallback?, _ handler: Handler?)

    @JavaMethod
    open func unregisterTorchCallback(_ callback: CameraManagerTorchCallback?)

    @JavaMethod
    open func openCamera(_ cameraId: String, _ callback: CameraDeviceStateCallback?, _ handler: Handler?) throws
}

/// `android.hardware.camera2.CameraManager.TorchCallback`.
@JavaClass("android.hardware.camera2.CameraManager$TorchCallback")
open class CameraManagerTorchCallback: JavaObject {}

extension CameraManager {
    /// The camera service of the attached app.
    public static func service(in environment: JNIEnvironment) throws -> CameraManager {
        let context = try AndroidContext.shared.applicationContext(in: environment)
        guard let manager = context.getSystemService("camera")?.as(CameraManager.self) else {
            throw AndroidError.serviceUnavailable("camera")
        }
        return manager
    }
}

// MARK: - CameraCharacteristics

/// `android.hardware.camera2.CameraCharacteristics`.
@JavaClass("android.hardware.camera2.CameraCharacteristics")
open class CameraCharacteristics: JavaObject {
    /// `<T> T get(CameraCharacteristics.Key<T>)`.
    @JavaMethod
    open func get(_ key: CameraCharacteristicsKey?) -> JavaObject!
}

extension JavaClass<CameraCharacteristics> {
    /// `Integer`: `LENS_FACING_FRONT` (0), `_BACK` (1), `_EXTERNAL` (2).
    @JavaStaticField(isFinal: true)
    public var LENS_FACING: CameraCharacteristicsKey!

    /// `Boolean`.
    @JavaStaticField(isFinal: true)
    public var FLASH_INFO_AVAILABLE: CameraCharacteristicsKey!

    /// `Integer`, API 33. 1 when the torch has no brightness levels.
    @JavaStaticField(isFinal: true)
    public var FLASH_INFO_STRENGTH_MAXIMUM_LEVEL: CameraCharacteristicsKey!

    /// `Integer`, API 33: the level `setTorchMode(id, true)` turns the torch on at.
    @JavaStaticField(isFinal: true)
    public var FLASH_INFO_STRENGTH_DEFAULT_LEVEL: CameraCharacteristicsKey!

    /// `Integer`: degrees (0, 90, 180, 270) the sensor image must be rotated
    /// clockwise to be upright in the device's natural orientation.
    @JavaStaticField(isFinal: true)
    public var SENSOR_ORIENTATION: CameraCharacteristicsKey!

    /// `StreamConfigurationMap`.
    @JavaStaticField(isFinal: true)
    public var SCALER_STREAM_CONFIGURATION_MAP: CameraCharacteristicsKey!
}

/// `android.hardware.camera2.CameraCharacteristics.Key`.
@JavaClass("android.hardware.camera2.CameraCharacteristics$Key")
open class CameraCharacteristicsKey: JavaObject {}

// MARK: - StreamConfigurationMap

/// `android.hardware.camera2.params.StreamConfigurationMap`.
@JavaClass("android.hardware.camera2.params.StreamConfigurationMap")
open class StreamConfigurationMap: JavaObject {
    @JavaMethod
    open func getOutputSizes(_ format: Int32) -> [Size?]
}

// MARK: - CameraDevice

/// `android.hardware.camera2.CameraDevice`.
@JavaClass("android.hardware.camera2.CameraDevice")
open class CameraDevice: JavaObject {
    @JavaMethod
    open func getId() -> String

    @JavaMethod
    open func createCaptureRequest(_ templateType: Int32) throws -> CaptureRequestBuilder!

    /// `createCaptureSession(List<Surface>, StateCallback, Handler)`.
    @JavaMethod
    open func createCaptureSession(
        _ outputs: List<Surface>?,
        _ callback: CameraCaptureSessionStateCallback?,
        _ handler: Handler?
    ) throws

    @JavaMethod
    open func close()
}

extension CameraDevice {
    public static let templatePreview: Int32 = 1
    public static let templateStillCapture: Int32 = 2
}

/// `android.hardware.camera2.CameraDevice.StateCallback`.
@JavaClass("android.hardware.camera2.CameraDevice$StateCallback")
open class CameraDeviceStateCallback: JavaObject {}

// MARK: - CameraCaptureSession

/// `android.hardware.camera2.CameraCaptureSession`.
@JavaClass("android.hardware.camera2.CameraCaptureSession")
open class CameraCaptureSession: JavaObject {
    @JavaMethod
    open func setRepeatingRequest(
        _ request: CaptureRequest?,
        _ listener: CameraCaptureSessionCaptureCallback?,
        _ handler: Handler?
    ) throws -> Int32

    @JavaMethod
    open func capture(
        _ request: CaptureRequest?,
        _ listener: CameraCaptureSessionCaptureCallback?,
        _ handler: Handler?
    ) throws -> Int32

    @JavaMethod
    open func stopRepeating() throws

    @JavaMethod
    open func close()
}

/// `android.hardware.camera2.CameraCaptureSession.StateCallback`.
@JavaClass("android.hardware.camera2.CameraCaptureSession$StateCallback")
open class CameraCaptureSessionStateCallback: JavaObject {}

/// `android.hardware.camera2.CameraCaptureSession.CaptureCallback`.
@JavaClass("android.hardware.camera2.CameraCaptureSession$CaptureCallback")
open class CameraCaptureSessionCaptureCallback: JavaObject {}

// MARK: - CaptureRequest

/// `android.hardware.camera2.CaptureRequest`.
@JavaClass("android.hardware.camera2.CaptureRequest")
open class CaptureRequest: JavaObject {}

/// `android.hardware.camera2.CaptureRequest.Builder`.
@JavaClass("android.hardware.camera2.CaptureRequest$Builder")
open class CaptureRequestBuilder: JavaObject {
    @JavaMethod
    open func addTarget(_ outputTarget: Surface?)

    @JavaMethod
    open func build() -> CaptureRequest!
}

// MARK: - android.view.Surface

/// `android.view.Surface`.
@JavaClass("android.view.Surface")
open class Surface: JavaObject {
    /// A surface that feeds `texture` (a preview into a TextureView, for one).
    @JavaMethod
    @_nonoverride public convenience init(_ texture: SurfaceTexture?, environment: JNIEnvironment? = nil)

    @JavaMethod
    open func release()
}

/// `android.graphics.SurfaceTexture`: frames streamed into an OpenGL ES texture,
/// which is what a TextureView shows.
@JavaClass("android.graphics.SurfaceTexture")
open class SurfaceTexture: JavaObject {
    @JavaMethod
    open func setDefaultBufferSize(_ width: Int32, _ height: Int32)
}

// MARK: - android.media

/// `android.media.ImageReader`.
@JavaClass("android.media.ImageReader")
open class ImageReader: JavaObject {
    @JavaMethod
    open func getSurface() -> Surface!

    @JavaMethod
    open func setOnImageAvailableListener(_ listener: ImageReaderOnImageAvailableListener?, _ handler: Handler?)

    @JavaMethod
    open func acquireLatestImage() throws -> Image!

    @JavaMethod
    open func acquireNextImage() throws -> Image!

    @JavaMethod
    open func close()
}

extension JavaClass<ImageReader> {
    @JavaStaticMethod
    public func newInstance(_ width: Int32, _ height: Int32, _ format: Int32, _ maxImages: Int32) -> ImageReader!
}

/// `android.media.ImageReader.OnImageAvailableListener`.
@JavaInterface("android.media.ImageReader$OnImageAvailableListener")
public struct ImageReaderOnImageAvailableListener {}

/// `android.media.Image`.
@JavaClass("android.media.Image")
open class Image: JavaObject {
    @JavaMethod
    open func getWidth() -> Int32

    @JavaMethod
    open func getHeight() -> Int32

    @JavaMethod
    open func getPlanes() -> [ImagePlane?]

    @JavaMethod
    open func close()
}

/// `android.media.Image.Plane`.
@JavaClass("android.media.Image$Plane")
open class ImagePlane: JavaObject {
    @JavaMethod
    open func getBuffer() -> JavaNioByteBuffer!
}

/// `android.graphics.ImageFormat` values.
public enum ImageFormat {
    public static let jpeg: Int32 = 0x100
    public static let yuv420888: Int32 = 0x23
}

// MARK: - java.nio

/// `java.nio.Buffer`, for the position and limit of an Image plane's buffer
/// (swift-java's own `ByteBuffer` wrapper does not declare Buffer's methods).
@JavaClass("java.nio.Buffer")
open class JavaNioBuffer: JavaObject {
    @JavaMethod
    open func position() -> Int32

    @JavaMethod
    open func remaining() -> Int32
}

/// `java.nio.ByteBuffer`, as the Buffer it is.
@JavaClass("java.nio.ByteBuffer")
open class JavaNioByteBuffer: JavaNioBuffer {}
