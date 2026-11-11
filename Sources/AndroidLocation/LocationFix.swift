//
//  LocationFix.swift
//  AndroidLocation
//
//  One position on request, and addresses for a position (reverse geocoding).
//

import AndroidCore
import SwiftJava

extension ALocation {
    /// Get one fresh position — waiting for the provider to deliver one,
    /// rather than the last known. It also becomes `current`.
    public func requestFix(timeoutMilliseconds: Int64 = 30_000) async throws -> ALocationFix {
        guard authorization != .denied else {
            throw ALocationError.notAuthorized
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try AndroidMainThread.shared.post { environment in
                    FixRequestSession(location: self, continuation: continuation)
                        .start(timeoutMilliseconds: timeoutMilliseconds, in: environment)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Street addresses for `fix`, best match first; empty when there are none.
    /// Uses the device's geocoder (a network service on most devices), off the
    /// main thread.
    public func addresses(for fix: ALocationFix, maxResults: Int = 3) async throws -> [AAddress] {
        let environment = try JavaVirtualMachine.shared().environment()
        guard try JavaClass<Geocoder>(environment: environment).isPresent() else {
            throw ALocationError.noGeocoder
        }
        let context = try AndroidContext.shared.applicationContext(in: environment)
        let geocoder = Geocoder(context, environment: environment)
        var addresses: [AAddress] = []
        if let list = try geocoder.getFromLocation(fix.latitude, fix.longitude, Int32(maxResults)) {
            for address in list {
                addresses.append(AAddress(address))
            }
        }
        return addresses
    }

    /// The provider a fix should come from, for the current access.
    func fixProvider() throws -> String {
        guard let provider = Self.provider(among: try enabledProviders(), precise: authorization == .precise) else {
            throw ALocationError.noProvider
        }
        return provider
    }

    func fixArrived(_ fix: ALocationFix) {
        received(fix)
    }

    var locationManager: LocationManager { manager }
}

/// One `requestFix`, from asking to its answer. Keeps itself alive until then.
final class FixRequestSession: @unchecked Sendable {
    private let location: ALocation
    private var continuation: CheckedContinuation<ALocationFix, any Error>?
    private var request: FixRequest?
    private var cancel: CancellationSignal?
    private var handle: Int64 = 0
    private var retainedSelf: Unmanaged<FixRequestSession>?

    init(location: ALocation, continuation: CheckedContinuation<ALocationFix, any Error>) {
        self.location = location
        self.continuation = continuation
    }

    /// On the main thread.
    func start(timeoutMilliseconds: Int64, in environment: JNIEnvironment) {
        retainedSelf = Unmanaged.passRetained(self)
        handle = NativeHandle.retain(self)
        do {
            let provider = try location.fixProvider()
            let request = FixRequest(handle, environment: environment)
            self.request = request
            let manager = location.locationManager
            if try AndroidContext.shared.sdkLevel(in: environment) >= 30 {
                let context = try AndroidContext.shared.applicationContext(in: environment)
                let cancel = CancellationSignal(environment: environment)
                self.cancel = cancel
                try manager.getCurrentLocation(provider, cancel, context.getMainExecutor(), request.as(JavaConsumer.self))
            } else {
                try manager.requestSingleUpdate(
                    provider, request.as(LocationListener.self), try JavaClass<Looper>(environment: environment).getMainLooper())
            }
            try AndroidMainThread.shared.post(afterMilliseconds: timeoutMilliseconds) { _ in
                self.finish(.failure(ALocationError.timedOut))
            }
        } catch {
            finish(.failure(error))
        }
    }

    func arrived(_ location: Location?) {
        guard let location else {
            finish(.failure(ALocationError.noFix))
            return
        }
        let fix = ALocationFix(location)
        self.location.fixArrived(fix)
        finish(.success(fix))
    }

    private func finish(_ result: Result<ALocationFix, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        request?.disarm()
        cancel?.cancel()
        if let request {
            location.locationManager.removeUpdates(request.as(LocationListener.self))
        }
        continuation.resume(with: result)
        NativeHandle<FixRequestSession>.release(handle)
        retainedSelf?.release()
        retainedSelf = nil
    }
}

/// A street address.
public final class AAddress: Sendable {
    /// The address as lines, the way it is written there.
    public let lines: [String]
    public let thoroughfare: String
    public let subThoroughfare: String
    public let locality: String
    public let postalCode: String
    public let adminArea: String
    public let countryName: String
    public let countryCode: String

    init(_ address: Address) {
        let last = address.getMaxAddressLineIndex()
        lines = last < 0 ? [] : (0...last).map { address.getAddressLine($0) }
        thoroughfare = address.getThoroughfare()
        subThoroughfare = address.getSubThoroughfare()
        locality = address.getLocality()
        postalCode = address.getPostalCode()
        adminArea = address.getAdminArea()
        countryName = address.getCountryName()
        countryCode = address.getCountryCode()
    }
}

// MARK: - Framework

extension LocationManager {
    /// API 30.
    @JavaMethod
    func getCurrentLocation(_ provider: String, _ cancellationSignal: CancellationSignal?, _ executor: Executor?, _ consumer: JavaConsumer?) throws

    @JavaMethod
    func requestSingleUpdate(_ provider: String, _ listener: LocationListener?, _ looper: Looper?) throws
}

/// `java.util.function.Consumer`.
@JavaInterface("java.util.function.Consumer")
public struct JavaConsumer {}

/// `android.location.Geocoder`.
@JavaClass("android.location.Geocoder")
open class Geocoder: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ context: Context?, environment: JNIEnvironment? = nil)

    @JavaMethod
    open func getFromLocation(_ latitude: Double, _ longitude: Double, _ maxResults: Int32) throws -> List<Address>!
}

extension JavaClass<Geocoder> {
    @JavaStaticMethod
    public func isPresent() -> Bool
}

/// `android.location.Address`. Missing parts come back as "".
@JavaClass("android.location.Address")
open class Address: JavaObject {
    @JavaMethod open func getMaxAddressLineIndex() -> Int32
    @JavaMethod open func getAddressLine(_ index: Int32) -> String
    @JavaMethod open func getThoroughfare() -> String
    @JavaMethod open func getSubThoroughfare() -> String
    @JavaMethod open func getLocality() -> String
    @JavaMethod open func getPostalCode() -> String
    @JavaMethod open func getAdminArea() -> String
    @JavaMethod open func getCountryName() -> String
    @JavaMethod open func getCountryCode() -> String
}

// MARK: - FixRequest (Android/java)

@JavaClass("org.nucleantui.android.location.FixRequest", implements: LocationListener.self, JavaConsumer.self)
class FixRequest: JavaObject {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.location.FixRequest")
extension FixRequest {
    @JavaMethod
    static func nativeOnFix(_ handle: Int64, _ location: Location?, environment: JNIEnvironment) {
        NativeHandle<FixRequestSession>.owner(handle)?.arrived(location)
    }
}
