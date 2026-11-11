//
//  AndroidError.swift
//  AndroidCore
//

/// Failures the Android capability targets report themselves (as opposed to
/// Java exceptions, which arrive as swift-java's `Throwable`).
public enum AndroidError: Error, CustomStringConvertible {
    /// No Activity has been handed over with `AndroidContext.attach(activity:)`.
    case noActivity
    /// A system service (`Context.getSystemService`) was not there.
    case serviceUnavailable(String)
    /// The work could not be posted to the main thread's Looper.
    case mainThreadUnavailable
    /// The feature needs a newer Android than the device runs.
    case requiresSDK(Int)
    /// A read or write on a file failed with this errno.
    case io(Int32)
    /// Another app or the system answered an intent with an unusable result.
    case unexpectedResult(String)

    public var description: String {
        switch self {
        case .noActivity:
            "No Activity attached; call AndroidContext.shared.attach(activity:) from onCreate"
        case .serviceUnavailable(let name):
            "The \(name) system service is not available"
        case .mainThreadUnavailable:
            "Could not post to the main thread's Looper"
        case .requiresSDK(let level):
            "Requires Android API level \(level) or newer"
        case .io(let code):
            "File I/O failed (errno \(code))"
        case .unexpectedResult(let what):
            what
        }
    }
}
