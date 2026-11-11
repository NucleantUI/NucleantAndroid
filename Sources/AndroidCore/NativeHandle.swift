//
//  NativeHandle.swift
//  AndroidCore
//
//  The `long` a Java callback helper carries back into Swift.
//
//  Android reports through listener objects (a torch callback, a content
//  observer, a sensor listener…). The capability classes register small Java
//  helpers from Android/java, each holding a handle and forwarding every
//  callback to a `static native` method with it. The handle is a retained box
//  holding its Swift owner *weakly*: a callback that arrives after the owner is
//  gone finds nil instead of freed memory.
//
//  The box itself lives until `release(_:)`, which the owner's teardown calls
//  on the main thread after disarming the Java helper — callbacks arrive on the
//  main thread too, so none can still be in flight with the handle by then.
//

public final class NativeHandle<Owner: AnyObject>: @unchecked Sendable {
    // Weak references are safe to load from any thread.
    private weak var owner: Owner?

    private init(_ owner: Owner) {
        self.owner = owner
    }

    /// A handle for `owner`, valid until `release(_:)`.
    public static func retain(_ owner: Owner) -> Int64 {
        Int64(Int(bitPattern: Unmanaged.passRetained(NativeHandle(owner)).toOpaque()))
    }

    /// The owner `handle` stands for, while it is alive.
    public static func owner(_ handle: Int64) -> Owner? {
        guard let pointer = UnsafeRawPointer(bitPattern: Int(handle)) else { return nil }
        return Unmanaged<NativeHandle<Owner>>.fromOpaque(pointer).takeUnretainedValue().owner
    }

    /// Give `handle` up. Only once the Java helper carrying it is disarmed.
    public static func release(_ handle: Int64) {
        guard let pointer = UnsafeRawPointer(bitPattern: Int(handle)) else { return }
        Unmanaged<NativeHandle<Owner>>.fromOpaque(pointer).release()
    }
}
