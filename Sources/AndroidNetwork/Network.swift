//
//  Network.swift
//  AndroidNetwork
//
//  The device's connection to the internet — its default network — kept
//  current through ConnectivityManager's default-network callback. Needs
//  `android.permission.ACCESS_NETWORK_STATE` in the manifest (a normal
//  permission: granted on install).
//
//  On the emulator: airplane mode or Wi-Fi off from quick settings, or
//  `adb shell svc wifi disable` / `svc data disable`.
//

import AndroidCore
import Observation
import SwiftJava

/// How a network reaches the outside (`NetworkCapabilities.TRANSPORT_*`).
public enum ANetworkTransport: Sendable, Hashable, CaseIterable {
    case cellular
    case wifi
    case bluetooth
    case ethernet
    case vpn

    var transportID: Int32 {
        switch self {
        case .cellular: 0
        case .wifi: 1
        case .bluetooth: 2
        case .ethernet: 3
        case .vpn: 4
        }
    }
}

/// The default network. Create and use it on the main thread, where changes
/// arrive; it listens for as long as it exists.
@Observable
public final class ANetwork: @unchecked Sendable {
    /// Whether there is a default network at all.
    public private(set) var isConnected = false
    /// Whether Android has checked it actually reaches the internet.
    public private(set) var isValidated = false
    /// Whether it may cost money per byte (cellular, a metered hotspot).
    public private(set) var isMetered = false
    public private(set) var transports: Set<ANetworkTransport> = []
    /// Estimated bandwidths in kbit/s; 0 when unknown.
    public private(set) var downstreamBandwidth = 0
    public private(set) var upstreamBandwidth = 0

    @ObservationIgnored private let manager: ConnectivityManager
    /// `Network.getNetworkHandle()` of the network the state describes.
    @ObservationIgnored private var currentNetwork: Int64?
    @ObservationIgnored private var callback: DefaultNetworkCallback?
    @ObservationIgnored private var handle: Int64 = 0

    public init() throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        guard let manager = context.getSystemService("connectivity")?.as(ConnectivityManager.self) else {
            throw AndroidError.serviceUnavailable("connectivity")
        }
        self.manager = manager
        if let network = manager.getActiveNetwork(), let capabilities = manager.getNetworkCapabilities(network) {
            update(network: network.getNetworkHandle(), capabilities)
        }
        // Calls back right away with the current default network, then on every change.
        let handle = NativeHandle.retain(self)
        let callback = DefaultNetworkCallback(handle, environment: environment)
        self.handle = handle
        self.callback = callback
        try manager.registerDefaultNetworkCallback(callback, try AndroidMainThread.shared.mainHandler(in: environment))
    }

    deinit {
        guard let callback else { return }
        let networkCallback = JavaGlobalReference(callback)
        let manager = JavaGlobalReference(self.manager)
        let handle = self.handle
        try? AndroidMainThread.shared.post { environment in
            let callback = networkCallback.wrapped(as: DefaultNetworkCallback.self, in: environment)
            callback.disarm()
            try? manager.wrapped(as: ConnectivityManager.self, in: environment).unregisterNetworkCallback(callback)
            NativeHandle<ANetwork>.release(handle)
        }
    }

    func update(network: Int64, _ capabilities: NetworkCapabilities) {
        currentNetwork = network
        isConnected = true
        isValidated = capabilities.hasCapability(Self.capabilityValidated)
        isMetered = !capabilities.hasCapability(Self.capabilityNotMetered)
        transports = Set(ANetworkTransport.allCases.filter { capabilities.hasTransport($0.transportID) })
        downstreamBandwidth = Int(capabilities.getLinkDownstreamBandwidthKbps())
        upstreamBandwidth = Int(capabilities.getLinkUpstreamBandwidthKbps())
    }

    /// When the default network switches, the old one can be reported lost after
    /// the new one is up; only losing the current one disconnects.
    func lost(network: Int64) {
        guard network == currentNetwork else { return }
        currentNetwork = nil
        isConnected = false
        isValidated = false
        isMetered = false
        transports = []
        downstreamBandwidth = 0
        upstreamBandwidth = 0
    }

    /// `NetworkCapabilities.NET_CAPABILITY_*`.
    static let capabilityNotMetered: Int32 = 11
    static let capabilityValidated: Int32 = 16
}

// MARK: - Framework

/// `android.net.ConnectivityManager`.
@JavaClass("android.net.ConnectivityManager")
open class ConnectivityManager: JavaObject {
    @JavaMethod
    open func getActiveNetwork() -> Network!

    @JavaMethod
    open func getNetworkCapabilities(_ network: Network?) -> NetworkCapabilities!

    /// `registerDefaultNetworkCallback(NetworkCallback, Handler)`, API 26.
    @JavaMethod
    open func registerDefaultNetworkCallback(_ callback: ConnectivityManagerNetworkCallback?, _ handler: Handler?) throws

    @JavaMethod
    open func unregisterNetworkCallback(_ callback: ConnectivityManagerNetworkCallback?) throws
}

/// `android.net.ConnectivityManager.NetworkCallback`.
@JavaClass("android.net.ConnectivityManager$NetworkCallback")
open class ConnectivityManagerNetworkCallback: JavaObject {}

/// `android.net.Network`.
@JavaClass("android.net.Network")
open class Network: JavaObject {
    @JavaMethod
    open func getNetworkHandle() -> Int64
}

/// `android.net.NetworkCapabilities`.
@JavaClass("android.net.NetworkCapabilities")
open class NetworkCapabilities: JavaObject {
    @JavaMethod
    open func hasTransport(_ transportType: Int32) -> Bool

    @JavaMethod
    open func hasCapability(_ capability: Int32) -> Bool

    @JavaMethod
    open func getLinkDownstreamBandwidthKbps() -> Int32

    @JavaMethod
    open func getLinkUpstreamBandwidthKbps() -> Int32
}

// MARK: - DefaultNetworkCallback (Android/java)

@JavaClass("org.nucleantui.android.network.DefaultNetworkCallback")
class DefaultNetworkCallback: ConnectivityManagerNetworkCallback {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.android.network.DefaultNetworkCallback")
extension DefaultNetworkCallback {
    @JavaMethod
    static func nativeOnCapabilitiesChanged(
        _ handle: Int64, _ network: Int64, _ capabilities: NetworkCapabilities?, environment: JNIEnvironment
    ) {
        guard let capabilities else { return }
        NativeHandle<ANetwork>.owner(handle)?.update(network: network, capabilities)
    }

    @JavaMethod
    static func nativeOnLost(_ handle: Int64, _ network: Int64, environment: JNIEnvironment) {
        NativeHandle<ANetwork>.owner(handle)?.lost(network: network)
    }
}
