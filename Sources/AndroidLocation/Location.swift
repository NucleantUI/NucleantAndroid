//
//  Location.swift
//  AndroidLocation
//
//  The device's position, through LocationManager.
//
//  Needs `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` in the manifest
//  and granted at run time (`requestAuthorization()`); the user may grant only
//  the coarse one (`.approximate`).
//
//  The emulator's position is set from Extended controls → Location (a single
//  point or a GPX/KML route), or `adb emu geo fix <longitude> <latitude>`.
//

import AndroidCore
import Observation
import SwiftJava

/// How precisely the app may know where the device is.
public enum ALocationAuthorization: Sendable, Hashable {
    case precise
    case approximate
    case denied
}

/// A position report.
public final class ALocationFix: Sendable {
    public let latitude: Double
    public let longitude: Double
    /// Meters above the WGS84 ellipsoid, if known.
    public let altitude: Double?
    /// Horizontal accuracy radius in meters (68% confidence), if known.
    public let accuracy: Double?
    /// m/s, if known.
    public let speed: Double?
    /// Degrees clockwise from north, if known.
    public let bearing: Double?
    /// When it was measured, in milliseconds since 1970-01-01 UTC.
    public let time: Int64
    /// The provider it came from ("gps", "network", "fused").
    public let provider: String

    init(_ location: Location) {
        latitude = location.getLatitude()
        longitude = location.getLongitude()
        altitude = location.hasAltitude() ? location.getAltitude() : nil
        accuracy = location.hasAccuracy() ? Double(location.getAccuracy()) : nil
        speed = location.hasSpeed() ? Double(location.getSpeed()) : nil
        bearing = location.hasBearing() ? Double(location.getBearing()) : nil
        time = location.getTime()
        provider = location.getProvider()
    }
}

/// The device's location. Create and use it on the main thread, where updates
/// arrive while `isUpdating`.
@Observable
public final class ALocation: @unchecked Sendable {
    public private(set) var authorization: ALocationAuthorization
    /// Whether location is switched on in the system settings.
    public private(set) var isEnabled: Bool
    public private(set) var isUpdating = false
    /// The latest position: the last known one until updates arrive.
    public private(set) var current: ALocationFix?
    /// The provider updates come from, while updating.
    public private(set) var provider: String?

    @ObservationIgnored let manager: LocationManager
    @ObservationIgnored private var listener: LocationUpdates?
    @ObservationIgnored private var handle: Int64 = 0

    static let fine = "android.permission.ACCESS_FINE_LOCATION"
    static let coarse = "android.permission.ACCESS_COARSE_LOCATION"

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        guard let manager = context.getSystemService("location")?.as(LocationManager.self) else {
            throw AndroidError.serviceUnavailable("location")
        }
        self.manager = manager
        authorization = try Self.currentAuthorization()
        isEnabled = manager.isLocationEnabled()
        current = lastKnown()
    }

    deinit {
        guard let listener else { return }
        let updates = JavaGlobalReference(listener)
        let manager = JavaGlobalReference(self.manager)
        let handle = self.handle
        try? AndroidMainThread.shared.post { environment in
            let listener = updates.wrapped(as: LocationUpdates.self, in: environment)
            listener.disarm()
            manager.wrapped(as: LocationManager.self, in: environment).removeUpdates(listener.locationListener)
            NativeHandle<ALocation>.release(handle)
        }
    }

    /// Ask for location access, precise if the user allows it.
    public func requestAuthorization() async throws -> ALocationAuthorization {
        let answer = try await AndroidContext.shared.requestPermissions([Self.fine, Self.coarse])
        let authorization = Self.authorization(fine: answer[Self.fine] ?? false, coarse: answer[Self.coarse] ?? false)
        try await AndroidMainThread.shared.run { _ in
            self.authorization = authorization
            if self.current == nil {
                self.current = self.lastKnown()
            }
        }
        return authorization
    }

    /// Start receiving positions into `current`: at most every
    /// `minimumInterval` milliseconds, and only after moving
    /// `minimumDistance` meters.
    public func startUpdates(minimumInterval: Int64 = 1000, minimumDistance: Float = 0) throws {
        guard authorization != .denied else {
            throw ALocationError.notAuthorized
        }
        let environment = try JavaVirtualMachine.shared().environment()
        guard let provider = Self.provider(
            among: try enabledProviders(), precise: authorization == .precise)
        else {
            throw ALocationError.noProvider
        }
        if listener == nil {
            handle = NativeHandle.retain(self)
            listener = LocationUpdates(handle, environment: environment)
        }
        guard let listener else { return }
        manager.removeUpdates(listener.locationListener)
        try manager.requestLocationUpdates(
            provider, minimumInterval, minimumDistance, listener.locationListener,
            try JavaClass<Looper>(environment: environment).getMainLooper())
        self.provider = provider
        isUpdating = true
    }

    public func stopUpdates() {
        if let listener {
            manager.removeUpdates(listener.locationListener)
        }
        isUpdating = false
        provider = nil
    }

    /// Read the settings switch and the permission state again.
    public func refresh() throws {
        authorization = try Self.currentAuthorization()
        isEnabled = manager.isLocationEnabled()
    }

    // MARK: - Callbacks

    func received(_ location: Location) {
        received(ALocationFix(location))
    }

    func received(_ fix: ALocationFix) {
        current = fix
    }

    func providerChanged(_ provider: String, enabled: Bool) {
        isEnabled = manager.isLocationEnabled()
        if !enabled, provider == self.provider {
            isUpdating = false
        }
    }

    // MARK: - Providers

    func enabledProviders() throws -> [String] {
        var names: [String] = []
        if let providers = manager.getProviders(true) {
            for name in providers {
                names.append(name.toString())
            }
        }
        return names
    }

    private func lastKnown() -> ALocationFix? {
        guard authorization != .denied, let names = try? enabledProviders() else { return nil }
        let fixes = names.compactMap { try? manager.getLastKnownLocation($0) }.map(ALocationFix.init)
        return fixes.max { $0.time < $1.time }
    }

    /// The provider to follow: the fused one where there is one, else GPS when
    /// precise access allows it, else the network.
    static func provider(among enabled: [String], precise: Bool) -> String? {
        let preference = precise ? ["fused", "gps", "network"] : ["fused", "network"]
        return preference.first(where: enabled.contains)
    }

    static func authorization(fine: Bool, coarse: Bool) -> ALocationAuthorization {
        fine ? .precise : coarse ? .approximate : .denied
    }

    static func currentAuthorization() throws -> ALocationAuthorization {
        authorization(
            fine: try AndroidContext.shared.isGranted(fine),
            coarse: try AndroidContext.shared.isGranted(coarse)
        )
    }
}

public enum ALocationError: Error, CustomStringConvertible {
    case notAuthorized
    case noProvider
    /// No position arrived in time.
    case timedOut
    /// The provider could not get a position.
    case noFix
    /// The device has no geocoding service.
    case noGeocoder

    public var description: String {
        switch self {
        case .notAuthorized: "Location access has not been granted"
        case .noProvider: "No location provider is enabled"
        case .timedOut: "No position arrived in time"
        case .noFix: "The location provider could not get a position"
        case .noGeocoder: "This device has no geocoding service"
        }
    }
}

// MARK: - Framework

/// `android.location.LocationManager`.
@JavaClass("android.location.LocationManager")
open class LocationManager: JavaObject {
    /// API 28.
    @JavaMethod
    open func isLocationEnabled() -> Bool

    @JavaMethod
    open func getProviders(_ enabledOnly: Bool) -> List<JavaString>!

    @JavaMethod
    open func getLastKnownLocation(_ provider: String) throws -> Location!

    @JavaMethod
    open func requestLocationUpdates(
        _ provider: String, _ minTimeMs: Int64, _ minDistanceM: Float, _ listener: LocationListener?, _ looper: Looper?
    ) throws

    @JavaMethod
    open func removeUpdates(_ listener: LocationListener?)
}

/// `android.location.Location`.
@JavaClass("android.location.Location")
open class Location: JavaObject {
    @JavaMethod open func getLatitude() -> Double
    @JavaMethod open func getLongitude() -> Double
    @JavaMethod open func hasAltitude() -> Bool
    @JavaMethod open func getAltitude() -> Double
    @JavaMethod open func hasAccuracy() -> Bool
    @JavaMethod open func getAccuracy() -> Float
    @JavaMethod open func hasSpeed() -> Bool
    @JavaMethod open func getSpeed() -> Float
    @JavaMethod open func hasBearing() -> Bool
    @JavaMethod open func getBearing() -> Float
    @JavaMethod open func getTime() -> Int64
    @JavaMethod open func getProvider() -> String
}

/// `android.location.LocationListener`.
@JavaInterface("android.location.LocationListener")
public struct LocationListener {}

// MARK: - LocationUpdates (Android/java)

@JavaClass("org.nucleantui.android.location.LocationUpdates", implements: LocationListener.self)
class LocationUpdates: JavaObject {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()

    var locationListener: LocationListener? { self.as(LocationListener.self) }
}

@JavaImplementation("org.nucleantui.android.location.LocationUpdates")
extension LocationUpdates {
    @JavaMethod
    static func nativeOnLocationChanged(_ handle: Int64, _ location: Location?, environment: JNIEnvironment) {
        guard let location else { return }
        NativeHandle<ALocation>.owner(handle)?.received(location)
    }

    @JavaMethod
    static func nativeOnProviderChanged(_ handle: Int64, _ provider: String, _ enabled: Bool, environment: JNIEnvironment) {
        NativeHandle<ALocation>.owner(handle)?.providerChanged(provider, enabled: enabled)
    }
}
