//
//  Notifications.swift
//  AndroidNotifications
//
//  Posting, updating and cancelling the app's notifications, on channels of
//  its own, through NotificationManager — and hearing which one the user
//  tapped. Android 13+ needs `android.permission.POST_NOTIFICATIONS` in the
//  manifest and granted at run time (`requestAuthorization()`); before that
//  they are on unless the user switched them off in settings.
//
//  Tapping a notification brings the app's launch Activity back. For that to
//  reach `lastTapped`, the host forwards `onNewIntent` to
//  `AndroidContext.handleNewIntent` (and declares the Activity `singleTop`, so
//  the running one gets the intent instead of a new one starting). A tap that
//  starts the app afresh is picked up from the launch intent.
//
//  Remote (push) notifications are not covered: they need Firebase Cloud
//  Messaging and a server.
//

import AndroidCore
import Observation
import SwiftJava

/// How much a channel's notifications interrupt (`NotificationManager.IMPORTANCE_*`).
public enum ANotificationImportance: Sendable, Hashable, CaseIterable {
    /// Not shown.
    case none
    /// In the shade only, collapsed.
    case min
    /// In the shade and the status bar, silently.
    case low
    /// With sound.
    case `default`
    /// With sound, and peeking onto the screen.
    case high

    var value: Int32 {
        switch self {
        case .none: 0
        case .min: 1
        case .low: 2
        case .default: 3
        case .high: 4
        }
    }

    init(value: Int32) {
        self = Self.allCases.first { $0.value == value } ?? .default
    }
}

/// One of the app's notification channels, as the system has it — the user
/// may have changed its importance in settings.
public final class ANotificationChannel: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let importance: ANotificationImportance

    init(id: String, name: String, importance: ANotificationImportance) {
        self.id = id
        self.name = name
        self.importance = importance
    }
}

/// The app's notifications. Create and use it on the main thread.
@Observable
public final class ANotifications: @unchecked Sendable {
    /// The channel posts go to unless told otherwise (created on init).
    public let defaultChannelID: String
    /// Whether notifications can be shown at all: permission granted (13+) and
    /// not switched off in the system settings.
    public private(set) var isAuthorized: Bool
    /// The app's notifications still in the shade, as of the last change made
    /// here or `refresh()`. Android does not tell apps when the user swipes one away.
    public private(set) var activeCount = 0
    public private(set) var channels: [ANotificationChannel] = []
    /// The id of the notification the user last tapped.
    public private(set) var lastTapped: Int32?
    public private(set) var tapCount = 0

    @ObservationIgnored private let manager: NotificationManager
    @ObservationIgnored private let context: Context
    @ObservationIgnored private let sdkLevel: Int
    @ObservationIgnored private var nextID: Int32 = 1

    static let permission = "android.permission.POST_NOTIFICATIONS"
    /// The launch intent's extra that says which notification was tapped.
    static let tappedExtra = "org.nucleantui.android.notifications.tapped"

    /// `channelName` is what the user sees for the default channel in the
    /// system settings.
    public init(channelID: String = "default", channelName: String = "Notifications") throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let context = try AndroidContext.shared.applicationContext(in: environment)
        guard let manager = context.getSystemService("notification")?.as(NotificationManager.self) else {
            throw AndroidError.serviceUnavailable("notification")
        }
        self.manager = manager
        self.context = context
        self.defaultChannelID = channelID
        self.sdkLevel = try AndroidContext.shared.sdkLevel(in: environment)
        self.isAuthorized = manager.areNotificationsEnabled()
        try createChannel(id: channelID, name: channelName, importance: .default)

        AndroidContext.shared.addIntentHandler { [weak self] intent in
            guard let self else { return false }
            self.received(intent)
            return true
        }
        // Started by a tap?
        if let launch = try? AndroidContext.shared.activity(in: environment).getIntent() {
            received(launch)
        }
        refresh()
    }

    // MARK: - Access

    /// Ask for permission to post (Android 13+; before that there is nothing to ask).
    public func requestAuthorization() async throws -> Bool {
        if sdkLevel >= 33 {
            _ = try await AndroidContext.shared.requestPermissions([Self.permission])
        }
        return try await AndroidMainThread.shared.run { _ in
            self.refresh()
            return self.isAuthorized
        }
    }

    // MARK: - Channels

    /// Create a channel, or rename an existing one. Its importance only takes
    /// on creation: after that it is the user's to change.
    public func createChannel(id: String, name: String, importance: ANotificationImportance) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        manager.createNotificationChannel(
            NotificationChannel(id, charSequence(name, in: environment), importance.value, environment: environment))
        refresh()
    }

    public func deleteChannel(_ id: String) {
        guard id != defaultChannelID else { return }
        manager.deleteNotificationChannel(id)
        refresh()
    }

    // MARK: - Posting

    /// Post a notification on `channelID` (the default channel when nil);
    /// tapping it opens the app and sets `lastTapped`. Returns its id.
    @discardableResult
    public func post(title: String, body: String, channelID: String? = nil) throws -> Int32 {
        let id = nextID
        nextID += 1
        try show(id: id, title: title, body: body, channelID: channelID ?? defaultChannelID)
        return id
    }

    /// Replace notification `id`'s text in place (it stays where it is in the shade).
    public func update(_ id: Int32, title: String, body: String, channelID: String? = nil) throws {
        try show(id: id, title: title, body: body, channelID: channelID ?? defaultChannelID)
    }

    public func cancel(_ id: Int32) {
        manager.cancel(id)
        refresh()
    }

    public func cancelAll() {
        manager.cancelAll()
        refresh()
    }

    private func show(id: Int32, title: String, body: String, channelID: String) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let builder = NotificationBuilder(context, channelID, environment: environment)
        _ = builder.setContentTitle(charSequence(title, in: environment))
        _ = builder.setContentText(charSequence(body, in: environment))
        _ = builder.setSmallIcon(try JavaClass<AndroidRDrawable>(environment: environment).ic_dialog_info)
        _ = builder.setAutoCancel(true)
        if let launch = context.getPackageManager()?.getLaunchIntentForPackage(context.getPackageName()) {
            _ = launch.putExtra(Self.tappedExtra, id)
            _ = launch.addFlags(Self.flagActivitySingleTop | Self.flagActivityClearTop)
            let pending = try JavaClass<PendingIntent>(environment: environment)
                .getActivity(context, id, launch, Self.flagImmutable | Self.flagUpdateCurrent)
            _ = builder.setContentIntent(pending)
        }
        manager.notify(id, builder.build())
        refresh()
    }

    // MARK: - State

    /// Read the permission state, channels and notifications in the shade again.
    public func refresh() {
        isAuthorized = manager.areNotificationsEnabled()
        activeCount = manager.getActiveNotifications().count
        var channels: [ANotificationChannel] = []
        if let list = manager.getNotificationChannels() {
            for channel in list {
                channels.append(ANotificationChannel(
                    id: channel.getId(),
                    name: channel.getName()?.toString() ?? channel.getId(),
                    importance: ANotificationImportance(value: channel.getImportance())
                ))
            }
        }
        self.channels = channels
    }

    private func received(_ intent: Intent) {
        guard intent.hasExtra(Self.tappedExtra) else { return }
        let id = intent.getIntExtra(Self.tappedExtra, -1)
        // Reported once: a recreated Activity gets the same intent back.
        intent.removeExtra(Self.tappedExtra)
        lastTapped = id
        tapCount += 1
        refresh()
    }

    static let flagUpdateCurrent: Int32 = 0x0800_0000
    static let flagImmutable: Int32 = 0x0400_0000
    static let flagActivitySingleTop: Int32 = 0x2000_0000
    static let flagActivityClearTop: Int32 = 0x0400_0000
}

// MARK: - Framework

/// `android.app.NotificationManager`.
@JavaClass("android.app.NotificationManager")
open class NotificationManager: JavaObject {
    @JavaMethod
    open func areNotificationsEnabled() -> Bool

    @JavaMethod
    open func createNotificationChannel(_ channel: NotificationChannel?)

    @JavaMethod
    open func deleteNotificationChannel(_ channelId: String)

    @JavaMethod
    open func getNotificationChannels() -> List<NotificationChannel>!

    @JavaMethod
    open func notify(_ id: Int32, _ notification: Notification?)

    @JavaMethod
    open func cancel(_ id: Int32)

    @JavaMethod
    open func cancelAll()

    @JavaMethod
    open func getActiveNotifications() -> [StatusBarNotification?]
}

/// `android.app.NotificationChannel`.
@JavaClass("android.app.NotificationChannel")
open class NotificationChannel: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(
        _ id: String, _ name: CharSequence?, _ importance: Int32, environment: JNIEnvironment? = nil)

    @JavaMethod
    open func getId() -> String

    @JavaMethod
    open func getName() -> CharSequence?

    @JavaMethod
    open func getImportance() -> Int32
}

/// `android.app.Notification`.
@JavaClass("android.app.Notification")
open class Notification: JavaObject {}

/// `android.app.Notification.Builder`.
@JavaClass("android.app.Notification$Builder")
open class NotificationBuilder: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(_ context: Context?, _ channelId: String, environment: JNIEnvironment? = nil)

    @JavaMethod
    open func setContentTitle(_ title: CharSequence?) -> NotificationBuilder!

    @JavaMethod
    open func setContentText(_ text: CharSequence?) -> NotificationBuilder!

    @JavaMethod
    open func setSmallIcon(_ icon: Int32) -> NotificationBuilder!

    @JavaMethod
    open func setAutoCancel(_ autoCancel: Bool) -> NotificationBuilder!

    @JavaMethod
    open func setContentIntent(_ intent: PendingIntent?) -> NotificationBuilder!

    @JavaMethod
    open func build() -> Notification!
}

/// `android.app.PendingIntent`.
@JavaClass("android.app.PendingIntent")
open class PendingIntent: JavaObject {}

extension JavaClass<PendingIntent> {
    @JavaStaticMethod
    public func getActivity(_ context: Context?, _ requestCode: Int32, _ intent: Intent?, _ flags: Int32) -> PendingIntent!
}

/// `android.service.notification.StatusBarNotification`.
@JavaClass("android.service.notification.StatusBarNotification")
open class StatusBarNotification: JavaObject {}

/// `android.R.drawable`, for a system icon to show in the status bar.
@JavaClass("android.R$drawable")
open class AndroidRDrawable: JavaObject {}

extension JavaClass<AndroidRDrawable> {
    @JavaStaticField(isFinal: true)
    public var ic_dialog_info: Int32
}
