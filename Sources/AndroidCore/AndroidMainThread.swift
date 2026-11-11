//
//  AndroidMainThread.swift
//  AndroidCore
//
//  Running Swift on the app's main (Looper) thread.
//
//  Android delivers UI work, permission requests and — for everything here
//  that passes a main-Looper Handler — framework callbacks on the main thread.
//  Swift code arriving from anywhere else (an async function, a background
//  thread) gets there the way Java code does: a Runnable posted to a Handler
//  on the main Looper. The Runnable is `org.nucleantui.android.NativeRunnable`
//  (Android/java), whose run() calls back into the closure posted here.
//
//  This is not Swift's MainActor: nothing services the main dispatch queue on
//  Android unless the host arranges for it, so `@MainActor` code would never run.
//

import SwiftJava

public final class AndroidMainThread: Sendable {
    public static let shared = AndroidMainThread()

    private init() {}

    /// Run `body` on the main thread, later. Returns once it is queued.
    public func post(_ body: @escaping @Sendable (JNIEnvironment) -> Void) throws {
        try post(afterMilliseconds: 0, body)
    }

    /// Run `body` on the main thread once `milliseconds` have passed.
    public func post(afterMilliseconds milliseconds: Int64, _ body: @escaping @Sendable (JNIEnvironment) -> Void) throws {
        let environment = try JavaVirtualMachine.shared().environment()
        let work = Unmanaged.passRetained(MainThreadWork(body))
        let runnable = NativeRunnable(Int64(Int(bitPattern: work.toOpaque())), environment: environment)
        let handler = try mainHandler(in: environment)
        let posted = milliseconds > 0
            ? handler.postDelayed(runnable.as(Runnable.self), milliseconds)
            : handler.post(runnable.as(Runnable.self))
        if !posted {
            work.release()
            throw AndroidError.mainThreadUnavailable
        }
    }

    /// Run `body` on the main thread and wait for its result. Runs it in place
    /// when already there.
    public func run<Result: Sendable>(
        _ body: @escaping @Sendable (JNIEnvironment) throws -> Result
    ) async throws -> Result {
        let environment = try JavaVirtualMachine.shared().environment()
        if try isMainThread(in: environment) {
            return try body(environment)
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try post { environment in
                    continuation.resume(with: Swift.Result { try body(environment) })
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Whether the calling thread is the main Looper's.
    public func isMainThread(in environment: JNIEnvironment) throws -> Bool {
        guard let looper = try JavaClass<Looper>(environment: environment).getMainLooper() else {
            throw AndroidError.mainThreadUnavailable
        }
        return looper.isCurrentThread()
    }

    /// A Handler on the main Looper, for framework calls that deliver their
    /// callbacks through one.
    public func mainHandler(in environment: JNIEnvironment) throws -> Handler {
        guard let looper = try JavaClass<Looper>(environment: environment).getMainLooper() else {
            throw AndroidError.mainThreadUnavailable
        }
        return Handler(looper, environment: environment)
    }
}

/// The closure a NativeRunnable carries, retained until it has run.
private final class MainThreadWork {
    let body: @Sendable (JNIEnvironment) -> Void

    init(_ body: @escaping @Sendable (JNIEnvironment) -> Void) {
        self.body = body
    }
}

@JavaImplementation("org.nucleantui.android.NativeRunnable")
extension NativeRunnable {
    @JavaMethod
    static func nativeRun(_ handle: Int64, environment: JNIEnvironment) {
        guard let pointer = UnsafeRawPointer(bitPattern: Int(handle)) else { return }
        let work = Unmanaged<MainThreadWork>.fromOpaque(pointer).takeRetainedValue()
        work.body(environment)
    }
}
