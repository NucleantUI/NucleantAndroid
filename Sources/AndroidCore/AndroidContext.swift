//
//  AndroidContext.swift
//  AndroidCore
//
//  The Android app NucleantAndroid's capabilities run in.
//
//  The capability types (AFlashlight, ACameras, APhotoLibrary, …) create
//  themselves without being handed a `Context` or an `Activity`. What they need
//  from the host is done here, once:
//
//  - `attach(activity:)` from `Activity.onCreate`, so there is a Context to
//    reach system services through and an Activity to request permissions on;
//  - `handlePermissionsResult(...)` from `Activity.onRequestPermissionsResult`,
//    because Android delivers the user's answer to the Activity and nowhere else;
//  - `handleActivityResult(...)` from `Activity.onActivityResult`, for the same
//    reason: pickers and other apps answer `startActivityForResult` there;
//  - `handleNewIntent(_:)` from `Activity.onNewIntent`, which is how a tapped
//    notification comes back to a running app.
//

import SwiftJava
import Synchronization

public final class AndroidContext: Sendable {
    /// The one Android app this process is.
    public static let shared = AndroidContext()

    private struct State {
        var activity: JavaGlobalReference?
        var sdkLevel: Int?
        var nextRequestCode: Int32 = AndroidContext.firstRequestCode
        var pendingRequests: [Int32: PendingPermissionRequest] = [:]
        var nextResultCode: Int32 = AndroidContext.firstResultCode
        var pendingResults: [Int32: CheckedContinuation<AndroidActivityResult, any Error>] = [:]
        var intentHandlers: [@Sendable (Intent) -> Bool] = []
    }

    private struct PendingPermissionRequest {
        let permissions: [String]
        let continuation: CheckedContinuation<[String: Bool], any Error>
    }

    /// Request codes NucleantAndroid passes to `requestPermissions`. Android
    /// only keeps the low 16 bits, and the host may use codes of its own, so
    /// these stay in one recognisable block ("NA" = 0x4E41) and wrap within it.
    static let firstRequestCode: Int32 = 0x4E41
    static let requestCodeCount: Int32 = 0x100
    /// The same, for `startActivityForResult` (0x4F00…).
    static let firstResultCode: Int32 = 0x4F00

    private let state = Mutex(State())

    private init() {}

    // MARK: - Activity

    /// Hand the host's Activity over. Call from `onCreate` — and again from a
    /// recreated Activity, which replaces the old one.
    public func attach(activity: JavaObject) {
        let reference = JavaGlobalReference(activity)
        state.withLock { $0.activity = reference }
    }

    /// `onDestroy`: forget the Activity, unless a newer one has been attached
    /// since (a recreated Activity's `onCreate` runs before the old one's
    /// `onDestroy`).
    public func detach(activity: JavaObject) {
        let environment = activity.javaEnvironment
        state.withLock { state in
            guard let current = state.activity else { return }
            if environment.interface.IsSameObject(environment, current.object, activity.javaThis) == JNI_TRUE {
                state.activity = nil
            }
        }
    }

    /// The attached Activity, wrapped for the calling thread.
    public func activity(in environment: JNIEnvironment) throws -> Activity {
        guard let reference = state.withLock({ $0.activity }) else {
            throw AndroidError.noActivity
        }
        return reference.wrapped(as: Activity.self, in: environment)
    }

    /// The application Context: outlives any one Activity, so it is the one
    /// to keep system services from.
    public func applicationContext(in environment: JNIEnvironment) throws -> Context {
        let activity = try activity(in: environment)
        guard let context = activity.getApplicationContext() else {
            throw AndroidError.noActivity
        }
        return context
    }

    /// `Build.VERSION.SDK_INT` of the device.
    public func sdkLevel(in environment: JNIEnvironment) throws -> Int {
        if let level = state.withLock({ $0.sdkLevel }) {
            return level
        }
        let level = Int(try JavaClass<BuildVersion>(environment: environment).SDK_INT)
        state.withLock { $0.sdkLevel = level }
        return level
    }

    // MARK: - Runtime permissions

    /// Whether `permission` (e.g. `"android.permission.CAMERA"`) is granted.
    public func isGranted(_ permission: String) throws -> Bool {
        let environment = try JavaVirtualMachine.shared().environment()
        return try applicationContext(in: environment).checkSelfPermission(permission)
            == PackageManagerConstants.permissionGranted
    }

    /// Ask the user for `permissions`, and wait for the answer.
    ///
    /// Permissions that are already granted are reported without showing
    /// anything. The rest are requested on the attached Activity; the answer
    /// arrives once the host forwards `onRequestPermissionsResult` to
    /// ``handlePermissionsResult(requestCode:permissions:grantResults:)``.
    public func requestPermissions(_ permissions: [String]) async throws -> [String: Bool] {
        var answer: [String: Bool] = [:]
        var missing: [String] = []
        for permission in permissions {
            if try isGranted(permission) {
                answer[permission] = true
            } else {
                missing.append(permission)
            }
        }
        if missing.isEmpty {
            return answer
        }

        let requested = missing
        let granted = try await withCheckedThrowingContinuation { continuation in
            let requestCode = state.withLock { state in
                let code = state.nextRequestCode
                state.nextRequestCode = Self.firstRequestCode
                    + (code - Self.firstRequestCode + 1) % Self.requestCodeCount
                state.pendingRequests[code] = PendingPermissionRequest(
                    permissions: requested,
                    continuation: continuation
                )
                return code
            }
            do {
                try AndroidMainThread.shared.post { environment in
                    do {
                        try self.activity(in: environment).requestPermissions(requested, requestCode)
                    } catch {
                        self.failRequest(requestCode, with: error)
                    }
                }
            } catch {
                failRequest(requestCode, with: error)
            }
        }
        return answer.merging(granted) { _, new in new }
    }

    /// `Activity.onRequestPermissionsResult`, forwarded by the host.
    ///
    /// Returns false for a request NucleantAndroid did not make, so the host
    /// knows to handle it itself.
    @discardableResult
    public func handlePermissionsResult(
        requestCode: Int32,
        permissions: [String],
        grantResults: [Int32]
    ) -> Bool {
        guard let request = state.withLock({ $0.pendingRequests.removeValue(forKey: requestCode) }) else {
            return false
        }
        // An interrupted request comes back with empty arrays: nothing granted.
        var answer = Dictionary(uniqueKeysWithValues: request.permissions.map { ($0, false) })
        for (permission, result) in zip(permissions, grantResults) {
            answer[permission] = result == PackageManagerConstants.permissionGranted
        }
        request.continuation.resume(returning: answer)
        return true
    }

    private func failRequest(_ requestCode: Int32, with error: any Error) {
        let request = state.withLock { $0.pendingRequests.removeValue(forKey: requestCode) }
        request?.continuation.resume(throwing: error)
    }

    // MARK: - Activity results

    /// Start `intent` on the attached Activity and wait for what it sends back:
    /// a picker's choice, another app's answer. The result arrives once the
    /// host forwards `onActivityResult` to
    /// ``handleActivityResult(requestCode:resultCode:data:)``.
    ///
    /// Throws when nothing on the device handles `intent`.
    public func startActivityForResult(_ intent: Intent) async throws -> AndroidActivityResult {
        let intent = JavaGlobalReference(intent)
        return try await withCheckedThrowingContinuation { continuation in
            let requestCode = state.withLock { state in
                let code = state.nextResultCode
                state.nextResultCode = Self.firstResultCode
                    + (code - Self.firstResultCode + 1) % Self.requestCodeCount
                state.pendingResults[code] = continuation
                return code
            }
            do {
                try AndroidMainThread.shared.post { environment in
                    do {
                        try self.activity(in: environment)
                            .startActivityForResult(intent.wrapped(as: Intent.self, in: environment), requestCode)
                    } catch {
                        self.failResult(requestCode, with: error)
                    }
                }
            } catch {
                failResult(requestCode, with: error)
            }
        }
    }

    /// `Activity.onActivityResult`, forwarded by the host. Returns false for a
    /// request NucleantAndroid did not make.
    @discardableResult
    public func handleActivityResult(requestCode: Int32, resultCode: Int32, data: JavaObject?) -> Bool {
        guard let continuation = state.withLock({ $0.pendingResults.removeValue(forKey: requestCode) }) else {
            return false
        }
        continuation.resume(returning: AndroidActivityResult(resultCode: resultCode, data: data.map(JavaGlobalReference.init)))
        return true
    }

    private func failResult(_ requestCode: Int32, with error: any Error) {
        let continuation = state.withLock { $0.pendingResults.removeValue(forKey: requestCode) }
        continuation?.resume(throwing: error)
    }

    // MARK: - New intents

    /// Hand every intent the host forwards to `handler`, on the main thread,
    /// for as long as it returns true.
    public func addIntentHandler(_ handler: @escaping @Sendable (Intent) -> Bool) {
        state.withLock { $0.intentHandlers.append(handler) }
    }

    /// `Activity.onNewIntent`, forwarded by the host (after `setIntent`): the
    /// app was brought back by an intent — a tapped notification, for one.
    public func handleNewIntent(_ intent: JavaObject) {
        let intent = Intent(javaThis: intent.javaThis, environment: intent.javaEnvironment)
        let handlers = state.withLock { $0.intentHandlers }
        let kept = handlers.filter { $0(intent) }
        state.withLock { state in
            // Keep the ones that said so, and any added while they ran.
            state.intentHandlers = kept + state.intentHandlers.dropFirst(handlers.count)
        }
    }
}

/// What an Activity started for a result sent back.
public final class AndroidActivityResult: Sendable {
    /// `Activity.RESULT_OK` (-1), `RESULT_CANCELED` (0), or the app's own code.
    public let resultCode: Int32
    /// The intent it answered with, if any.
    public let data: JavaGlobalReference?

    init(resultCode: Int32, data: JavaGlobalReference?) {
        self.resultCode = resultCode
        self.data = data
    }

    public var isOK: Bool {
        resultCode == -1
    }
}

/// `android.content.pm.PackageManager` values NucleantAndroid compares against.
enum PackageManagerConstants {
    static let permissionGranted: Int32 = 0
}
