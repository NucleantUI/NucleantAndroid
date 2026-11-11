//
//  Device.swift
//  AndroidDevice
//
//  What the device is (Build), its screen (DisplayMetrics) and memory
//  (ActivityManager), plus the two screen settings an app may override for
//  its own window: keeping the screen on, and its brightness.
//  No permission needed.
//

import AndroidCore
import Observation
import SwiftJava

/// The device. Create and use it on the main thread: the screen settings go
/// through the attached Activity's window.
@Observable
public final class ADevice: @unchecked Sendable {
    public let manufacturer: String
    public let model: String
    public let brand: String
    /// Build.DEVICE: the industrial design's codename.
    public let deviceName: String
    public let product: String
    public let hardware: String
    public let fingerprint: String
    /// ABIs the device runs, preferred first.
    public let supportedABIs: [String]
    public let sdkLevel: Int
    /// The Android version ("16").
    public let release: String
    /// Whether this looks like the Android emulator (by its build properties).
    public let isEmulator: Bool

    /// The screen in pixels, and the density factor (pixels per dp).
    public let screenWidth: Int
    public let screenHeight: Int
    public let screenDensity: Double
    public let screenDPI: Int

    /// Total and available RAM in bytes, as of init or the last `refresh()`.
    public private(set) var totalMemory: Int64 = 0
    public private(set) var availableMemory: Int64 = 0
    /// Whether the system considers memory low.
    public private(set) var isLowOnMemory = false

    /// Whether the app's window keeps the screen from turning off.
    public private(set) var keepsScreenOn = false
    /// The app window's brightness override, 0...1; nil follows the system.
    public private(set) var screenBrightness: Double?

    @ObservationIgnored private let activityManager: ActivityManager?

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let build = try JavaClass<Build>(environment: environment)
        let version = try JavaClass<BuildVersion>(environment: environment)
        manufacturer = build.MANUFACTURER
        model = build.MODEL
        brand = build.BRAND
        deviceName = build.DEVICE
        product = build.PRODUCT
        hardware = build.HARDWARE
        fingerprint = build.FINGERPRINT
        supportedABIs = build.SUPPORTED_ABIS
        sdkLevel = Int(version.SDK_INT)
        release = version.RELEASE
        isEmulator = Self.looksLikeEmulator(fingerprint: fingerprint, hardware: hardware, product: product)

        let context = try AndroidContext.shared.applicationContext(in: environment)
        let metrics = context.getResources()?.getDisplayMetrics()
        screenWidth = Int(metrics?.widthPixels ?? 0)
        screenHeight = Int(metrics?.heightPixels ?? 0)
        screenDensity = Double(metrics?.density ?? 1)
        screenDPI = Int(metrics?.densityDpi ?? 160)
        activityManager = context.getSystemService("activity")?.as(ActivityManager.self)

        if let window = try? AndroidContext.shared.activity(in: environment).getWindow(),
           let attributes = window.getAttributes()
        {
            keepsScreenOn = attributes.flags & WindowLayoutParams.flagKeepScreenOn != 0
            screenBrightness = attributes.screenBrightness < 0 ? nil : Double(attributes.screenBrightness)
        }
        try refresh()
    }

    /// Read the memory figures again.
    public func refresh() throws {
        guard let activityManager else { return }
        let info = ActivityManagerMemoryInfo(environment: try JavaVirtualMachine.shared().environment())
        activityManager.getMemoryInfo(info)
        totalMemory = info.totalMem
        availableMemory = info.availMem
        isLowOnMemory = info.lowMemory
    }

    /// Keep the screen on while the app's window is showing.
    public func setKeepsScreenOn(_ on: Bool) throws {
        let window = try activityWindow()
        if on {
            window.addFlags(WindowLayoutParams.flagKeepScreenOn)
        } else {
            window.clearFlags(WindowLayoutParams.flagKeepScreenOn)
        }
        keepsScreenOn = on
    }

    /// Override the screen's brightness (0...1) while the app's window is
    /// showing; nil hands it back to the system.
    public func setScreenBrightness(_ brightness: Double?) throws {
        let window = try activityWindow()
        guard let attributes = window.getAttributes() else { return }
        attributes.screenBrightness = brightness.map { Float(min(max($0, 0), 1)) } ?? -1
        window.setAttributes(attributes)
        screenBrightness = brightness.map { min(max($0, 0), 1) }
    }

    private func activityWindow() throws -> Window {
        let environment = try JavaVirtualMachine.shared().environment()
        guard let window = try AndroidContext.shared.activity(in: environment).getWindow() else {
            throw AndroidError.noActivity
        }
        return window
    }

    static func looksLikeEmulator(fingerprint: String, hardware: String, product: String) -> Bool {
        fingerprint.hasPrefix("generic") || fingerprint.contains("emulator") || fingerprint.contains("/sdk_")
            || hardware == "ranchu" || hardware == "goldfish"
            || product.hasPrefix("sdk") || product.contains("_sdk")
    }
}

// MARK: - Framework

/// `android.os.Build`.
@JavaClass("android.os.Build")
open class Build: JavaObject {}

extension JavaClass<Build> {
    @JavaStaticField(isFinal: true) public var MANUFACTURER: String
    @JavaStaticField(isFinal: true) public var MODEL: String
    @JavaStaticField(isFinal: true) public var BRAND: String
    @JavaStaticField(isFinal: true) public var DEVICE: String
    @JavaStaticField(isFinal: true) public var PRODUCT: String
    @JavaStaticField(isFinal: true) public var HARDWARE: String
    @JavaStaticField(isFinal: true) public var FINGERPRINT: String
    @JavaStaticField(isFinal: true) public var SUPPORTED_ABIS: [String]
}

/// `android.app.ActivityManager`.
@JavaClass("android.app.ActivityManager")
open class ActivityManager: JavaObject {
    @JavaMethod
    open func getMemoryInfo(_ outInfo: ActivityManagerMemoryInfo?)
}

/// `android.app.ActivityManager.MemoryInfo`.
@JavaClass("android.app.ActivityManager$MemoryInfo")
open class ActivityManagerMemoryInfo: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(environment: JNIEnvironment? = nil)

    @JavaField public var totalMem: Int64
    @JavaField public var availMem: Int64
    @JavaField public var lowMemory: Bool
}
