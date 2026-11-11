//
//  CaptureCallbacks.swift
//  AndroidCamera
//
//  The Java side of PhotoCapture's callbacks: Android/java's
//  org.nucleantui.android.camera helpers, which subclass Camera2's abstract
//  callback classes (Swift cannot) and forward each callback to a
//  `static native` method implemented here.
//
//  The class names and `native` method names below must match the Java
//  sources exactly — JNI binds them by symbol name. NativeMethodBindingTests
//  checks that every `native` in Android/java has its symbol.
//

import AndroidHardwareCamera2
import SwiftJava

// MARK: - CameraStateCallback

@JavaClass("org.nucleantui.android.camera.CameraStateCallback")
class CameraStateCallback: CameraDeviceStateCallback {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.camera.CameraStateCallback")
extension CameraStateCallback {
    @JavaMethod
    static func nativeOnOpened(_ handle: Int64, _ camera: CameraDevice?, environment: JNIEnvironment) {
        guard let capture = CameraSession.from(handle: handle), let camera else { return }
        capture.opened(camera, in: environment)
    }

    @JavaMethod
    static func nativeOnDisconnected(_ handle: Int64, _ camera: CameraDevice?, environment: JNIEnvironment) {
        CameraSession.from(handle: handle)?.failed(.disconnected, in: environment)
    }

    @JavaMethod
    static func nativeOnError(_ handle: Int64, _ camera: CameraDevice?, _ error: Int32, environment: JNIEnvironment) {
        CameraSession.from(handle: handle)?.failed(.deviceError(error), in: environment)
    }
}

// MARK: - CaptureSessionCallback

@JavaClass("org.nucleantui.android.camera.CaptureSessionCallback")
class CaptureSessionCallback: CameraCaptureSessionStateCallback {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.camera.CaptureSessionCallback")
extension CaptureSessionCallback {
    @JavaMethod
    static func nativeOnConfigured(_ handle: Int64, _ session: CameraCaptureSession?, environment: JNIEnvironment) {
        guard let capture = CameraSession.from(handle: handle), let session else { return }
        capture.configured(session, in: environment)
    }

    @JavaMethod
    static func nativeOnConfigureFailed(_ handle: Int64, _ session: CameraCaptureSession?, environment: JNIEnvironment) {
        CameraSession.from(handle: handle)?.failed(.sessionConfigurationFailed, in: environment)
    }
}

// MARK: - ImageAvailableListener

@JavaClass("org.nucleantui.android.camera.ImageAvailableListener", implements: ImageReaderOnImageAvailableListener.self)
class ImageAvailableListener: JavaObject {
    @JavaMethod
    convenience init(_ handle: Int64, _ stream: Int32, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.camera.ImageAvailableListener")
extension ImageAvailableListener {
    @JavaMethod
    static func nativeOnImageAvailable(_ handle: Int64, _ stream: Int32, _ reader: ImageReader?, environment: JNIEnvironment) {
        guard let capture = CameraSession.from(handle: handle), let reader else { return }
        capture.imageAvailable(stream: stream, reader: reader, in: environment)
    }
}
