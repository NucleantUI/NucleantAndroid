//
//  Battery.swift
//  AndroidBattery
//
//  The battery and power state, kept current from Android's battery broadcast
//  (`ACTION_BATTERY_CHANGED`, sent on every change of level, charger, health or
//  temperature) and the power-saver broadcast. No permission needed.
//
//  The emulator's battery is virtual and fully controllable: Extended controls
//  → Battery, or `adb emu power capacity 30` / `adb emu power ac off`.
//

import AndroidCore
import Observation
import SwiftJava

/// Whether the battery is charging (`BatteryManager.BATTERY_STATUS_*`).
public enum ABatteryState: Sendable, Hashable {
    case unknown
    case charging
    case discharging
    /// Plugged in, but not taking charge.
    case notCharging
    case full

    init(status: Int32) {
        switch status {
        case 2: self = .charging
        case 3: self = .discharging
        case 4: self = .notCharging
        case 5: self = .full
        default: self = .unknown
        }
    }
}

/// What the device is plugged into (`BatteryManager.BATTERY_PLUGGED_*`).
public enum APowerSource: Sendable, Hashable {
    case battery
    case ac
    case usb
    case wireless
    case dock

    init(plugged: Int32) {
        switch plugged {
        case 1: self = .ac
        case 2: self = .usb
        case 4: self = .wireless
        case 8: self = .dock
        default: self = .battery
        }
    }
}

/// `BatteryManager.BATTERY_HEALTH_*`.
public enum ABatteryHealth: Sendable, Hashable {
    case unknown
    case good
    case overheat
    case dead
    case overVoltage
    case failure
    case cold

    init(health: Int32) {
        switch health {
        case 2: self = .good
        case 3: self = .overheat
        case 4: self = .dead
        case 5: self = .overVoltage
        case 6: self = .failure
        case 7: self = .cold
        default: self = .unknown
        }
    }
}

/// The battery, as Android last reported it. Create and use it on the main
/// thread, where the broadcasts arrive; it listens for as long as it exists.
@Observable
public final class ABattery: @unchecked Sendable {
    /// Charge, 0...1; nil when the device reports none.
    public private(set) var level: Double?
    public private(set) var state: ABatteryState = .unknown
    public private(set) var powerSource: APowerSource = .battery
    public private(set) var health: ABatteryHealth = .unknown
    /// °C; nil when the device reports none.
    public private(set) var temperature: Double?
    /// Volts; nil when the device reports none.
    public private(set) var voltage: Double?
    /// "Li-ion" and the like; empty when unknown.
    public private(set) var technology = ""
    /// Battery saver.
    public private(set) var isPowerSaveMode = false

    public var isCharging: Bool {
        state == .charging || state == .full
    }

    @ObservationIgnored private let context: Context
    @ObservationIgnored private let powerManager: PowerManager?
    @ObservationIgnored private var receiver: BatteryReceiver?
    @ObservationIgnored private var handle: Int64 = 0

    static let batteryChanged = "android.intent.action.BATTERY_CHANGED"
    static let powerSaveModeChanged = "android.os.action.POWER_SAVE_MODE_CHANGED"

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        self.context = context
        self.powerManager = context.getSystemService("power")?.as(PowerManager.self)
        isPowerSaveMode = powerManager?.isPowerSaveMode() ?? false

        let handle = NativeHandle.retain(self)
        let receiver = BatteryReceiver(handle, environment: environment)
        self.handle = handle
        self.receiver = receiver
        let filter = IntentFilter(Self.batteryChanged, environment: environment)
        filter.addAction(Self.powerSaveModeChanged)
        let flags = try AndroidContext.shared.sdkLevel(in: environment) >= 33 ? Context.receiverNotExported : 0
        // BATTERY_CHANGED is sticky: registering returns the latest one at once.
        let latest = context.registerReceiver(
            receiver, filter, nil, try AndroidMainThread.shared.mainHandler(in: environment), flags)
        if let latest {
            update(from: latest)
        }
    }

    deinit {
        guard let receiver else { return }
        let batteryReceiver = JavaGlobalReference(receiver)
        let context = JavaGlobalReference(self.context)
        let handle = self.handle
        try? AndroidMainThread.shared.post { environment in
            let receiver = batteryReceiver.wrapped(as: BatteryReceiver.self, in: environment)
            receiver.disarm()
            context.wrapped(as: Context.self, in: environment).unregisterReceiver(receiver)
            NativeHandle<ABattery>.release(handle)
        }
    }

    func received(_ intent: Intent) {
        if intent.getAction() == Self.powerSaveModeChanged {
            isPowerSaveMode = powerManager?.isPowerSaveMode() ?? false
        } else {
            update(from: intent)
        }
    }

    /// From a BATTERY_CHANGED intent's extras (`BatteryManager.EXTRA_*`).
    private func update(from intent: Intent) {
        level = Self.level(raw: intent.getIntExtra("level", -1), scale: intent.getIntExtra("scale", -1))
        state = ABatteryState(status: intent.getIntExtra("status", 1))
        powerSource = APowerSource(plugged: intent.getIntExtra("plugged", 0))
        health = ABatteryHealth(health: intent.getIntExtra("health", 1))
        let tenthsOfDegree = intent.getIntExtra("temperature", Int32.min)
        temperature = tenthsOfDegree == Int32.min ? nil : Double(tenthsOfDegree) / 10
        let millivolts = intent.getIntExtra("voltage", -1)
        voltage = millivolts <= 0 ? nil : Double(millivolts) / 1000
        technology = intent.getStringExtra("technology")
    }

    /// `level / scale`, or nil when either is missing.
    static func level(raw: Int32, scale: Int32) -> Double? {
        guard raw >= 0, scale > 0 else { return nil }
        return min(1, Double(raw) / Double(scale))
    }
}

// MARK: - Framework

/// `android.os.PowerManager`.
@JavaClass("android.os.PowerManager")
open class PowerManager: JavaObject {
    @JavaMethod
    open func isPowerSaveMode() -> Bool
}

// MARK: - BatteryReceiver (Android/java)

@JavaClass("org.nucleantui.android.battery.BatteryReceiver")
class BatteryReceiver: BroadcastReceiver {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.battery.BatteryReceiver")
extension BatteryReceiver {
    @JavaMethod
    static func nativeOnReceive(_ handle: Int64, _ intent: Intent?, environment: JNIEnvironment) {
        guard let intent else { return }
        NativeHandle<ABattery>.owner(handle)?.received(intent)
    }
}
