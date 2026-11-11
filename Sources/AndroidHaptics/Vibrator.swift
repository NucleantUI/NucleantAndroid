//
//  Vibrator.swift
//  AndroidHaptics
//
//  The device's vibration motor: timed vibrations, patterns, and the system's
//  predefined haptic effects. Needs `android.permission.VIBRATE` in the
//  manifest (a normal permission: granted on install).
//
//  The emulator reports a vibrator and accepts every call, but nothing moves —
//  logcat's "Vibrator" lines are where it shows.
//

import AndroidCore
import Observation
import SwiftJava

/// The system's predefined haptic effects (`VibrationEffect.EFFECT_*`).
public enum AHapticEffect: Sendable, Hashable, CaseIterable {
    case click
    case doubleClick
    case tick
    case heavyClick

    var effectID: Int32 {
        switch self {
        case .click: 0
        case .doubleClick: 1
        case .tick: 2
        case .heavyClick: 5
        }
    }
}

/// The vibrator.
@Observable
public final class AVibrator: @unchecked Sendable {
    /// Whether there is a vibration motor at all.
    public let hasVibrator: Bool
    /// Whether vibrations can have an intensity, rather than only on/off.
    public let hasAmplitudeControl: Bool

    @ObservationIgnored private let vibrator: Vibrator
    @ObservationIgnored private let sdkLevel: Int

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        sdkLevel = try AndroidContext.shared.sdkLevel(in: environment)
        let found: Vibrator? = sdkLevel >= 31
            ? context.getSystemService("vibrator_manager")?.as(VibratorManager.self)?.getDefaultVibrator()
            : context.getSystemService("vibrator")?.as(Vibrator.self)
        guard let found else {
            throw AndroidError.serviceUnavailable("vibrator")
        }
        vibrator = found
        hasVibrator = found.hasVibrator()
        hasAmplitudeControl = found.hasAmplitudeControl()
    }

    /// Vibrate for `milliseconds` at `intensity` (0...1; only matters with
    /// `hasAmplitudeControl`).
    public func vibrate(milliseconds: Int, intensity: Double = 1) throws {
        let effects = try JavaClass<VibrationEffect>(environment: JavaVirtualMachine.shared().environment())
        try vibrator.vibrate(effects.createOneShot(Int64(milliseconds), amplitude(intensity)))
    }

    /// Play `segments` one after another: each runs for its milliseconds at its
    /// intensity, 0 being a pause. With `repeating`, the pattern starts over
    /// until `cancel()`.
    public func vibrate(pattern segments: [(milliseconds: Int, intensity: Double)], repeating: Bool = false) throws {
        let effects = try JavaClass<VibrationEffect>(environment: JavaVirtualMachine.shared().environment())
        let timings = segments.map { Int64($0.milliseconds) }
        let amplitudes = segments.map { $0.intensity <= 0 ? 0 : amplitude($0.intensity) }
        try vibrator.vibrate(try effects.createWaveform(timings, amplitudes, repeating ? 0 : -1))
    }

    /// Play one of the system's haptic effects.
    public func play(_ effect: AHapticEffect) throws {
        let effects = try JavaClass<VibrationEffect>(environment: JavaVirtualMachine.shared().environment())
        try vibrator.vibrate(effects.createPredefined(effect.effectID))
    }

    /// Whether the device has a tuned implementation of `effect` (Android 11+;
    /// nil when it cannot tell). Without one, Android plays an approximation.
    public func supports(_ effect: AHapticEffect) -> Bool? {
        guard sdkLevel >= 30 else { return nil }
        switch vibrator.areEffectsSupported([effect.effectID]).first {
        case 1: return true
        case 2: return false
        default: return nil
        }
    }

    /// Stop whatever is vibrating.
    public func cancel() {
        vibrator.cancel()
    }

    private func amplitude(_ intensity: Double) -> Int32 {
        hasAmplitudeControl ? Self.amplitude(forIntensity: intensity) : -1 // VibrationEffect.DEFAULT_AMPLITUDE
    }

    /// `intensity` (0...1) as a VibrationEffect amplitude, 1...255.
    static func amplitude(forIntensity intensity: Double) -> Int32 {
        Int32(max(1, min(255, (min(max(intensity, 0), 1) * 255).rounded())))
    }
}

// MARK: - Framework

/// `android.os.Vibrator`.
@JavaClass("android.os.Vibrator")
open class Vibrator: JavaObject {
    @JavaMethod
    open func hasVibrator() -> Bool

    @JavaMethod
    open func hasAmplitudeControl() -> Bool

    @JavaMethod
    open func vibrate(_ effect: VibrationEffect?) throws

    /// API 30. `VIBRATION_EFFECT_SUPPORT_*` per effect.
    @JavaMethod
    open func areEffectsSupported(_ effectIds: [Int32]) -> [Int32]

    @JavaMethod
    open func cancel()
}

/// `android.os.VibratorManager`, API 31.
@JavaClass("android.os.VibratorManager")
open class VibratorManager: JavaObject {
    @JavaMethod
    open func getDefaultVibrator() -> Vibrator!
}

/// `android.os.VibrationEffect`.
@JavaClass("android.os.VibrationEffect")
open class VibrationEffect: JavaObject {}

extension JavaClass<VibrationEffect> {
    @JavaStaticMethod
    public func createOneShot(_ milliseconds: Int64, _ amplitude: Int32) -> VibrationEffect!

    @JavaStaticMethod
    public func createWaveform(_ timings: [Int64], _ amplitudes: [Int32], _ repeatIndex: Int32) throws -> VibrationEffect!

    /// API 29.
    @JavaStaticMethod
    public func createPredefined(_ effectId: Int32) -> VibrationEffect!
}
