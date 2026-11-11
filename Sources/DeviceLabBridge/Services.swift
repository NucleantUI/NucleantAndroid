//
//  Services.swift
//  DeviceLabBridge
//
//  AndroidLocation, AndroidClipboard, AndroidNetwork, AndroidNotifications,
//  AndroidSpeech and AndroidBiometrics for Kotlin.
//

import AndroidBiometrics
import AndroidClipboard
import AndroidCore
import AndroidLocation
import AndroidNetwork
import AndroidNotifications
import AndroidSpeech
import Observation
import SwiftJava

// MARK: - Location

public final class LabLocation: @unchecked Sendable {
    let location: ALocation
    let observer = ChangeObserver()

    public init() throws {
        location = try ALocation()
    }

    /// "precise", "approximate" or "denied".
    public var authorization: String { "\(location.authorization)" }
    public var isEnabled: Bool { location.isEnabled }
    public var isUpdating: Bool { location.isUpdating }
    /// Empty while not updating.
    public var provider: String { location.provider ?? "" }
    public var hasFix: Bool { location.current != nil }
    public var latitude: Double { orNaN(location.current?.latitude) }
    public var longitude: Double { orNaN(location.current?.longitude) }
    public var altitude: Double { orNaN(location.current?.altitude) }
    public var accuracy: Double { orNaN(location.current?.accuracy) }
    public var speed: Double { orNaN(location.current?.speed) }
    public var bearing: Double { orNaN(location.current?.bearing) }
    /// Milliseconds since 1970; -1 without a fix.
    public var time: Int64 { location.current?.time ?? -1 }
    public var fixProvider: String { location.current?.provider ?? "" }

    public func requestAccess() async throws -> String {
        "\(try await location.requestAuthorization())"
    }

    public func start() throws { try location.startUpdates(minimumInterval: 1000, minimumDistance: 0) }

    /// One fresh position (it also becomes the current one).
    public func requestFix() async throws { _ = try await location.requestFix() }

    /// The current position's addresses, each as one line.
    public func lookUpAddresses() async throws -> [String] {
        guard let fix = location.current else { return [] }
        return try await location.addresses(for: fix).map { address in
            address.lines.isEmpty
                ? [address.thoroughfare, address.locality, address.countryName].filter { !$0.isEmpty }.joined(separator: ", ")
                : address.lines.joined(separator: ", ")
        }
    }
    public func stop() { location.stopUpdates() }
    public func refresh() throws { try location.refresh() }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [location] in
            _ = (location.authorization, location.isEnabled, location.isUpdating, location.provider)
            _ = location.current
        }, listener: listener)
    }
}

// MARK: - Clipboard

public final class LabClipboard: @unchecked Sendable {
    let clipboard: AClipboard
    let observer = ChangeObserver()

    public init() throws {
        clipboard = try AClipboard()
    }

    /// Empty when it holds no text.
    public var text: String { clipboard.text ?? "" }
    public var hasText: Bool { clipboard.hasText }
    public var changeCount: Int64 { Int64(clipboard.changeCount) }

    public func setText(text: String) throws { try clipboard.setText(text, label: "Device Lab") }
    public func clear() { clipboard.clear() }
    public func refresh() { clipboard.refresh() }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [clipboard] in _ = (clipboard.text, clipboard.changeCount) }, listener: listener)
    }
}

// MARK: - Network

public final class LabNetwork: @unchecked Sendable {
    let network: ANetwork
    let observer = ChangeObserver()

    public init() throws {
        network = try ANetwork()
    }

    public var isConnected: Bool { network.isConnected }
    public var isValidated: Bool { network.isValidated }
    public var isMetered: Bool { network.isMetered }
    /// "wifi", "cellular", "ethernet", "bluetooth", "vpn".
    public var transports: [String] { network.transports.map { "\($0)" }.sorted() }
    public var downstreamBandwidth: Int32 { Int32(network.downstreamBandwidth) }
    public var upstreamBandwidth: Int32 { Int32(network.upstreamBandwidth) }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [network] in
            _ = (network.isConnected, network.isValidated, network.isMetered, network.transports)
            _ = (network.downstreamBandwidth, network.upstreamBandwidth)
        }, listener: listener)
    }
}

// MARK: - Notifications

public final class LabNotifications: @unchecked Sendable {
    let notifications: ANotifications
    let observer = ChangeObserver()

    public init() throws {
        notifications = try ANotifications(channelID: "device-lab", channelName: "Device Lab")
    }

    public var isAuthorized: Bool { notifications.isAuthorized }
    public var activeCount: Int32 { Int32(notifications.activeCount) }

    public func requestAccess() async throws -> Bool { try await notifications.requestAuthorization() }
    /// `channelID` empty for the default channel.
    public func post(title: String, body: String, channelID: String) throws -> Int32 {
        try notifications.post(title: title, body: body, channelID: channelID.isEmpty ? nil : channelID)
    }

    public func update(id: Int32, title: String, body: String) throws {
        try notifications.update(id, title: title, body: body)
    }

    public var channels: [LabChannel] { notifications.channels.map(LabChannel.init) }
    public var defaultChannelID: String { notifications.defaultChannelID }

    /// `importance`: "none", "min", "low", "default", "high".
    public func createChannel(id: String, name: String, importance: String) throws {
        let level = ANotificationImportance.allCases.first { "\($0)" == importance } ?? .default
        try notifications.createChannel(id: id, name: name, importance: level)
    }

    public func deleteChannel(id: String) { notifications.deleteChannel(id) }
    public func cancel(id: Int32) { notifications.cancel(id) }

    /// The id of the last notification tapped; -1 when none has been.
    public var lastTapped: Int32 { notifications.lastTapped ?? -1 }
    public var tapCount: Int32 { Int32(notifications.tapCount) }
    public func cancelAll() { notifications.cancelAll() }
    public func refresh() { notifications.refresh() }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [notifications] in
            _ = (notifications.isAuthorized, notifications.activeCount, notifications.channels, notifications.lastTapped, notifications.tapCount)
        }, listener: listener)
    }
}

// MARK: - Speech

public final class LabSpeech: @unchecked Sendable {
    let speech: ATextToSpeech
    let observer = ChangeObserver()

    public init() throws {
        speech = try ATextToSpeech()
    }

    public var isReady: Bool { speech.isReady }
    public var initializationFailed: Bool { speech.initializationFailed }
    public var isSpeaking: Bool { speech.isSpeaking }
    public var engine: String { speech.engine ?? "" }
    public var rate: Float { speech.rate }
    public var pitch: Float { speech.pitch }

    public func speak(text: String) throws { try speech.speak(text) }
    public func stop() { speech.stop() }
    public func setRate(rate: Float) { speech.setRate(rate) }
    public func setPitch(pitch: Float) { speech.setPitch(pitch) }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [speech] in
            _ = (speech.isReady, speech.initializationFailed, speech.isSpeaking, speech.engine, speech.rate, speech.pitch)
        }, listener: listener)
    }
}

// MARK: - Biometrics

public final class LabBiometrics: @unchecked Sendable {
    let biometrics: ABiometrics
    let observer = ChangeObserver()

    public init() throws {
        biometrics = try ABiometrics()
    }

    /// "available", "noneEnrolled", "noHardware", "unavailable", …
    public var availability: String { "\(biometrics.availability)" }
    public var isAuthenticating: Bool { biometrics.isAuthenticating }
    public var failedAttempts: Int32 { Int32(biometrics.failedAttempts) }

    public func authenticate(title: String, subtitle: String) async throws -> Bool {
        try await biometrics.authenticate(title: title, subtitle: subtitle.isEmpty ? nil : subtitle)
    }

    public func refresh() { biometrics.refresh() }

    /// `listener` is a `java.lang.Runnable`, run on the main thread after each change.
    public func observe(listener: JavaObject) {
        observer.observe({ [biometrics] in
            _ = (biometrics.availability, biometrics.isAuthenticating, biometrics.failedAttempts)
        }, listener: listener)
    }
}

public final class LabChannel: @unchecked Sendable {
    let channel: ANotificationChannel

    init(_ channel: ANotificationChannel) {
        self.channel = channel
    }

    public var id: String { channel.id }
    public var name: String { channel.name }
    public var importance: String { "\(channel.importance)" }
}
