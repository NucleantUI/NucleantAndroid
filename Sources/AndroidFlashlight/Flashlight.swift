//
//  Flashlight.swift
//  AndroidFlashlight
//
//  The device's flashlight (the camera flash used as a torch), through
//  CameraManager's torch mode.
//
//  No permission is needed: torch mode is not camera access. `AFlashlight()`
//  is nil on a device without a flash unit. Recent emulator images emulate one
//  (Android 16's: on camera 1, with 10 brightness levels).
//

import AndroidCore
import AndroidHardwareCamera2
import Observation
import SwiftJava

/// The flashlight. Create and use it on the main thread; its state changes
/// there too, including when the torch is switched from outside the app — it
/// listens to Android's torch callback for as long as it exists.
@Observable
public final class AFlashlight: @unchecked Sendable {
    /// The camera whose flash unit this is.
    public let cameraID: String
    /// Brightness levels the torch has; 1 when it is only on or off.
    public let maximumLevel: Int

    /// Whether the torch is on.
    public private(set) var isOn = false
    /// Whether the torch can be switched right now: false while an app has the
    /// camera it belongs to open.
    public private(set) var isAvailable = true
    /// The brightness level the torch is (or turns) on at, 1...maximumLevel.
    public private(set) var level: Int

    @ObservationIgnored private let manager: CameraManager
    @ObservationIgnored private var torchCallback: TorchCallback?
    @ObservationIgnored private var handle: Int64 = 0

    /// The device's flashlight, or nil when it has none. Prefers the flash of a
    /// back-facing camera, as the system's own torch does.
    public init?() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let manager = try CameraManager.service(in: environment)
        let keys = try JavaClass<CameraCharacteristics>(environment: environment)
        let sdkLevel = try AndroidContext.shared.sdkLevel(in: environment)

        var chosen: (id: String, characteristics: CameraCharacteristics)?
        for id in try manager.getCameraIdList() {
            guard let characteristics = try manager.getCameraCharacteristics(id),
                  characteristics.get(keys.FLASH_INFO_AVAILABLE)?.as(JavaBoolean.self)?.booleanValue() == true
            else { continue }
            let facing = characteristics.get(keys.LENS_FACING)?.as(JavaInteger.self)?.intValue()
            if chosen == nil || facing == Self.lensFacingBack {
                chosen = (id, characteristics)
            }
            if facing == Self.lensFacingBack { break }
        }
        guard let chosen else { return nil }

        var maximumLevel = 1
        var defaultLevel = 1
        if sdkLevel >= 33 {
            maximumLevel = Int(chosen.characteristics.get(keys.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL)?
                .as(JavaInteger.self)?.intValue() ?? 1)
            defaultLevel = Int(chosen.characteristics.get(keys.FLASH_INFO_STRENGTH_DEFAULT_LEVEL)?
                .as(JavaInteger.self)?.intValue() ?? Int32(maximumLevel))
        }
        self.manager = manager
        self.cameraID = chosen.id
        self.maximumLevel = max(1, maximumLevel)
        self.level = min(max(1, defaultLevel), max(1, maximumLevel))

        // Android calls back right away with the current state, then on every change.
        let handle = NativeHandle.retain(self)
        let callback = TorchCallback(handle, environment: environment)
        self.handle = handle
        self.torchCallback = callback
        manager.registerTorchCallback(callback, try AndroidMainThread.shared.mainHandler(in: environment))
    }

    deinit {
        guard let torchCallback else { return }
        let callback = JavaGlobalReference(torchCallback)
        let manager = JavaGlobalReference(self.manager)
        let handle = self.handle
        try? AndroidMainThread.shared.post { environment in
            let torchCallback = callback.wrapped(as: TorchCallback.self, in: environment)
            torchCallback.disarm()
            manager.wrapped(as: CameraManager.self, in: environment).unregisterTorchCallback(torchCallback)
            NativeHandle<AFlashlight>.release(handle)
        }
    }

    /// Whether `turnOn(brightness:)` can choose a brightness.
    public var supportsBrightness: Bool {
        maximumLevel > 1
    }

    /// `level` as a fraction of the brightest, 0...1.
    public var brightness: Double {
        Double(level) / Double(maximumLevel)
    }

    // MARK: - Switching

    /// Turn the torch on at its current level.
    public func turnOn() throws {
        try turnOn(level: level)
    }

    /// Turn the torch on at `brightness`, from 0 (dimmest) to 1 (brightest).
    /// Without `supportsBrightness`, any brightness is simply on.
    public func turnOn(brightness: Double) throws {
        try turnOn(level: Self.level(forBrightness: brightness, maximumLevel: maximumLevel))
    }

    public func turnOff() throws {
        try manager.setTorchMode(cameraID, false)
        isOn = false
    }

    public func toggle() throws {
        if isOn {
            try turnOff()
        } else {
            try turnOn()
        }
    }

    private func turnOn(level: Int) throws {
        if supportsBrightness {
            try manager.turnOnTorchWithStrengthLevel(cameraID, Int32(level))
            self.level = level
        } else {
            try manager.setTorchMode(cameraID, true)
        }
        isOn = true
    }

    // MARK: - Android's torch callback

    func torchModeChanged(cameraID: String, enabled: Bool) {
        guard cameraID == self.cameraID else { return }
        isAvailable = true
        isOn = enabled
    }

    func torchModeUnavailable(cameraID: String) {
        guard cameraID == self.cameraID else { return }
        isAvailable = false
        isOn = false
    }

    func torchStrengthLevelChanged(cameraID: String, level: Int) {
        guard cameraID == self.cameraID else { return }
        self.level = min(max(1, level), maximumLevel)
    }

    /// The torch level for `brightness` (0...1): 1 is the dimmest level the
    /// torch has, `maximumLevel` the brightest.
    static func level(forBrightness brightness: Double, maximumLevel: Int) -> Int {
        let clamped = min(max(brightness, 0), 1)
        return max(1, Int((clamped * Double(maximumLevel)).rounded(.up)))
    }

    /// `CameraCharacteristics.LENS_FACING_BACK`.
    private static let lensFacingBack: Int32 = 1
}

// MARK: - TorchCallback (Android/java)

@JavaClass("org.nucleantui.android.flashlight.TorchCallback")
class TorchCallback: CameraManagerTorchCallback {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.flashlight.TorchCallback")
extension TorchCallback {
    @JavaMethod
    static func nativeOnTorchModeChanged(_ handle: Int64, _ cameraId: String, _ enabled: Bool, environment: JNIEnvironment) {
        NativeHandle<AFlashlight>.owner(handle)?.torchModeChanged(cameraID: cameraId, enabled: enabled)
    }

    @JavaMethod
    static func nativeOnTorchModeUnavailable(_ handle: Int64, _ cameraId: String, environment: JNIEnvironment) {
        NativeHandle<AFlashlight>.owner(handle)?.torchModeUnavailable(cameraID: cameraId)
    }

    @JavaMethod
    static func nativeOnTorchStrengthLevelChanged(_ handle: Int64, _ cameraId: String, _ level: Int32, environment: JNIEnvironment) {
        NativeHandle<AFlashlight>.owner(handle)?.torchStrengthLevelChanged(cameraID: cameraId, level: Int(level))
    }
}
