//
//  DeviceLabBridge.swift
//  DeviceLabBridge
//
//  What the Device Lab app (Demo/) calls from Kotlin.
//
//  jextract turns every `public` declaration in this target into Java in
//  `org.nucleantui.devicelab.bridge`: free functions become static methods of
//  `DeviceLabBridge`, classes Java classes of the same name, `async` functions
//  return a CompletableFuture, and `throws` becomes a Java exception. The glue
//  is compiled into libDeviceLabBridge.so, the app's one Swift library.
//
//  Each `Lab*` class wraps one of the capability targets' `A*` models in the
//  types jextract handles well (Int32/Int64, [UInt8] as byte[], strings for
//  enums, no default arguments), and forwards to it. `observe(onChange:)`
//  follows the model with Observation — `withObservationTracking` — and calls
//  the Kotlin closure on the main thread after every change, which is how the
//  app's views follow the Swift state.
//
//  Kotlin calls everything except the `async` functions on the main thread,
//  which is where the models live.
//

import AndroidCore
import Observation
import SwiftJava

// MARK: - Host

/// `Activity.onCreate`.
public func attachActivity(activity: JavaObject) {
    AndroidContext.shared.attach(activity: activity)
}

/// `Activity.onDestroy`.
public func detachActivity(activity: JavaObject) {
    AndroidContext.shared.detach(activity: activity)
}

/// `Activity.onActivityResult`. False for a request Swift did not make.
public func activityResult(requestCode: Int32, resultCode: Int32, data: JavaObject?) -> Bool {
    AndroidContext.shared.handleActivityResult(requestCode: requestCode, resultCode: resultCode, data: data)
}

/// `Activity.onNewIntent`, after `setIntent`.
public func newIntent(intent: JavaObject) {
    AndroidContext.shared.handleNewIntent(intent)
}

/// `Activity.onRequestPermissionsResult`. False for a request Swift did not make.
public func permissionsResult(requestCode: Int32, permissions: [String], grantResults: [Int32]) -> Bool {
    AndroidContext.shared.handlePermissionsResult(
        requestCode: requestCode,
        permissions: permissions,
        grantResults: grantResults
    )
}

// MARK: - Observing

/// Runs a Kotlin `Runnable` on the main thread after anything `read` touches
/// changes, re-tracking each time, until `observe` is called again or `stop()`.
///
/// The listener arrives as a plain `java.lang.Runnable` (jextract passes it as
/// `JavaObject`) and is called through swift-java, kept by a global reference.
final class ChangeObserver: @unchecked Sendable {
    /// Bumped by every observe/stop; a tracking pass from an older one ends.
    private var generation = 0

    private final class Callbacks: @unchecked Sendable {
        let read: () -> Void
        let listener: JavaGlobalReference

        init(read: @escaping () -> Void, listener: JavaGlobalReference) {
            self.read = read
            self.listener = listener
        }
    }

    func observe(_ read: @escaping () -> Void, listener: JavaObject) {
        generation += 1
        track(Callbacks(read: read, listener: JavaGlobalReference(listener)), generation: generation)
    }

    func stop() {
        generation += 1
    }

    private func track(_ callbacks: Callbacks, generation: Int) {
        withObservationTracking {
            callbacks.read()
        } onChange: {
            // Called as the change is about to happen, on the thread making it;
            // by the time this runs on the main thread, it has.
            try? AndroidMainThread.shared.post { environment in
                guard generation == self.generation else { return }
                callbacks.listener.wrapped(as: Runnable.self, in: environment).run()
                self.track(callbacks, generation: generation)
            }
        }
    }
}

/// `value`, or NaN for Kotlin when there is none.
func orNaN(_ value: Double?) -> Double {
    value ?? .nan
}
