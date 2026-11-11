//
//  JavaGlobalReference.swift
//  AndroidCore
//
//  A Java object that can be kept and used from any thread.
//
//  A swift-java wrapper keeps the JNIEnv of the thread that made it, and a
//  JNIEnv is only valid on its own thread — so a wrapper handed to another
//  thread would call into the wrong environment (CheckJNI, on in every debug
//  build and on the emulator, aborts on that). The JNI global reference under
//  the wrapper is valid everywhere. `JavaGlobalReference` carries only that,
//  as a Sendable value; `boundToCurrentThread()` re-wraps an object in place.
//

import SwiftJava

public final class JavaGlobalReference: @unchecked Sendable {
    /// The global reference. Deleted only in `deinit`; JNI global references
    /// may be used from any thread — hence `@unchecked Sendable`.
    public let object: jobject

    public init(_ object: some AnyJavaObject) {
        let environment = (try? JavaVirtualMachine.shared().environment()) ?? object.javaEnvironment
        self.object = environment.interface.NewGlobalRef(environment, object.javaThis)!
    }

    /// The object as `type`, for use on the thread `environment` belongs to.
    public func wrapped<T: AnyJavaObject>(as type: T.Type = T.self, in environment: JNIEnvironment) -> T {
        T(javaThis: object, environment: environment)
    }

    deinit {
        if let environment = try? JavaVirtualMachine.shared().environment() {
            environment.interface.DeleteGlobalRef(environment, object)
        }
    }
}

extension AnyJavaObject {
    /// This object, wrapped for the calling thread's JNIEnv.
    public func boundToCurrentThread() throws -> Self {
        Self(javaThis: javaThis, environment: try JavaVirtualMachine.shared().environment())
    }
}
