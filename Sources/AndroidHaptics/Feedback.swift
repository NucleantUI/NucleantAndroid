//
//  Feedback.swift
//  AndroidHaptics
//
//  The system's standard haptic feedback — the tap, confirm and reject the
//  system UI uses itself — through `View.performHapticFeedback` on the
//  attached Activity's window. Unlike the vibrator, it follows the user's
//  "touch feedback" setting, and the device's tuning of each kind.
//

import AndroidCore
import SwiftJava

/// Standard feedback kinds (`HapticFeedbackConstants`).
public enum AHapticFeedback: Sendable, Hashable, CaseIterable {
    /// A key or button press.
    case tap
    case longPress
    case contextClick
    /// A detent: a dial or picker passing a step.
    case tick
    /// Something completed (Android 11+; a click before).
    case success
    /// Something was refused (Android 11+; a heavy click before).
    case error
    /// A drag or swipe starting / ending (Android 11+).
    case gestureStart
    case gestureEnd
    /// A switch turned on / off (Android 14+).
    case toggleOn
    case toggleOff

    var constant: Int32 {
        switch self {
        case .tap: 1 // VIRTUAL_KEY
        case .longPress: 0
        case .contextClick: 6
        case .tick: 4 // CLOCK_TICK
        case .success: 16 // CONFIRM
        case .error: 17 // REJECT
        case .gestureStart: 12
        case .gestureEnd: 13
        case .toggleOn: 21
        case .toggleOff: 22
        }
    }

    /// The first Android with the constant.
    var minimumSDK: Int {
        switch self {
        case .tap, .longPress, .contextClick, .tick: 23
        case .success, .error, .gestureStart, .gestureEnd: 30
        case .toggleOn, .toggleOff: 34
        }
    }

    /// What plays on an Android without the constant.
    var fallback: AHapticEffect? {
        switch self {
        case .success: .click
        case .error: .heavyClick
        case .gestureStart, .gestureEnd, .toggleOn, .toggleOff: .tick
        default: nil
        }
    }
}

extension AVibrator {
    /// Play standard feedback on the attached Activity's window. On the main
    /// thread. False when the system skipped it (touch feedback off, or no
    /// window).
    @discardableResult
    public func perform(_ feedback: AHapticFeedback) throws -> Bool {
        let environment = try JavaVirtualMachine.shared().environment()
        if try AndroidContext.shared.sdkLevel(in: environment) < feedback.minimumSDK {
            guard let fallback = feedback.fallback else { return false }
            try play(fallback)
            return true
        }
        guard let view = try AndroidContext.shared.activity(in: environment).getWindow()?.getDecorView() else {
            return false
        }
        return view.performHapticFeedback(feedback.constant)
    }
}

// MARK: - Framework

extension Window {
    @JavaMethod
    func getDecorView() -> FeedbackView!
}

/// `android.view.View`: what feedback needs of it.
@JavaClass("android.view.View")
open class FeedbackView: JavaObject {
    @JavaMethod
    open func performHapticFeedback(_ feedbackConstant: Int32) -> Bool
}
