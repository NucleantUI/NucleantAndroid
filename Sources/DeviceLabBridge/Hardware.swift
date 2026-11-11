//
//  Hardware.swift
//  DeviceLabBridge
//
//  AndroidHaptics, AndroidBattery, AndroidSensors and AndroidDevice for Kotlin.
//

import AndroidBattery
import AndroidCore
import AndroidDevice
import AndroidHaptics
import AndroidSensors
import Observation
import SwiftJava

// MARK: - Haptics

public final class LabVibrator: @unchecked Sendable {
    let vibrator: AVibrator

    public init() throws {
        vibrator = try AVibrator()
    }

    public var hasVibrator: Bool { vibrator.hasVibrator }
    public var hasAmplitudeControl: Bool { vibrator.hasAmplitudeControl }

    public func vibrate(milliseconds: Int64, intensity: Double) throws {
        try vibrator.vibrate(milliseconds: Int(milliseconds), intensity: intensity)
    }

    /// Segments of `milliseconds[i]` at `intensities[i]` (0 = pause).
    public func vibratePattern(milliseconds: [Int64], intensities: [Double], repeating: Bool) throws {
        try vibrator.vibrate(
            pattern: zip(milliseconds, intensities).map { (milliseconds: Int($0), intensity: $1) },
            repeating: repeating)
    }

    /// "click", "doubleClick", "tick", "heavyClick".
    public var effectNames: [String] { AHapticEffect.allCases.map(Self.name) }

    public func playEffect(name: String) throws {
        guard let effect = AHapticEffect.allCases.first(where: { Self.name($0) == name }) else { return }
        try vibrator.play(effect)
    }

    /// 1 tuned for this device, 0 approximated, -1 unknown.
    public func effectSupport(name: String) -> Int32 {
        guard let effect = AHapticEffect.allCases.first(where: { Self.name($0) == name }) else { return -1 }
        return vibrator.supports(effect).map { $0 ? 1 : 0 } ?? -1
    }

    public func cancel() { vibrator.cancel() }

    /// "tap", "longPress", "contextClick", "tick", "success", "error", "gestureStart", …
    public var feedbackNames: [String] { AHapticFeedback.allCases.map { "\($0)" } }

    /// False when the system skipped it (touch feedback switched off).
    public func performFeedback(name: String) throws -> Bool {
        guard let feedback = AHapticFeedback.allCases.first(where: { "\($0)" == name }) else { return false }
        return try vibrator.perform(feedback)
    }

    static func name(_ effect: AHapticEffect) -> String {
        switch effect {
        case .click: "click"
        case .doubleClick: "doubleClick"
        case .tick: "tick"
        case .heavyClick: "heavyClick"
        }
    }
}

// MARK: - Battery

public final class LabBattery: @unchecked Sendable {
    let battery: ABattery
    let observer = ChangeObserver()

    public init() throws {
        battery = try ABattery()
    }

    /// 0...1; NaN when unknown.
    public var level: Double { orNaN(battery.level) }
    public var isCharging: Bool { battery.isCharging }
    public var state: String { "\(battery.state)" }
    public var powerSource: String { "\(battery.powerSource)" }
    public var health: String { "\(battery.health)" }
    /// °C; NaN when unknown.
    public var temperature: Double { orNaN(battery.temperature) }
    /// Volts; NaN when unknown.
    public var voltage: Double { orNaN(battery.voltage) }
    public var technology: String { battery.technology }
    public var isPowerSaveMode: Bool { battery.isPowerSaveMode }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [battery] in
            _ = (battery.level, battery.state, battery.powerSource, battery.health)
            _ = (battery.temperature, battery.voltage, battery.technology, battery.isPowerSaveMode)
        }, listener: listener)
    }
}

// MARK: - Sensors

public final class LabSensors: @unchecked Sendable {
    let sensors: ASensors

    public init() throws {
        sensors = try ASensors()
    }

    public var all: [LabSensor] { sensors.all.map(LabSensor.init) }
}

public final class LabSensor: @unchecked Sendable {
    let sensor: ASensor
    let observer = ChangeObserver()

    init(_ sensor: ASensor) {
        self.sensor = sensor
    }

    public var name: String { sensor.name }
    public var vendor: String { sensor.vendor }
    public var typeName: String { sensor.typeName }
    public var unit: String { sensor.unit }
    public var maximumRange: Float { sensor.maximumRange }
    public var resolution: Float { sensor.resolution }
    /// Milliamps.
    public var power: Float { sensor.power }
    public var isRunning: Bool { sensor.isRunning }
    public var values: [Float] { sensor.values }
    public var accuracy: Int32 { Int32(sensor.accuracy) }

    /// `rate`: "normal", "ui", "game" or "fastest".
    public func start(rate: String) throws -> Bool {
        let rates: [ASensorRate] = [.normal, .ui, .game, .fastest]
        return try sensor.start(rate: rates.first { "\($0)" == rate } ?? .ui)
    }

    public var rate: String { "\(sensor.rate)" }
    /// Whether it needs a runtime permission (the step sensors).
    public var needsPermission: Bool { sensor.permission != nil }
    public var isAuthorized: Bool { (try? sensor.isAuthorized()) ?? false }
    public func requestAccess() async throws -> Bool { try await sensor.requestAuthorization() }
    public func stop() { sensor.stop() }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [sensor] in _ = (sensor.values, sensor.accuracy, sensor.isRunning) }, listener: listener)
    }

    public func stopObserving() { observer.stop() }
}

// MARK: - Device

public final class LabDevice: @unchecked Sendable {
    let device: ADevice
    let observer = ChangeObserver()

    public init() throws {
        device = try ADevice()
    }

    public var manufacturer: String { device.manufacturer }
    public var model: String { device.model }
    public var brand: String { device.brand }
    public var deviceName: String { device.deviceName }
    public var product: String { device.product }
    public var hardware: String { device.hardware }
    public var fingerprint: String { device.fingerprint }
    public var supportedABIs: [String] { device.supportedABIs }
    public var sdkLevel: Int32 { Int32(device.sdkLevel) }
    public var release: String { device.release }
    public var isEmulator: Bool { device.isEmulator }
    public var screenWidth: Int32 { Int32(device.screenWidth) }
    public var screenHeight: Int32 { Int32(device.screenHeight) }
    public var screenDensity: Double { device.screenDensity }
    public var screenDPI: Int32 { Int32(device.screenDPI) }
    public var totalMemory: Int64 { device.totalMemory }
    public var availableMemory: Int64 { device.availableMemory }
    public var isLowOnMemory: Bool { device.isLowOnMemory }
    public var keepsScreenOn: Bool { device.keepsScreenOn }
    /// 0...1; -1 when the system decides.
    public var screenBrightness: Double { device.screenBrightness ?? -1 }

    public func setKeepsScreenOn(on: Bool) throws { try device.setKeepsScreenOn(on) }

    /// 0...1; negative hands it back to the system.
    public func setScreenBrightness(brightness: Double) throws {
        try device.setScreenBrightness(brightness < 0 ? nil : brightness)
    }

    public func refresh() throws { try device.refresh() }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [device] in
            _ = (device.availableMemory, device.isLowOnMemory, device.keepsScreenOn, device.screenBrightness)
        }, listener: listener)
    }
}
