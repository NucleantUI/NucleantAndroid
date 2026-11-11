//
//  Sensors.swift
//  AndroidSensors
//
//  The device's sensors — motion, environment, position — and their readings,
//  through SensorManager. No permission needed (except body sensors, which are
//  not covered here).
//
//  The emulator has virtual ones (accelerometer, gyroscope, magnetometer,
//  light, pressure, proximity, …) driven from Extended controls → Virtual
//  sensors.
//

import AndroidCore
import Observation
import SwiftJava

/// The well-known sensor types: `Sensor.TYPE_*`.
public enum ASensorKind: Int32, Sendable {
    case accelerometer = 1
    case magneticField = 2
    case gyroscope = 4
    case light = 5
    case pressure = 6
    case proximity = 8
    case gravity = 9
    case linearAcceleration = 10
    case rotationVector = 11
    case relativeHumidity = 12
    case ambientTemperature = 13
    case stepDetector = 18
    case stepCounter = 19

    /// The unit of its readings.
    public var unit: String {
        switch self {
        case .accelerometer, .gravity, .linearAcceleration: "m/s²"
        case .magneticField: "µT"
        case .gyroscope: "rad/s"
        case .light: "lx"
        case .pressure: "hPa"
        case .proximity: "cm"
        case .relativeHumidity: "%"
        case .ambientTemperature: "°C"
        case .stepDetector, .stepCounter: "steps"
        case .rotationVector: ""
        }
    }
}

/// How often a sensor reports: `SensorManager.SENSOR_DELAY_*`.
public enum ASensorRate: Int32, Sendable {
    case fastest = 0
    case game = 1
    case ui = 2
    case normal = 3
}

// MARK: - ASensors

/// The sensors the device has. The list is fixed for the life of the app.
@Observable
public final class ASensors: @unchecked Sendable {
    public let all: [ASensor]

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        guard let manager = context.getSystemService("sensor")?.as(SensorManager.self) else {
            throw AndroidError.serviceUnavailable("sensor")
        }
        var sensors: [ASensor] = []
        if let list = manager.getSensorList(-1) { // Sensor.TYPE_ALL
            for sensor in list {
                sensors.append(ASensor(sensor, manager: manager))
            }
        }
        all = sensors
    }

    /// The first sensor of `kind`, the one `SensorManager.getDefaultSensor` picks.
    public func first(_ kind: ASensorKind) -> ASensor? {
        all.first { $0.kind == kind }
    }
}

// MARK: - ASensor

/// One sensor, and its latest reading once started. Use it on the main thread,
/// where its readings arrive.
@Observable
public final class ASensor: Identifiable, @unchecked Sendable {
    public let name: String
    public let vendor: String
    /// Android's `Sensor.TYPE_*` for it.
    public let type: Int32
    /// `type` as one of the well-known kinds; nil for any other.
    public let kind: ASensorKind?
    /// Android's name for its type ("android.sensor.accelerometer").
    public let typeName: String
    /// Largest value it reports, in `unit`.
    public let maximumRange: Float
    public let resolution: Float
    /// Milliamps while running.
    public let power: Float
    @ObservationIgnored public let sensor: Sensor

    /// Whether readings are coming in.
    public private(set) var isRunning = false
    /// How often it reports, while running.
    public private(set) var rate: ASensorRate = .ui
    /// The latest reading: one value per axis or quantity, in `unit`.
    public private(set) var values: [Float] = []
    /// `SensorManager.SENSOR_STATUS_*`: 0 unreliable … 3 high.
    public private(set) var accuracy: Int = 0
    /// Nanoseconds since boot of the latest reading.
    public private(set) var timestamp: Int64 = 0

    public var id: String { "\(typeName)/\(name)" }

    /// The unit of its readings ("" when its kind is not a well-known one).
    public var unit: String { kind?.unit ?? "" }

    @ObservationIgnored private let manager: SensorManager
    @ObservationIgnored private var listener: SensorListener?
    @ObservationIgnored private var handle: Int64 = 0

    init(_ sensor: Sensor, manager: SensorManager) {
        self.sensor = sensor
        self.manager = manager
        name = sensor.getName()
        vendor = sensor.getVendor()
        type = sensor.getType()
        kind = ASensorKind(rawValue: type)
        typeName = sensor.getStringType()
        maximumRange = sensor.getMaximumRange()
        resolution = sensor.getResolution()
        power = sensor.getPower()
    }

    deinit {
        guard let listener else { return }
        let sensorListener = JavaGlobalReference(listener)
        let manager = JavaGlobalReference(self.manager)
        let handle = self.handle
        try? AndroidMainThread.shared.post { environment in
            let listener = sensorListener.wrapped(as: SensorListener.self, in: environment)
            listener.disarm()
            manager.wrapped(as: SensorManager.self, in: environment).unregisterListener(listener.eventListener)
            NativeHandle<ASensor>.release(handle)
        }
    }

    /// The runtime permission reading it needs, if any: the step sensors need
    /// `ACTIVITY_RECOGNITION` (Android 10+), declared in the manifest too.
    public var permission: String? {
        switch kind {
        case .stepCounter, .stepDetector: "android.permission.ACTIVITY_RECOGNITION"
        default: nil
        }
    }

    /// Whether `permission` is granted (true when there is none to grant).
    public func isAuthorized() throws -> Bool {
        guard let permission else { return true }
        return try AndroidContext.shared.isGranted(permission)
    }

    /// Ask for `permission`, if the sensor has one. True when it may be read.
    public func requestAuthorization() async throws -> Bool {
        guard let permission else { return true }
        return try await AndroidContext.shared.requestPermissions([permission])[permission] ?? false
    }

    /// Start reporting into `values` at `rate` (or change the rate while
    /// running). Returns false when the sensor refuses.
    @discardableResult
    public func start(rate: ASensorRate = .ui) throws -> Bool {
        guard try isAuthorized() else {
            throw ASensorError.notAuthorized
        }
        let environment = try JavaVirtualMachine.shared().environment()
        if listener == nil {
            handle = NativeHandle.retain(self)
            listener = SensorListener(handle, environment: environment)
        }
        guard let listener else { return false }
        manager.unregisterListener(listener.eventListener)
        isRunning = manager.registerListener(
            listener.eventListener, sensor, rate.rawValue, try AndroidMainThread.shared.mainHandler(in: environment))
        self.rate = rate
        return isRunning
    }

    public func stop() {
        if let listener {
            manager.unregisterListener(listener.eventListener)
        }
        isRunning = false
    }

    func changed(values: [Float], accuracy: Int32, timestamp: Int64) {
        self.values = values
        self.accuracy = Int(accuracy)
        self.timestamp = timestamp
    }

    func accuracyChanged(_ accuracy: Int32) {
        self.accuracy = Int(accuracy)
    }
}

public enum ASensorError: Error, CustomStringConvertible {
    case notAuthorized

    public var description: String {
        switch self {
        case .notAuthorized: "Reading this sensor needs a permission that has not been granted"
        }
    }
}

// MARK: - Framework

/// `android.hardware.SensorManager`.
@JavaClass("android.hardware.SensorManager")
open class SensorManager: JavaObject {
    @JavaMethod
    open func getSensorList(_ type: Int32) -> List<Sensor>!

    @JavaMethod
    open func registerListener(
        _ listener: SensorEventListener?, _ sensor: Sensor?, _ samplingPeriodUs: Int32, _ handler: Handler?
    ) -> Bool

    @JavaMethod
    open func unregisterListener(_ listener: SensorEventListener?)
}

/// `android.hardware.Sensor`.
@JavaClass("android.hardware.Sensor")
open class Sensor: JavaObject {
    @JavaMethod
    open func getName() -> String

    @JavaMethod
    open func getVendor() -> String

    @JavaMethod
    open func getType() -> Int32

    @JavaMethod
    open func getStringType() -> String

    @JavaMethod
    open func getMaximumRange() -> Float

    @JavaMethod
    open func getResolution() -> Float

    @JavaMethod
    open func getPower() -> Float
}

/// `android.hardware.SensorEventListener`.
@JavaInterface("android.hardware.SensorEventListener")
public struct SensorEventListener {}

// MARK: - SensorListener (Android/java)

@JavaClass("org.nucleantui.android.sensors.SensorListener", implements: SensorEventListener.self)
class SensorListener: JavaObject {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

extension SensorListener {
    /// As the interface `registerListener` takes.
    var eventListener: SensorEventListener? { self.as(SensorEventListener.self) }
}

@JavaImplementation("org.nucleantui.android.sensors.SensorListener")
extension SensorListener {
    @JavaMethod
    static func nativeOnSensorChanged(
        _ handle: Int64, _ values: [Float], _ accuracy: Int32, _ timestamp: Int64, environment: JNIEnvironment
    ) {
        NativeHandle<ASensor>.owner(handle)?.changed(values: values, accuracy: accuracy, timestamp: timestamp)
    }

    @JavaMethod
    static func nativeOnAccuracyChanged(_ handle: Int64, _ accuracy: Int32, environment: JNIEnvironment) {
        NativeHandle<ASensor>.owner(handle)?.accuracyChanged(accuracy)
    }
}
